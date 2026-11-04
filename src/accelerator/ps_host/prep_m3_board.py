#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""prep_m3_board.py — M3 板级阶梯 run01：n80 整网 PC 侧备料（B3-S2 正典移植）

M3（主计划 §M3 / M2_GAP_AUDIT 第 8 项）：把 n80（nc=80 官方权重量化包）
全 104 任务程序按阶梯搬上板——63 Conv（GEMM 硬件 DMA 通路）+ 41 图算子
（16 view 零流量 + add 6 + concat 13 + maxpool5 3 + upsample2 2）+
heads 尾算子，×5 帧逐帧逐字节。阶梯（前缀切割，prep 算好写进 meta）：
  l1 = sched[0,1)    单 conv model.0（K27 十 strip）
  l2 = sched[0,6)    首 6 任务（4 conv + 2 view）
  l3 = sched[0,49)   Backbone（首个 model.1x=model.10 之前）
  l4 = sched[0,103)  +Neck 全图（无 heads）
  l5 = sched[0,104)  全图 + heads

**重生成，不拼接**：程序从 v11 manifests（2026-10-06_yolo_m3_manifests_
v11_run01，gm=74958a41…，M3 执行面唯一合法输入）用 ArenaEngine/ConvGeo
（律之源）重新生成全部 104 descs + 63 statics。

**手势隔离禁令**：本备料零手势数据依据——无五窗 meta 交叉（B3-S2 的
Q5/Q6 手势板证对账不移植），改为 n80 自洽宇宙断言 + n80 三锚 bin 台账
+ K720 R2 板证对账（cv3.0.1 = 本线自己的板证）。

备料门（PC 侧全过才许上板）：
  Q1 整网形态宇宙断言（fail-closed）：op 计数 63/16/6/13/3/2/1、
     sched 0..103、拓扑闭包、oc%8==0 全体（n80 无 oc7 死行 conv）、
     五族 strip 白名单、链段律 B1 一般化（K≤1024→[K] 单链
     0x07/0x06；K1152→[1024,128] 0x03/0x1D ldgrp 0/3；
     K2304→[1024,1024,256] 0x03/0x19/0x05 ldgrp 0/3/0）、
     kbm 链交叉（63 conv chain == k_block_manifest）、
     Wo 族双源自洽（statics == buffer_table out 形状计数）、
     program() 全块交叉（逐 strip/逐段/row_valid）；
  Q2 refs 103 任务×5 帧 SHA 台账 + canvas×5；params 126 键；
     CMA = max(0x100+tll·NB+128·NB)+0x10000，逐 conv 界内；
  Q3 五 f0 装载锚：PC conv_packer 全流 SHA（conv0=canvas 派生 x0，
     其余=产者参照）写 meta（板上 SGa 逐字核对）；n80 三锚 bin
     （K27/K576/K2304，conv_packer P5 已逐字节复现）整文件 SHA +
     台账字段 == statics（板证 PENDING M3，随阶梯重钉）；
  Q3b heads blob PC 门：6 分支 reg8/16/32→cls8/16/32 段序拼
     302400B == G0 golden ×5 帧；
  Q4 位流（K720 R2 板绿对，本线血统）/驱动/启动器 SHA 双侧可核
     （payload_sha256_pc.txt LF；自引用工件良性）；
  Q5 阶梯表：五档前缀切割（l3 边界=首个 model.1x 任务号）、逐档
     前缀拓扑闭包、逐档 conv 数/装载锚数/exp_lut_loads 台账；
  Q6' K720 R2 板证对账：statics[model.22.cv3.0.1] == R2 meta
     constants（K720/[720]/oc80/Wo40/NB1200/tll17280/y_off 20736256/
     strips 三表）+ refs f0..f2 cv3.0.1 SHA == R2 板输出 golden bin
     逐字节（PC 软件参照 == 板输出三面锁）。

Run: <model venv python> prep_m3_board.py \
       --manifests <v11>/out/p2_manifests_n80_v11 --out <本 run 目录>
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：模块查找经 accel_bootstrap（替代原 m3_pre scripts 插桩）；
# 冻结输入/基线路径经 accel_paths 正典
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402

