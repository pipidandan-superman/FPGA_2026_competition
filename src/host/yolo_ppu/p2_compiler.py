#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p2_compiler.py -- PPU 图编译器 v1.1（F2 run01：view 别名修正版）

前身 = P2.0 run02 p2_compiler.py v1.0（4_metrics/logs/
2026-09-21_yolo_p2_0_run02_manifests/，F0 封存证据，保持只读）。

v1.1 修正的缺陷（F2 筹备期发现，手册五处明文为据）：
  v1.0 的 Layout 给 16 个 view out buffer 各自独立占位（独立 span+guard），
  违反手册冻结语义——
    §1 算子表   "view | buffer 表别名，PL 零搬移 | 数据复制"
    §3          "纯地址视图（base+c0·H·W，尺寸 (c1−c0)·H·W）"
    §3          "view 不新增 DDR 存储，仅在 buffer 表登记别名项"
    §4.1 opcode "0x10 VIEW 零搬移（buffer 表别名已在装载期完成）"
    §9 容量     "104 逻辑项 ≤ 128（view 别名项含在内）"
  后果（若不修）：RTL view 零搬移完成后消费者读 out 地址 = 独立空区 → 全图
  数据流断裂。v1.0 自身 docstring 亦写明"view 别名不新增 DDR"，属实现背离
  自身规范的工具缺陷，非手册缺陷——修工具不改手册。

修正内容：
  1. 布局两遍化：第一遍照旧放置全部非 view-out 图 buffer（id 序）+
     weights/bias/lut/heads_out/mirror；第二遍 view out 一律别名
     base_off = parent_base_off + c0·H·W（不新增 span、不推进水位、无 guard）。
  2. overlaps() 跳过别名 span（别名落在父 span 内是设计使然）。
  3. buf_entries 别名项 guard=0 并附 alias_of=parent id（诊断字段）。
  4. arena/memory_account 相应收缩；新增 view_alias_bytes 记账。
  5. 增加 --out 参数（v1.0 只能落脚本所在目录）。

不变的冻结链：schedule.json / quant.json SHA 校验照旧；六 manifest 结构与
字段名不变（只有 base_off 数值与 arena 统计变）；descriptor 逻辑表零变化。

