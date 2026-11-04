#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""rehearse_m3_driver.py — M3 n80 整网驱动律的 PC 侧彩排（上板前门）

pl_m3.py 自包含（律=重打字，非导入）。按 Y_OFF 转录教训，上板前必须
证明驱动自己的律 == conv_packer_n80 泛化律 == n80 正典字节：

  R1 载荷字节：驱动 pack_tile 装载流 SHA == conv_packer_n80.pack_tile
     同帧同 conv 装载流 SHA（63 conv × 5 帧 = 315 流，逐字节；
     'fill'+'fetch' 双律、五 strip 族混布、单（含 K720）/双/三链段、
     死行 W 补 0；数据流=refs 喂进 + canvas 派生 x0，与板上同律）；
  R2 gather：驱动 gather 律（槽→[oc,Ho,Wo]，rows=min(8,oc-8rc)）对
     n80 参照槽↔平面往返——八例（形态各一）：model.0（Wo=160 十
     strip）、首 Wo=80 conv、model.6.m.0.cv1（fetch K576）、model.7
     （K1152 'fill' 双链）、model.19（双链）、model.22.cv2.0.0（Wo=40
     三 strip）、model.22.cv2.2.0（三链 K2304）、model.22.cv3.2.2
     （Wo=10 单 strip；n80 无 oc7）；
  R3 全软件走图 ×5 帧：41 图算子按驱动律重打字执行（view 切片零流量/
     add 双尺度 rne/concat 逐入重标/maxpool5/upsample2/heads 6 分支
     段序拼包 302400B），逐任务 == G0 参照 nerr==0；heads blob ==
     meta == G0 ×5；
  R4 驱动台账：Geo 构建断言（63 节点全过）+ 静态交叉（NB/tll/逐
     strip 表/链段表/死行律/jobcfg/y_off/Wq/LUT/pctl/masked_law vs
     conv_packer_n80 ConvGeo）+ 五 f0 装载锚（packer 全流 == meta；
     三锚 bin 整文件 SHA == anchors_meta 台账）+ 阶梯表五档前缀
     闭包/计数/锚分布 + CMA 审计 + params 126 键 + Q6' 复核
     （cv3.0.1 refs f0..f2 == K720 R2 板 golden 逐位）。