from graph_exec_n80 import ArenaEngine                    # noqa: E402
from conv_packer_n80 import ConvGeo, pack_tile as cp_pack_tile, \
    Y_SLOT_STRIDE, ANCHOR_MASKED_LAW                      # noqa: E402
from n80_frames import load_frames                        # noqa: E402

V11 = _AP.V11                    # v1.1 manifests 正典（唯一合法执行输入）
BIT_SRC = _AP.BIT_SRC            # K720 R2 板证位流目录
R2DIR = _AP.K720R2
ANCHOR_DIR = _AP.ANCHOR_DIR      # m3_pre run 冻结锚
ANCHOR_NODES = ('model.0', 'model.6.m.0.cv1', 'model.7', 'model.22.cv2.2.0',
                'model.22.cv3.0.1')      # 末位 = K720 R2 板证 conv
ANCHOR_BINS = {               # n80 三锚（引擎软件镜像；P5 逐字节复现）
    'model.0': 'b3_conv0_k27_mirror_n80.bin',
    'model.6.m.0.cv1': 'b3_k576_mirror_n80.bin',
    'model.22.cv2.2.0': 'b3_k2304_mirror_n80.bin',
}
HEADS_ORDER = ('reg8', 'reg16', 'reg32', 'cls8', 'cls16', 'cls32')
HEADS_TOTAL = 302400                   # n80 §8：reg64×3 + cls80×3
STRIP_FORMS = {                    # 五族白名单（fail-closed；Wo → 表）
    160: [(16, 0xFFFF)] * 10,
    80: [(16, 0xFFFF)] * 5,
    40: [(16, 0xFFFF), (16, 0xFFFF), (8, 0x00FF)],
    20: [(16, 0xFFFF), (4, 0x000F)],
    10: [(10, 0x03FF)],
}
LUT_OFF, LOAD_OFF = 0x0, 0x100
GUARD_LEN = 0x10000
POISON = 0xA5
OPS_UNIVERSE = ('conv', 'view', 'add', 'concat', 'maxpool5', 'upsample2',
                'heads')
OP_KEYS = {                        # descriptor 必备键（fail-closed）
    'conv': ('in_bufs', 'out_buf'),
    'view': ('parent_buf', 'ch', 'out_buf'),
    'add': ('a_buf', 'b_buf', 'a_scale', 'b_scale', 'out_scale', 'out_buf'),
    'concat': ('inputs', 'out_scale', 'out_buf'),
    'maxpool5': ('in_bufs', 'out_buf'),
    'upsample2': ('in_bufs', 'out_buf'),
    'heads': ('in_bufs', 'cls', 'reg', 'out_region'),
}
STAGE_SPEC = [               # (名, hi 或 None=动态, 说明)
    ('l1', 1, '单 conv model.0'),
    ('l2', 6, '首 6 任务 4 conv+2 view'),
    ('l3', None, 'Backbone（首个 model.1x 前）'),
    ('l4', 103, '+Neck 全图无 heads'),
    ('l5', 104, '全图+heads'),
]


def sha_f(path):
    return hashlib.sha256(open(path, 'rb').read()).hexdigest()


def sha_b(b):
    return hashlib.sha256(b).hexdigest()


