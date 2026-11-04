#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""p2_compiler_n80_v11.py -- n80 六 manifest v1.1 重生成（view 别名修正移植）

母本 = 3_host/yolo_ppu/p2_compiler.py v1.1（view 别名修正版 + 2026-10-06
B1 一般化同版）。v1.0→v1.1 的缺陷与修正全文见母本卷首，要旨：
  v1.0 Layout 给 16 个 view out 各自独立占位（独立 span+guard），违反
  手册 §1/§3/§4.1/§9 五处明文（"view 不新增 DDR，纯地址视图 base+c0·H·W"）。
  v1.1 两遍布局：第一遍非 view-out 图 buffer（id 序）+ weights/bias/lut/
  heads_out/mirror；第二遍 view out 一律别名 base_off = parent+c0·H·W
  （不新增 span、不推水位、guard=0、登记 alias_of）；overlaps() 跳别名
  span；memory_account 增 view_alias_bytes 记账。

缘起（n80 线）：2026-10-06_yolo_k720_b1_kbm_regen_run01 六 manifest 系
v1.0 布局血统（其母本=run02 p2_compiler.py v1.0），16 view 独立占位——
graph_exec v1.1 执行法第一帧即拦（view 别名几何违例 desc3，aliased
0/16）。F2 张量语义回放与 F9 链不变量均不触别名几何，缺陷潜伏至
M3 前置（gen_anchors_n80）才显形。本 run 重生成 = M3 执行面唯一合法输入。

与母本的差异（仅此 6 处，布局/派生/校验逻辑逐行等价）：
  1. ROM <- dryrun_run01/out/quant_n80（官方 yolov8n.pt 量化包，只读）；
  2. SRC_SHA <- quant_n80/src_pin.json（gen_schedule_n80 实算写入，免手工
     转录，保留防漂移语义；母本为源码内硬编码常量）；
  3. B1_EXTENSION 常量 + kbm 注记（[720] BOARD_PROVEN R1/R2）；
  4. kbm b1_table / oracle source / backend round 文本行取 n80 口径；
  5. graph_manifest：n80 溯源 + supersedes（b1regen v1.0 布局版
     gm=9d915ce1…，why=view 独立 span -> 父内纯地址别名）；
  6. 输出名 P2_COMPILER_N80_V11（--out 参数保留）。

预期 vs b1regen（v1.0 布局）基线：descriptor_table / k_block_manifest /
oracle_manifest / backend_map 逐字节同；buffer_table 仅 view 16 项别名化
+ 其后非 view 项 base_off 前移；memory_account 水位/arena_total 收缩 +
view_alias_bytes 新账；graph_manifest SHA 重算。mirror_per_conv 逐字节
不变（F9 链不变量：mirror 与布局无关）。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe
     p2_compiler_n80_v11.py --out <run>/out/p2_manifests_n80_v11
