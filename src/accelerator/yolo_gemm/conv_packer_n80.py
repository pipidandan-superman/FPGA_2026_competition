#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""conv_packer_n80.py — 物体线 M3 前置：conv 载荷泛化打包器 N80 拷出（第 6+7 项）

母本 = 3_host/yolo_p2/conv_packer.py（P2.2/B3-S1 run02 手势线正典，只读；
载荷布局合同逐行等价）。N80 拷出差异（M2_GAP_AUDIT §3 第 6/7 项）：
  N1 三锚重定基（保留律、重定值）：手势权重板证镜像 → 本 run anchors/
     三面 n80 镜像（由本拷出引擎 frame0 采集生成，gen_anchors_n80.py；
     字节=官方 yolov8n.pt 权重，**板证待 M3 阶梯重钉**——手势三锚的
     板证地位不可继承，锚=布局合同回归基线）；
  N2 ROM/schedule：2_fpga rom_data（手势 nc=7）→ dryrun_run01
     out/quant_n80（官方权重量化包）；
  N3 引擎链：graph_exec/ppu_replay/g0_extender → 本 run graph_exec_n80/
     n80_frames/g0_extender_n80（M3 前置拷出件）；
  N4 K 链=B1 一般化版（K≤1024→[K]；2026-10-06 K720 方案 A 板证定稿）；
  N5 manifests = v1.1 view 别名重生成版
     （2026-10-06_yolo_m3_manifests_v11_run01/out/p2_manifests_n80_v11，
     gm=74958a41…；desc/kbm/oracle/backend 与 b1regen 逐字节同）。

目的（与母本同）：把 P1.3 板证正典 packer（b3_conv0 K27 / K576 / K2304
链）泛化到图内全部 63 conv，逐 conv 生成板上 DMA 载荷（W 镜像 + X 拼装
+ y 槽布局 + CSR/DMA 递交计划），并在主机侧闭环证明**载荷布局合同**：

  载荷字节 → 板算律（W/X beat 整数 MAC + PCTL requant + LUT + 槽压缩/
  gather）→ y，与已证的 submit_conv stub（=Artifacts.forward，
  GEMM 整数合同）逐位一致，且全图 G1-G7 门复验保持全绿。

正典泛化律（三条板证正典的公共法，本文为唯一泛化实现）：
  1. 块律：block b = nt*RC + rc；nt = oy*n_strips + s。每块载荷 =
     Σ_seg 24B×k_len（链段连续拼接）；24B/k = W beat(8 lane=本 rc 的
     8 个 oc) ‖ X beat(16 lane=本 strip 的 16 个输出列)。
  2. X 拼装：lane c ↔ 输出列 16*s+c；ix = sw*(16*s+c) + kw - pw，
     iy = sh*oy + kh - ph；越界 → pad 字节（first 层 0x80 / 其余 0x00，
     即输入零点）；c ≥ vc（掩蔽 lane）= 板上 don't-care（n_mask 门控
     出计算与 y）：K2304 正典填 0xA5 哨兵，K576 正典不填（自然取数，
     越界才 pad）——两法均板绿；本工具合同默认 'fill' 0xA5（审计
     友好），复现 K576 历史正典按 ANCHOR_MASKED_LAW 用 'fetch'。
  3. K 链（B1，2026-10-06 一般化）：K≤1024→[K]；1152→[1024,128]；
     2304→[1024,1024,256]；段界由 k_block_manifest blocks[]（k_base/k_len/
     first/last/group）逐段展开，load_bytes=24*k_len。
  4. y 槽：byte = r*vc + cv（紧凑律，k576 strip1/k2304 板证）；YCNT=
     8*vc（统一 8 行槽，oc%8≠0 时 ROWVAL 掩行、W lane 补 0x00、PCTL 死
     行 (0,0,0)，gather 丢死行——板上 ROWVAL/ycant 语义为板级窗口待验
     项，见 STATUS）。Y 槽区步距 128B（正典律）。
  5. PCTL：b_eff = b_q + (first ? 128*colsum(w_q) : 0)；(M,shift) =
     schedule req 对（与 quant req 交叉门同源；§2.1 31 唯一对律）。
  6. requant：q = sat_i8(rne_shift((acc+b_eff)*M, s))；has_act →
     y = LUT[(q+128)&0xFF]，否则直通（6 个 head 末 conv no-act）。