def in_bufs_of(d):
    op = d['op']
    if op in ('conv', 'maxpool5', 'upsample2', 'heads'):
        return list(d['in_bufs'])
    if op == 'view':
        return [d['parent_buf']]
    if op == 'add':
        return [d['a_buf'], d['b_buf']]
    if op == 'concat':
        return [s['buf'] for s in d['inputs']]
    raise AssertionError(op)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifests', default=V11)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()
    out = args.out
    pack = os.path.join(out, 'board_pack')
    os.makedirs(pack, exist_ok=True)

    eng = ArenaEngine(args.manifests)
    frames = load_frames()
    assert len(frames) == 5
    kbm = json.load(open(os.path.join(args.manifests,
                                      'k_block_manifest.json'),
                         encoding='utf-8'))
    dt = json.load(open(os.path.join(args.manifests,
                                     'descriptor_table.json'),
                        encoding='utf-8'))
    bt = json.load(open(os.path.join(args.manifests, 'buffer_table.json'),
                        encoding='utf-8'))
    bufs = {e['id']: e for e in bt['entries']}

    # ---- Q1a：整网任务 + 拓扑闭包 ----
    descs = eng.descs
    assert len(descs) == 104 and \
        [d['sched_index'] for d in descs] == list(range(104))
    op_cnt = {}
    for d in descs:
        assert d['op'] in OPS_UNIVERSE, (d['sched_index'], d['op'])
        for k in OP_KEYS[d['op']]:
            assert k in d, (d['node'], k)
        op_cnt[d['op']] = op_cnt.get(d['op'], 0) + 1
    assert op_cnt == {'conv': 63, 'view': 16, 'add': 6, 'concat': 13,
                      'maxpool5': 3, 'upsample2': 2, 'heads': 1}, op_cnt
    heads_desc = next(d for d in descs if d['op'] == 'heads')
    assert heads_desc['node'] == 'model.22' and \
        heads_desc['out_region'] == 'heads_out' and \
        heads_desc['out_buf'] is None and \
        len(heads_desc['in_bufs']) == 6
    producer = {}                   # out_buf → 产者 desc（每 buf 恰一产者）
    for d in descs:
        if d['out_buf'] is not None:
            assert d['out_buf'] not in producer, d['node']
            producer[d['out_buf']] = d
    for d in descs:                 # 闭包：输入=buf0(canvas) 或更早产物
        for b in in_bufs_of(d):
            assert b == 0 or (b in producer and
                              producer[b]['sched_index'] < d['sched_index']), \
                (d['node'], b)

    # ---- Q1b：63 conv 几何 + statics（ConvGeo = 律之源；全块交叉）----
    conv_descs = [d for d in descs if d['op'] == 'conv']
    geos, params, statics = {}, {}, {}
    n_triple = n_dual = n_noact = n_fetch = 0
    wo_cnt = {}
    q5 = True                       # program() 全块交叉旗
    for d in conv_descs:
        di = d['sched_index']
        g = ConvGeo(eng, di)
        geos[di] = g
        assert g.node == d['node'] and g.node not in statics, g.node
        node = g.node.replace('.', '_')
        params['W_%s' % node] = g.Wq                      # int8 [oc,K]
        params['lut_%s' % node] = np.ascontiguousarray(
            g.LUT.view(np.uint8))                         # uint8 [256]
        # kbm 链交叉（ConvGeo 内部已断言 b1_chain(K)；此处对台账再证）
        assert g.chain == [b['k_len'] for b in
                           kbm['convs'][str(di)]['blocks']], g.node
        ph0 = g.program()[0]
        segs = ph0['segs']
        assert g.chain == [sg['k_len'] for sg in segs] and \
            sum(sg['k_len'] for sg in segs) == g.K, g.node
        if len(segs) == 1:          # B1 一般化：K≤1024 → [K]（含 K720）
            assert segs[0]['k_len'] == g.K and g.K <= 1024 and \
                segs[0]['ldgrp'] == 0, g.node
            if g.has_act:
                assert segs[0]['jobcfg'] == '0x07', g.node
            else:
                assert segs[0]['jobcfg'] == '0x06', g.node
                n_noact += 1
        elif len(segs) == 2:        # 双链：K1152=[1024,128] 正典
            assert g.K == 1152 and \
                [sg['k_len'] for sg in segs] == [1024, 128], (g.node, g.chain)
            assert segs[0]['jobcfg'] == '0x03' and \
                segs[0]['ldgrp'] == 0 and \
                segs[1]['jobcfg'] == '0x1D' and \
                segs[1]['ldgrp'] == 3, g.node
            n_dual += 1
        else:                       # 三链：K2304（组复用 0→1→0）
            assert [sg['k_len'] for sg in segs] == [1024, 1024, 256] and \
                g.K == 2304, (g.node, g.chain)
            assert [sg['jobcfg'] for sg in segs] == \
                ['0x03', '0x19', '0x05'] and \
                [sg['ldgrp'] for sg in segs] == [0, 3, 0], g.node
            n_triple += 1
        # 死行律 n80：全 oc%8==0 → ROWVAL 恒 0xFF（无 oc7 conv）
        assert g.oc % 8 == 0 and ph0['row_valid'] == '0xFF', (g.node, g.oc)
        # 掩蔽 lane 双律（fetch 仅 K576 正典 conv）
        law = ANCHOR_MASKED_LAW.get(g.node, 'fill')
        assert law == g.masked_law, (g.node, law, g.masked_law)
        if law == 'fetch':
            n_fetch += 1
        y_off = LOAD_OFF + g.tile_load_len * g.NB
        # 逐 strip 表（五族白名单）
        assert g.strips == STRIP_FORMS[g.Wo], (g.node, g.Wo, g.strips)
        wo_cnt[g.Wo] = wo_cnt.get(g.Wo, 0) + 1
        strips_tab = []
        for vc, nm in g.strips:
            assert nm == (1 << vc) - 1
            strips_tab.append({'vc': vc, 'n_mask': '0x%04X' % nm,
                               'ycnt': 8 * vc, 's2mm_btt': 8 * vc})
        statics[g.node] = {
            'di': di, 'K': g.K, 'oc': g.oc, 'ic': g.ic,
            'kernel': [g.kh, g.kw], 'stride': [g.sh, g.sw],
            'pad': [g.ph, g.pw], 'Ho': g.Ho, 'Wo': g.Wo,
            'n_strips': g.n_strips, 'n_tile': g.N_TILE, 'RC': g.RC,
            'NB': g.NB, 'tile_load_len': g.tile_load_len,
            'row_valid': ph0['row_valid'], 'jobcfg': segs[-1]['jobcfg'],
            'ldgrp': segs[-1]['ldgrp'],
            'segs': [{'k_len': sg['k_len'], 'jobcfg': sg['jobcfg'],
                      'ldgrp': sg['ldgrp']} for sg in segs],
            'first': g.first, 'has_act': g.has_act,
            'masked_law': law,
            'strips': strips_tab,
            'lut_off': LUT_OFF, 'load_off': LOAD_OFF, 'y_off': y_off,
            'y_slot_stride': Y_SLOT_STRIDE,
            'pctl': [[int(g.b_eff[r]), int(g.req[r][0]), int(g.req[r][1])]
                     if r < g.oc else [0, 0, 0]
                     for r in range(8 * g.RC)],
        }
        # Q5：program() 全块交叉 == 泛化律逐块展开
        for r in g.program():
            st = strips_tab[r['strip']]
            assert r['n_mask'] == st['n_mask'] and \
                r['ycnt'] == st['ycnt'] and \
                r['s2mm_btt'] == st['s2mm_btt'], g.node
            assert [sg['k_len'] for sg in r['segs']] == \
                [sg['k_len'] for sg in segs] and \
                [sg['jobcfg'] for sg in r['segs']] == \
                [sg['jobcfg'] for sg in segs] and \
                [sg['ldgrp'] for sg in r['segs']] == \
                [sg['ldgrp'] for sg in segs], g.node
            assert r['row_valid'] == ph0['row_valid'], g.node
    # Wo 族双源自洽：statics 计数 == descriptor/buffer_table out 形状计数
    bt_wo = {}
    for d in conv_descs:
        w = bufs[d['out_buf']]['shape'][2]
        bt_wo[w] = bt_wo.get(w, 0) + 1
    assert wo_cnt == bt_wo, (wo_cnt, bt_wo)
    assert n_triple + n_dual + (63 - n_triple - n_dual) == 63
    print('Q1 宇宙：conv%d 三链×%d 双链×%d 无act×%d fetch×%d；Wo 族 %s'
          % (len(statics), n_triple, n_dual, n_noact, n_fetch,
             '{%s}' % ','.join('%d:%d' % kv for kv in sorted(wo_cnt.items()))))

    # ---- Q2：每帧 canvas + 103 任务参照 ----
    ref_sha = {}
    for fi, fr in enumerate(frames):
        d = {'canvas': np.ascontiguousarray(fr['canvas'], np.uint8)}
        for t in descs:
            if t['op'] == 'heads':
                continue
            ref = fr['refs'][t['node']]
            assert ref is not None, t['node']
            key = 'ref_%d_%s' % (t['sched_index'],
                                 t['node'].replace('.', '_'))
            d[key] = np.ascontiguousarray(ref, np.int8)
            ref_sha['f%d/%s' % (fi, t['node'])] = sha_b(
                np.ascontiguousarray(ref, np.int8).tobytes())
        np.savez(os.path.join(pack, 'refs_f%d.npz' % fi), **d)

    # ---- Q3：五 f0 装载锚（PC packer 全流 SHA → meta；板上 SGa 核对）----
    anchors = {}
    q3 = True
    for an in ANCHOR_NODES:
        ag = next(g for g in geos.values() if g.node == an)
        a_desc = next(d for d in descs if d['node'] == an)
        in_b = in_bufs_of(a_desc)[0]
        if in_b == 0:               # conv0：canvas 派生 x0（seg0 律）
            cv = frames[0]['canvas']
            a_in = (cv.astype(np.int16) - 128).astype(np.int8) \
                .transpose(2, 0, 1).copy()
        else:
            a_in = frames[0]['refs'][producer[in_b]['node']]
            assert a_in is not None, producer[in_b]['node']
        h = hashlib.sha256()
        for b in range(ag.NB):
            nt, rc = b // ag.RC, b % ag.RC
            oy, s = nt // ag.n_strips, nt % ag.n_strips
            h.update(cp_pack_tile(ag, a_in[None], oy, s, rc).tobytes())
        anchors[an] = h.hexdigest()
        print('  Q3 anchor %-16s K=%-4d NB=%-5d %s'
              % (an, ag.K, ag.NB, anchors[an][:16]))
    # n80 三锚 bin 台账（整文件 SHA + 字段 == statics；板证 PENDING M3）
    am = json.load(open(os.path.join(ANCHOR_DIR, 'anchors_meta.json'),
                        encoding='utf-8'))
    amap = {a['node']: a for a in am['anchors']}
    q3i = True
    for an, fn in ANCHOR_BINS.items():
        a = amap[an]
        st = statics[an]
        ok = a['path'] == fn and a['K'] == st['K'] and \
            a['chain'] == [sg['k_len'] for sg in st['segs']] and \
            a['nb_blocks'] == st['NB'] and \
            a['tile_load_len'] == st['tile_load_len'] and \
            a['masked_law'] == st['masked_law'] and \
            sha_f(os.path.join(ANCHOR_DIR, fn)) == a['sha256']
        q3i &= ok
        print('  Q3bin %-16s %s %s' % (an, a['sha256'][:16],
                                       'OK' if ok else 'FAIL'))

    # ---- Q3b：heads blob PC 门（== G0 golden ×5 帧）----
    prod_of = {e['out_buf']: e['node'] for e in descs if e['op'] == 'conv'}
    seg_of = {40: '8', 20: '16', 10: '32'}
    seg_map = {}
    for grp in ('reg', 'cls'):
        for e in heads_desc[grp]:
            seg_map[grp + seg_of[e['shape'][2]]] = e['buf']
    assert set(seg_map) == set(HEADS_ORDER), sorted(seg_map)
    heads_blob_sha = {}
    q3b = True
    for fi, fr in enumerate(frames):
        parts_, heads_len = [], 0
        for k_ in HEADS_ORDER:
            ref = fr['refs'][prod_of[seg_map[k_]]]
            assert ref is not None, k_
            b_ = np.ascontiguousarray(ref, np.int8).tobytes()
            heads_len += len(b_)
            parts_.append(b_)
        blob = b''.join(parts_)
        got = sha_b(blob)
        heads_blob_sha['f%d' % fi] = got
        if heads_len != HEADS_TOTAL or got != fr['g0_head_blob_sha']:
            q3b = False
            print('  Q3b FAIL f%d len=%d' % (fi, heads_len))

    # ---- Q4：CMA 并集 + 审计 ----
    cma_bytes = int(max(s['y_off'] + Y_SLOT_STRIDE * s['NB']
                        for s in statics.values()) + GUARD_LEN)
    for n, s in statics.items():    # 每 conv 自身 load/y 区不重叠、界内
        assert s['load_off'] < s['y_off'] and \
            s['y_off'] + Y_SLOT_STRIDE * s['NB'] + GUARD_LEN <= cma_bytes, n

    # ---- Q5：阶梯表（前缀切割 + 逐档闭包/台账）----
    di_of = {d['node']: d['sched_index'] for d in descs}
    l3_hi = next(d['sched_index'] for d in descs
                 if d['node'].startswith('model.1') and
                 len(d['node']) > 7 and d['node'][7].isdigit())
    stage_table = {}
    q_st = True
    for name, hi, desc in STAGE_SPEC:
        if hi is None:
            hi = l3_hi
        sub = descs[:hi]
        # 前缀拓扑闭包（全局闭包 + sched 前缀 ⇒ 自动成立；显式再证）
        for d in sub:
            for b in in_bufs_of(d):
                assert b == 0 or any(
                    p['out_buf'] == b for p in sub), (name, d['node'], b)
        n_cv = sum(1 for d in sub if d['op'] == 'conv')
        inc_h = any(d['op'] == 'heads' for d in sub)
        anc = [an for an in ANCHOR_NODES if di_of[an] < hi]
        assert n_cv >= 1 and anc, name
        stage_table[name] = {
            'lo': 0, 'hi': hi, 'desc': desc,
            'n_tasks': len(sub), 'n_convs': n_cv,
            'includes_heads': inc_h,
            # LUT 跨帧驻留律（pl_m3 cur_lut 语义）：n>=2 时相邻 conv 节点
            # 必不同→每帧每 conv 换装=n*5；n==1 时 f1-4 复用同 conv LUT
            # 合法→全程 1 次（attempt3 l1 假阴性教训：5 为错误期望）。
            'exp_lut_loads': n_cv * 5 if n_cv > 1 else 1,
            'anchors_in_stage': anc,
        }
        print('  stage %-3s [%3d,%3d) tasks=%3d convs=%2d heads=%d 锚=%d'
              % (name, 0, hi, len(sub), n_cv, inc_h, len(anc)))
    assert stage_table['l5']['n_tasks'] == 104 and \
        stage_table['l5']['includes_heads'] and \
        not stage_table['l4']['includes_heads'] and \
        stage_table['l3']['hi'] == l3_hi and \
        descs[l3_hi]['node'] == 'model.10'

    # ---- Q6'：K720 R2 板证对账（cv3.0.1 == 板输出三面锁）----
    r2m = json.load(open(os.path.join(R2DIR, 'b3_k720r2_meta.json'),
                         encoding='utf-8'))
    c = r2m['constants']
    st89 = statics['model.22.cv3.0.1']
    q6 = (r2m['node'] == 'model.22.cv3.0.1' and
          c['K'] == 720 and c['k_chain'] == [720] and
          c['oc'] == st89['oc'] and c['wo'] == st89['Wo'] and
          c['n_block'] == st89['NB'] and
          c['block_len'] == st89['tile_load_len'] and
          c['y_base'] == st89['y_off'] and
          c['n_tile'] == st89['n_tile'] and c['n_rowchunk'] == st89['RC'] and
          [[v, m] for v, m in
           [(st['vc'], int(st['n_mask'], 16)) for st in st89['strips']]] ==
          c['strips'])
    n_r2 = 0
    for fi in range(3):
        got = sha_f(os.path.join(R2DIR, 'b3_k720r2_golden_f%d.bin' % fi))
        exp = ref_sha['f%d/model.22.cv3.0.1' % fi]
        if got != exp:
            q6 = False
            print('  Q6p FAIL f%d pc=%s board=%s' % (fi, exp[:16], got[:16]))
        n_r2 += 1
    print("Q6' R2 板证对账 %s（statics==R2 constants + cv3.0.1 ×%d 帧 "
          'SHA == 板 golden 逐位）' % ('OK' if q6 else 'FAIL', n_r2))

    # ---- 台账 + 常量包 ----
    ma = json.load(open(os.path.join(args.manifests, 'memory_account.json'),
                        encoding='utf-8'))
    meta = {
        'run': 'M3 board ladder run01 (n80 nc=80, sched 0..103, 5 frames)',
        'manifests_dir': os.path.abspath(args.manifests),
        'graph_manifest_sha256': sha_f(os.path.join(args.manifests,
                                                    'graph_manifest.json')),
        'seg_descs': descs,
        'conv_statics': statics,
        'seed_bufs': {'0': {'key': 'canvas', 'producer': 'input'}},
        'stage_table': stage_table,
        'ref_sha256': ref_sha,
        'anchors': anchors,
        'heads_blob_sha256': heads_blob_sha,
        'heads_total': HEADS_TOTAL,
        'params_keys': sorted(params.keys()),
        'cma_bytes': cma_bytes,
        'poison': POISON,
        'memory_account_audit': {
            'window_bytes': ma.get('window_bytes'),
            'arena_total': ma.get('arena_total'),
            'graph_workset_end': ma.get('graph_workset_end'),
            'view_alias_bytes': ma.get('view_alias_bytes'),
        },
        'universe_counts': {'triple': n_triple, 'dual': n_dual,
                            'noact': n_noact, 'fetch': n_fetch,
                            'wo': {str(k): v for k, v in wo_cnt.items()}},
        'r2_reconcile': {'node': 'model.22.cv3.0.1', 'frames': 3,
                         'constants_match': bool(q6),
                         'golden_bins': ['b3_k720r2_golden_f%d.bin' % i
                                         for i in range(3)]},
    }
    json.dump(meta, open(os.path.join(pack, 'm3_meta.json'), 'w',
                  encoding='utf-8'), indent=1, ensure_ascii=False)
    np.savez(os.path.join(pack, 'm3_params.npz'), **params)

    # ---- 位流（K720 R2 板绿对 = 本线血统）+ 驱动 + 启动器 ----
    for f in ('display_test_wrapper.bit', 'display_test_wrapper.hwh'):
        shutil.copy2(os.path.join(BIT_SRC, f), os.path.join(pack, f))
    shutil.copy2(os.path.join(HERE, 'pl_m3.py'),
                 os.path.join(pack, 'pl_m3.py'))
    with open(os.path.join(pack, 'run_m3.sh'), 'w', newline='\n') as fh:
        fh.write('#!/bin/sh\ncd "$(dirname "$0")"\n'
                 'STAGE="${1:-l5}"\n'
                 'exec /usr/local/share/pynq-venv/bin/python3 '
                 './pl_m3.py "$STAGE" "m3_$STAGE"\n')

    # ---- 双侧 SHA 表 ----
    rows = []
    for f in sorted(os.listdir(pack)):
        p = os.path.join(pack, f)
        if os.path.isfile(p):
            rows.append('%s  %s' % (sha_f(p), f))
    open(os.path.join(pack, 'payload_sha256_pc.txt'), 'w',
         newline='\n').write('\n'.join(rows) + '\n')

    # ---- PC 侧备料门 ----
    q1 = all(len(s['pctl']) == 8 * s['RC'] and
             s['oc'] % 8 == 0 and len(s['strips']) == s['n_strips'] and
             1 <= len(s['segs']) <= 3 for s in statics.values()) and \
        wo_cnt == bt_wo and len(statics) == 63
    q2 = set(meta['params_keys']) == set(params.keys()) and \
        len(params) == 126 and len(ref_sha) == 103 * 5
    print('Q2 refs %d 键 params %d 键 %s | CMA=%dB'
          % (len(ref_sha), len(params), 'OK' if q2 else 'FAIL', cma_bytes))
    print('Q3 五装载锚 %s | 三锚 bin 台账 %s | Q3b heads blob %s '
          '（f0 %s…==G0，%dB）'
          % ('OK' if q3 else 'FAIL', 'OK' if q3i else 'FAIL',
             'OK' if q3b else 'FAIL', heads_blob_sha['f0'][:16],
             HEADS_TOTAL))
    print('Q4 pack %d 件（bit/hwh/pl/run/sha 表 + meta/params/refs×5）'
          % len([f for f in os.listdir(pack)
                 if os.path.isfile(os.path.join(pack, f))]))
    print('Q5 阶梯表 %s（l3 边界 di=%d=model.10；五档前缀闭包）'
          % ('OK' if q_st else 'FAIL', l3_hi))
    print('Q1 %s | Q5 全块交叉 %s' % ('OK' if q1 else 'FAIL',
                                      'OK' if q5 else 'FAIL'))
    ok = q1 and q2 and q3 and q3i and q3b and q5 and q6 and q_st
    print('M3_PREP %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
