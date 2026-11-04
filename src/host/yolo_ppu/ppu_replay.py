#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ppu_replay.py — PPU-F2：软件全图回放（三 .bin 驱动，禁 JSON 旁路）

目的（followup replan §PPU-F2）：在任何 RTL 之前证明同一 binary 合同可以
跑完整图。执行语义只来自 descriptor.bin / buffer.bin / quant.bin 经
ppu_packer.unpack() 重建的 records——schedule.json / descriptor_table.json /
buffer_table.json 在执行路径上一律不打开（run05 旧回放正是 JSON 驱动，本轮
整体替换）。

F2 期间裁定（手册未逐字规定处，登记于此）：
  D-F2a 禁旁路边界：图执行语义（调度顺序、opcode、in/out、shape/stride、
       view 别名、段表、量化对、拓扑链）只从三 .bin 来。JSON 仅限两类
       非图语义辅助（下两条）。
  D-F2b conv 引擎绑定：conv 的权重/bias/LUT/逐 OC (M,shift)（= GEMM 线
       DMA 权重通道数据，D-F1b 已定不占 quant 表）从 rom_data 工件 +
       k_block_manifest（desc 序号→node 名/first 标志）读取——等价 RTL
       侧 GEMM 引擎自身配置流，非图旁路。数值实现 = g0_extender.Artifacts
       单一源（run04 已对 G0 位级验证）。
  D-F2c oracle 绑定：oracle_manifest（desc 序号→g0_key）仅用于校验侧
       对号（哪个 out 与哪个 G0 golden 比），不参与执行。
  D-F2d view 执行语义 = 零拷贝别名：c0 从 .bin 地址推导
       c0 = (out_base − parent_base) / (H·W)（描述符不含 c0，地址即语义，
       手册 §3"纯地址视图"）；numpy 切片天然零拷贝，与 RTL 零搬移同构。
  D-F2e 跨帧三档（8/32/128）计数器：generation 回退 = 写入世代 ≤ 该 buffer
       历史最大世代；地址越界 = 写张量 nbytes > buffer size 或出 CMA 窗；
       cache 交接遗漏 = 消费者读到非本帧产物（last_write_frame != 当前帧）。
       owner 记账（方案 A PL 只读，D-F1e）按诊断计数保留：提前释放 =
       consumer_count 未扣完即 FREE 后再读。

F2 PASS 判据（followup replan §PPU-F2 原文）：
  1) 104 task 拓扑完整；2) 每个可比 tensor nerr=0（103 项）；
  3) raw head 149100 B SHA 与 G0 一致；4) 重复运行 SHA 稳定；
  5) 8/32/128 帧（本轮含 1 帧档）无 generation 回退/地址越界/cache 交接遗漏；
  6) 软件级错误注入（提前释放/错误 generation/错误 stride/错误段长/错误
     frame_id）首错可定位且不伪造 PASS。

执行规模：1、8、32、128 帧四档 × 双输入模式（同一确定性帧重复 rep /
固定帧库循环 cyc），共 338 次全图执行。