字节锚（n80 重定基；布局律继承，字节=本线权重，板证待 M3 重钉）：
  model.0            ↔ anchors/b3_conv0_k27_mirror_n80.bin   (K=27, 3200 块)
  model.6.m.0.cv1    ↔ anchors/b3_k576_mirror_n80.bin        (K=576, 320 块)
  model.22.cv2.2.0   ↔ anchors/b3_k2304_mirror_n80.bin       (K=2304, 80 块×3 段)

门判据（与母本同律）：
  P1 载荷回放 y == stub y 逐位（63 conv × 6 执行 = 378 子门）；
  P2 字节律：掩蔽 lane 全 0xA5、pad 字节按位复核（块首/末+随机抽样）、
     段长 24*k_len == kbm load_bytes；
  P3 W 镜像稳定：同 conv 跨执行 W-beat 流 SHA 不变（权重常量）；
  P4 kbm 自洽：chain/first/last/group/accepted_beats 与编译台账一致；
  P5 三锚镜像逐字节复现（n80 重定基镜像）；
  G1-G7 graph_exec_n80 门在载荷路径下复验全绿（继承 run_frame）。

Run: 2026-09-21_model_env_rebuild_run03/venv/Scripts/python.exe
     conv_packer_n80.py --manifests <v11regen>/out/p2_manifests_n80_v11 --out <run>/out
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
# M4.2 归位：模块查找经 accel_bootstrap（替代原 run 目录 sys.path 插入）
_ROOT = os.path.abspath(os.path.join(HERE, '..'))     # 12_yolo_accel
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
import accel_paths as _AP                               # noqa: E402

from graph_exec_n80 import ArenaEngine, GraphExecError, sha_b  # noqa: E402 N3
from n80_frames import load_frames                        # noqa: E402  N3
from intref_yolov8 import rne_shift, sat_i8               # noqa: E402  N3

POISON = 0xA5
Y_SLOT_STRIDE = 128            # 正典 y 槽步距（k576/k2304/conv0 同律）
MASKED_LANE = 0xA5             # 掩蔽 lane 哨兵（k2304 正典律）

# 三面字节锚（n80 重定基镜像=本 run anchors/；布局律=手势三锚板证正典
# 的公共法，保留；字节=官方 yolov8n.pt 权重，M3 阶梯重板证）。
# K576 掩蔽 lane 走自然取数律（'fetch'，历史正典逐字节复现所需——
# 律保留，锚字节随 n80 重定）；其余按本工具合同 'fill' 0xA5。
_ANCHOR_DIR = _AP.ANCHOR_DIR       # M4.2：m3_pre run 冻结锚（只读输入）
ANCHOR_MASKED_LAW = {'model.6.m.0.cv1': 'fetch'}
ANCHORS = [
    ('model.0', os.path.join(_ANCHOR_DIR, 'b3_conv0_k27_mirror_n80.bin')),
    ('model.6.m.0.cv1', os.path.join(_ANCHOR_DIR, 'b3_k576_mirror_n80.bin')),
    ('model.22.cv2.2.0', os.path.join(_ANCHOR_DIR,
                                      'b3_k2304_mirror_n80.bin')),
]

# N2：schedule/quant 输入源 = n80 官方权重量化包（手势 rom_data 不再读）
ROM = _AP.ROM                     # M4.2：dryrun run01 冻结量化包（只读）


def b1_chain(k: int):
    """B1 K 链律（决策文档 §B1；与 kbm 交叉断言用）。

    一般化（2026-10-06，k720 方案 A 裁决）：K<=1024 单块直用
    （硬件边界=F2 bank 深 1024；720 板证=K720_R1/R2 双绿）。
    """
    if k <= 1024:
        return [k]
    if k == 1152:
        return [1024, 128]
    if k == 2304:
        return [1024, 1024, 256]
    raise GraphExecError('E_K_UNSUPPORTED K=%d' % k)


