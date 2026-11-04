#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""f3_prep_n80.py — PPU-F3 仿真备料（M5.0 归位拷出，n80 专用）

母本 = 3_host/yolo_ppu/f3_prep.py（手势线，只读基线；源 SHA256 =
4DD25D099585EE012F3C70FAB073F6A23240C07C2DF68F244D40659EE0C397FC）。
M5.0 归位适配（其余逐行等价；手势隔离禁令下本拷出仅供 n80 物料）：
  M5-N1 sys.path 手式 → accel_bootstrap 边界导入；unpack 取自
        ppu_packer_n80（同目录），ppu_desc_bundle 解析到 abi/。
  M5-N2 CANON 手势绝对路径删除——正典 .bin 目录改为必填命令行参数
        （python f3_prep_n80.py <bundle_dir> <evid_dir> 双必填），禁默认回退手势基线。
  M5-N3 HEADS_OFF 手势 nc=7 常量表删除——改由 ppu_desc_bundle 的
        §8 权威 HEADS_LAYOUT/HEADS_SEG_ORDER 累计派生（单一事实源，
        nc 任意自适应；须与 RTL ppu_engine_mux heads_off 一致，M5.1
        xsim heads 逐字节门即两者的交叉锁）。
  M5-N4 变异用例 L17/L18 view 父缓冲取用从硬编码 bufs[3] 改为
        "任一 view 描述符的父"（n80 表索引布局不同，泛化取用）。

正典 F1 .bin（n80 打包 run 的 out/ 三件套）为唯一输入，产出 TB 消费
的全部数据件：

  G1 Python 九步 loader 镜像 —— 104 真实描述符全过（先于 RTL 定规矩；
     RTL 与本镜像逐步对齐，镜像与手册 §4.3 逐步对齐）
  G2 表镜像 hex —— descriptor/buffer/quant .bin → $readmemh 字表
     （A 集=正典+合成槽位 104..107；B 集=A+变异槽位 108+110..127）
  G3 DDR 预置与金根流 —— 全 104 缓冲 PRNG 图像（D-F3a：确定性 LCG，
     测的是地址/变换精确性，数据真实性是 F2 已关域）+ 逐描述符读/写
     beat 金根流（addr data strb 三列，含 8B 尾部 strb 掩码）
  G4 合成与变异用例 —— S1/S2（1/0 字节段）、S3（last=1 供 stop 门）、
     S4（8B/8B 容量边界正例，V1.3）、L1..L19（九步负向逐条；L19=
     9B>8B 容量负例）写入表位
  G5 manifest_f3.json —— 门单、账目、SHA、种子，TB 与 README 共用