Run: D:/work/Python/python.exe ppu_replay.py --bins <run01>/out --out <run02>
"""

from __future__ import annotations

import argparse
import copy
import gzip
import hashlib
import json
import os
import sys
import time

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
WT = os.path.abspath(os.path.join(HERE, '..', '..'))
ROM = os.path.join(WT, '2_fpga', '3_yolo_zynq', 'rom_data')
G0 = os.path.join(WT, '4_metrics', 'logs',
                  '2026-09-15_yolo7020_g2_quant_rne_run04')
RUN04 = os.path.join(WT, '4_metrics', 'logs',
                     '2026-09-21_yolo_p2_0_run04_g0ext')
RUN01_MAN = os.path.join(WT, '4_metrics', 'logs',
                         '2026-09-21_yolo_ppu_f2_run01_viewalias', 'manifests')
# F2 run00 golden 恢复件（原 G0/golden npz 已失，经"重下 v6 对 hash → 字节
# 同一脚本确定性再生 → SHA 对 golden_index.json 逐位核验"复原；G0 目录仍只读）
RUN00 = os.path.join(WT, '4_metrics', 'logs',
                     '2026-09-21_yolo_ppu_f2_run00_golden_restore')
sys.path.insert(0, HERE)
sys.path.insert(0, G0)
sys.path.insert(0, RUN04)

from ppu_packer import unpack                                    # noqa: E402
from ppu_desc_bundle import (                                    # noqa: E402
    CMA_WINDOW, HEADS_LAYOUT, HEADS_SEG_ORDER, HEADS_TOTAL_BYTES,
    PRODUCER_EXTERNAL,
)
from intref_yolov8 import (                                      # noqa: E402
    rne_shift, sat_i8, sat_i32, maxpool5, upsample_nearest2,
)
from g0_extender import Artifacts                                # noqa: E402

OP_CONV, OP_VIEW, OP_ADD, OP_CONCAT = 0x01, 0x10, 0x11, 0x12
OP_MAXPOOL5, OP_UPSAMPLE2, OP_HEADS = 0x13, 0x14, 0x15
OPNAME = {OP_CONV: 'conv', OP_VIEW: 'view', OP_ADD: 'add',
          OP_CONCAT: 'concat', OP_MAXPOOL5: 'maxpool5',
          OP_UPSAMPLE2: 'upsample2', OP_HEADS: 'heads'}
HISTOGRAM = {OP_CONV: 63, OP_VIEW: 16, OP_ADD: 6, OP_CONCAT: 13,
             OP_MAXPOOL5: 3, OP_UPSAMPLE2: 2, OP_HEADS: 1}
# G0 raw_* 键名与 heads 段的对应（校验侧命名，D-F2c）
HEADS_RAWKEY = {'reg8': 'raw_reg_s8', 'reg16': 'raw_reg_s16',
                'reg32': 'raw_reg_s32', 'cls8': 'raw_cls_s8',
                'cls16': 'raw_cls_s16', 'cls32': 'raw_cls_s32'}


class ReplayError(Exception):
    """回放期违例（fail-closed；携带首错定位）。"""


def sha_bytes(a) -> str:
    return hashlib.sha256(np.ascontiguousarray(a).tobytes()).hexdigest()


# ----------------------------------------------------------------------------
# 输入装载（G0 只读）
# ----------------------------------------------------------------------------
def load_frames():
    """5 帧输入：canvas + golden/g0_ext 参考张量 + raw heads + head blob SHA。

    D-F2f（run00 恢复后立）：golden npz 原件已失，恢复件位于 RUN00/golden，
    装载时逐文件对 G0/golden_index.json 的 SHA 台账核验；g0_ext 逐文件对
    RUN04/g0_ext_report.json 的 ext_sha256 核验。任一不符 = fail-closed。
    """
    idx = json.load(open(os.path.join(G0, 'golden_index.json'),
                         encoding='utf-8'))
    ext_rep = json.load(open(os.path.join(RUN04, 'g0_ext_report.json'),
                             encoding='utf-8'))
    ext_by_name = {fr['frame']: fr for fr in ext_rep['frames']}
    frames = []
    for ent in idx:                              # 台账序（非目录序）
        gf = ent['file'].split('/', 1)[1]        # golden/golden_XX_….npz
        gp_path = os.path.join(RUN00, 'golden', gf)
        got = hashlib.sha256(open(gp_path, 'rb').read()).hexdigest()
        if got != ent['sha256']:
            raise ReplayError(f'golden SHA mismatch {gf}: {got} != '
                              f"{ent['sha256']}（恢复件与台账不符，fail-closed）")
        efr = ext_by_name.get(gf)
        if efr is None:
            raise ReplayError(f'g0_ext binding missing for {gf}')
        ef = gf.replace('golden_', 'g0_ext_', 1)
        ep_path = os.path.join(RUN04, ef)
        egot = hashlib.sha256(open(ep_path, 'rb').read()).hexdigest()
        if egot != efr['ext_sha256']:
            raise ReplayError(f'g0_ext SHA mismatch {ef}: {egot} != '
                              f"{efr['ext_sha256']}")
        gp = np.load(gp_path)
        ep = np.load(ep_path)
        refs = {k[5:]: gp[k] for k in gp.files if k.startswith('int8_')}
        for k in ep.files:
            if k.startswith('int8_'):
                refs.setdefault(k[5:], ep[k])
        raws = {HEADS_RAWKEY[k]: gp[HEADS_RAWKEY[k]]
                for k in HEADS_SEG_ORDER}
        blob = b''.join(np.ascontiguousarray(raws[HEADS_RAWKEY[k]]).tobytes()
                        for k in HEADS_SEG_ORDER)
        frames.append({'name': gf, 'canvas': gp['canvas_u8'], 'refs': refs,
                       'raws': raws, 'g0_head_blob_sha':
                       hashlib.sha256(blob).hexdigest(),
                       'lineage': {'g0_sha256': ent['sha256'],
                                   'restored_sha256': got,
                                   'ext_sha256': efr['ext_sha256']}})
    if len(frames) != 5:
        raise ReplayError(f'frame library {len(frames)} != 5')
    return frames


# ----------------------------------------------------------------------------
# T1 拓扑门（纯二进制侧；违反即 fail-closed）
# ----------------------------------------------------------------------------
def topology_gate(b) -> dict:
    used = [d for d in b.descs if d is not None]
    bufs = {x.index: x for x in b.bufs if x is not None}
    if len(used) != 104 or len(bufs) != 104:
        raise ReplayError(f'T1 counts {len(used)}/{len(bufs)} != 104/104')
    if [d.index for d in used] != list(range(104)):
        raise ReplayError('T1 desc indices not 0..103')
    hist = {}
    for d in used:
        hist[d.opcode] = hist.get(d.opcode, 0) + 1
    if hist != HISTOGRAM:
        raise ReplayError(f'T1 opcode histogram {hist}')
    if [d.index for d in used if d.last] != [103]:
        raise ReplayError('T1 last != [103]')
    # next 链：0→1→…→103→0xFFFF 逐项可走且覆盖全部
    chain, i = [], 0
    while True:
        chain.append(i)
        nxt = used[i].next_id
        if i == 103:
            if nxt != 0xFFFF:
                raise ReplayError(f'T1 desc103 next=0x{nxt:X} != 0xFFFF')
            break
        if nxt != i + 1:
            raise ReplayError(f'T1 desc{i} next={nxt} != {i + 1}')
        i = nxt
    if len(chain) != 104:
        raise ReplayError('T1 chain does not cover 104')
    # buffer 几何/窗口/stride/别名（§4.3 装载校验的回放侧重放）
    view_outs = {d.out for d in used if d.opcode == OP_VIEW}
    spans = []
    for x in b.bufs:
        if x is None:
            continue
        if min(x.c, x.h, x.w) <= 0 or x.c * x.h * x.w > x.size:
            raise ReplayError(f'T1 buf{x.index} C·H·W > size')
        if x.line_stride < x.w:
            raise ReplayError(f'T1 buf{x.index} stride {x.line_stride} < W {x.w}')
        if not (CMA_WINDOW[0] <= x.base and x.base + x.size <= CMA_WINDOW[1]):
            raise ReplayError(f'T1 buf{x.index} outside CMA window')
        if x.index not in view_outs:
            spans.append((x.base, x.base + x.size, x.index))
    spans.sort()
    for i in range(1, len(spans)):
        if spans[i - 1][1] > spans[i][0]:
            raise ReplayError(f'T1 span overlap buf{spans[i - 1][2]}/buf{spans[i][2]}')
    # view 别名（D-F2d 地址推导）+ w14 一致
    refs50 = 0
    for d in used:
        ob = b.bufs[d.out] if d.out != 0x3FF else None
        pb = b.bufs[d.in0]
        if d.opcode == OP_VIEW:
            delta, hw = ob.base - pb.base, d.h * d.w
            if delta < 0 or delta % hw or delta // hw + d.c > pb.c:
                raise ReplayError(f'T1 desc{d.index} view alias broken '
                                  f'(delta=0x{delta:X})')
            if ob.line_stride != pb.line_stride:
                raise ReplayError(f'T1 desc{d.index} view stride != parent')
        elif d.opcode != OP_HEADS:
            if ob.size != d.out_bytes:
                raise ReplayError(f'T1 desc{d.index} w14 != out size')
        if d.opcode == OP_HEADS and d.out_bytes != HEADS_TOTAL_BYTES:
            raise ReplayError('T1 heads w14 != 149100')
        # 语义引用计数（手册事实 50）：add 的 w5 两域 + 各段表 prof；
        # concat 的 prof_in0 是段表首项镜像（§4 word2/word5），不重复计
        if d.opcode == OP_ADD:
            refs50 += (1 if d.prof_in0 else 0) + (1 if d.prof_in1 else 0)
        refs50 += sum(1 for s in d.segments if s.prof)
    # 手册冻结事实从二进制复核：50 语义引用 / 32 装载单元 / 31 个不同值
    # （恒等对与某 r=1.0 比值同值异槽——装载冗余，无 ABI 影响；F1 G1 的
    # 31 唯一对/50 引用为装载器视角，已在 run01 复核）
    if refs50 != 50:
        raise ReplayError(f'T1 quant refs {refs50} != 50 (manual fact)')
    loaded = [q for q in b.quant if q is not None]
    cells = {(q.m, q.shift) for q in loaded}
    if len(loaded) != 32 or b.quant[0] is None or \
            (b.quant[0].m, b.quant[0].shift) != (1 << 30, 30):
        raise ReplayError(f'T1 quant cells {len(loaded)} != 32 or id0 '
                          'not identity')
    if len(cells) != 31:
        raise ReplayError(f'T1 quant distinct pairs {len(cells)} != 31')
    for d in used:                       # 引用的 profile 必须已装载
        for pid in [d.prof_in0, d.prof_in1] + [s.prof for s in d.segments]:
            if pid and (pid >= 256 or b.quant[pid] is None):
                raise ReplayError(f'T1 desc{d.index} profile {pid} unloaded')
    # dep 一致性：dep_id == 实际输入的 max(producer_desc)
    for d in used:
        ins = [d.in0] + ([d.in1] if d.opcode == OP_ADD else []) \
            + [s.buf for s in d.segments]
        pd = [bufs[x].producer_desc for x in ins
              if bufs[x].producer_desc != PRODUCER_EXTERNAL]
        want = max(pd) if pd else 0
        if d.dep_id != want:
            raise ReplayError(f'T1 desc{d.index} dep_id {d.dep_id} != '
                              f'max(producer) {want}')
        for x in ins:
            p = bufs[x].producer_desc
            if p != PRODUCER_EXTERNAL and p >= d.index:
                raise ReplayError(f'T1 desc{d.index} reads buf{x} producer {p} '
                                  'not in past')
    return {'n_desc': 104, 'n_buf': 104, 'histogram':
            {OPNAME[k]: v for k, v in hist.items()},
            'quant_refs': refs50, 'quant_unique': len(cells) - 1,
            'chain_len': len(chain)}


# ----------------------------------------------------------------------------
# 软件执行引擎（每帧一个实例化调用；状态挂在对象上）
# ----------------------------------------------------------------------------
class SWEngine:
    """三 .bin 驱动的软件 PPU。conv = Artifacts（GEMM 合同单一源，D-F2b）；
    其余算子按 opcode 用 intref 原语 + quant 表 (M,shift) 实现。"""

    def __init__(self, bundle, kbind, oracle):
        self.b = bundle
        self.A = Artifacts()
        self.kb = kbind                    # desc index -> {node,z_sum_w}
        self.oracle = oracle               # desc index -> {node,g0_key}

    # -- 跨帧/帧内记账 ------------------------------------------------------
    def _reset_state(self, faults=None):
        self.flt = faults or {}
        self.store = {}                    # bid -> int8 4D
        self.gen = {}                      # bid -> 写入世代
        self.max_gen = {}                  # bid -> 历史最大世代（回退检测）
        self.last_write_frame = {}         # bid -> 帧号（cache 交接检测）
        self.owner_free = set()            # consumer_count 扣完即 FREE
        self.left_reads = {}               # bid -> 剩余消费次数
        self.cnt = dict(gen_rollback=0, addr_range=0, cache_handover=0,
                        owner_premature=0, shape=0)

    def _read(self, bid, frame_id, di):
        x = self.b.bufs[bid]
        if x.producer_desc == PRODUCER_EXTERNAL:
            pass                            # 外部输入每帧重写
        elif self.last_write_frame.get(bid) != frame_id:
            self.cnt['cache_handover'] += 1
            raise ReplayError(
                f'cache 交接遗漏：desc{di} 读 buf{bid} 为 '
                f'frame{self.last_write_frame.get(bid)} 旧物（当前 '
                f'frame{frame_id}）')
        if bid in self.owner_free:
            self.cnt['owner_premature'] += 1
            raise ReplayError(f'提前释放后读：desc{di} 读 buf{bid} 已 FREE')
        self.left_reads[bid] = self.left_reads.get(bid, x.consumer_count) - 1
        if self.left_reads[bid] == 0:
            self.owner_free.add(bid)       # 记账式释放（诊断，方案 A）
        return self.store[bid]

    def _write(self, bid, ten, frame_id, di, nbytes_expect=None):
        x = self.b.bufs[bid]
        if int(ten[0].nbytes) > x.size or \
                not (CMA_WINDOW[0] <= x.base and x.base + x.size
                     <= CMA_WINDOW[1]):
            self.cnt['addr_range'] += 1
            raise ReplayError(f'地址越界：desc{di} 写 buf{bid} '
                              f'{ten[0].nbytes}B > size {x.size}')
        if nbytes_expect is not None and int(ten[0].nbytes) != nbytes_expect:
            self.cnt['shape'] += 1
            raise ReplayError(f'shape 违例：desc{di} 写 buf{bid} '
                              f'{int(ten[0].nbytes)} != {nbytes_expect}B')
        g = self.gen.get(bid, 0) + 1
        if g <= self.max_gen.get(bid, 0):
            self.cnt['gen_rollback'] += 1
            raise ReplayError(f'generation 回退：desc{di} 写 buf{bid} '
                              f'gen {g} <= max {self.max_gen.get(bid)}')
        self.gen[bid], self.max_gen[bid] = g, g
        self.last_write_frame[bid] = frame_id
        self.owner_free.discard(bid)
        if self.flt.get('premature_free_bid') == bid:
            self.owner_free.add(bid)       # 负向注入：刚产即"提前释放"
        self.store[bid] = ten

    # -- 帧执行 --------------------------------------------------------------
    def run_frame(self, canvas, frame_id, faults=None):
        """faults：负向注入钩子（正常运行为 None）。返回 (rows, heads_blob)。
        任一不变量破坏抛 ReplayError（fail-closed，不续跑伪造 PASS）。"""
        flt = faults or {}
        self._reset_state(faults)
        rows, heads_blob = [], None
        x0 = (canvas.astype(np.int16) - 128).astype(np.int8)[None] \
            .transpose(0, 3, 1, 2).copy()
        self._write(0, x0, frame_id, -1)          # 外部输入

        for d in self.b.descs:
            if d is None:
                continue
            di, op = d.index, d.opcode
            if flt.get('gen_rollback_bid') == di:
                self.max_gen[d.out] = self.gen.get(d.out, 0) + 5
            try:
                if op == OP_CONV:
                    x = self._read(d.in0, frame_id, di)
                    ib = self.b.bufs[d.in0]
                    if tuple(x.shape[1:]) != (ib.c, ib.h, ib.w):
                        raise ReplayError(
                            f'conv 输入形状 desc{di}: got {x.shape[1:]} '
                            f'buf{(ib.c, ib.h, ib.w)}')
                    k = self.kb[di]
                    y = self.A.forward(k['node'], x,
                                       first=bool(k['z_sum_w']))
                    ob = self.b.bufs[d.out]
                    if tuple(y.shape[1:]) != (d.c, d.h, d.w) or \
                            tuple(y.shape[1:]) != (ob.c, ob.h, ob.w):
                        raise ReplayError(
                            f'shape 三方不一致 desc{di}: got {y.shape[1:]} '
                            f'desc {(d.c, d.h, d.w)} buf '
                            f'{(ob.c, ob.h, ob.w)}')
                    self._write(d.out, y, frame_id, di, ob.size)
                    out = y
                elif op == OP_VIEW:
                    p = self._read(d.in0, frame_id, di)
                    ob, pb = self.b.bufs[d.out], self.b.bufs[d.in0]
                    c0 = (ob.base - pb.base) // (d.h * d.w)   # D-F2d 地址推导
                    y = p[:, c0:c0 + d.c]                      # 零拷贝别名
                    if y.shape != (1, d.c, d.h, d.w):
                        raise ReplayError(f'view 切片形状 desc{di} {y.shape}')
                    self._write(d.out, y, frame_id, di, ob.size)
                    out = y
                elif op == OP_ADD:
                    a = self._read(d.in0, frame_id, di)
                    bb = self._read(d.in1, frame_id, di)
                    if a.shape != bb.shape:
                        raise ReplayError(f'add 异形 desc{di}')
                    qa = self.b.quant[d.prof_in0]
                    qb = self.b.quant[d.prof_in1]
                    A_ = rne_shift(a.astype(np.int64) * qa.m, qa.shift)
                    B_ = rne_shift(bb.astype(np.int64) * qb.m, qb.shift)
                    y = sat_i8(sat_i32(A_ + B_))               # intref 同式
                    self._write(d.out, y, frame_id, di,
                                self.b.bufs[d.out].size)
                    out = y
                elif op == OP_CONCAT:
                    parts, total = [], 0
                    for s in d.segments:
                        p = self._read(s.buf, frame_id, di)
                        if s.nbytes != int(p[0].nbytes):
                            raise ReplayError(
                                f'段长违例 desc{di} seg buf{s.buf} '
                                f'{s.nbytes} != 实际 {int(p[0].nbytes)}B')
                        if s.prof:
                            q = self.b.quant[s.prof]
                            p = sat_i8(rne_shift(
                                p.astype(np.int64) * q.m, q.shift))
                        parts.append(p)
                        total += s.nbytes
                    ob = self.b.bufs[d.out]
                    if total != ob.size or total != d.out_bytes:
                        raise ReplayError(f'Σseg {total} != out {ob.size}')
                    y = np.concatenate(parts, axis=1)
                    self._write(d.out, y, frame_id, di, ob.size)
                    out = y
                elif op == OP_MAXPOOL5:
                    if d.prof_in0 or d.prof_in1:
                        raise ReplayError(f'maxpool5 profile != 0 desc{di}')
                    y = maxpool5(self._read(d.in0, frame_id, di))
                    self._write(d.out, y, frame_id, di,
                                self.b.bufs[d.out].size)
                    out = y
                elif op == OP_UPSAMPLE2:
                    if d.prof_in0 or d.prof_in1:
                        raise ReplayError(f'upsample2 profile != 0 desc{di}')
                    y = upsample_nearest2(self._read(d.in0, frame_id, di))
                    self._write(d.out, y, frame_id, di,
                                self.b.bufs[d.out].size)
                    out = y
                elif op == OP_HEADS:
                    blob_parts, src_detail = [], []
                    for key, s in zip(HEADS_SEG_ORDER, d.segments):
                        ten = self._read(s.buf, frame_id, di)
                        want = HEADS_LAYOUT[key][0]
                        if tuple(ten.shape[1:]) != want or \
                                int(ten[0].nbytes) != s.nbytes:
                            raise ReplayError(f'heads 段 {key} 形状/长度违例')
                        blob_parts.append(np.ascontiguousarray(ten[0]))
                        src_detail.append((key, s.buf))
                    heads_blob = b''.join(x.tobytes() for x in blob_parts)
                    if len(heads_blob) != HEADS_TOTAL_BYTES:
                        raise ReplayError('heads blob != 149100')
                    rows.append({'i': di, 'op': 'heads',
                                 'node': self.oracle[di]['node'],
                                 'buf': None, 'gen': None,
                                 'sha': hashlib.sha256(heads_blob).hexdigest(),
                                 'nerr': None})
                    continue
                else:
                    raise ReplayError(f'未知 opcode 0x{op:02X} desc{di}')
            except ReplayError:
                raise
            rows.append({'i': di, 'op': OPNAME[op],
                         'node': self.oracle[di]['node'], 'buf': d.out,
                         'gen': self.gen.get(d.out),
                         'sha': sha_bytes(out[0]), 'nerr': None})
        return rows, heads_blob


# ----------------------------------------------------------------------------
# 比对（校验侧，D-F2c）
# ----------------------------------------------------------------------------
def compare(frames, fi, rows, store, eng):
    """校验侧（D-F2c）：逐任务 out 对 G0（golden ∪ ext）；heads 对 raw_*。"""
    fr = frames[fi]
    comp, nerr_tot = 0, 0
    for r in rows:
        if r['op'] == 'heads':
            continue
        ref = fr['refs'].get(r['node'])
        if ref is None:
            raise ReplayError(f'oracle 缺参考 {r["node"]}')
        got = store[r['buf']][0]
        neq = int(np.sum(got != ref))
        r['nerr'] = neq
        if neq:
            r['first_mismatch_offset'] = int(np.argmax(got != ref))
        nerr_tot += neq
        comp += 1
    # heads 源逐段比对（§8 序 → G0 raw_*）
    heads_ok, head_detail = True, []
    heads_desc = [d for d in eng.b.descs if d is not None
                  and d.opcode == OP_HEADS][0]
    for key, s in zip(HEADS_SEG_ORDER, heads_desc.segments):
        raw = fr['raws'][HEADS_RAWKEY[key]]
        got = eng.store[s.buf][0]
        ne = int(np.sum(got != raw))
        heads_ok &= (ne == 0)
        head_detail.append({'seg': key, 'buf': s.buf, 'nerr': ne})
    return nerr_tot, comp, (heads_ok, head_detail)


# ----------------------------------------------------------------------------
# 主门
# ----------------------------------------------------------------------------
def run_gate(bins_dir, out_dir, scales):
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    bins = {n: open(os.path.join(bins_dir, n), 'rb').read()
            for n in ('descriptor.bin', 'buffer.bin', 'quant.bin')}
    bin_sha = {k: hashlib.sha256(v).hexdigest() for k, v in bins.items()}
    b = unpack(bins)
    topo = topology_gate(b)

    # D-F2b/c 辅助绑定（k_block=引擎配置；oracle=校验对号）
    kb = {int(k): v for k, v in json.load(
        open(os.path.join(RUN01_MAN, 'k_block_manifest.json'),
             encoding='utf-8'))['convs'].items()}
    oracle = {r['sched_index']: r for r in json.load(
        open(os.path.join(RUN01_MAN, 'oracle_manifest.json'),
             encoding='utf-8'))['rows']}
    eng = SWEngine(b, kb, oracle)
    frames = load_frames()
    n_frames = len(frames)

    report = {'gate': 'F2', 'bins_sha256': bin_sha, 'topology': topo,
              'scales': {}, 'negatives': {}, 'frames': n_frames}
    detail = gzip.open(os.path.join(out_dir, 'frames_detail.jsonl.gz'),
                       'wt', encoding='utf-8')
    sha_ledger = {}                        # (frame_id, bid) -> sha 稳定性账本
    head_ledger = {}                       # frame_id -> blob sha
    all_ok = True

    for N in scales:
        for mode, pick in (('rep', lambda i: 0), ('cyc', lambda i: i % n_frames)):
            agg = {'attempts': 0, 'nerr': 0, 'compared': 0,
                   'heads_ok': True, 'counters': dict(
                       gen_rollback=0, addr_range=0, cache_handover=0,
                       owner_premature=0, shape=0), 'sha_unstable': 0,
                   'exec_rows_total': 0}
            for i in range(N):
                fi = pick(i)
                fr = frames[fi]
                rows, blob = eng.run_frame(fr['canvas'], frame_id=fi)
                nerr, comp, heads = compare(frames, fi, rows, eng.store, eng)
                heads_ok, head_detail = heads
                blob_sha = hashlib.sha256(blob).hexdigest()
                ok = (nerr == 0 and comp == 103 and heads_ok
                      and blob_sha == fr['g0_head_blob_sha']
                      and not any(eng.cnt.values()))
                # SHA 稳定性（重复运行）：同帧同 buffer 必须同 SHA
                for r in rows:
                    if r['buf'] is None:
                        continue
                    key = (fi, r['buf'])
                    if key in sha_ledger and sha_ledger[key] != r['sha']:
                        agg['sha_unstable'] += 1
                        ok = False
                    sha_ledger[key] = r['sha']
                if fi in head_ledger and head_ledger[fi] != blob_sha:
                    agg['sha_unstable'] += 1
                    ok = False
                head_ledger[fi] = blob_sha
                agg['attempts'] += 1
                agg['nerr'] += nerr
                agg['compared'] += comp
                agg['heads_ok'] &= heads_ok
                for k, v in eng.cnt.items():
                    agg['counters'][k] += v
                agg['exec_rows_total'] += len(rows)
                if not ok:
                    all_ok = False
                    first = next((r for r in rows if r.get('nerr')), None)
                    agg['first_error'] = {
                        'attempt': i, 'frame': fi,
                        'task': first and (first['i'], first['node'],
                                           first.get('first_mismatch_offset'))}
                detail.write(json.dumps(
                    {'N': N, 'mode': mode, 'seq': i, 'frame_id': fi,
                     'pass': ok, 'nerr': nerr, 'compared': comp,
                     'heads': head_detail, 'counters': eng.cnt,
                     'head_blob_sha': blob_sha,
                     'g0_head_blob_sha': fr['g0_head_blob_sha'],
                     'tasks': rows}, ensure_ascii=False) + '\n')
            agg['pass'] = (agg['attempts'] == N and agg['nerr'] == 0
                           and agg['compared'] == 103 * N and agg['heads_ok']
                           and agg['sha_unstable'] == 0
                           and not any(agg['counters'].values()))
            report['scales'][f'{mode}{N}'] = agg
            print('%-7s attempts=%-3d nerr=%d compared=%d/%d heads=%s '
                  'cnt=%s sha_unstable=%d -> %s'
                  % (f'{mode}{N}', agg['attempts'], agg['nerr'],
                     agg['compared'], 103 * N, 'OK' if agg['heads_ok'] else 'FAIL',
                     {k: v for k, v in agg['counters'].items() if v} or 0,
                     agg['sha_unstable'], 'PASS' if agg['pass'] else 'FAIL'))
    detail.close()

    # ---- 负向注入（master plan 五类：首错可定位 + 不伪造 PASS） ----------
    def expect_detected(name, fn):
        try:
            fn()
            report['negatives'][name] = 'NOT-DETECTED（门失败）'
            return False
        except ReplayError as e:
            report['negatives'][name] = f'detected: {e}'
            return True

    def n_stride():
        bb = copy.deepcopy(b)
        bb.bufs[1].line_stride = 1
        topology_gate(bb)

    def n_seglen():
        bb = copy.deepcopy(b)
        for d in bb.descs:
            if d is not None and d.opcode == OP_CONCAT:
                d.segments[0].nbytes += 1
                break
        e2 = SWEngine(bb, kb, oracle)
        e2.run_frame(frames[0]['canvas'], 0)
        # 走到这里未被拦截 = NOT-DETECTED（expect_detected 判门失败）

    def n_genrollback():
        e2 = SWEngine(b, kb, oracle)
        di = next(d.index for d in b.descs
                  if d is not None and d.opcode == OP_CONV)
        e2.run_frame(frames[0]['canvas'], 0,
                     faults={'gen_rollback_bid': di})

    def n_premature():
        e2 = SWEngine(b, kb, oracle)
        bid = next(d.in0 for d in b.descs
                   if d is not None and d.opcode == OP_CONCAT)
        e2.run_frame(frames[0]['canvas'], 0,
                     faults={'premature_free_bid': bid})

    def n_frameid():
        # 错误 frame_id：用 frame0 的 canvas 但对 frame2 的 G0 参考比对；
        # 失配必须 >0 且首错可定位，否则 NOT-DETECTED
        rows, blob = eng.run_frame(frames[0]['canvas'], frame_id=0)
        nerr, comp, heads = compare(frames, 2, rows, eng.store, eng)
        if nerr == 0:
            return                          # 未察觉 → NOT-DETECTED（门失败）
        first = next((r for r in rows if r.get('nerr')), None)
        raise ReplayError(
            'frame_id 错配检出：first=%s nerr=%d'
            % (first and (first['i'], first['node'],
                          first.get('first_mismatch_offset')), nerr))

    neg_ok = all([expect_detected('wrong_stride', n_stride),
                  expect_detected('wrong_seglen', n_seglen),
                  expect_detected('gen_rollback', n_genrollback),
                  expect_detected('premature_free', n_premature),
                  expect_detected('wrong_frame_id', n_frameid)])
    report['negatives_pass'] = neg_ok
    report['sha_ledger_buffers'] = len({k[1] for k in sha_ledger})

    verdict = ('PASS' if all_ok and neg_ok
               and all(s['pass'] for s in report['scales'].values())
               else 'FAIL')
    report['verdict'] = verdict
    report['elapsed_s'] = round(time.time() - t0, 1)
    with open(os.path.join(out_dir, 'f2_replay_report.json'), 'w',
              encoding='utf-8') as f:
        json.dump(report, f, ensure_ascii=False, indent=1)
    print('F2_REPLAY %s (%.1fs)' % (verdict, report['elapsed_s']))
    return 0 if verdict == 'PASS' else 1


def main():
    try:
        sys.stdout.reconfigure(encoding='utf-8')
    except Exception:
        pass
    ap = argparse.ArgumentParser(description='PPU-F2 .bin-driven whole-graph '
                                              'replay')
    ap.add_argument('--bins', required=True, help='run01 out 目录（三 .bin）')
    ap.add_argument('--out', required=True, help='证据输出目录')
    ap.add_argument('--scales', default='1,8,32,128')
    args = ap.parse_args()
    scales = [int(x) for x in args.scales.split(',')]
    return run_gate(args.bins, args.out, scales)


if __name__ == '__main__':
    sys.exit(main())
