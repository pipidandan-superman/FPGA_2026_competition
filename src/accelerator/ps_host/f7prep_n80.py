#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""f7prep_n80.py — M5.1 walker 备料（tb_ppu_f7 F7A-D 消费件，n80 物料）。

生成（全部 PRNG 帧像 + 纯参考数学；无手势张量——隔离禁令）：
  - desc/buf/quant 三 A 表：SHA 链复制自本 run F3 备料（out/prep，其
    谱系 = F1 out/bundle 三 .bin → f3_prep_n80）；表与金样同源同表字节。
  - preload_f0..f4.txt：帧像（D-F3a LCG 律，帧参数化种子扩展）
  - rd/wr_golden_f{fr}_{di}.txt：25 引擎任务 × 5 帧读/写拍金样
  - desc_table_D1/D2/D3.hex：协议负例 splice（f6_prep 同式）
  - manifest_f7prep.json + prep_sha256.txt + prep_run.log

参考数学谱系（nc 无关实现遗产，逐字内移植 + 出处注明）：
  wr_golden/rd_golden/preload 式/区域互斥 : f5ad_prep.py（F5AD run 源）
  beat_rows / mp5_ref                    : f5m_prep.py
  ups2_ref                               : f5c_prep.py
  add_ref / add_rd_rows / CHUNK=64       : f5aa_prep.py
  rne_shift / sat_i8（intref 原语）       : 12_yolo_accel/tools/intref_yolov8.py

requant 符号律（本生成器对 F3 时代模型的修正，负载-bearing）：
  RTL yolo_ppu_xfer.sv L172 与 yolo_ppu_add.sv L130-131 均为
  $signed({{24{x[7]}}, x}) * $signed(m) —— 数据字节按 int8 符号扩展。
  F3 时代 f3_prep.requant 按无符号 byte 计算（该路径从未被 walker 级
  字节比较消费）；walker 级正典（F5AD SWEngine / f5aa add_ref）为
  signed int8 并在 f7xsm_run01 F7A-D 与板上逐字节验证。本生成器按
  RTL 律执行 signed requant。
恒等捷径（三支模型，ppu_engine_mux.v L523-524 + xfer L116）：
  seg prof==0 → shell 写 IDENT(2^30,30) → 引擎旁路原字节；
  prof 指向 (2^30,30) 单元 → 同旁路；否则 signed requant。

用法：python f7prep_n80.py <run_out_dir> [dst_dir]
  <run_out_dir> = 含 bundle/ 与 prep/ 的 run out 目录
  [dst_dir]     = 输出目录（默认 <run_out_dir>/prep_f7）
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))
_ROOT = os.path.abspath(os.path.join(_HERE, '..'))
for _p in (_HERE, os.path.join(_ROOT, 'tools'), _ROOT):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import numpy as np                                 # noqa: E402
import ppu_packer_n80 as PK                        # noqa: E402
from ppu_desc_bundle import (                      # noqa: E402
    HEADS_LAYOUT, HEADS_SEG_ORDER, HEADS_TOTAL_BYTES,
)

try:
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
except Exception:
    pass

OP_CONV, OP_VIEW, OP_ADD, OP_CONCAT = 0x01, 0x10, 0x11, 0x12
OP_MP5, OP_UPS, OP_HEADS = 0x13, 0x14, 0x15
CHUNK = 64                                         # f5aa：ADD 交替块
N_FRAMES = 5

# tb_ppu_f7.sv L3543 PROG 字面量（三重锁之一：bundle ↔ TB ↔ v11）
TB_PROG = [7, 8, 16, 19, 20, 28, 31, 32, 40, 41, 44, 45, 46, 47,
           49, 50, 56, 58, 59, 65, 68, 74, 77, 83, 103]
V11_MAN = (r'E:\competition\4_metrics\logs\2026-10-06_yolo_m3_manifests_v11'
           r'_run01\out\p2_manifests_n80_v11\descriptor_table.json')