用法：python f3_prep_n80.py <bundle_out_dir(.bin 三件套)> <evid_out_dir>
"""

from __future__ import annotations

import hashlib
import json
import os
import sys

# M5-N1: boundary import via accel_bootstrap (abi/ + ps_host/ on sys.path)
_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..'))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
from ppu_packer_n80 import unpack                        # noqa: E402
from ppu_desc_bundle import (                            # noqa: E402
    CMA_WINDOW, HEADS_LAYOUT, HEADS_SEG_ORDER, HEADS_TOTAL_BYTES,
)

# ---- 常量（与 yolo_csr_pkg.sv / 手册 v1.1 对齐）---------------------------
# M5-N2: CANON 手势绝对路径已删——正典目录由 argv[1] 必填传入
DESC_ITEMS, DESC_WORDS = 128, 32
BUF_ITEMS, BUF_WORDS = 128, 8
QUANT_ITEMS, QUANT_WORDS = 256, 4
OP_CONV, OP_VIEW, OP_ADD, OP_CONCAT = 0x01, 0x10, 0x11, 0x12
OP_MAXPOOL5, OP_UPSAMPLE2, OP_HEADS = 0x13, 0x14, 0x15
XFER_OPS = (OP_CONCAT, OP_HEADS)


# M5-N3: §8 段序累计偏移，从 ppu_desc_bundle 权威布局派生（nc 自适应；
# 手势母本硬编码 [0,102400,128000,134400,145600,148400] 已删）
def _heads_offsets():
    offs, acc = [], 0
    for _k in HEADS_SEG_ORDER:
        offs.append(acc)
        acc += HEADS_LAYOUT[_k][1]
    assert acc == HEADS_TOTAL_BYTES, (acc, HEADS_TOTAL_BYTES)
    return offs


HEADS_OFF = _heads_offsets()                             # 手册 §8
IDENT_M, IDENT_S = 1 << 30, 30

# loader 错误映射（D-F3c：手册 §4.3 只定了步序与"统一报 E_BIT_BUFFER/
# E_BIT_DESC + ERROR_INFO"，bit/code 配对按 pkg 语义归位）
E_BIT_DMA_RD, E_BIT_DMA_WR, E_BIT_DESC, E_BIT_BUFFER, E_BIT_QUANT = 1, 2, 3, 4, 5
E_BIT_TIMEOUT = 7
E_DESC_INVALID, E_ADDR_ALIGN, E_ADDR_REGION = 0x01, 0x13, 0x14

# 合成缓冲区落位（CMA 窗内、避开正典 104 缓冲的空域）
SYN_BASE = 0x1F000000
SYN_BASE_B = 0x1F001000          # B 集变异用例缓冲落位


# ---- RNE（与 RTL/GEMM 尾部同式，位精确）----------------------------------
def rne_shift(n: int, s: int) -> int:
    if s == 0:
        return n
    q = n >> s
    rem = n - (q << s)
    twice = 2 * rem
    adj = 1 if twice > (1 << s) else (-1 if twice < -(1 << s) else 0)
    if adj == 0 and abs(twice) == (1 << s) and (q & 1):
        adj = 1                                                  # tie→偶
    return q + adj


def sat_i8(v: int) -> int:
    return -128 if v < -128 else (127 if v > 127 else v)


def requant(x: int, m: int, s: int) -> int:
    return sat_i8(rne_shift(x * m, s))


# ---- PRNG（确定性 LCG，逐字节；D-F3a）------------------------------------
def prng_bytes(bid: int, n: int) -> bytearray:
    x = (0x9E3779B9 ^ (bid * 2654435761 + 1)) & 0xFFFFFFFF
    out = bytearray(n)
    for i in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out[i] = (x >> 16) & 0xFF
    return out


# ---- Python 九步镜像（与 RTL ppu_loader 逐步对齐）-------------------------
class StepErr(Exception):
    def __init__(self, step, bit, code):
        self.step, self.bit, self.code = step, bit, code


def loader_mirror(d, bufs, quant, desc_words=None):
    """返回 None=过，或 (step,bit,code)。与 RTL 同序：首错即停。"""
    op = d.opcode
    # 步1 opcode
    if not (op == OP_CONV or OP_VIEW <= op <= OP_HEADS):
        raise StepErr(1, E_BIT_DESC, E_DESC_INVALID)
    # 步2 w0 位域（镜像侧由记录字段等价表达）
    if not d.valid or (desc_words is not None and desc_words[0] & 0xFC00):
        raise StepErr(2, E_BIT_DESC, E_DESC_INVALID)
    # 引用集
    ids = [d.in0]
    if op == OP_ADD:
        ids.append(d.in1)
    if op != OP_HEADS:
        ids.append(d.out)
    segs = list(d.segments) if op in XFER_OPS else []
    ids += [s.buf for s in segs]
    # 步3 id 合法 + 项 valid
    for b in ids:
        if b >= BUF_ITEMS or bufs[b] is None or not bufs[b].valid:
            raise StepErr(3, E_BIT_BUFFER, E_DESC_INVALID)
    # 步4 几何（所有引用缓冲统一：C/H/W>0、stride>=W、CHW<=size）
    for b in ids:
        x = bufs[b]
        if x.c == 0 or x.h == 0 or x.w == 0 or x.line_stride < x.w \
                or x.c * x.h * x.w > x.size:
            raise StepErr(4, E_BIT_BUFFER, E_DESC_INVALID)
    # 步5 输入侧 producer（外部 0xFF 豁免；view 的 out=本 desc 产物不查）
    for b in ([d.in0, d.in1] if op == OP_ADD else [d.in0]) + \
             [s.buf for s in segs]:
        pd = bufs[b].producer_desc
        if pd != 0xFF and pd >= d.index:
            raise StepErr(5, E_BIT_BUFFER, E_DESC_INVALID)
    # 步6 地址域 + 8B 对齐（D-F3b：beat 化需要）
    for b in ids:
        x = bufs[b]
        if (x.base >> 32) != 0:
            raise StepErr(6, E_BIT_BUFFER, E_ADDR_REGION)
        if not (CMA_WINDOW[0] <= x.base and x.base + x.size <= CMA_WINDOW[1]):
            raise StepErr(6, E_BIT_BUFFER, E_ADDR_REGION)
        if x.base & 7:
            raise StepErr(6, E_BIT_BUFFER, E_ADDR_ALIGN)
    # 步7 quant（add 双入；concat 段 prof>0 者；heads 恒等豁免；id<256）
    qids = []
    if op == OP_ADD:
        qids += [d.prof_in0, d.prof_in1]
    if op == OP_CONCAT:
        qids += [s.prof for s in segs if s.prof]
    for q in qids:
        if q >= QUANT_ITEMS or quant[q] is None:
            raise StepErr(7, E_BIT_QUANT, E_DESC_INVALID)
    # 步8 段账（concat/heads）——V1.2 删 out.size 等值项（手册 §4.3 步 8
    #   只要求 N_seg≤8 + Σ段长=w14；步 4 允许 size 余量，<8B 张量的 8B
    #   对齐最小分配 size=8 合法，B2 S1 desc104 即此例）；
    #   V1.3 补容量上界（用户 2026-09-22 裁定，与 RTL V1.3 锁步）——删
    #   等值后 w14 与 size 失绑：CHW=8/size=8/Σ=w14=9 可全步通过并向
    #   8B 缓冲 DMA 写 9B。补 concat 且 w14>out.size 拒绝（heads 出侧
    #   走 §8 HEAD_BASE 固定布局，out 槽不取包，与被删等值项同域收窄）。
    if op in XFER_OPS:
        if d.n_seg > 8 or len(segs) != d.n_seg or \
                sum(s.nbytes for s in segs) != d.out_bytes:
            raise StepErr(8, E_BIT_BUFFER, E_DESC_INVALID)
        if op == OP_CONCAT and d.out_bytes > bufs[d.out].size:
            raise StepErr(8, E_BIT_BUFFER, E_DESC_INVALID)
    # 步9 view 边界（c0 地址推导，D-F2d）
    if op == OP_VIEW:
        pb, ob = bufs[d.in0], bufs[d.out]
        hw = d.h * d.w
        off = ob.base - pb.base
        if off < 0 or off % hw or off // hw + d.c > pb.c:
            raise StepErr(9, E_BIT_BUFFER, E_DESC_INVALID)
    return None


# ---- beat 化（8B 对齐基址；尾拍 strb 掩码；lane0=低地址字节）--------------
def beats(addr, data, n=None):
    """(addr,data bytes)→[(beat_addr, u64, strb)]；addr 必须 8B 对齐。"""
    assert addr % 8 == 0
    if n is None:
        n = len(data)
    out = []
    for off in range(0, n, 8):
        chunk = data[off:off + 8]
        chunk = chunk + b'\x00' * (8 - len(chunk))
        u64 = int.from_bytes(chunk, 'little')
        strb = (1 << min(8, n - off)) - 1
        out.append((addr + off, u64, strb))
    return out


def wr_bytes_line(f, lst):
    for a, u, s in lst:
        f.write(f'{a:08X} {u:016X} {s:02X}\n')


# ---- 合成/变异工厂 ---------------------------------------------------------
def mk_desc(idx, op, in0, out, c, h, w, nbytes, valid=1, last=0,
           segs=((0, 0, 0),), n_seg=None):
    words = [0] * DESC_WORDS
    words[0] = op | (valid << 8) | (last << 9)
    words[1] = (idx & 0xFF) | (0xFFFF << 16)
    words[2] = (in0 & 0x3FF) | ((out & 0x3FF) << 20)
    words[3] = (c & 0xFFFF) | ((h & 0xFFFF) << 16)
    words[4] = w & 0xFFFF
    ns = len(segs) if n_seg is None else n_seg
    words[6] = ns & 0xFFFF
    words[13] = 1 | (ns << 8)
    words[14] = nbytes & 0xFFFFFFFF
    for i, (buf, prof, ln) in enumerate(segs):
        words[16 + 2 * i] = (buf & 0x3FF) | ((prof & 0x3FF) << 16)
        words[17 + 2 * i] = ln & 0xFFFFFFFF
    return words


def mk_buf(base, size, c, h, w, producer, valid=1, is_view=0, stride=None):
    words = [0] * BUF_WORDS
    words[0] = base & 0xFFFFFFFF
    words[2] = size & 0xFFFFFFFF
    words[3] = (w if stride is None else stride) & 0xFFFFFFFF
    words[4] = (c & 0xFFFF) | ((h & 0xFFFF) << 16)
    words[5] = (w & 0xFFFF) | (valid << 24) | (is_view << 25)
    words[6] = producer & 0xFF
    return words


def main():
    # M5-N2: 双必填参数——正典 .bin 目录（输入）与证据目录（输出）；
    # 无默认值，禁默认回退任何历史基线
    if len(sys.argv) != 3:
        sys.exit('usage: f3_prep_n80.py <bundle_out_dir(.bin 三件套)> '
                 '<evid_out_dir>')
    canon = os.path.abspath(sys.argv[1])
    evid = os.path.abspath(sys.argv[2])
    prep = os.path.join(evid, 'prep')
    os.makedirs(prep, exist_ok=True)
    bins = {k: open(os.path.join(canon, k + '.bin'), 'rb').read()
            for k in ('descriptor', 'buffer', 'quant')}
    bn = unpack({k + '.bin': v for k, v in bins.items()})
    sha_in = {k: hashlib.sha256(v).hexdigest()
              for k, v in bins.items()}
    bufs, quant, used = bn.bufs, bn.quant, [x for x in bn.descs if x]
    desc_raw = [[int.from_bytes(bins['descriptor'][4 * (i * 32 + w):4 * (i * 32 + w) + 4], 'little')
                 for w in range(32)] for i in range(DESC_ITEMS)]

    # ---- G1 九步镜像 ------------------------------------------------------
    stats, fail = {}, []
    for d in used:
        try:
            loader_mirror(d, bufs, quant, desc_raw[d.index])
            stats[d.opcode] = stats.get(d.opcode, 0) + 1
        except StepErr as e:
            fail.append((d.index, e.step, e.bit, e.code))
    views = [d.index for d in used if d.opcode == OP_VIEW]
    xfer = [d.index for d in used if d.opcode in XFER_OPS]
    assert not fail, f'镜像自身未过: {fail}'
    assert len(used) == 104 and len(views) == 16 and len(xfer) == 14

    # ---- G3 之前：正典缓冲 PRNG 图像 + XFER 拓扑执行金根 ------------------
    bmap = {}                                   # byte addr -> value
    for b in bufs:
        if b is None:
            continue
        img = prng_bytes(b.index, b.size)
        for i, v in enumerate(img):
            bmap[b.base + i] = v

    def rd_bytes(addr, n):
        return bytes(bmap[addr + i] for i in range(n))

    golden, account = {}, {}
    for di in xfer:
        d = bn.descs[di]
        rd_all, wr_all, rb, wb = [], [], 0, 0
        dst = SYN_BASE - 0x1000 if False else None    # 占位防误用
        if d.opcode == OP_CONCAT:
            base_out = bufs[d.out].base
            off = 0
            for s in d.segments:
                data = rd_bytes(bufs[s.buf].base, s.nbytes)
                rd_all += beats(bufs[s.buf].base, data)
                if s.prof:
                    q = quant[s.prof]
                    data = bytes(requant(x, q.m, q.shift) for x in data)
                assert base_out + off == base_out + off
                wr_all += beats(base_out + off, data)
                off += s.nbytes
                rb += s.nbytes
                wb += s.nbytes
        else:                                   # heads：恒等拷贝到 HEAD_BASE
            for s, ho in zip(d.segments, HEADS_OFF):
                data = rd_bytes(bufs[s.buf].base, s.nbytes)
                rd_all += beats(bufs[s.buf].base, data)
                wr_all += beats(0x1F800000 + ho, data)
                rb += s.nbytes
                wb += s.nbytes
                for i, v in enumerate(data):
                    bmap[0x1F800000 + ho + i] = v
        if d.opcode == OP_CONCAT:               # 写侧回灌 bmap 供后续读
            for a, u, s in wr_all:
                for k in range(8):
                    if s >> k & 1:
                        bmap[a + k] = (u >> (8 * k)) & 0xFF
        golden[di] = (rd_all, wr_all)
        account[di] = dict(rd_bytes=rb, wr_bytes=wb,
                           rd_beats=len(rd_all), wr_beats=len(wr_all))

    # ---- G2/G4 表镜像 + 合成 + 变异 ---------------------------------------
    dt_a = [row[:] for row in desc_raw]
    bt = [[0] * BUF_WORDS for _ in range(BUF_ITEMS)]
    for i, b in enumerate(bufs):
        if b is not None:
            bt[i] = [b.base & 0xFFFFFFFF, 0, b.size, b.line_stride,
                     (b.c & 0xFFFF) | ((b.h & 0xFFFF) << 16),
                     (b.w & 0xFFFF) | (b.valid << 24) | (b.is_view << 25)
                     | (b.is_input << 26),
                     b.producer_desc & 0xFF, b.consumer_count & 0xFF]
    qt = [[0] * QUANT_WORDS for _ in range(QUANT_ITEMS)]
    for i, q in enumerate(quant):
        if q is not None:
            qt[i] = [q.m & 0xFFFFFFFF, q.shift & 0xFF, 0, 0]

    # 合成 S1/S2/S3（A 集，槽位 104..106 / 缓冲 104..110）
    dt_a[104] = mk_desc(104, OP_CONCAT, 0, 105, 1, 1, 1, 1,
                        segs=((104, 0, 1),))
    bt[104] = mk_buf(SYN_BASE + 0x00, 8, 1, 1, 1, 0xFF)
    bt[105] = mk_buf(SYN_BASE + 0x08, 8, 1, 1, 1, 104)
    dt_a[105] = mk_desc(105, OP_CONCAT, 0, 108, 40, 1, 1, 40,
                        segs=((106, 0, 0), (107, 0, 40)))
    bt[106] = mk_buf(SYN_BASE + 0x10, 8, 1, 1, 1, 0xFF)
    bt[107] = mk_buf(SYN_BASE + 0x18, 40, 40, 1, 1, 0xFF)
    bt[108] = mk_buf(SYN_BASE + 0x40, 40, 40, 1, 1, 105)
    dt_a[106] = mk_desc(106, OP_CONCAT, 0, 110, 64, 1, 1, 64,
                        last=1, segs=((109, 0, 64),))
    bt[109] = mk_buf(SYN_BASE + 0x70, 64, 64, 1, 1, 0xFF)
    bt[110] = mk_buf(SYN_BASE + 0xB0, 64, 64, 1, 1, 106)
    for i, a in ((104, SYN_BASE), (105, SYN_BASE + 8), (106, SYN_BASE + 0x10),
                 (107, SYN_BASE + 0x18), (108, SYN_BASE + 0x40),
                 (109, SYN_BASE + 0x70), (110, SYN_BASE + 0xB0)):
        img = prng_bytes(i, bt[i][2])
        for k, v in enumerate(img):
            bmap[a + k] = v
    # 读金样尾拍死 lane 取 bmap 实像：AXI 读拍按内存携带全 lane（引擎只
    # 消费 len 内字节），零垫与自产 preload 矛盾（run01 B2_run3 desc104
    # rd 拍0 实测失配）；写侧死 lane 仍零垫（汇编器 V1.2 掩 0 合同）。
    rd104 = beats(SYN_BASE, rd_bytes(SYN_BASE, 1))
    rd104[-1] = (SYN_BASE, int.from_bytes(
        bytes(bmap.get(SYN_BASE + k, 0) for k in range(8)), 'little'), 1)
    golden[104] = (rd104, beats(SYN_BASE + 8, rd_bytes(SYN_BASE, 1)))
    account[104] = dict(rd_bytes=1, wr_bytes=1, rd_beats=1, wr_beats=1)
    golden[105] = (beats(SYN_BASE + 0x18, rd_bytes(SYN_BASE + 0x18, 40)),
                   beats(SYN_BASE + 0x40, rd_bytes(SYN_BASE + 0x18, 40)))
    account[105] = dict(rd_bytes=40, wr_bytes=40, rd_beats=5, wr_beats=5)
    golden[106] = (beats(SYN_BASE + 0x70, rd_bytes(SYN_BASE + 0x70, 64)),
                   beats(SYN_BASE + 0xB0, rd_bytes(SYN_BASE + 0x70, 64)))
    account[106] = dict(rd_bytes=64, wr_bytes=64, rd_beats=8, wr_beats=8)
    # 合成 S4（V1.3 容量边界正例，用户 2026-09-22 裁定）：desc107 8B/8B
    # 满容量——CHW=8/size=8/Σ=w14=8 合法（等值边界，非余量）；段复用
    # buf107 前 8B（prof=0 恒等直通 → wr 字节=rd 字节，无 requant 算术），
    # 出缓冲 bt[111] 落 SYN 区下一空位 +0xF0（buf110 到 0xEF 止；B 集
    # alloc 从槽 112 起，111 两集共用无冲突；读域 preload 已含 buf107 图像）
    dt_a[107] = mk_desc(107, OP_CONCAT, 0, 111, 8, 1, 1, 8,
                        segs=((107, 0, 8),))
    bt[111] = mk_buf(SYN_BASE + 0xF0, 8, 8, 1, 1, 107)
    golden[107] = (beats(SYN_BASE + 0x18, rd_bytes(SYN_BASE + 0x18, 8)),
                   beats(SYN_BASE + 0xF0, rd_bytes(SYN_BASE + 0x18, 8)))
    account[107] = dict(rd_bytes=8, wr_bytes=8, rd_beats=1, wr_beats=1)

    # B 集变异（descs 110..127；缓冲 112..127；逐条唯一触发步号）
    dt_b = [row[:] for row in dt_a]
    bt_b = [row[:] for row in bt]
    cur_buf = 112
    cur_off = 0

    def alloc(size, c, h, w, producer, valid=1, is_view=0, base=None,
              stride=None):
        nonlocal cur_buf, cur_off
        bid = cur_buf
        cur_buf += 1
        a = base if base is not None else SYN_BASE_B + cur_off
        cur_off += max(size, 8) + 8
        bt_b[bid] = mk_buf(a, size, c, h, w, producer, valid, is_view, stride)
        return bid

    def bi():        # 常规输入缓冲（64B）
        return alloc(64, 64, 1, 1, 0xFF)

    def bo(pd):      # 常规输出缓冲（64B）
        return alloc(64, 64, 1, 1, pd)

    L = {}

    def case(name, words, expect):
        idx = 110 + len(L)
        words[1] = (idx & 0xFF) | (words[1] & 0xFFFF00)   # w1 槽位自洽
        L[name] = dict(desc=idx, step=expect[0], bit=expect[1],
                       code=expect[2])
        dt_b[idx] = words

    i0 = bi(); o0 = bo(110)
    # L1/L2/L3/L4 等 opcode/w0 位违例用例不触段表（步 1/2 先停），
    # segs 形状统一三元组
    case('L1_opcode0', mk_desc(110, 0x00, i0, o0, 64, 1, 1, 64,
                               segs=((i0, 0, 64),)), (1, 3, 1))
    case('L2_opcode_rsv', mk_desc(111, 0x2F, i0, o0, 64, 1, 1, 64,
                                  segs=((i0, 0, 64),)), (1, 3, 1))
    case('L3_valid0', mk_desc(114, OP_CONCAT, i0, o0, 64, 1, 1, 64,
                              valid=0, segs=((i0, 0, 64),)), (2, 3, 1))
    w4 = mk_desc(113, OP_CONCAT, i0, o0, 64, 1, 1, 64)
    w4[0] |= (1 << 10)                          # first=1 → 步2
    case('L4_first_bit', w4, (2, 3, 1))
    iv = alloc(64, 64, 1, 1, 0xFF, valid=0)     # valid=0 项 → 步3
    case('L5_buf_invalid', mk_desc(114, OP_CONCAT, iv, o0, 64, 1, 1, 64), (3, 4, 1))
    case('L6_out_null', mk_desc(115, OP_CONCAT, i0, 0x3FF, 64, 1, 1, 64), (3, 4, 1))
    ic0 = alloc(64, 0, 1, 1, 0xFF)              # C=0 → 步4
    case('L7_c_zero', mk_desc(116, OP_CONCAT, ic0, o0, 64, 1, 1, 64), (4, 4, 1))
    ist = alloc(64, 8, 1, 8, 0xFF, stride=1)    # stride(1)<W(8) → 步4
    case('L8_stride_lt_w', mk_desc(117, OP_CONCAT, ist, o0, 64, 1, 1, 64), (4, 4, 1))
    ism = alloc(8, 64, 1, 1, 0xFF)              # CHW>size → 步4
    case('L9_chw_gt_size', mk_desc(118, OP_CONCAT, ism, o0, 64, 1, 1, 64), (4, 4, 1))
    ipd = alloc(64, 64, 1, 1, 200)              # producer>=id → 步5
    case('L10_producer', mk_desc(119, OP_CONCAT, ipd, o0, 64, 1, 1, 64), (5, 4, 1))
    ihi = alloc(64, 64, 1, 1, 0xFF)
    bt_b[ihi][1] = 1                            # base 高字≠0 → 步6
    case('L11_base_hi', mk_desc(120, OP_CONCAT, ihi, o0, 64, 1, 1, 64), (6, 4, 0x14))
    ireg = alloc(64, 64, 1, 1, 0xFF, base=0x1FFFF000)
    bt_b[ireg][2] = 0x2000                      # base+size>窗端 → 步6
    case('L12_region', mk_desc(121, OP_CONCAT, ireg, o0, 64, 1, 1, 64), (6, 4, 0x14))
    ial = alloc(64, 64, 1, 1, 0xFF, base=SYN_BASE_B + 4)   # 非 8B 对齐 → 步6
    case('L13_align', mk_desc(122, OP_CONCAT, ial, o0, 64, 1, 1, 64), (6, 4, 0x13))
    case('L14_quant_id', mk_desc(123, OP_CONCAT, i0, o0, 64, 1, 1, 64,
                                 segs=((i0, 300, 64),)), (7, 5, 1))
    case('L15_nseg9', mk_desc(124, OP_CONCAT, i0, o0, 64, 1, 1, 64,
                              segs=((i0, 0, 64),), n_seg=9), (8, 4, 1))
    case('L16_sum_ne_w14', mk_desc(125, OP_CONCAT, i0, o0, 64, 1, 1, 72,
                                   segs=((i0, 0, 64),)), (8, 4, 1))
    _vpar_id = next(d.in0 for d in used if d.opcode == OP_VIEW)
    par = bufs[_vpar_id]       # M5-N4: 真 view 父缓冲（任一 view 的父）
    hw = par.h * par.w
    ovw = alloc((par.c + 1) * hw, par.c + 1, par.h, par.w, 127,
                is_view=1, base=par.base)       # c1=C+1≠父 C → 步9
    case('L17_view_c1', mk_desc(126, OP_VIEW, _vpar_id, ovw, par.c + 1,
                                par.h, par.w, par.c * par.h * par.w), (9, 4, 1))
    ovx = alloc(hw, 1, par.h, par.w, 127, is_view=1,
                base=par.base + 8)              # 偏移非 H·W 倍 → 步9
    case('L18_view_off', mk_desc(127, OP_VIEW, _vpar_id, ovx, 1, par.h,
                                 par.w, hw), (9, 4, 1))
    # L19 容量上界（V1.3，用户 2026-09-22 裁定）：CHW=8/size=8/Σ=w14=9
    # ——步 4（8≤8）与旧步 8 三项（n_seg/present/Σ=w14）全过，仅新容量
    # 项 w14>out.size 拒绝（9B 拒入 8B 缓冲）。槽 108 直挂（case() 的
    # 110+len 序号机制只发 110..127；108/109 为合成区后空闲槽）
    dt_b[108] = mk_desc(108, OP_CONCAT, 0, 111, 8, 1, 1, 9,
                        segs=((107, 0, 9),))
    L['L19_cap_w14'] = dict(desc=108, step=8, bit=4, code=1)

    # B 集镜像自检：每条唯一命中预期步号（防误造通过例）
    import copy
    class Rec:                                   # 极小记录替身
        pass
    for name, c in L.items():
        ws = dt_b[c['desc']]
        segs = [type('S', (), {'buf': ws[16 + 2 * i] & 0x3FF,
                               'prof': (ws[16 + 2 * i] >> 16) & 0x3FF,
                               'nbytes': ws[17 + 2 * i]})()
                for i in range(8) if ws[16 + 2 * i] or ws[17 + 2 * i]]
        r = Rec()
        r.index = c['desc']; r.opcode = ws[0] & 0xFF
        r.valid = (ws[0] >> 8) & 1; r.last = (ws[0] >> 9) & 1
        r.in0 = ws[2] & 0x3FF; r.in1 = (ws[2] >> 10) & 0x3FF
        r.out = (ws[2] >> 20) & 0x3FF
        r.c = ws[3] & 0xFFFF; r.h = ws[3] >> 16; r.w = ws[4] & 0xFFFF
        r.prof_in0 = ws[5] & 0xFFFF; r.prof_in1 = ws[5] >> 16
        r.n_seg = ws[6] & 0xFFFF; r.segments = segs
        r.out_bytes = ws[14] & 0xFFFFFFFF
        fake_bufs = [None] * BUF_ITEMS
        for i2 in range(BUF_ITEMS):
            if any(bt_b[i2]):
                fake_bufs[i2] = type('B', (), {
                    'base': (bt_b[i2][1] << 32) | bt_b[i2][0],
                    'size': bt_b[i2][2], 'line_stride': bt_b[i2][3],
                    'c': bt_b[i2][4] & 0xFFFF, 'h': bt_b[i2][4] >> 16,
                    'w': bt_b[i2][5] & 0xFFFF,
                    'valid': (bt_b[i2][5] >> 24) & 1,
                    'is_view': (bt_b[i2][5] >> 25) & 1,
                    'producer_desc': bt_b[i2][6] & 0xFF})()
        for i2 in range(BUF_ITEMS):              # 正典缓冲沿用真记录
            if bufs[i2] is not None and not any(bt_b[i2]):
                fake_bufs[i2] = bufs[i2]
        try:
            got = loader_mirror(r, fake_bufs, quant, ws)
            assert got is None, f'{name} 意外通过'
            raise SystemExit(f'{name} 应失败却通过')
        except StepErr as e:
            assert (e.step, e.bit, e.code) == (c['step'], c['bit'],
                                               c['code']), \
                f"{name} 命中 ({e.step},{e.bit},{e.code}) != 预期"

    # ---- 写文件 ------------------------------------------------------------
    def wr_hex(path, tab, words):
        with open(path, 'w') as f:
            for row in tab:
                for w2 in row[:words]:
                    f.write(f'{w2:08X}\n')

    wr_hex(os.path.join(prep, 'desc_table_A.hex'), dt_a, DESC_WORDS)
    wr_hex(os.path.join(prep, 'buf_table_A.hex'), bt, BUF_WORDS)
    wr_hex(os.path.join(prep, 'quant_table_A.hex'), qt, QUANT_WORDS)
    wr_hex(os.path.join(prep, 'desc_table_B.hex'), dt_b, DESC_WORDS)
    wr_hex(os.path.join(prep, 'buf_table_B.hex'), bt_b, BUF_WORDS)

    # DDR 预置：XFER 读域+合成读域的 beat 图像（只预置将被读的拍，未读报错）
    pre = set()
    for di in xfer:
        for a, u, s in golden[di][0]:
            pre.add(a)
    for di in (104, 105, 106, 107):
        for a, u, s in golden[di][0]:
            pre.add(a)
    with open(os.path.join(prep, 'preload.txt'), 'w') as f:
        for a in sorted(pre):
            chunk = bytes(bmap.get(a + k, 0) for k in range(8))
            f.write(f'{a:08X} {int.from_bytes(chunk, "little"):016X} FF\n')

    for di in list(xfer) + [104, 105, 106, 107]:
        with open(os.path.join(prep, f'rd_golden_{di}.txt'), 'w') as f:
            wr_bytes_line(f, golden[di][0])
        with open(os.path.join(prep, f'wr_golden_{di}.txt'), 'w') as f:
            wr_bytes_line(f, golden[di][1])

    man = dict(
        src=dict(dir=canon, sha256=sha_in),
        gate=dict(loader_total=len(used), views=views, xfer=xfer,
                  synth=[104, 105, 106, 107]),
        loader_cases=L,
        account={str(k): v for k, v in account.items()},
        heads_base=0x1F800000,
        quant_used={str(i): [quant[i].m, quant[i].shift]
                    for i in sorted({q for d in used if d.opcode in XFER_OPS
                                     for q in [s.prof for s in d.segments
                                               if s.prof]} |
                                    {p for d in used if d.opcode == OP_ADD
                                     for p in (d.prof_in0, d.prof_in1)})},
        d3=dict(test_data='PRNG-LCG per buffer id（D-F3a）',
                align8='所有正典 base 8B 对齐已核',
                err_map='D-F3c', quant_loaded='全 256 项视为已装载（D-F3g）'),
    )
    with open(os.path.join(prep, 'manifest_f3.json'), 'w',
              encoding='utf-8') as f:
        json.dump(man, f, ensure_ascii=False, indent=1, sort_keys=True)

    # SHA 清单
    sha_out = {}
    for fn in sorted(os.listdir(prep)):
        p = os.path.join(prep, fn)
        sha_out[fn] = hashlib.sha256(open(p, 'rb').read()).hexdigest()
    with open(os.path.join(prep, 'prep_sha256.txt'), 'w') as f:
        for k, v in sha_out.items():
            f.write(f'{v}  {k}\n')

    print(f'[f3_prep] loader mirror: 104/104 PASS '
          f'(views={len(views)} xfer={len(xfer)} conv/add/pool={104-16-14})')
    print(f'[f3_prep] xfer bytes rd={sum(v["rd_bytes"] for k, v in account.items() if int(k) < 104)} '
          f'wr={sum(v["wr_bytes"] for k, v in account.items() if int(k) < 104)}')
    print(f'[f3_prep] loader cases: {len(L)}（B 集）每条镜像命中预期步号')
    print(f'[f3_prep] artifacts → {prep}（{len(sha_out)} 件）')


if __name__ == '__main__':
    main()