Run: <model venv python> rehearse_m3_driver.py <本 run 目录>
"""

from __future__ import annotations

import hashlib
import io
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：模块查找经 accel_bootstrap（替代原 m3_pre scripts + 本目录
# 插桩；pl_m3 同在 ps_host，bootstrap 覆盖）
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402

_run_arg = sys.argv[1] if len(sys.argv) > 1 else None
sys.argv = [sys.argv[0], 'l5']      # 彩排按最大档 l5 导入驱动（板上
# pl_m3.py 的严格档断言不受此影响）
import pl_m3 as DRV                               # 板上驱动（被彩排件）
from graph_exec_n80 import ArenaEngine            # noqa: E402
from conv_packer_n80 import ConvGeo, pack_tile as REF_PACK   # noqa: E402
from n80_frames import load_frames                # noqa: E402

R2DIR = _AP.K720R2
ANCHOR_DIR = _AP.ANCHOR_DIR      # m3_pre run 冻结锚
ANCHOR_BINS = {
    'model.0': 'b3_conv0_k27_mirror_n80.bin',
    'model.6.m.0.cv1': 'b3_k576_mirror_n80.bin',
    'model.22.cv2.2.0': 'b3_k2304_mirror_n80.bin',
}
HEADS_ORDER = ('reg8', 'reg16', 'reg32', 'cls8', 'cls16', 'cls32')
LOAD_OFF, GUARD_LEN = 0x100, 0x10000


def sha_b(b):
    return hashlib.sha256(b).hexdigest()


def sha_f(p):
    return hashlib.sha256(open(p, 'rb').read()).hexdigest()


def gather_roundtrip(geo_d, y_ref):
    """R2：参照平面 → 槽字节流（驱动紧凑律 byte=r*vc+cv）→ 驱动 gather
    律还原 → 与参照逐位。逐 strip vc 取块/取长。"""
    assert y_ref.shape[0] == geo_d.oc
    slots = np.full(geo_d.stride_slot * geo_d.NB, 0xA5, np.uint8)
    for b in range(geo_d.NB):
        nt, rc = b // geo_d.RC, b % geo_d.RC
        oy, s = nt // geo_d.n_strips, nt % geo_d.n_strips
        vc = geo_d.vc_of(s)
        rows = min(8, geo_d.oc - 8 * rc)
        blk = y_ref[8 * rc:8 * rc + rows, oy, 16 * s:16 * s + vc]
        slots[geo_d.stride_slot * b:
              geo_d.stride_slot * b + rows * vc] = \
            np.ascontiguousarray(blk).reshape(-1)
    y_back = np.empty((geo_d.oc, geo_d.Ho, geo_d.Wo), dtype=np.uint8)
    for b in range(geo_d.NB):
        nt, rc = b // geo_d.RC, b % geo_d.RC
        oy, s = nt // geo_d.n_strips, nt % geo_d.n_strips
        vc = geo_d.vc_of(s)
        rows = min(8, geo_d.oc - 8 * rc)
        slot = slots[geo_d.stride_slot * b:
                     geo_d.stride_slot * b + 8 * vc]
        y_back[8 * rc:8 * rc + rows, oy, 16 * s:16 * s + vc] = \
            slot[:rows * vc].reshape(rows, vc)
    return np.array_equal(y_back.view(np.int8), y_ref)


def main():
    run_dir = _run_arg if _run_arg is not None else \
        os.path.join(WT, '4_metrics', 'logs', '2026-10-06_yolo_m3_board_run01')
    meta = json.load(io.open(os.path.join(run_dir, 'board_pack',
                                          'm3_meta.json'),
                             encoding='utf-8'))
    P = dict(np.load(os.path.join(run_dir, 'board_pack',
                                  'm3_params.npz')))
    eng = ArenaEngine(meta['manifests_dir'])
    frames = load_frames()
    descs = meta['seg_descs']
    assert DRV.STAGE == 'l5'                  # 彩排按最大档导入（默认档）

    # Geo 构建全过（R4 前半：驱动侧断言不爆——五族 strip+单双三链段+
    # 死行律 n80+双掩蔽律内洽）
    geos = {n: DRV.Geo(n, s, P) for n, s in meta['conv_statics'].items()}
    conv_di = [d['sched_index'] for d in descs if d['op'] == 'conv']
    ref_geos = {di: ConvGeo(eng, di) for di in conv_di}
    by_node = {g.node: g for g in ref_geos.values()}
    assert set(geos) == set(by_node) and len(geos) == 63

    # ---- R4a：静态交叉（63 节点台账 vs conv_packer_n80 ConvGeo）----
    xstat = True
    for n, dg in geos.items():
        rg = by_node[n]
        if not (dg.NB == rg.NB and dg.tll == rg.tile_load_len and
                dg.n_strips == rg.n_strips and
                [st['vc'] for st in dg.strips_tab] ==
                [vc for vc, _ in rg.strips] and
                [int(st['n_mask'], 16) for st in dg.strips_tab] ==
                [nm for _, nm in rg.strips] and
                all(dg.ycnt_of(s) == 8 * rg.strips[s][0] and
                    dg.btt_of(s) == 8 * rg.strips[s][0] and
                    dg.nmask_of(s) == rg.strips[s][1]
                    for s in range(rg.n_strips)) and
                dg.row_valid == int(rg.program()[0]['row_valid'], 16) and
                [sg['k_len'] for sg in dg.segs] == rg.chain and
                all(sg['jobcfg'] == pr['jobcfg'] and
                    sg['ldgrp'] == pr['ldgrp']
                    for sg, pr in zip(dg.segs, rg.program()[0]['segs'])) and
                dg.y_off == 0x100 + rg.tile_load_len * rg.NB and
                dg.masked_law == rg.masked_law and
                np.array_equal(dg.Wq, rg.Wq.astype(np.int8)) and
                np.array_equal(dg.lut, rg.LUT.view(np.uint8)) and
                all(dg.pctl[r][0] == int(rg.b_eff[r]) and
                    dg.pctl[r][1] == int(rg.req[r][0]) and
                    dg.pctl[r][2] == int(rg.req[r][1])
                    for r in range(rg.oc))):
            xstat = False
            print('  XSTAT FAIL %s' % n)
    print('R4 静态交叉（63 节点：NB/tll/strip 表/链段表/死行律/law/'
          'Wq/LUT/pctl）%s' % ('OK' if xstat else 'FAIL'))

    # ---- R4b：五 f0 装载锚（packer 全流 == meta）+ 三锚 bin 台账 ----
    producer = {}
    for d in descs:
        if d['out_buf'] is not None:
            producer[d['out_buf']] = d
    am = json.load(io.open(os.path.join(ANCHOR_DIR, 'anchors_meta.json'),
                           encoding='utf-8'))
    amap = {a['node']: a for a in am['anchors']}
    r4a = True
    for an, want in meta['anchors'].items():
        ag = by_node[an]
        a_desc = next(d for d in descs if d['node'] == an)
        in_b = a_desc['in_bufs'][0] if a_desc['op'] == 'conv' else None
        if in_b == 0:
            cv = frames[0]['canvas']
            a_in = (cv.astype(np.int16) - 128).astype(np.int8) \
                .transpose(2, 0, 1).copy()
        else:
            a_in = frames[0]['refs'][producer[in_b]['node']]
        h = hashlib.sha256()
        for b in range(ag.NB):
            nt, rc = b // ag.RC, b % ag.RC
            oy, s = nt // ag.n_strips, nt % ag.n_strips
            h.update(REF_PACK(ag, a_in[None], oy, s, rc).tobytes())
        ok = h.hexdigest() == want
        if an in ANCHOR_BINS:
            ok &= sha_f(os.path.join(ANCHOR_DIR, ANCHOR_BINS[an])) == \
                amap[an]['sha256']
        r4a &= ok
        print('  R4 anchor %-16s %s (%s)'
              % (an, want[:16], 'OK' if ok else 'FAIL'))
    print('R4 五装载锚（packer 全流==meta；三锚 bin==anchors_meta）%s'
          % ('OK' if r4a else 'FAIL'))

    # ---- R4s：阶梯表（五档前缀闭包/计数/锚分布 + l5 边界）----
    def _in_b(d):
        op = d['op']
        if op in ('conv', 'maxpool5', 'upsample2', 'heads'):
            return list(d['in_bufs'])
        if op == 'view':
            return [d['parent_buf']]
        if op == 'add':
            return [d['a_buf'], d['b_buf']]
        return [s['buf'] for s in d['inputs']]     # concat

    r4s = True
    di_of = {d['node']: d['sched_index'] for d in descs}
    for name, e in meta['stage_table'].items():
        sub = descs[e['lo']:e['hi']]
        closed = all(b == 0 or any(p['out_buf'] == b for p in sub)
                     for d in sub for b in _in_b(d))
        anc_ok = all(di_of[an] < e['hi']
                     for an in e['anchors_in_stage']) and \
            e['anchors_in_stage'] == [an for an in meta['anchors']
                                      if di_of[an] < e['hi']]
        ok = closed and anc_ok and e['n_tasks'] == len(sub) and \
            e['n_convs'] == sum(1 for d in sub if d['op'] == 'conv') and \
            e['includes_heads'] == any(d['op'] == 'heads' for d in sub) and \
            e['exp_lut_loads'] == (e['n_convs'] * 5 if e['n_convs'] > 1
                                   else 1)
        r4s &= ok
        if not ok:
            print('  R4s FAIL stage %s' % name)
    assert meta['stage_table']['l3']['hi'] == \
        di_of['model.10'] and \
        meta['stage_table']['l5']['n_tasks'] == 104
    print('R4 阶梯表（五档前缀闭包/计数/锚分布）%s'
          % ('OK' if r4s else 'FAIL'))

    # ---- R4c：CMA 审计 + params 键 ----
    cma = meta['cma_bytes']
    r4c = all(s['load_off'] < s['y_off'] and
              s['y_off'] + s['y_slot_stride'] * s['NB'] + GUARD_LEN <= cma
              for s in meta['conv_statics'].values()) and \
        len(meta['params_keys']) == 126 and \
        set(P.keys()) == set(meta['params_keys'])
    print('R4 CMA 审计+params %s（cma=%dB 126 键）'
          % ('OK' if r4c else 'FAIL', cma))

    # ---- R4r：Q6' 复核（cv3.0.1 == K720 R2 板 golden 逐位 ×3 帧）----
    r4r = True
    for fi in range(3):
        exp = sha_f(os.path.join(R2DIR, 'b3_k720r2_golden_f%d.bin' % fi))
        if meta['ref_sha256']['f%d/model.22.cv3.0.1' % fi] != exp:
            r4r = False
            print('  R4r FAIL f%d' % fi)
    print("R4 K720 R2 板证复核 %s（cv3.0.1 ×3 帧 refs==板 golden）"
          % ('OK' if r4r else 'FAIL'))

    # ---- R1：315 载荷流（驱动律 == conv_packer_n80 泛化律）----
    r1 = True
    n_conv = 0
    for fi, fr in enumerate(frames):
        fdata = dict(np.load(os.path.join(
            run_dir, 'board_pack', 'refs_f%d.npz' % fi)))
        cv = fdata['canvas']
        x0 = (cv.astype(np.int16) - 128).astype(np.int8) \
            .transpose(2, 0, 1).copy()
        tensors = {0: x0}
        for td in descs:
            key = 'ref_%d_%s' % (td['sched_index'],
                                 td['node'].replace('.', '_'))
            if td['op'] == 'conv':
                dg = geos[td['node']]
                rg = by_node[td['node']]
                x_in = tensors[td['in_bufs'][0]]
                x1 = x_in[None]                 # [1,C,H,W]
                h_drv = hashlib.sha256()
                h_ref = hashlib.sha256()
                for b in range(dg.NB):
                    nt, rc = b // dg.RC, b % dg.RC
                    oy, s = nt // dg.n_strips, nt % dg.n_strips
                    h_drv.update(DRV.pack_tile(dg, x_in, oy, s,
                                               rc).tobytes())
                    h_ref.update(REF_PACK(rg, x1, oy, s, rc).tobytes())
                if h_drv.hexdigest() != h_ref.hexdigest():
                    r1 = False
                    print('  R1 FAIL %s f%d' % (td['node'], fi))
                n_conv += 1
            if td['op'] != 'heads':
                tensors[td['out_buf']] = fdata[key]   # 喂参照，链路推进
    print('R1 驱动载荷字节==conv_packer_n80 泛化律（63 conv×5 帧=%d 流；'
          'fill/fetch 双律、五 strip 族、单[含 K720]/双/三链、死行 W 补 0）'
          '%s' % (n_conv, 'OK' if r1 else 'FAIL'))

    # ---- R2：gather 形律——八例（五 strip 族+双掩蔽律+三链段）----
    wo80 = next(n for n, s in sorted(meta['conv_statics'].items(),
                                     key=lambda kv: kv[1]['di'])
                if s['Wo'] == 80)
    probes = ('model.0', wo80, 'model.6.m.0.cv1', 'model.7', 'model.19',
              'model.22.cv2.0.0', 'model.22.cv2.2.0', 'model.22.cv3.2.2')
    for p_ in probes:                      # fail-closed：八例名必须全在
        assert p_ in geos, p_
    r2 = True
    for probe in probes:
        gd = geos[probe]
        y_ref = frames[0]['refs'][probe]
        ok = gather_roundtrip(gd, y_ref)
        r2 &= ok
        vcs = '+'.join(str(st['vc']) for st in gd.strips_tab)
        chain = '+'.join(str(sg['k_len']) for sg in gd.segs)
        print('  R2 %-16s f0 strips(v%s) K=%s oc=%d law=%s %s'
              % (probe, vcs, chain, gd.oc, gd.masked_law,
                 'OK' if ok else 'FAIL'))
    print('R2 gather 形律（槽↔平面往返，rows=min(8,oc-8rc)；八例）%s'
          % ('OK' if r2 else 'FAIL'))

    # ---- R3：全软件走图 ×5 帧（41 图算子驱动律重打字 == G0 参照）----
    r3 = True
    n_g = 0
    for fi, fr in enumerate(frames):
        fdata = dict(np.load(os.path.join(
            run_dir, 'board_pack', 'refs_f%d.npz' % fi)))
        cv = fdata['canvas']
        x0 = (cv.astype(np.int16) - 128).astype(np.int8) \
            .transpose(2, 0, 1).copy()
        tensors = {0: x0}
        for td in descs:
            op, node = td['op'], td['node']
            key = 'ref_%d_%s' % (td['sched_index'],
                                 node.replace('.', '_'))
            ref = fdata.get(key)
            if op == 'conv':
                tensors[td['out_buf']] = ref     # conv 喂参照（板域）
                continue
            if op == 'view':
                par = tensors[td['parent_buf']]
                y = par[td['ch'][0]:td['ch'][1]]
                zero = np.shares_memory(y, par)
                ok = zero and np.array_equal(y, ref)
                tensors[td['out_buf']] = y
            elif op == 'add':
                qa = DRV.req_pair(td['a_scale'] / td['out_scale'])
                qb = DRV.req_pair(td['b_scale'] / td['out_scale'])
                A_ = DRV.rne_shift(tensors[td['a_buf']].astype(
                    np.int64) * qa[0], qa[1])
                B_ = DRV.rne_shift(tensors[td['b_buf']].astype(
                    np.int64) * qb[0], qb[1])
                y = DRV.sat_i8(DRV.sat_i32(A_ + B_))
                ok = np.array_equal(y, ref)
                tensors[td['out_buf']] = y
            elif op == 'concat':
                parts = []
                for s_ in td['inputs']:
                    q = DRV.req_pair(s_['scale'] / td['out_scale'])
                    parts.append(DRV.sat_i8(DRV.rne_shift(
                        tensors[s_['buf']].astype(np.int64) * q[0], q[1])))
                y = np.concatenate(parts, axis=0)
                ok = np.array_equal(y, ref)
                tensors[td['out_buf']] = y
            elif op == 'maxpool5':
                y = DRV.maxpool5(tensors[td['in_bufs'][0]])
                ok = np.array_equal(y, ref)
                tensors[td['out_buf']] = y
            elif op == 'upsample2':
                y = DRV.upsample_nearest2(tensors[td['in_bufs'][0]])
                ok = np.array_equal(y, ref)
                tensors[td['out_buf']] = y
            elif op == 'heads':
                seg_of = {40: '8', 20: '16', 10: '32'}   # 驱动同式
                seg_map = {}
                for grp in ('reg', 'cls'):
                    for e in td[grp]:
                        seg_map[grp + seg_of[e['shape'][2]]] = e['buf']
                all_entries = td['reg'] + td['cls']
                parts_, heads_len = [], 0
                for k_ in HEADS_ORDER:
                    buf = seg_map[k_]
                    e = next(x for x in all_entries if x['buf'] == buf)
                    t_ = tensors[buf]
                    assert list(t_.shape) == e['shape'], k_
                    b_ = np.ascontiguousarray(t_).tobytes()
                    heads_len += len(b_)
                    parts_.append(b_)
                got = sha_b(b''.join(parts_))
                ok = (heads_len == meta['heads_total'] and
                      got == meta['heads_blob_sha256']['f%d' % fi] and
                      got == fr['g0_head_blob_sha'])
                n_g += 1
                if not ok:
                    r3 = False
                    print('  R3 FAIL heads f%d (%dB %s)'
                          % (fi, heads_len, got[:16]))
                continue                     # heads 无 out_buf
            else:
                raise AssertionError(op)
            n_g += 1
            if not ok:
                r3 = False
                print('  R3 FAIL %s %s f%d' % (op, node, fi))
    assert n_g == 41 * 5, n_g
    print('R3 图算子律==G0（view/add/concat/mp5/ups/heads 41 任务×5 帧）%s'
          % ('OK' if r3 else 'FAIL'))

    ok = r1 and r2 and r3 and r4a and r4s and r4c and r4r and xstat
    print('M3_REHEARSAL %s' % ('PASS' if ok else 'FAIL'))
    return 0 if ok else 1


if __name__ == '__main__':
    raise SystemExit(main())