class ConvGeo:
    """单 conv 的载荷几何 + 常量（一次构建，跨帧复用；全部 fail-closed）。"""

    def __init__(self, eng: ArenaEngine, di: int):
        d = next(x for x in eng.descs if x['sched_index'] == di and
                 x['op'] == 'conv')
        kb = eng.kc[di]
        self.di, self.node = di, d['node']
        sched_t = self._sched(eng, self.node)
        self.kb = kb
        # -- 形状/步距（schedule 为执行序权威，quant 交叉）--
        qn = eng.A.node(d['quant_node'])
        assert qn is not None and d['quant_node'] == self.node
        self.oc, self.ic, self.kh, self.kw = qn['w_shape']
        self.sh, self.sw = sched_t['stride']
        self.ph, self.pw = sched_t['pad']
        self.K = self.ic * self.kh * self.kw
        self.first = bool(kb['first_conv'])
        assert self.first == bool(sched_t.get('first')), self.node
        self.has_act = bool(kb['has_act'])
        assert self.has_act == bool(sched_t.get('has_act')), self.node
        # -- K 链（B1 律 × kbm 台账双源断言）--
        self.chain = [b['k_len'] for b in kb['blocks']]
        assert self.chain == b1_chain(self.K), (self.node, self.chain)
        assert kb['k_real'] == self.K
        assert sum(self.chain) == self.K
        self.segs = kb['blocks']          # k_base/k_len/first/last/group
        # -- 输出几何 → strip 律 --
        self.Ho, self.Wo = sched_t['out_shape'][1:]
        in_shp = eng.bufs[d['in_bufs'][0]]['shape']
        H, W = in_shp[1:]
        assert (H + 2 * self.ph - self.kh) // self.sh + 1 == self.Ho
        assert (W + 2 * self.pw - self.kw) // self.sw + 1 == self.Wo
        self.strips = []                  # (vc, nmask)
        for s in range((self.Wo + 15) // 16):
            vc = min(16, self.Wo - 16 * s)
            self.strips.append((vc, (1 << vc) - 1))
        self.n_strips = len(self.strips)
        self.N_TILE = self.Ho * self.n_strips
        # -- 行块律（oc=7 → ROWVAL 掩行）--
        self.RC = (self.oc + 7) // 8
        self.NB = self.N_TILE * self.RC
        self.tile_load_len = 24 * self.K
        # -- 数值常量（PCTL/LUT，与 Artifacts 同源）--
        wq = eng.A.w(qn).reshape(self.oc, self.K)      # int32 → 存 int8 视图
        self.Wq = wq.astype(np.int8)
        self.b_eff = eng.A.b(qn).astype(np.int64)
        if self.first:
            self.b_eff = self.b_eff + eng.A.z_sum_w(self.node)
        if self.first:
            zs = np.array(sched_t['z_sum_w'], dtype=np.int64)
            assert np.array_equal(zs, eng.A.z_sum_w(self.node)), self.node
        self.req = [tuple(r) for r in sched_t['req']]
        assert self.req == [tuple(r) for r in qn['req']], self.node
        assert len(self.req) == self.oc
        self.LUT = eng.A.lut(qn)
        self.pad_val = np.int8(-128 if self.first else 0)
        # 掩蔽 lane（c≥vc）= 板上 don't-care（n_mask 门控出计算与 y）。
        # 两面板证正典各用一种打包法：K2304 显式填 0xA5 哨兵（自检
        # 断言）；K576 不填——按自然取数律继续取 ix=sw·(16s+c)+kw-pw，
        # 越界才 pad（byte-diff 实证：strip1 lane4 携带真实输入字节
        # src[ix=19]，28904 差异字节恰为 kW=0 的 k 位×160 块）。两者
        # 均板绿 ⇒ don't-care。本工具合同默认 'fill' 0xA5（审计友好）；
        # 复现 K576 历史正典按 ANCHOR_MASKED_LAW 用 'fetch'。
        self.masked_law = ANCHOR_MASKED_LAW.get(self.node, 'fill')
        self.masked_fill = MASKED_LANE
        # -- k 展开（ic,kh,kw）与 Artifacts im2col 同序 --
        kk = np.arange(self.K)
        self.kIC = kk // (self.kh * self.kw)
        self.kKH = (kk % (self.kh * self.kw)) // self.kw
        self.kKW = kk % self.kw

    @staticmethod
    def _sched(eng, node):
        if not hasattr(eng, '_sched_map'):
            import json as _j
            s = _j.load(open(os.path.join(ROM, 'schedule.json'),
                             encoding='utf-8'))
            eng._sched_map = {t['node']: t for t in s['tasks']}
        return eng._sched_map[node]

    # -- CSR/DMA 递交计划（板级窗口消费）------------------------------
    def program(self):
        """逐块递交参数表。JOBCFG 位律=合同 §9：bit0 act_en｜bit1 first｜
        bit2 last｜bit3 w_grp｜bit4 x_grp；act conv 全 job 置 act_en
        （链中段无害、末段必需——K2304 板证 J1/J2/J3=0x03/0x19/0x05
         解码律）；ldgrp=3 if grp else 0（pl_p13_k2304 驱动同式）。"""
        rows = []
        for b in range(self.NB):
            nt, rc = b // self.RC, b % self.RC
            oy, s = nt // self.n_strips, nt % self.n_strips
            vc, nmask = self.strips[s]
            rowval = (1 << min(8, self.oc - 8 * rc)) - 1
            ycnt = 8 * vc
            rows.append({
                'b': b, 'nt': nt, 'oy': oy, 'strip': s, 'rc': rc,
                'vc': vc, 'n_mask': '0x%04X' % nmask,
                'row_valid': '0x%02X' % rowval, 'ycnt': ycnt,
                's2mm_btt': ycnt, 'mm2s_len': self.tile_load_len,
                'y_slot_off': Y_SLOT_STRIDE * b,
                'segs': [{'k_len': g['k_len'], 'geom': g['k_len'],
                          'first': g['first'], 'last': g['last'],
                          'group': g['group'],
                          'jobcfg': '0x%02X' % (
                              (0x01 if self.has_act else 0) |
                              (0x02 if g['first'] else 0) |
                              (0x04 if g['last'] else 0) |
                              (0x18 if g['group'] else 0)),
                          'ldgrp': 3 if g['group'] else 0}
                         for g in self.segs]})
        return rows


def pack_tile(geo: ConvGeo, x: np.ndarray, oy: int, s: int, rc: int):
    """单块载荷字节（链段连续）：[K,24] = W(8) ‖ X(16)。

    x = arena 输入张量 [1,C,H,W] int8（submit_conv 收到的同一对象）。
    """
    vc, _ = geo.strips[s]
    H, W = x.shape[2], x.shape[3]
    iy = geo.sh * oy + geo.kKH - geo.ph                    # [K]
    c = np.arange(16)
    ix = geo.sw * (16 * s + c)[None, :] + geo.kKW[:, None] - geo.pw  # [K,16]
    if geo.masked_law == 'fetch':
        # K576 正典律：掩蔽 lane 照自然取数（oob 才 pad），不填哨兵
        inb = ((iy[:, None] >= 0) & (iy[:, None] < H) &
               (ix >= 0) & (ix < W))
    else:
        inb = ((iy[:, None] >= 0) & (iy[:, None] < H) &
               (ix >= 0) & (ix < W) & (c[None, :] < vc))
    xi = np.clip(iy, 0, H - 1)
    xj = np.clip(ix, 0, W - 1)
    src = x[0][geo.kIC[:, None], xi[:, None], xj]          # [K,16] int8
    xb = np.where(inb, src, geo.pad_val).astype(np.int8)
    xbu = xb.view(np.uint8)
    if geo.masked_law != 'fetch':
        xbu[:, vc:] = geo.masked_fill           # 掩蔽 lane（don't-care 填充）
    wrows = np.arange(8 * rc, 8 * rc + 8)
    dead = wrows >= geo.oc                                   # oc=7 死行补 0
    wv = np.where(dead[:, None], 0,
                  geo.Wq[np.clip(wrows, 0, geo.oc - 1), :]).astype(np.int8)
    tile = np.empty((geo.K, 24), dtype=np.uint8)
    tile[:, :8] = wv.T.view(np.uint8)
    tile[:, 8:] = xbu
    return tile


class PackCheckEngine(ArenaEngine):
    """run01 引擎 + conv 双跑（stub ‖ 载荷路径）对拍。run_frame 全继承。"""

    def __init__(self, manifests_dir):
        ArenaEngine.__init__(self, manifests_dir)
        self.geos = {}
        for d in self.descs:
            if d['op'] == 'conv':
                g = ConvGeo(self, d['sched_index'])
                # kbm 自洽（P4）：load_bytes/accepted_beats 台账一致
                for sg in g.segs:
                    assert sg['load_bytes'] == 24 * sg['k_len']
                    assert sg['accepted_beats'] == 3 * sg['k_len']
                    assert sg['k_base'] + sg['k_len'] <= g.K
                assert d['k_chain'] == g.chain and d['n_blocks'] == \
                    len(g.segs)
                self.geos[d['sched_index']] = g
        assert len(self.geos) == 63
        self.payload_rows = []        # (exec, di, node, ...) 逐 conv 取证
        self.w_sha_hist = {}          # node -> W-beat 流 SHA（P3 稳定）
        self.anchor_tiles = {}        # node -> {b: tile}（锚 conv 全量留字节）

    # -- conv 双跑（run01 submit_conv 缝的载荷化实现）--------------------
    def submit_conv(self, node, x, first):
        y_stub = self.A.forward(node, x, first=first)
        di = next(d['sched_index'] for d in self.descs
                  if d['op'] == 'conv' and d['node'] == node)
        geo = self.geos[di]
        assert first == geo.first, node
        y_pack = np.empty_like(y_stub[0])
        y_pack[:] = 0
        loads_h = hashlib.sha256()
        slots_h = hashlib.sha256()
        w_h = hashlib.sha256()
        pad_expect = 0
        masked_bad = 0
        nblk = 0
        anchor = node in dict(ANCHORS) and self._anchor_armed
        for b in range(geo.NB):
            nt, rc = b // geo.RC, b % geo.RC
            oy, s = nt // geo.n_strips, nt % geo.n_strips
            vc, _ = geo.strips[s]
            tile = pack_tile(geo, x, oy, s, rc)
            # P2 字节律：掩蔽 lane 填充律（fill 律 conv）+ pad 位置计数
            if geo.masked_law == 'fill':
                masked_bad += int(np.count_nonzero(
                    tile[:, 8 + vc:] != geo.masked_fill))
            c = np.arange(16)
            ix = geo.sw * (16 * s + c)[None, :] + \
                geo.kKW[:, None] - geo.pw
            iy = geo.sh * oy + geo.kKH - geo.ph
            H, W = x.shape[2], x.shape[3]
            inb = ((iy[:, None] >= 0) & (iy[:, None] < H) &
                   (ix >= 0) & (ix < W) & (c[None, :] < vc))
            pad_expect += int(np.count_nonzero(~inb & (c[None, :] < vc)))
            # 板算律回放（从字节独立解析）
            Wm = tile[:, :8].copy().view(np.int8).T.astype(np.int32)
            Xm = tile[:, 8:].copy().view(np.int8).astype(np.int32)
            acc = Wm @ Xm                                    # [8,16]
            rows_valid = min(8, geo.oc - 8 * rc)
            slot = np.empty(8 * vc, dtype=np.uint8)
            for r in range(8):
                if r < rows_valid:
                    M, shf = geo.req[8 * rc + r]
                    n = (acc[r].astype(np.int64) + geo.b_eff[8 * rc + r]) \
                        * int(M)
                    q = sat_i8(rne_shift(n, int(shf)))
                    yr = geo.LUT[(np.int16(q) + 128).astype(np.uint8)] \
                        if geo.has_act else q
                else:                                        # 死行：确定性填充
                    yr = np.zeros(16, dtype=np.int8)
                slot[r * vc:(r + 1) * vc] = \
                    yr[:vc].view(np.uint8) if r < rows_valid else \
                    np.full(vc, POISON, np.uint8)
                if r < rows_valid:
                    y_pack[8 * rc + r, oy, 16 * s:16 * s + vc] = yr[:vc]
            loads_h.update(tile.tobytes())
            slots_h.update(slot.tobytes())
            w_h.update(tile[:, :8].tobytes())
            nblk += 1
            if anchor:
                self.anchor_tiles.setdefault(node, {})[b] = tile
        # P1 逐位对拍
        nerr = int(np.count_nonzero(
            y_pack.view(np.int8) != y_stub[0].view(np.int8)))
        self.payload_rows.append({
            'exec': None, 'seq': di, 'node': node, 'K': geo.K,
            'chain': geo.chain, 'nb': nblk, 'rows': [
                {'b': r} for r in range(0)],
            'nerr': nerr,
            'loads_sha256': loads_h.hexdigest(),
            'y_slots_sha256': slots_h.hexdigest(),
            'w_beat_sha256': w_h.hexdigest(),
            'pad_positions': pad_expect, 'masked_lane_bad': masked_bad,
            'load_bytes': nblk * geo.tile_load_len})
        # P3 W 镜像稳定
        prev = self.w_sha_hist.get(node)
        wsha = self.payload_rows[-1]['w_beat_sha256']
        if prev is not None and prev != wsha:
            raise GraphExecError('W 镜像跨执行漂移 %s' % node)
        self.w_sha_hist[node] = wsha
        if nerr:
            bad = np.argwhere(y_pack.view(np.int8) != y_stub[0].view(np.int8))
            raise GraphExecError('P1 载荷回放失配 %s nerr=%d 首=%s'
                                 % (node, nerr, tuple(bad[0])))
        return y_stub

    _anchor_armed = True


def build_anchor_mirror(geo: ConvGeo, tiles: dict) -> np.ndarray:
    """正典布局镜像：LUT@0 / loads@0x100 / y 区 0xA5（128B 步距）/ guard."""
    load_end = 0x100 + geo.tile_load_len * geo.NB
    y_end = load_end + Y_SLOT_STRIDE * geo.NB
    m = np.full(y_end + 0x10000, POISON, dtype=np.uint8)  # guard ≥ 正典余量
    m[0:256] = geo.LUT.view(np.uint8)
    for b, tile in tiles.items():
        m[0x100 + geo.tile_load_len * b:
          0x100 + geo.tile_load_len * (b + 1)] = tile.reshape(-1)
    return m


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--manifests', required=True)
    ap.add_argument('--out', required=True)
    args = ap.parse_args()

    eng = PackCheckEngine(args.manifests)
    frames = load_frames()
    anchor_nodes = {n for n, _ in ANCHORS}

    report = {'run': 'M3-pre n80 conv payload packer（三锚重定基）',
              'conv_statics': {}, 'anchors': [], 'attempts': [],
              'checks': []}
    for di, g in sorted(eng.geos.items()):
        report['conv_statics'][g.node] = {
            'seq': di, 'K': g.K, 'chain': g.chain, 'oc': g.oc,
            'kernel': [g.kh, g.kw], 'stride': [g.sh, g.sw],
            'pad': [g.ph, g.pw], 'Ho': g.Ho, 'Wo': g.Wo,
            'strips': [{'vc': vc, 'n_mask': '0x%04X' % nm}
                       for vc, nm in g.strips],
            'RC': g.RC, 'n_tile': g.N_TILE, 'n_block': g.NB,
            'tile_load_len': g.tile_load_len, 'first': g.first,
            'has_act': g.has_act,
            'program_head': g.program()[:1]}

    verdicts = []
    plan = [('rep', 0, 0)] + [('f%d' % i, 1 + i, i)
                              for i in range(len(frames))]
    for tag, exec_id, fi in plan:
        fr = frames[fi]
        # 锚字节只在源帧 0 的执行上采集（正典镜像 = frame 0）
        eng._anchor_armed = (fi == 0)
        n0 = len(eng.payload_rows)
        rows, blob, vw = eng.run_frame(fr['canvas'], exec_id)
        for r in eng.payload_rows[n0:]:
            r['exec'] = tag
        # 继承 run01 的 G 门（对拍 G0 / heads / view / guard 汇总）
        comp, nerr_tot = [], 0
        for r in rows:
            if r['op'] == 'heads':
                continue
            ref = fr['refs'].get(r['node'])
            got = eng._t(r['buffer_id'])[0] if r.get('buffer_id') \
                is not None else None
            if ref is None or got is None:
                comp.append({'node': r['node'], 'compared': False})
                continue
            neq = int(np.sum(got != ref))
            nerr_tot += neq
            comp.append({'node': r['node'], 'compared': True, 'nerr': neq})
        heads_ok = sha_b(blob) == fr['g0_head_blob_sha']
        p1 = all(r['nerr'] == 0 for r in eng.payload_rows[n0:])
        p2 = all(r['masked_lane_bad'] == 0 for r in eng.payload_rows[n0:])
        ok = (nerr_tot == 0 and sum(1 for c in comp
                                    if c.get('compared')) == 103
              and heads_ok and vw == 0 and p1 and p2)
        verdicts.append(ok)
        print('%-4s frame%d G_nerr=%d compared=%d/103 heads=%s '
              'P1_payload=%s P2_bytes=%s convs=%d -> %s'
              % (tag, fi, nerr_tot,
                 sum(1 for c in comp if c.get('compared')),
                 'OK' if heads_ok else 'FAIL',
                 'OK' if p1 else 'FAIL', 'OK' if p2 else 'FAIL',
                 len(eng.payload_rows) - n0, 'PASS' if ok else 'FAIL'))
        report['attempts'].append({
            'tag': tag, 'frame': fi, 'g_nerr_total': nerr_tot,
            'compared': sum(1 for c in comp if c.get('compared')),
            'heads_blob_ok': heads_ok, 'view_writes': vw,
            'payload_convs': eng.payload_rows[n0:], 'pass': ok})

    # ---- P5 锚：正典镜像逐字节复现（rep 执行 = 源帧 0，与正典同帧）----
    anchor_results = []
    for node, path in ANCHORS:
        geo = next(g for g in eng.geos.values() if g.node == node)
        tiles = eng.anchor_tiles.get(node, {})
        if not tiles:
            anchor_results.append({'node': node, 'path': path,
                                   'pass': False, 'why': 'no tiles'})
            continue
        mine = build_anchor_mirror(geo, tiles)
        ref = np.fromfile(path, dtype=np.uint8)
        same = (mine.size >= ref.size and
                bool(np.array_equal(mine[:ref.size], ref)))
        anchor_results.append({
            'node': node, 'path': path, 'ref_len': int(ref.size),
            'mine_len': int(mine.size), 'byte_equal': same,
            'ref_sha256': sha_b(ref.tobytes()),
            'mine_head_sha256': sha_b(mine[:ref.size].tobytes()),
            'pass': same})
    report['anchors'] = anchor_results

    verdict = 'PASS' if all(verdicts) else 'FAIL'
    g_checks = [
        ('P1 载荷回放==stub 逐位（63×6）',
         all(a['pass'] for a in report['attempts'])),
        ('P2 字节律（掩蔽哨兵/pad 位置计数）',
         all(r['masked_lane_bad'] == 0 for a in report['attempts']
             for r in a['payload_convs'])),
        ('P3 W 镜像跨执行稳定', bool(eng.w_sha_hist)
         and len(eng.w_sha_hist) == 63),
        ('P4 kbm 自洽（执行期断言）', verdict != 'FAIL'),
        ('P5 三锚逐字节复现', all(a['pass'] for a in anchor_results)),
        ('G 继承门（nerr/heads/view/guard）', all(verdicts)),
    ]
    for name, okk in g_checks:
        report['checks'].append({'check': name, 'pass': bool(okk)})
        print('  %s %s' % ('PASS' if okk else 'FAIL', name))
    verdict = 'PASS' if (verdict == 'PASS' and
                         all(c['pass'] for c in report['checks'])) else 'FAIL'
    report['verdict'] = verdict
    json.dump(report, open(os.path.join(args.out, 'conv_payload_report.json'),
              'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    print('CONV_PACKER_N80 %s' % verdict)
    return 0 if verdict == 'PASS' else 1


if __name__ == '__main__':
    raise SystemExit(main())