RTL_MUX = os.path.join(_ROOT, 'yolo_graph', 'rtl', 'PPU', 'shell',
                       'ppu_engine_mux.v')
RTL_XFER = os.path.join(_ROOT, 'yolo_graph', 'rtl', 'PPU', 'xfer',
                        'yolo_ppu_xfer.sv')
RTL_ADD = os.path.join(_ROOT, 'yolo_graph', 'rtl', 'PPU', 'add',
                       'yolo_ppu_add.sv')
HEAD_BASE = 0x1F800000


def sha_b(x: bytes) -> str:
    return hashlib.sha256(x).hexdigest()


def sha_f(p: str) -> str:
    h = hashlib.sha256()
    with open(p, 'rb') as f:
        for blk in iter(lambda: f.read(1 << 20), b''):
            h.update(blk)
    return h.hexdigest()


# ---- PRNG（D-F3a LCG 律；M5 帧参数化扩展：seed ^= (fr+1)*0x85EBCA6B）----
def prng_bytes(bid: int, n: int, fr: int) -> bytearray:
    x = (0x9E3779B9 ^ (bid * 2654435761 + 1)
         ^ ((fr + 1) * 0x85EBCA6B)) & 0xFFFFFFFF
    out = bytearray(n)
    for i in range(n):
        x = (1664525 * x + 1013904223) & 0xFFFFFFFF
        out[i] = (x >> 16) & 0xFF
    return out