Run: D:/work/Python/python.exe p2_compiler.py --out <manifests_dir>
"""

import argparse
import collections
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(HERE, '..', '..'))
ROM = os.path.join(WT, '2_fpga', '3_yolo_zynq', 'rom_data')

# ---- 冻结参数（A1.1 / 本编译器设计参数，全部记录进 manifest）----
CMA_WIN_LO = 0x10000000
CMA_WIN_HI = 0x20000000          # ch2 A1.1 物理窗口
ALIGN = 64                       # base 至少 64B 对齐
GUARD = 64                       # 每项前后 guard 区（设计参数，初值 0xA5）
BUF_TABLE_MAX = 128              # A1.1 buffer 表容量
DESC_TABLE_MAX = 128
CANON = {'conv': 63, 'view': 16, 'concat': 13, 'add': 6,
         'maxpool5': 3, 'upsample2': 2, 'heads': 1}

SRC_SHA = {
    'schedule.json': '1bc33538cef7ee9bd338f69a6e3c23ca5f9b72070f759ee1b124b0f06825d473',
    'quant.json': '6b2392d3402a40f6c692f8a49a459ef639fbefb6519a9bb4e2bb722a52b35433',
}


def b1_chain(k):
    # B1 一般化（2026-10-06，k720 方案 A 裁决）：K<=1024 单块直用。
    # 硬件边界=F2 bank 深 1024；720 单块 2160 拍 < 3072 tlast 守卫，
    # 板证=K720_R1/R2（BOARD_P13_K720_PASS / BOARD_P13_K720_R2_PASS）。
    if k <= 1024:
        return [k]
    if k == 1152:
        return [1024, 128]
    if k == 2304:
        return [1024, 1024, 256]
    return None


def sha256_file(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def sha256_json(o):
    return hashlib.sha256(
        json.dumps(o, sort_keys=True, ensure_ascii=False,
                   indent=1).encode('utf-8')).hexdigest()


def mirror_bytes_for_conv(t, bufs, k_chain):
    """P1.3 布局律：镜像 = LUT 区 + 每块装载×块数 + y 槽 + guard.

    n_tile = OUT_H（每输出行一 tile）；rc = ceil(OC/8)；NB = n_tile*rc。
    tile_load_len = sum(24*k_len)。y_slot=128B；ycnt=80 上界（8 行×10 列
    上界取 P1.3 律：min(80, 8*W)）。镜像含 0x100 LUT 头 + 0xA5 guard 尾。
    """
    oc, oh, ow = t['out_shape']
    n_tile = oh
    rc = (oc + 7) // 8
    nb = n_tile * rc
    tile_load = sum(24 * k for k in k_chain)
    y_slot = 128
    ycnt = min(80, 8 * ow) if ow >= 10 else 8 * ow
    lut_head = 0x100
    y_arena = y_slot * nb
    ycnt_zone = ycnt            # s2mm 账（不占镜像，仅记录）
    guard_tail = 0x1000
    total = lut_head + tile_load * nb + y_arena + guard_tail
    return {
        'node': t['node'], 'oc': oc, 'oh': oh, 'ow': ow,
        'n_tile': n_tile, 'rc': rc, 'n_block': nb,
        'tile_load_len': tile_load, 'y_arena': y_arena, 'ycnt': ycnt_zone,
        'mirror_bytes': total,
    }


class Layout:
    """线性规划器：顺序放置、ALIGN 对齐、前后 GUARD；v1.1 增别名登记。"""

    def __init__(self):
        self.spans = []          # (off, size, name, is_alias)
        self.cur = 0

    def place(self, size, name):
        base = (self.cur + GUARD + ALIGN - 1) // ALIGN * ALIGN
        self.spans.append((base, size, name, False))
        self.cur = base + size + GUARD
        return base

    def alias(self, off, size, name):
        """view 别名：只登记 span，不推进水位（手册：view 不新增 DDR）。"""
        self.spans.append((off, size, name, True))
        return off

    def overlaps(self):
        # v1.1：别名 span 不参与重叠判定（按定义落在父 span 内部）
        s = sorted(x for x in self.spans if not x[3])
        for i in range(1, len(s)):
            if s[i - 1][0] + s[i - 1][1] > s[i][0]:
                return (s[i - 1][2], s[i][2])
        return None


def main():
    ap = argparse.ArgumentParser(description='PPU graph compiler v1.1')
    ap.add_argument('--out', required=True,
                    help='manifest 输出目录（六件套落此）')
    args = ap.parse_args()
    os.makedirs(args.out, exist_ok=True)

    errs = []
    sched_p = os.path.join(ROM, 'schedule.json')
    quant_p = os.path.join(ROM, 'quant.json')
    for n, p in (('schedule.json', sched_p), ('quant.json', quant_p)):
        got = sha256_file(p)
        if got != SRC_SHA[n]:
            errs.append('E_SRC_SHA %s %s' % (n, got))
    s = json.load(open(sched_p, encoding='utf-8'))
    q = json.load(open(quant_p, encoding='utf-8'))
    tasks, bufs = s['tasks'], s['buffers']
    qmap = {n['node']: n for n in q['nodes']}

    # C1 计数（run01 口径内联复验）
    opcnt = collections.Counter(t['op'] for t in tasks)
    if dict(opcnt) != CANON or len(tasks) != 104:
        errs.append('E_OP_COUNT %s' % dict(opcnt))
    if not (len(bufs) <= BUF_TABLE_MAX):
        errs.append('E_BUF_TABLE_FULL %d' % len(bufs))

    # ---- 派生：producer / consumers / 视图父引用 ----
    producer = {b['id']: b['producer'] for b in bufs}
    in_bufs_of = {}              # task idx -> [buffer ids read]
    for i, t in enumerate(tasks):
        op = t['op']
        if op == 'conv':
            in_bufs_of[i] = [t['in']]
        elif op == 'view':
            in_bufs_of[i] = [t['in']]
        elif op in ('maxpool5', 'upsample2'):
            in_bufs_of[i] = [t['in']]
        elif op == 'add':
            in_bufs_of[i] = [t['a'], t['b']]
        elif op == 'concat':
            # inputs 是 [{buf, scale}, ...]（逐段重定标，B2 口径保留原值）
            in_bufs_of[i] = [e['buf'] for e in t['inputs']]
        elif op == 'heads':
            # cls/reg 是 [{buf, scale, shape}, ...]；heads 无 out buffer，
            # 写独立 heads_out 驻留区（本布局单独放置）
            in_bufs_of[i] = [e['buf'] for e in t['cls']] \
                + [e['buf'] for e in t['reg']]
        else:
            errs.append('E_OP_UNKNOWN %s' % op)
    consumers = collections.defaultdict(list)   # buf id -> [task idx]
    for i, bl in in_bufs_of.items():
        for b in bl:
            consumers[b].append(i)
    sched_pos = {b['id']: None for b in bufs}
    for i, t in enumerate(tasks):
        if 'out' in t:
            sched_pos[t['out']] = i

    # 拓扑检查：每个输入 buffer 的 producer 任务必须排在本任务之前
    for i, bl in in_bufs_of.items():
        for b in bl:
            if b == 0:
                continue                      # 输入图像，producer=input
            pi = sched_pos[b]
            if pi is None:
                errs.append('E_NO_PRODUCER task%d buf%d' % (i, b))
            elif pi >= i:
                errs.append('E_TOPO task%d reads buf%d produced at %d'
                            % (i, b, pi))

    # view 合法性：ch 切片落在父通道内
    for i, t in enumerate(tasks):
        if t['op'] == 'view':
            c0, c1 = t['ch']
            pc = bufs[t['in']]['shape'][0]
            if not (0 <= c0 < c1 <= pc):
                errs.append('E_VIEW_RANGE %s ch=%s parentC=%d'
                            % (t['node'], t['ch'], pc))

    # heads last 唯一
    heads_idx = [i for i, t in enumerate(tasks) if t['op'] == 'heads']
    if len(heads_idx) != 1:
        errs.append('E_HEADS_COUNT %d' % len(heads_idx))

    # ---- K 链（B1，run01 已审计；此处展开并复核）----
    k_blocks = {}
    for i, t in enumerate(tasks):
        if t['op'] != 'conv':
            continue
        ic = bufs[t['in']]['shape'][0]
        kh, kw = t['k']
        k_real = ic * kh * kw
        chain = b1_chain(k_real)
        if chain is None:
            errs.append('E_K_UNSUPPORTED %s K=%d' % (t['node'], k_real))
            continue
        wq = qmap[t['node']]['w_shape']
        if not (wq[1] * wq[2] * wq[3] == k_real):
            errs.append('E_K_MISMATCH %s' % t['node'])
        # 组分配：P1.3 律 —— 单块 grp0；两块 0,1；三块 0,1,0（B3 组重用）
        grp = {1: [0], 2: [0, 1], 3: [0, 1, 0]}[len(chain)]
        blocks = []
        kbase = 0
        for bi, kl in enumerate(chain):
            blocks.append({
                'idx': bi, 'k_base': kbase, 'k_len': kl,
                'first': 1 if bi == 0 else 0,
                'last': 1 if bi == len(chain) - 1 else 0,
                'group': grp[bi],
                'load_bytes': 24 * kl, 'accepted_beats': 3 * kl,
            })
            kbase += kl
        k_blocks[i] = {
            'sched_index': i, 'node': t['node'], 'k_real': k_real,
            'chain': chain, 'blocks': blocks,
            'first_conv': bool(t.get('first')), 'has_act': bool(t['has_act']),
            'z_sum_w': 'z_sum_w' in t,
        }

    # ---- 静态布局 v1.1：两遍（第一遍非 view-out；第二遍 view 别名） ----
    view_tasks = {i: t for i, t in enumerate(tasks) if t['op'] == 'view'}
    view_out_ids = {t['out'] for t in view_tasks.values()}
    lay = Layout()
    placed_off = {}              # buf id -> base_off（第一遍产物）
    buf_entries = {b['id']: None for b in bufs}
    for b in sorted(bufs, key=lambda x: x['id']):
        if b['id'] in view_out_ids:
            continue                       # 第二遍处理
        c, h, w = b['shape']
        size = c * h * w
        off = lay.place(size, 'buf%03d_%s' % (b['id'], b['producer']))
        placed_off[b['id']] = off
        buf_entries[b['id']] = {
            'id': b['id'], 'base_off': off, 'size': size,
            'shape': b['shape'], 'line_stride': w,
            'producer': b['producer'], 'producer_task': sched_pos[b['id']],
            'consumers': consumers[b['id']],
            'generation': 0, 'guard': GUARD, 'cache': 'wb-cacheable',
            'is_view_out': False,
        }
    # 第二遍：view out = 父内纯地址别名（base+c0·H·W，不新增 DDR）
    view_alias_bytes = 0
    for i, t in sorted(view_tasks.items()):
        c0, c1 = t['ch']
        pid = t['in']
        if pid in view_out_ids:
            errs.append('E_VIEW_PARENT_VIEW task%d buf%d' % (i, pid))
            continue
        pc, ph, pw = bufs[pid]['shape']
        want_off = placed_off[pid] + c0 * ph * pw
        if want_off + (c1 - c0) * ph * pw > placed_off[pid] + pc * ph * pw:
            errs.append('E_VIEW_ALIAS_RANGE task%d off=0x%X' % (i, want_off))
        lay.alias(want_off, (c1 - c0) * ph * pw,
                  'buf%03d_%s' % (t['out'], t['node']))
        placed_off[t['out']] = want_off
        buf_entries[t['out']] = {
            'id': t['out'], 'base_off': want_off,
            'size': (c1 - c0) * ph * pw,
            'shape': bufs[t['out']]['shape'],
            'line_stride': bufs[t['out']]['shape'][2],
            'producer': bufs[t['out']]['producer'],
            'producer_task': sched_pos[t['out']],
            'consumers': consumers[t['out']],
            'generation': 0, 'guard': 0, 'cache': 'wb-cacheable',
            'is_view_out': True, 'alias_of': pid,
        }
        view_alias_bytes += (c1 - c0) * ph * pw
    graph_ws_end = lay.cur

    # ---- 权重/LUT/bias 驻留 + heads 输出 + GEMM 镜像 arena ----
    w_sz = os.path.getsize(os.path.join(ROM, 'weights.bin'))
    b_sz = os.path.getsize(os.path.join(ROM, 'bias.bin'))
    l_sz = os.path.getsize(os.path.join(ROM, 'lut.bin'))
    off_w = lay.place(w_sz, 'weights_bin')
    off_b = lay.place(b_sz, 'bias_bin')
    off_l = lay.place(l_sz, 'lut_bin')

    # heads 输出尺寸 = Σ(cls 段) + Σ(reg 段)（schedule 自带逐段 shape，
    # 直接积和；布局编排是 PPU v1.1 ABI 项，此处只定字节数）
    ht = tasks[heads_idx[0]]
    heads_size = sum(e['shape'][0] * e['shape'][1] * e['shape'][2]
                     for e in ht['cls'] + ht['reg'])
    for e in ht['cls'] + ht['reg']:
        if e['buf'] >= len(bufs):
            errs.append('E_HEADS_REF buf%d' % e['buf'])
    off_heads = lay.place(heads_size, 'heads_out')

    mirror_info, mirror_max = {}, 0
    for i, kb in k_blocks.items():
        m = mirror_bytes_for_conv(tasks[i], bufs, kb['chain'])
        mirror_info[kb['node']] = m
        mirror_max = max(mirror_max, m['mirror_bytes'])
    off_mirror = lay.place(mirror_max, 'gemm_mirror_arena_max')

    ov = lay.overlaps()
    if ov:
        errs.append('E_SPAN_OVERLAP %s' % (ov,))

    arena_total = lay.cur
    # provisional 保留（F5 前实测核对；来源：现有 display 工程经验预算）
    RESERVE = [
        {'name': 'camera_vdma_frames', 'bytes': 0x02000000,
         'src': 'provisional（display 工程 720p 级三帧缓冲经验值）'},
        {'name': 'linux_cma_runtime', 'bytes': 0x01000000,
         'src': 'provisional（pynq cma 运行时余量经验值）'},
    ]
    reserve_total = sum(r['bytes'] for r in RESERVE)
    window = CMA_WIN_HI - CMA_WIN_LO
    used = arena_total + reserve_total
    margin = (window - used) / window
    if used > window:
        errs.append('E_CMA_WINDOW used=0x%X window=0x%X' % (used, window))
    if margin < 0.25:
        errs.append('E_CMA_MARGIN %.3f' % margin)

    # ---- descriptor（逻辑表，与 v1.0 逐字段一致）----
    descs = []
    for i, t in enumerate(tasks):
        d = {
            'desc_id': i, 'sched_index': i, 'op': t['op'], 'node': t['node'],
            'in_bufs': in_bufs_of[i],
            'out_buf': t.get('out', None),
            'out_region': 'heads_out' if t['op'] == 'heads'
                          else 'graph_buf',
            'deps': sorted({sched_pos[b] for b in in_bufs_of[i]
                            if sched_pos[b] is not None}),
            'last': 1 if t['op'] == 'heads' else 0,
            'frame_end': 1 if t['op'] == 'heads' else 0,
        }
        if t['op'] == 'conv':
            d['quant_node'] = t['node']
            d['k_chain'] = k_blocks[i]['chain']
            d['n_blocks'] = len(k_blocks[i]['chain'])
        elif t['op'] == 'view':
            d['parent_buf'] = t['in']
            d['ch'] = t['ch']
        elif t['op'] == 'add':
            d.update({'a_buf': t['a'], 'b_buf': t['b'],
                      'a_scale': t['a_scale'], 'b_scale': t['b_scale'],
                      'out_scale': t['out_scale']})
        elif t['op'] == 'concat':
            d.update({'inputs': t['inputs'], 'out_scale': t['out_scale']})
        elif t['op'] == 'heads':
            d.update({'cls': t['cls'], 'reg': t['reg']})
        descs.append(d)
    if len(descs) > DESC_TABLE_MAX:
        errs.append('E_DESC_TABLE_FULL %d' % len(descs))
    n_last = sum(d['last'] for d in descs)
    if n_last != 1:
        errs.append('E_LAST_UNIQUE %d' % n_last)

    # ---- oracle manifest（长度/oracle 源；SHA 由 F2 填）----
    oracle_rows = []
    for i, t in enumerate(tasks):
        if t['op'] == 'heads':
            bshape, blen = 'heads_composite', heads_size
        else:
            bshape = bufs[t['out']]['shape']
            blen = bshape[0] * bshape[1] * bshape[2]
        oracle_rows.append({
            'sched_index': i, 'node': t['node'], 'op': t['op'],
            'out_len': blen,
            'out_shape': bshape,
            'g0_key': 'int8_' + t['node'],
            'g0_present': None,          # F2 填（扩展导出后核对）
            'out_sha256': None,          # F2 填
            'first_mismatch_offset': None,
        })

    # ---- backend map ----
    be = {'conv': 'gemm', 'view': 'software', 'concat': 'software',
          'add': 'software', 'maxpool5': 'software',
          'upsample2': 'software', 'heads': 'software'}
    backend = {t['node']: be[t['op']] for t in tasks}

    # ---- 落盘六份 + 内存账 ----
    def dump(name, obj):
        p = os.path.join(args.out, name)
        json.dump(obj, open(p, 'w', encoding='utf-8'), indent=1,
                  ensure_ascii=False)
        return sha256_file(p)

    shas = {}
    shas['buffer_table.json'] = dump('buffer_table.json', {
        'arena_base': None, 'arena_total': arena_total,
        'params': {'align': ALIGN, 'guard': GUARD,
                   'cma_window': [CMA_WIN_LO, CMA_WIN_HI],
                   'buf_table_max': BUF_TABLE_MAX},
        'entries': [buf_entries[k] for k in sorted(buf_entries)]})
    shas['descriptor_table.json'] = dump('descriptor_table.json', {
        'params': {'desc_table_max': DESC_TABLE_MAX},
        'entries': descs})
    shas['k_block_manifest.json'] = dump('k_block_manifest.json', {
        'b1_table': 'frozen (ch2 B1)', 'convs': k_blocks})
    shas['oracle_manifest.json'] = dump('oracle_manifest.json', {
        'source': 'G0 = 2026-09-15_yolo7020_g2_quant_rne_run04 frame0',
        'rows': oracle_rows})
    shas['backend_map.json'] = dump('backend_map.json', {
        'round': 'B3-S0/S1 首轮', 'map': backend})
    shas['memory_account.json'] = dump('memory_account.json', {
        'window': [CMA_WIN_LO, CMA_WIN_HI], 'window_bytes': window,
        'graph_workset_end': graph_ws_end,
        'view_alias_bytes': view_alias_bytes,
        'view_alias_rule': ('v1.1: view out = parent_base_off + c0*H*W '
                            '纯地址别名，不新增 DDR（手册 §1/§3/§4.1/§9）'),
        'spans': [{'off': o, 'size': z, 'name': n, 'alias': a}
                  for o, z, n, a in lay.spans],
        'mirror_max_node': max(mirror_info,
                               key=lambda k: mirror_info[k]['mirror_bytes']),
        'mirror_per_conv': mirror_info,
        'reservations_provisional': RESERVE,
        'arena_total': arena_total, 'used_with_reserve': used,
        'margin_ratio': round(margin, 4),
        'verdict': 'OK' if used <= window else 'OVER',
    })

    verdict = 'PASS' if not errs else 'FAIL'
    gm = {
        'plan': 'yolo_p2_integrated_master_plan_20260921.md F1/P2.0',
        'run': 'PPU-F2 run01 view-alias compiler v1.1',
        'tool': 'p2_compiler.py v1.1',
        'date': '2026-09-21', 'src_sha': {
            'schedule.json': sha256_file(sched_p),
            'quant.json': sha256_file(quant_p),
            'weights.bin': sha256_file(os.path.join(ROM, 'weights.bin')),
            'bias.bin': sha256_file(os.path.join(ROM, 'bias.bin')),
            'lut.bin': sha256_file(os.path.join(ROM, 'lut.bin'))},
        'fixes': ['v1.0→v1.1: 16 个 view out 由独立占位改为父内纯地址别名'
                  '（base+c0·H·W，不新增 DDR；手册 §1/§3/§4.1/§9 五处明文）'],
        'counts': dict(opcnt), 'n_buffers': len(bufs),
        'arena_total': arena_total, 'heads_size': heads_size,
        'mirror_max': mirror_max, 'margin_ratio': round(margin, 4),
        'sub_manifest_sha256': shas,
        'errors': errs, 'verdict': verdict,
    }
    json.dump(gm, open(os.path.join(args.out, 'graph_manifest.json'), 'w',
                  encoding='utf-8'), indent=1, ensure_ascii=False)

    print('P2_COMPILER %s' % verdict)
    if errs:
        for e in errs[:20]:
            print('  ERR', e)
    print('  buffers=%d (view alias %d B 不占 arena) arena=0x%X (%.2f MB) '
          'window=0x%X margin=%.1f%%'
          % (len(bufs), view_alias_bytes, arena_total, arena_total / 1048576,
             window, margin * 100))
    print('  weights=0x%X bias=0x%X lut=0x%X heads=0x%X mirror_max=0x%X'
          % (w_sz, b_sz, l_sz, heads_size, mirror_max))
    print('  desc=%d last=1 heads_size=%d' % (len(descs), heads_size))
    return 0 if verdict == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