"""

import argparse
import collections
import hashlib
import json
import os

HERE = os.path.dirname(os.path.abspath(__file__))
# ROM：n80 量化包为 dryrun_run01 冻结产物（只读），不随本 run 复制。
# M4.2 归位：绝对路径改经 accel_paths 正典（12_yolo_accel 唯一配置入口）。
import sys as _sys                                    # noqa: E402
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in _sys.path:
    _sys.path.insert(0, _ROOT)
import accel_paths as _AP                             # noqa: E402
ROM = _AP.ROM

# ---- 冻结参数（A1.1 / 本编译器设计参数，全部记录进 manifest）----
CMA_WIN_LO = 0x10000000
CMA_WIN_HI = 0x20000000          # ch2 A1.1 物理窗口
ALIGN = 64                       # base 至少 64B 对齐
GUARD = 64                       # 每项前后 guard 区（设计参数，初值 0xA5）
BUF_TABLE_MAX = 128              # A1.1 buffer 表容量
DESC_TABLE_MAX = 128
CANON = {'conv': 63, 'view': 16, 'concat': 13, 'add': 6,
         'maxpool5': 3, 'upsample2': 2, 'heads': 1}

B1_EXTENSION = {'k': 720, 'chain': [720],
                'why': 'nc=80 model.22.cv3.x.1 IC=80*3*3',
                'status': ('BOARD_PROVEN 2026-10-06 R1+R2: '
                           'BOARD_P13_K720_PASS / BOARD_P13_K720_R2_PASS; '
                           'B1 generalized K<=1024 -> [K]')}

SRC_SHA = json.load(open(os.path.join(ROM, 'src_pin.json'), encoding='utf-8'))


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
        if k_real == 720:
            k_blocks[i]['b1_extension'] = (
                'B1_GENERALIZED [720] BOARD_PROVEN 2026-10-06 R1+R2 '
                '(was DRYRUN_HYPOTHESIS [576,144])')

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
        'b1_table': ('frozen (ch2 B1) generalized 2026-10-06: K<=1024 -> [K] '
                     '(k720 plan A board-proven); 1152->[1024,128] / '
                     '2304->[1024,1024,256] unchanged; others E_K_UNSUPPORTED'),
        'b1_extension': B1_EXTENSION,
        'convs': k_blocks})
    shas['oracle_manifest.json'] = dump('oracle_manifest.json', {
        'source': 'G0-N80 = 2026-10-05_yolov8n80_toolchain_dryrun_run01 '
                  'out/quant_n80 golden frame0 (DRYRUN, no board)',
        'rows': oracle_rows})
    shas['backend_map.json'] = dump('backend_map.json', {
        'round': 'N80 dry-run 首轮', 'map': backend})
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
        'plan': 'yolov8_object_hardware_accel_replan_2026-10-05.md M1/M2 dry-run',
        'run': 'm3 manifests v1.1 view-alias regen（inputs from dryrun run01）',
        'tool': 'p2_compiler_n80_v11.py = p2_compiler.py v1.1 拷出适配',
        'date': '2026-10-06', 'dryrun': True,
        'b1_extension': B1_EXTENSION,
        'supersedes': {
            'run': '2026-10-06_yolo_k720_b1_kbm_regen_run01',
            'graph_manifest_sha256':
                '9d915ce13d85d378de3ee14be2527bb5bc866959199f085f3097d5839f2926d9',
            'why': ('v1.0 布局血统 16 view out 独立占位 -> v1.1 父内纯地址'
                    '别名（base+c0·H·W 不新增 DDR，手册 §1/§3/§4.1/§9）；'
                    'graph_exec v1.1 执行法前置拦截（aliased 0/16）')},
        'src_sha': {
            'schedule.json': sha256_file(sched_p),
            'quant.json': sha256_file(quant_p),
            'weights.bin': sha256_file(os.path.join(ROM, 'weights.bin')),
            'bias.bin': sha256_file(os.path.join(ROM, 'bias.bin')),
            'lut.bin': sha256_file(os.path.join(ROM, 'lut.bin'))},
        'fixes': ['v1.0→v1.1: 16 个 view out 由独立占位改为父内纯地址别名'
                  '（base+c0·H·W，不新增 DDR；手册 §1/§3/§4.1/§9 五处明文）',
                  'n80 移植：ROM/SRC_SHA/B1_EXTENSION/溯源（详见卷首 6 差异）'],
        'counts': dict(opcnt), 'n_buffers': len(bufs),
        'arena_total': arena_total, 'heads_size': heads_size,
        'mirror_max': mirror_max, 'margin_ratio': round(margin, 4),
        'sub_manifest_sha256': shas,
        'errors': errs, 'verdict': verdict,
    }
    json.dump(gm, open(os.path.join(args.out, 'graph_manifest.json'), 'w',
                  encoding='utf-8'), indent=1, ensure_ascii=False)

    print('P2_COMPILER_N80_V11 %s' % verdict)
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