# ---- beat 行（f5m_prep.py L78-89 逐字）----------------------------------
def beat_rows(data: bytes, base: int, force_ff=False):
    pad = (-len(data)) % 8
    d = data + b'\x00' * pad
    rows = []
    for k in range(len(d) // 8):
        v = min(8, len(data) - 8 * k)
        mask = 0xFF if (force_ff or v == 8) else (1 << v) - 1
        rows.append((base + 8 * k,
                     int.from_bytes(d[8 * k:8 * k + 8], 'little'),
                     mask))
    return rows


def wr_rows(raw, base):
    return beat_rows(raw, base)


def rd_rows(parts):
    rows = []
    for raw, base in parts:
        rows += beat_rows(raw, base)
    return rows


# ---- 参考数学（f5aa/f5m/f5c 逐字移植；requant signed 律见模件头注）------
def rne_shift(n, s):
    """tools/intref_yolov8.py L37-59 逐字（仅 numpy 依赖；母本模块顶层
    import torch 故内植）。floor + rem>half 进位 + tie→偶（q LSB）。"""
    s = int(s)
    if s <= 0:
        if s == 0:
            return n.astype(np.int64)
        v = n.astype(np.int64) << (-s)
        assert np.abs(v).max(initial=0) < 2 ** 63, 'shift-left overflow'
        return v
    q = n >> s                      # arithmetic floor
    rem = n - (q << s)              # (-2^s, 2^s)
    twice = rem * 2
    full = 1 << s                   # tie threshold: |2*rem| == 2^s
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q


def sat_i8(x):
    """tools/intref_yolov8.py L62-63 逐字。"""
    return np.clip(x, -128, 127).astype(np.int8)


def add_ref(raw_a, raw_b, m0, s0, m1, s1):
    """f5aa_prep.py L104-111 逐字（int8 符号律 = RTL add L130-131）。"""
    a = np.frombuffer(bytes(raw_a), dtype=np.int8).astype(np.int64)
    b = np.frombuffer(bytes(raw_b), dtype=np.int8).astype(np.int64)
    A_ = rne_shift(a * m0, s0)
    B_ = rne_shift(b * m1, s1)
    return sat_i8(A_ + B_).tobytes()


def requant_vec(raw, m, s):
    """xfer 段 requant：signed int8 × signed m，RNE tie→even，sat_i8
    （RTL xfer L172 符号扩展律；rne_shift 与 RTL S3 方程逐位等价）。"""
    x = np.frombuffer(bytes(raw), dtype=np.int8).astype(np.int64)
    return sat_i8(rne_shift(x * m, s)).tobytes()


def mp5_ref(raw, c, h, w):
    """f5m_prep.py L92-118 逐字（pad 种子 -128，CHW 线性同形输出）。"""
    def sgn(b):
        return b - 256 if b > 127 else b

    out = bytearray()
    a = bytes(raw)
    for ci in range(c):
        b0 = ci * h * w
        for y in range(h):
            for x in range(w):
                m = -128
                for dy in range(-2, 3):
                    yy = y + dy
                    if not (0 <= yy < h):
                        continue
                    for dx in range(-2, 3):
                        xx = x + dx
                        if 0 <= xx < w:
                            v = sgn(a[b0 + yy * w + xx])
                            if v > m:
                                m = v
                out.append(m & 0xFF)
    return bytes(out)


def ups2_ref(raw, c, h, w):
    """f5c_prep.py L63-73 逐字（行内 ×2 再整行重复）。"""
    out = bytearray()
    a = bytes(raw)
    for ci in range(c):
        b0 = ci * h * w
        for y in range(h):
            row = a[b0 + y * w: b0 + (y + 1) * w]
            r2 = bytes(bb for bb in row for _ in range(2))
            out += r2 + r2
    return bytes(out)


def add_rd_rows(raw0, raw1, b0, b1, chunk=CHUNK):
    """f5aa_prep.py L114-143 逐字（64B 块 A/B 交替，side0=in0 先读）。"""
    img0 = bytes(raw0) + b'\x00' * ((-len(raw0)) % 8)
    img1 = bytes(raw1) + b'\x00' * ((-len(raw1)) % 8)
    rows = []
    off0 = off1 = 0
    side = 0
    while off0 < len(raw0) or off1 < len(raw1):
        if side == 0 and off0 < len(raw0):
            base, img, off, tot = b0, img0, off0, len(raw0)
        elif side == 1 and off1 < len(raw1):
            base, img, off, tot = b1, img1, off1, len(raw1)
        elif off0 < len(raw0):
            base, img, off, tot = b0, img0, off0, len(raw0)
        else:
            base, img, off, tot = b1, img1, off1, len(raw1)
        cl = min(chunk, tot - off)
        nb = (cl + 7) // 8
        for k in range(nb):
            a = base + off + 8 * k
            d = int.from_bytes(img[off + 8 * k:off + 8 * k + 8], 'little')
            rows.append((a, d, 0xFF))
        if base == b0:
            off0 += cl
        else:
            off1 += cl
        side ^= 1
    return rows


# ---- 区域合并（preload 同基/嵌套去重；仅合并真重叠，不合并相接）--------
def merge_regions(regs):
    """regs = [(base, size, tag)] → 合并重叠区域 [(lo, hi, [tags])]。"""
    rs = sorted((b, b + s, t) for b, s, t in regs)
    out = []
    for lo, hi, t in rs:
        if out and lo < out[-1][1]:
            out[-1][1] = max(out[-1][1], hi)
            out[-1][2].append(t)
        else:
            out.append([lo, hi, [t]])
    return [(lo, hi, ts) for lo, hi, ts in out]


def sgn32(v):
    return v - (1 << 32) if v >= (1 << 31) else v


def main():
    if len(sys.argv) not in (2, 3):
        print('usage: f7prep_n80.py <run_out_dir> [dst_dir]')
        return 2
    RUN = os.path.abspath(sys.argv[1])
    DST = os.path.abspath(sys.argv[2]) if len(sys.argv) == 3 \
        else os.path.join(RUN, 'prep_f7')
    PREP = os.path.join(RUN, 'prep')
    BUND = os.path.join(RUN, 'bundle')
    os.makedirs(DST, exist_ok=True)
    log = open(os.path.join(DST, 'prep_run.log'), 'w', encoding='utf-8')

    def say(msg):
        print(msg)
        log.write(msg + '\n')
        log.flush()

    # ---- 0. 源锁定：bin SHA 对 manifest_f3 谱系；表 SHA 对 prep 链 -------
    mf3 = json.load(open(os.path.join(PREP, 'manifest_f3.json'),
                         encoding='utf-8'))
    bins = {}
    for k in ('descriptor', 'buffer', 'quant'):
        p = os.path.join(BUND, k + '.bin')
        bins[k + '.bin'] = open(p, 'rb').read()
        got = sha_b(bins[k + '.bin'])
        assert got == mf3['src']['sha256'][k], \
            f'{k}.bin SHA 漂移: {got} != manifest_f3 {mf3["src"]["sha256"][k]}'
    chain = {}
    for line in open(os.path.join(PREP, 'prep_sha256.txt'), encoding='utf-8'):
        parts = line.split()
        if len(parts) == 2:
            chain[parts[1]] = parts[0]
    tables = {}
    for name in ('desc_table_A.hex', 'buf_table_A.hex', 'quant_table_A.hex'):
        src = os.path.join(PREP, name)
        got = sha_f(src)
        assert name in chain and chain[name] == got, \
            f'{name} SHA 不在 prep_sha256 链（{got}）'
        tables[name] = open(src, 'rb').read()
        open(os.path.join(DST, name), 'wb').write(tables[name])
        assert sha_f(os.path.join(DST, name)) == got
    say('[0] 源锁定 OK：三 .bin + 三 A 表 SHA 链复制（F1/F3 谱系不变）')

    # ---- 1. bundle 解包 + 类别推导 + 三重锁 ------------------------------
    b = PK.unpack(bins)
    D, B, Q = b.descs, b.bufs, b.quant

    ADD_D = [i for i in range(104) if D[i] and D[i].opcode == OP_ADD]
    CAT_D = [i for i in range(104) if D[i] and D[i].opcode == OP_CONCAT]
    MP5_D = [i for i in range(104) if D[i] and D[i].opcode == OP_MP5]
    UPS_D = [i for i in range(104) if D[i] and D[i].opcode == OP_UPS]
    HD_D = [i for i in range(104) if D[i] and D[i].opcode == OP_HEADS]
    ENG = sorted(ADD_D + CAT_D + MP5_D + UPS_D + HD_D)
    assert ENG == TB_PROG, f'bundle 引擎任务 {ENG} != TB PROG {TB_PROG}'

    v11 = json.load(open(V11_MAN, encoding='utf-8'))
    v11_eng = [e['desc_id'] for e in v11['entries']
               if e['op'] not in ('conv', 'view')]
    assert sorted(v11_eng) == ENG == TB_PROG, \
        f'v11 引擎任务 {sorted(v11_eng)} != {ENG}'
    say(f'[1] 三重锁 OK：bundle == tb_ppu_f7 PROG == v11（{len(ENG)} 任务：'
        f'add{len(ADD_D)} cat{len(CAT_D)} mp5{len(MP5_D)} ups{len(UPS_D)} '
        f'heads{len(HD_D)}）')

    # RTL 交叉锁：heads_off 六常量 == §8 累计；xfer/add 符号扩展律在场
    off, acc = [], 0
    for k in HEADS_SEG_ORDER:
        off.append(acc)
        acc += HEADS_LAYOUT[k][1]
    assert acc == HEADS_TOTAL_BYTES
    mux = open(RTL_MUX, encoding='utf-8').read()
    for i, v in enumerate(off):
        label = 'default' if i == len(off) - 1 else str(i)
        assert re.search(r"%s:\s*heads_off = 32'd%d;" % (label, v), mux), \
            f'ppu_engine_mux heads_off[{i}] != {v}（§8 累计律破坏）'
    xf = open(RTL_XFER, encoding='utf-8').read()
    ad = open(RTL_ADD, encoding='utf-8').read()
    assert "{{24{x1_r[7]}}, x1_r}) * $signed(m1_r)" in xf, 'xfer 符号律漂移'
    assert "{{24{x1a_r[7]}}, x1a_r}) * $signed(ma_r)" in ad, 'add 符号律漂移'
    say(f'[1b] RTL 锁 OK：heads_off={off}（§8）+ xfer/add $signed 字节律')

    # ---- 2. 静态合同（结构关系；无 nc 常数）------------------------------
    for di in ADD_D:
        d = D[di]
        assert d.valid and not d.last and d.n_seg == 1 and not d.segments
        bi, bj, bo = B[d.in0], B[d.in1], B[d.out]
        c, h, w = bi.c, bi.h, bi.w
        assert (d.c, d.h, d.w) == (c, h, w) == \
            (bj.c, bj.h, bj.w) == (bo.c, bo.h, bo.w), f'desc{di} 三槽不同形'
        chw = c * h * w
        assert chw == d.out_bytes == bo.size == bi.size == bj.size
        assert chw % 8 == 0, f'desc{di} ADD chw%8!=0（尾拍合同未证域）'
        for qid in (d.prof_in0, d.prof_in1):
            assert qid < 256 and Q[qid] is not None, f'desc{di} quant {qid}'
    for di in MP5_D:
        d = D[di]
        assert d.valid and not d.last and d.n_seg == 1 and not d.segments \
            and d.mode == 0
        bi, bo = B[d.in0], B[d.out]
        c, h, w = bi.c, bi.h, bi.w
        assert (d.c, d.h, d.w) == (c, h, w) == (bo.c, bo.h, bo.w), \
            f'desc{di} mp5 出入同形破坏'
        assert c * h * w == bi.size == bo.size == d.out_bytes
    for di in UPS_D:
        d = D[di]
        assert d.valid and not d.last and d.n_seg == 1 and not d.segments \
            and d.mode == 0
        bi, bo = B[d.in0], B[d.out]
        c, h, w = bi.c, bi.h, bi.w
        assert (d.c, d.h, d.w) == (c, 2 * h, 2 * w) == (bo.c, bo.h, bo.w)
        assert bi.size == c * h * w and 4 * c * h * w == d.out_bytes == bo.size
    nseg_eq = 0
    for di in CAT_D:
        d = D[di]
        assert d.valid and not d.last and d.n_seg == len(d.segments) \
            and 1 <= d.n_seg <= 8
        assert sum(s.nbytes for s in d.segments) == d.out_bytes \
            and d.out_bytes <= B[d.out].size, f'desc{di} 段账/w14 破坏'
        for s in d.segments:
            assert B[s.buf] is not None and B[s.buf].size >= s.nbytes, \
                f'desc{di} 段 buf{s.buf} 容量'
            assert s.nbytes % 8 == 0, f'desc{di} 段长%8!=0（尾拍合同未证域）'
            if B[s.buf].size == s.nbytes:
                nseg_eq += 1
            if s.prof:
                assert s.prof < 256 and Q[s.prof] is not None, \
                    f'desc{di} 段 quant {s.prof}'
    assert HD_D == [103]
    hd = D[103]
    assert hd.valid and hd.last and hd.n_seg == 6 and hd.out == 0x3FF
    assert [s.nbytes for s in hd.segments] == \
        [HEADS_LAYOUT[k][1] for k in HEADS_SEG_ORDER]
    assert sum(s.nbytes for s in hd.segments) == HEADS_TOTAL_BYTES
    for s in hd.segments:
        assert s.prof == 0 and B[s.buf].size == s.nbytes \
            and s.nbytes % 8 == 0
    say(f'[2] 静态合同 OK（CAT 段 buf size==nbytes {nseg_eq}/'
        f'{sum(len(D[i].segments) for i in CAT_D)}；heads 六段恒等 Σ='
        f'{HEADS_TOTAL_BYTES}）')

    # ---- 3. 预载集 + 区域律 ------------------------------------------------
    RTL_OUT = ({D[i].out for i in CAT_D} | {D[i].out for i in MP5_D + UPS_D}
               | {D[i].out for i in ADD_D})
    reads = ({s.buf for i in CAT_D for s in D[i].segments}
             | {D[i].in0 for i in MP5_D + UPS_D}
             | {s.buf for s in hd.segments}
             | {D[i].in0 for i in ADD_D} | {D[i].in1 for i in ADD_D})
    PRE = sorted(reads - RTL_OUT)
    n_view = sum(1 for bid in reads if B[bid].is_view)
    pl_regs = [(B[k].base, B[k].size, k) for k in PRE]
    wr_regs = [(B[D[i].out].base, D[i].out_bytes, i)
               for i in ENG if D[i].opcode != OP_HEADS]
    wr_regs.append((HEAD_BASE, HEADS_TOTAL_BYTES, 103))
    merged = merge_regions(pl_regs)
    say(f'[3] 预载集 {len(PRE)} buf（含 view {n_view}，平读模型）→ '
        f'{len(merged)} 互斥区；RTL 写区 {len(wr_regs)}（含 HEAD_BASE）')
    for lo, hi, ts in merged:
        for b0, sz, t in wr_regs:
            assert hi <= b0 or b0 + sz <= lo, \
                f'预载区 [{lo:#x},{hi:#x}) 与 desc{t} 写区重叠'
    for i in range(len(wr_regs)):
        for j in range(i + 1, len(wr_regs)):
            a0, asz, ai = wr_regs[i]
            c0, csz, ci = wr_regs[j]
            assert a0 + asz <= c0 or c0 + csz <= a0, \
                f'RTL 写区重叠: desc{ai} vs desc{ci}'
    # 预载图像：每合并区一像（种子 = 区内最小 buf id；D-F3a 律帧参数化）
    pl_map = {('lohi', lo, hi): (min(ts), hi - lo) for lo, hi, ts in merged}
    say('[3b] 区域律 OK：预载合并区/写区两两互斥')

    # ---- 4. 逐帧：执行 25 任务 → preload + rd/wr 金样 ---------------------
    frames_meta = []
    preload_beats = None
    for fr in range(N_FRAMES):
        mem = {}

        def img(bid, need=None):
            assert bid in mem, f'帧{fr} buf{bid} 读先于产（数据流破坏）'
            m = mem[bid]
            if need is not None:
                assert len(m) >= need, \
                    f'帧{fr} buf{bid} 读 {need} > 产 {len(m)}'
                return m[:need]
            return m

        pl_imgs = []
        for lo, hi, ts in merged:
            seed_bid, sz = pl_map[('lohi', lo, hi)]
            data = bytes(prng_bytes(seed_bid, sz, fr))
            pl_imgs.append((lo, data))
            for k in ts:
                mem[k] = data[B[k].base - lo: B[k].base - lo + B[k].size]
        acc_meta = {}
        for di in ENG:
            d = D[di]
            if d.opcode == OP_ADD:
                qa, qb = Q[d.prof_in0], Q[d.prof_in1]
                out = add_ref(img(d.in0), img(d.in1),
                              sgn32(qa.m), qa.shift, sgn32(qb.m), qb.shift)
                rd = add_rd_rows(img(d.in0), img(d.in1),
                                 B[d.in0].base, B[d.in1].base)
                wr = wr_rows(out, B[d.out].base)
            elif d.opcode == OP_MP5:
                bi = B[d.in0]
                out = mp5_ref(img(d.in0), bi.c, bi.h, bi.w)
                rd = rd_rows([(img(d.in0), bi.base)])
                wr = wr_rows(out, B[d.out].base)
            elif d.opcode == OP_UPS:
                bi = B[d.in0]
                out = ups2_ref(img(d.in0), bi.c, bi.h, bi.w)
                rd = rd_rows([(img(d.in0), bi.base)])
                wr = wr_rows(out, B[d.out].base)
            elif d.opcode == OP_CONCAT:
                parts, wrseg = [], []
                for s in d.segments:
                    raw = img(s.buf, s.nbytes)
                    parts.append((raw, B[s.buf].base))
                    if s.prof:
                        q = Q[s.prof]
                        if (q.m, q.shift) == (1 << 30, 30):
                            wrseg.append(raw)          # 恒等单元旁路
                        else:
                            wrseg.append(requant_vec(raw, sgn32(q.m),
                                                     q.shift))
                    else:
                        wrseg.append(raw)              # prof=0 恒等
                rd = rd_rows(parts)
                out = b''.join(wrseg)
                assert len(out) == d.out_bytes
                wr = wr_rows(out, B[d.out].base)
            else:                                       # heads：六恒等段
                segs = [img(s.buf, s.nbytes) for s in hd.segments]
                blob = b''.join(segs)
                assert len(blob) == HEADS_TOTAL_BYTES
                rd = rd_rows([(raw, B[s.buf].base)
                              for raw, s in zip(segs, hd.segments)])
                wr = wr_rows(blob, HEAD_BASE)
                out = blob
            if d.opcode != OP_HEADS:
                assert d.out not in mem, f'帧{fr} desc{di} 出槽重复产'
                mem[d.out] = out
            for nm, rows in (('rd', rd), ('wr', wr)):
                with open(os.path.join(
                        DST, f'{nm}_golden_f{fr}_{di}.txt'), 'w',
                        newline='') as f:
                    f.write('\n'.join('%08X %016X %02X' % r for r in rows)
                            + '\n')
            acc_meta[str(di)] = {
                'op': {OP_ADD: 'add', OP_MP5: 'maxpool5', OP_UPS: 'upsample2',
                       OP_CONCAT: 'concat', OP_HEADS: 'heads'}[d.opcode],
                'out': d.out if d.opcode != OP_HEADS else None,
                'out_sha256': sha_b(out),
                'rd_beats': len(rd), 'wr_beats': len(wr)}
        frames_meta.append(acc_meta)

        rows_n = 0
        with open(os.path.join(DST, f'preload_f{fr}.txt'), 'w',
                  newline='') as f:
            for lo, data in sorted(pl_imgs):
                for a, v, m in beat_rows(data, lo, force_ff=True):
                    f.write('%08X %016X %02X\n' % (a, v, m))
                    rows_n += 1
        if preload_beats is None:
            preload_beats = rows_n
        else:
            assert rows_n == preload_beats, \
                f'帧{fr} preload 拍数 {rows_n} != 首帧 {preload_beats}'
        say(f'[4] 帧{fr}: preload_f{fr}.txt {rows_n} 拍 / 25 任务 rd+wr 落盘')

    # ---- 5. D1/D2/D3 splice（f6_prep.py Q2 逐式）--------------------------
    base_words = [int(x, 16) for x in
                  tables['desc_table_A.hex'].decode('ascii').split()]
    assert len(base_words) == 4096, f'desc 表字数 {len(base_words)} != 4096'
    assert base_words[32 * 50] & 0xFF == 0x12, 'desc50 非 CAT'
    assert base_words[32 * 7] & 0xFF == 0x11, 'desc7 非 ADD'

    def splice(widx, mask, val, name):
        w = base_words[widx]
        nw = (w & mask) | val
        out_w = list(base_words)
        out_w[widx] = nw
        txt = '\n'.join(f'{x:08X}' for x in out_w) + '\n'
        with open(os.path.join(DST, name), 'w', newline='',
                  encoding='ascii') as f:
            f.write(txt)
        say(f'[5] {name}: word[{widx}] {w:08X} -> {nw:08X}')
        return nw

    nw = splice(32 * 50 + 0, ~0x100 & 0xFFFFFFFF, 0x0, 'desc_table_D1.hex')
    assert nw & 0x100 == 0 and (nw & 0xFF) == 0x12
    nw = splice(32 * 50 + 0, 0xFFFFFF00, 0x20, 'desc_table_D2.hex')
    assert nw & 0xFF == 0x20 and nw & 0x100 == \
        (base_words[32 * 50] & 0x100)
    nw = splice(32 * 7 + 5, 0x00000000, 0x02000200, 'desc_table_D3.hex')
    assert (nw & 0xFFFF) == 0x0200 and (nw >> 16) == 0x0200

    # ---- 6. 台账 + SHA -----------------------------------------------------
    man = {
        'gate': 'F7PREP-n80', 'date': '2026-10-07',
        'tb': 'tb_ppu_f7.sv（F7A-D；PREP=本目录）',
        'dispatch_order': ENG,
        'rtl_task_classes': {'add': ADD_D, 'concat': CAT_D, 'maxpool5': MP5_D,
                             'upsample2': UPS_D, 'heads': [103]},
        'read_order': {'add': '64B 块 A/B 交替（f5aa 同源，side0=in0）',
                       'cat': '段序逐段', 'mp5/ups': '单段流',
                       'heads': '六段序（§8 段序）'},
        'requant_law': ('signed int8 × signed m32（RTL xfer L172 / add '
                        'L130-131 $signed 符号扩展；rne tie→even；sat_i8；'
                        'prof=0 与 (2^30,30) 单元恒等旁路）'),
        'prng_law': ('LCG 1664525/1013904223，seed=0x9E3779B9^(bid*'
                     '2654435761+1)^((fr+1)*0x85EBCA6B)（D-F3a 帧扩展）'),
        'no_reset_between_frames': True,
        'heads_layout': {k: list(HEADS_LAYOUT[k]) for k in HEADS_SEG_ORDER},
        'heads_off': off, 'head_base': HEAD_BASE,
        'preload': {'bufs': len(PRE), 'regions': len(merged),
                    'beats_per_frame': preload_beats, 'buf_ids': PRE},
        'frames': frames_meta,
        'lineage': {
            'bins_sha256': {k: sha_b(v) for k, v in bins.items()},
            'tables_sha256': {k: sha_b(v) for k, v in tables.items()},
            'v11_descriptor_table': sha_f(V11_MAN),
            'rtl_ppu_engine_mux': sha_f(RTL_MUX),
            'rtl_yolo_ppu_xfer': sha_f(RTL_XFER),
            'rtl_yolo_ppu_add': sha_f(RTL_ADD),
            'f3_manifest': 'prep/manifest_f3.json（src.sha256 源锁）'},
        'payload_policy': ('prep 载荷（preload_f*/金样）不入库，本地保全；'
                           '本台账+f7prep_n80.py 确定性再生成'),
    }
    with open(os.path.join(DST, 'manifest_f7prep.json'), 'w',
              encoding='utf-8') as f:
        json.dump(man, f, ensure_ascii=False, indent=1, sort_keys=True)

    log.close()
    n_files = 0
    with open(os.path.join(DST, 'prep_sha256.txt'), 'w') as f:
        for fn in sorted(os.listdir(DST)):
            if fn in ('prep_sha256.txt', 'prep_run.log'):
                continue
            p = os.path.join(DST, fn)
            if os.path.isfile(p):
                f.write('%s %s\n' % (sha_f(p), fn))
                n_files += 1
    print('[6] prep_sha256.txt 重生成（%d 文件）' % n_files)
    print('M5_F7PREP_N80 PASS')
    return 0


if __name__ == '__main__':
    sys.exit(main())
