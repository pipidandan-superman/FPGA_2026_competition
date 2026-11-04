#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pl_m3.py — M3 板级阶梯 run01：n80 整网回放板级驱动（自包含，阶梯切割）

被测件：K720 R2 板绿位流（本线 n80 血统）+ run02 泛化载荷律。
**阶梯执行 --stage 前缀切割**：l1=model.0 单 conv → l2=首 6 任务 →
l3=Backbone（首个 model.1x 前）→ l4=+Neck 全图（无 heads）→
l5=全图+heads；63 Conv 走 GEMM 硬件 DMA 通路 + 41 图算子（16 view
零流量 + add 6 + concat 13 + maxpool5 3 + upsample2 2）+ heads 尾
算子（6 分支 blob 打包），×5 帧逐帧逐字节一致。
唯一外部种子 = canvas 帧（buf0：x0=(canvas-128)→int8→CHW，seg0 律）；
（M3 n80：v11 图内闭环，唯一外部种子=canvas，无跨窗种子概念；
全部中间量=图内生产者的真实进程内数据流。）

整网形态宇宙（n80 = v11 manifests 自洽宇宙 + K720 R2 板证）：
  strip 五族：Wo=160 十 strip 16｜Wo=80 五 strip 16｜Wo=40 三 strip
  16/16/8｜Wo=20 两 strip 16/4｜Wo=10 单 strip (10,03FF)；
  K 链（B1 一般化）：K≤1024 → 单链 [K]（含 K720=板证正典）、双链 [1024,128]
  0x03/0x1D ldgrp 0/3、三链 K2304=[1024,1024,256] 0x03/0x19/0x05
  ldgrp 0/3/0（组复用 0→1→0，k2304 serial 板证正典）；
  死行律（run07 attempt1/2 板证改型，**合并铁律**）：**ROWVAL 恒 0xFF**
  ——0x7F 会使引擎 y 流按有效行截断，vc=16（112B=14 拍）可闭流、
  vc=4（28B=3.5 拍）无法闭流致 S2MM 永等；死行 W 由 packer 补 0
  （第 8 行计算确定无害），gather 端取 rows=min(8,oc-8rc) 行。**注意
  seg1 单链驱动旧写法为 A_ROWVAL=geo.row_valid，本驱动一律取 seg4 的
  无条件 0xFF 递交，row_valid 仅作审计数据。**
  掩蔽 lane 双律：默认 'fill' 0xA5；model.6.m.0.cv1（K576 正典）
  'fetch' 自然取数（run02 ANCHOR_MASKED_LAW）。
  heads：6 分支（reg 64×H×W ×3 + cls 80×H×W ×3）按段序
  reg8/reg16/reg32/cls8/cls16/cls32 拼接 302400B blob，SHA==G0。

板上门（M3 阶梯档门；主计划 §M3；档=meta stage_table 前缀）：
  CK0-CK6/DB1-DB2  上电正典
  SGi    CMA 对齐 + meta/npz 台账核验（126 params 键）
  STG    阶梯档台账（前缀区间/conv 数/heads/档内锚）
  SGa    档内 f0 装载锚 == meta 锚（prep 已对 conv_packer 全流/
         n80 三锚 bin 台账证明；五锚=model.0/k576/model.7/k2304/
         cv3.0.1[K720 R2 板证 conv]）
  SG1    档内 conv × 5 帧 gather == G0 参照逐位
  SG2    DMA 无挂死（2s 轮询超时即 dump_state 停）
  SG3    guard 0xA5：每 conv 本 conv 镜像外 0x10000 保持
  SG4    档内图算子 × 5 帧逐位（view 零流量/add/concat/mp5/ups +
         heads blob SHA==G0 ×5）
  SGl    LUT 记忆跨帧全程有效（期望 n_convs×5 次载入）
失败策略 §11：首块错 → 状态 dump → 停 → FAIL。
预算：172,450 块 ≈16-18 min（nohup 脱离 + run_exit.txt 正典）。

Usage (root): python3 pl_m3.py <l1|l2|l3|l4|l5> [tag]
"""
import os, sys, time, hashlib, subprocess, mmap, struct, json, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'display_test_wrapper.bit')
META_F = os.path.join(HERE, 'm3_meta.json')
PARAMS_F = os.path.join(HERE, 'm3_params.npz')
STAGES = ('l1', 'l2', 'l3', 'l4', 'l5')   # M3 阶梯（meta stage_table）
STAGE = sys.argv[1] if len(sys.argv) > 1 else 'l5'
assert STAGE in STAGES, STAGE
tag = sys.argv[2] if len(sys.argv) > 2 else 'm3_' + STAGE
VERDICT_PASS = 'BOARD_M3_%s_PASS' % STAGE.upper()   # 单一常量（防错串）
VERDICT_FAIL = 'BOARD_M3_%s_FAIL' % STAGE.upper()

GEMM_BASE, CSR_BASE, DMA_BASE = 0x43C00000, 0x43C10000, 0x40400000
EXP_GEMM_ID = 0x20260919
EXP_FCLK0_RAW = 0x00200500            # run25 正典：真 100 MHz

# ---- GEMM CSR map（合同 §9）----
A_ID, A_CTRL, A_STATUS = 0x00, 0x04, 0x08
A_GEOM, A_ROWVAL, A_NMASK, A_JOBCFG, A_LDGRP = 0x0C, 0x10, 0x14, 0x18, 0x1C
A_P_BIAS, A_P_M, A_P_SH, A_PCTL = 0x20, 0x24, 0x28, 0x2C
A_LDSTAT, A_LDLEN, A_LUTD = 0x3C, 0x40, 0x44
A_YSTAT = 0x48
A_BRGSTAT, A_STALLCNT = 0x54, 0x58
# ---- DMA map ----
D_MM2S_DMACR, D_MM2S_DMASR, D_MM2S_SA, D_MM2S_LEN = 0x00, 0x04, 0x18, 0x28
D_S2MM_DMACR, D_S2MM_DMASR, D_S2MM_DA, D_S2MM_LEN = 0x30, 0x34, 0x48, 0x58
B_RS = 0x1
B_HALTED, B_IDLE, B_SGINCLD = 0x1, 0x2, 0x8
B_ERRS = 0x70
B_IOC_IRQ, B_ERR_IRQ = 0x1000, 0x4000
PAGE = 0x1000

POISON = 0xA5
MASKED_LANE = 0xA5
GUARD_LEN = 0x10000
results = {}
counts = {'wop': 0, 'rop': 0, 'blocks': 0, 'timeouts': 0, 'lut_loads': 0}


def emit(m):
    line = '[%s %s %s]' % (tag, m, time.strftime('%H:%M:%S'))
    print(line, flush=True)
    try:
        with open('/dev/console', 'a') as c:
            c.write(line + '\n'); c.flush()
    except Exception as e:
        print('[console-fail %r]' % e, flush=True)


def wr(m, a, dd):
    m.write(a & 0xFFFFFFFF, dd & 0xFFFFFFFF)
    counts['wop'] += 1


def rd(m, a):
    v = m.read(a)
    counts['rop'] += 1
    return v


# ---- 内嵌算律（intref_yolov8 同式，无 torch）--------------------------
def rne_shift(n, s):
    s = int(s)
    q = n >> s
    rem = n - (q << s)
    twice = rem * 2
    full = 1 << s
    q = q + np.where(twice > full, 1, 0) + np.where(twice < -full, -1, 0)
    tie = (twice == full) | (twice == -full)
    q = q + np.where(tie & ((q & 1) == 1), np.where(twice > 0, 1, -1), 0)
    return q


def sat_i8(x):
    return np.clip(x, -128, 127).astype(np.int8)


def sat_i32(x):
    return np.clip(x, -2 ** 31, 2 ** 31 - 1).astype(np.int32)


def req_pair(r):
    if r <= 0.0:
        return (0, 0)
    f, e = math.frexp(r)
    m = int(round(f * (1 << 31)))
    shift = 31 - e
    if shift > 62:
        return (0, 0)
    assert (1 << 30) <= m < (1 << 31), 'M out of range'
    return (m, shift)


def maxpool5(x):
    """5×5 stride1 maxpool，pad -128（intref 同式；x=[C,H,W] int8）。"""
    C, H, W = x.shape
    p = 2
    xp = np.full((C, H + 2 * p, W + 2 * p), -128, dtype=np.int8)
    xp[:, p:p + H, p:p + W] = x
    out = np.full((C, H, W), -128, dtype=np.int8)
    for i in range(5):
        for j in range(5):
            np.maximum(out, xp[:, i:i + H, j:j + W], out=out)
    return out


def upsample_nearest2(x):
    """最近邻 2×（intref 同式；x=[C,H,W]）。"""
    return x.repeat(2, axis=1).repeat(2, axis=2)


# ---- 几何记录（b3s2_meta.json 台账 → 运行期对象）----------------------
class Geo(object):
    def __init__(self, node, s, P):
        self.node = node
        self.K, self.oc = s['K'], s['oc']
        self.kh, self.kw = s['kernel']
        self.sh, self.sw = s['stride']
        self.ph, self.pw = s['pad']
        self.Ho, self.Wo = s['Ho'], s['Wo']
        self.n_strips, self.N_TILE = s['n_strips'], s['n_tile']
        self.RC, self.NB = s['RC'], s['NB']
        self.tll = s['tile_load_len']
        self.row_valid = int(s['row_valid'], 16)
        self.jobcfg = int(s['jobcfg'], 16)
        self.ldgrp = s['ldgrp']
        self.first, self.has_act = s['first'], s['has_act']
        self.masked_law = s['masked_law']     # 'fill' 默认；'fetch'=K576 律
        assert self.masked_law in ('fill', 'fetch'), node
        self.lut_off, self.load_off, self.y_off = \
            s['lut_off'], s['load_off'], s['y_off']
        self.stride_slot = s['y_slot_stride']
        self.pctl = s['pctl']
        self.pad_val = np.int8(-128 if self.first else 0)
        # K 链段表（本窗核心：三链段 K2304=[1024,1024,256] 组复用 0→1→0）
        self.segs = s['segs']
        assert 1 <= len(self.segs) <= 3, node
        assert sum(sg['k_len'] for sg in self.segs) == self.K, node
        for sg in self.segs:
            assert 24 * sg['k_len'] > 0 and sg['k_len'] <= 1024, node
            assert 0 <= int(sg['jobcfg'], 16) <= 0xFF and \
                sg['ldgrp'] in (0, 3), node
        jc = [int(sg['jobcfg'], 16) for sg in self.segs]
        lg = [sg['ldgrp'] for sg in self.segs]
        if len(self.segs) == 1:            # 单链：0x07(act)/0x06(无act)
            # B1 一般化 K≤1024 → [K]（含 K720=cv3.x.1 板证）
            assert jc == [0x07] or (jc == [0x06] and not self.has_act), node
            assert lg == [0] and self.segs[0]['k_len'] == self.K, node
            assert self.K <= 1024, node
        elif len(self.segs) == 2:          # 双链 [1024,128] 正典
            assert [sg['k_len'] for sg in self.segs] == [1024, 128], node
            assert jc == [0x03, 0x1D] and lg == [0, 3], node
        else:                              # 三链 K2304（组复用 0→1→0）
            assert [sg['k_len'] for sg in self.segs] == \
                [1024, 1024, 256], node
            assert jc == [0x03, 0x19, 0x05] and lg == [0, 3, 0], node
        # strip 形态宇宙（五族=五窗板证并集，fail-closed 按 Wo 枚举）
        self.strips_tab = s['strips']
        assert len(self.strips_tab) == self.n_strips, node
        FORMS = {                       # Wo → 逐 strip (vc, n_mask) 表
            160: [(16, 0xFFFF)] * 10,
            80: [(16, 0xFFFF)] * 5,
            40: [(16, 0xFFFF), (16, 0xFFFF), (8, 0x00FF)],
            20: [(16, 0xFFFF), (4, 0x000F)],
            10: [(10, 0x03FF)],
        }
        assert self.Wo in FORMS, (node, self.Wo)
        for st, (vc_e, nm_e) in zip(self.strips_tab, FORMS[self.Wo]):
            assert st['vc'] == vc_e and \
                int(st['n_mask'], 16) == nm_e and \
                st['ycnt'] == 8 * vc_e and \
                st['s2mm_btt'] == 8 * vc_e, node
        # 死行律 n80：全 oc%8==0 → ROWVAL 恒 0xFF（无 oc7 conv）
        assert self.oc % 8 == 0 and self.row_valid == 0xFF, node
        key = node.replace('.', '_')
        self.Wq = P['W_%s' % key]
        self.lut = P['lut_%s' % key]
        assert self.Wq.shape == (self.oc, self.K), node
        assert self.lut.shape == (256,), node
        assert len(self.pctl) == 8 * self.RC, node
        kk = np.arange(self.K)
        self.kIC = kk // (self.kh * self.kw)
        self.kKH = (kk % (self.kh * self.kw)) // self.kw
        self.kKW = kk % self.kw

    def vc_of(self, s):
        return self.strips_tab[s]['vc']

    def nmask_of(self, s):
        return int(self.strips_tab[s]['n_mask'], 16)

    def ycnt_of(self, s):
        return self.strips_tab[s]['ycnt']

    def btt_of(self, s):
        return self.strips_tab[s]['s2mm_btt']


def pack_tile(geo, x, oy, s, rc):
    """run02 泛化律：[K,24] = W(8) ‖ X(16)；x=[C,H,W] int8。

    掩蔽 lane（c≥vc）双律（run02 ANCHOR_MASKED_LAW，seg1 板证移入）：
    默认 'fill' 0xA5 哨兵（审计友好）；K576 正典 conv（model.6.m.0.cv1）
    'fetch' 自然取数（oob 才 pad）。两律均板绿（don't-care，n_mask 门控
    出计算与 y）。链段在字节流上连续，双/三链段由递交端按 24*k_len
    分段流送；死行 W 补 0。"""
    H, W = x.shape[1], x.shape[2]
    vc = geo.vc_of(s)
    iy = geo.sh * oy + geo.kKH - geo.ph
    c = np.arange(16)
    ix = geo.sw * (16 * s + c)[None, :] + geo.kKW[:, None] - geo.pw
    if geo.masked_law == 'fetch':
        inb = ((iy[:, None] >= 0) & (iy[:, None] < H) &
               (ix >= 0) & (ix < W))
    else:
        inb = ((iy[:, None] >= 0) & (iy[:, None] < H) &
               (ix >= 0) & (ix < W) & (c[None, :] < vc))
    xi = np.clip(iy, 0, H - 1)
    xj = np.clip(ix, 0, W - 1)
    src = x[geo.kIC[:, None], xi[:, None], xj]
    xb = np.where(inb, src, geo.pad_val).astype(np.int8)
    xbu = xb.view(np.uint8)
    if geo.masked_law != 'fetch':
        xbu[:, vc:] = MASKED_LANE        # 'fill' 律（合同默认）
    wrows = np.arange(8 * rc, 8 * rc + 8)
    dead = wrows >= geo.oc
    wv = np.where(dead[:, None], 0,
                  geo.Wq[np.clip(wrows, 0, geo.oc - 1), :]).astype(np.int8)
    tile = np.empty((geo.K, 24), dtype=np.uint8)
    tile[:, :8] = wv.T.view(np.uint8)
    tile[:, 8:] = xbu
    return tile


def dump_state(g, d, node, b):
    emit('STATE %s b=%d STATUS=%08X LDSTAT=%08X LDLEN=%08X YSTAT=%08X '
         'BRGSTAT=%08X' % (node, b, rd(g, A_STATUS), rd(g, A_LDSTAT),
                           rd(g, A_LDLEN), rd(g, A_YSTAT), rd(g, A_BRGSTAT)))
    emit('STATE %s b=%d MM2S_DMASR=%08X S2MM_DMASR=%08X'
         % (node, b, d.read(D_MM2S_DMASR), d.read(D_S2MM_DMASR)))


def load_lut(g, geo):
    for i in range(256):
        wr(g, A_LUTD, (i << 8) | int(geo.lut[i]))
    wr(g, A_CTRL, 0x4)
    time.sleep(0.01)
    st, brg = rd(g, A_STATUS), rd(g, A_BRGSTAT)
    ok = ((st >> 6) & 0xF) == 0 and (brg & 0x1D) == 0
    emit('SGl %s LUTD x256 STATUS=%08X BRGSTAT=%08X -> %s'
         % (geo.node, st, brg, 'PASS' if ok else 'FAIL'))
    return ok


def _mm2s_seg(d, g, cma, geo, b, off, k_len, node):
    """一段装载：清粘滞→LDGRP 已由调用方写→MM2S→轮询→LDLEN 核。"""
    d.write(D_MM2S_DMASR, B_IOC_IRQ | B_ERR_IRQ)
    d.write(D_MM2S_SA, cma['phys'] + geo.load_off + geo.tll * b + off)
    d.write(D_MM2S_LEN, 24 * k_len)
    t0 = time.time()
    while time.time() - t0 < 2.0:
        ms = d.read(D_MM2S_DMASR)
        if (ms & B_IDLE) and (ms & B_IOC_IRQ):
            break
        time.sleep(0.0005)
    else:
        counts['timeouts'] += 1
        dump_state(g, d, node, b)
        return False
    ldlen = rd(g, A_LDLEN)
    if (ldlen & 0x1FFF) != k_len or ((ldlen >> 13) & 0x1FFF) != k_len:
        emit('SG2 %s b=%d seg(k=%d) LDLEN=%08X' % (node, b, k_len, ldlen))
        dump_state(g, d, node, b)
        return False
    return True


def wait_pend_clear(g, tmo=2.0):
    t0 = time.time()
    while time.time() - t0 < tmo:
        if not (g.read(A_STATUS) & 0x2):
            return True
        time.sleep(0.0005)
    counts['rop'] += 1
    return False


def arm_and_run(g, d, cma, geo, b):
    """n 段 serial 正典（单/双=k1152 run06、三=k2304 run07 P1.3 板证）：
    L1→job1 寄存器→[i=1: L2→start1→pend→job2 寄存器→queue2→(非末段)
    pend]→[i≥2: Li→jobi 寄存器→queue_i→(非末段) pend]→完成轮询。
    三链段 L3 复用 grp0（LDGRP 0/3/0）。返回 (ok, wall_us)。"""
    nt, rc = b // geo.RC, b % geo.RC
    s = nt % geo.n_strips
    t0 = time.perf_counter()
    for r in range(8):
        p = geo.pctl[rc * 8 + r]
        wr(g, A_P_BIAS, p[0] & 0xFFFFFFFF)
        wr(g, A_P_M, p[1] & 0xFFFFFFFF)
        wr(g, A_P_SH, p[2] & 0x3F)
        wr(g, A_PCTL, 0x100 | r)
    wr(g, A_ROWVAL, 0xFF)
    # 死行律（attempt1/2 板证改型）：ROWVAL<0xFF 使引擎 y 流按有效行
    # 截断——vc=16 时 112B=14 拍可闭流（cv3.0.2 120 块过），vc=4 时
    # 28B=3.5 拍无法闭流 → S2MM 永等（tile_done/ycnt=28 而 DMASR=0）。
    # 故递交恒 0xFF：死行 W 已由 packer 补 0（R1 板证），第 8 行计算
    # 确定无害，gather 端 rows=min(8,oc-8rc) 截取（PC 律不变）。
    wr(g, A_NMASK, geo.nmask_of(s))
    d.write(D_S2MM_DA, cma['phys'] + geo.y_off +
            geo.stride_slot * b)
    d.write(D_S2MM_LEN, geo.btt_of(s))
    segs = geo.segs
    # ---- 段 0 装载 → job1 寄存器 ----
    wr(g, A_LDGRP, segs[0]['ldgrp'])
    if not _mm2s_seg(d, g, cma, geo, b, 0, segs[0]['k_len'], geo.node):
        return False, 0
    wr(g, A_GEOM, segs[0]['k_len'])
    wr(g, A_JOBCFG, int(segs[0]['jobcfg'], 16))
    if len(segs) == 1:
        wr(g, A_CTRL, 1)                   # 单链：直接起跑
    else:
        off = 24 * segs[0]['k_len']
        for i in range(1, len(segs)):
            sg = segs[i]
            # ---- 段 i 装载（serial：compute 前；三链末段复用 grp0）----
            wr(g, A_LDGRP, sg['ldgrp'])
            if not _mm2s_seg(d, g, cma, geo, b, off, sg['k_len'],
                             geo.node):
                return False, 0
            off += 24 * sg['k_len']
            if i == 1:                     # start1（job1 起跑）
                wr(g, A_CTRL, 1)
                if not wait_pend_clear(g):
                    counts['timeouts'] += 1
                    emit('SG2 %s b=%d pend1_timeout' % (geo.node, b))
                    dump_state(g, d, geo.node, b)
                    return False, 0
            wr(g, A_GEOM, sg['k_len'])
            wr(g, A_JOBCFG, int(sg['jobcfg'], 16))
            wr(g, A_CTRL, 1)               # queue job_i
            if i < len(segs) - 1:          # 非末段：等 job_i 接受
                if not wait_pend_clear(g):
                    counts['timeouts'] += 1
                    emit('SG2 %s b=%d pend%d_timeout'
                         % (geo.node, b, i + 1))
                    dump_state(g, d, geo.node, b)
                    return False, 0
    # ---- 完成轮询：busy=0 + tile_done + pend 清 + 双 DMA idle/IOC ----
    t_c = time.time()
    st = ms = ss = 0
    while time.time() - t_c < 2.0:
        st = g.read(A_STATUS)
        ms = d.read(D_MM2S_DMASR)
        ss = d.read(D_S2MM_DMASR)
        if (not (st & 1)) and (st & 0x20) and (not (st & 0x2)) and \
           (ms & B_IDLE) and (ms & B_IOC_IRQ) and \
           (ss & B_IDLE) and (ss & B_IOC_IRQ):
            break
        time.sleep(0.0005)
    else:
        counts['timeouts'] += 1
        dump_state(g, d, geo.node, b)
        return False, 0
    counts['rop'] += 3
    d.write(D_MM2S_DMASR, B_IOC_IRQ | B_ERR_IRQ)
    d.write(D_S2MM_DMASR, B_IOC_IRQ | B_ERR_IRQ)
    brg = rd(g, A_BRGSTAT)
    yst = rd(g, A_YSTAT)
    ycnt = yst & 0xFFFF
    # ycnt 门=四窗正典 8*vc（ROWVAL 恒 0xFF 后死行块同律：第 8 行由
    # packer 补 0 的 W 计算出确定值，照常入流）
    wall_us = int((time.perf_counter() - t0) * 1e6)
    ok = ((not (st & 0x3)) and (st & 0x20) and
          ((st >> 6) & 0xF) == 0 and
          not (ms & B_ERRS) and not (ss & B_ERRS) and
          ((brg >> 2) & 0x7) == 0 and (brg & 0x2) and
          (yst & 0x20000) and ycnt == geo.ycnt_of(s))
    if not ok:
        emit('SG2 %s b=%d status=%08X brg=%08X ystat=%08X ycnt=%d '
             'exp=%d ms=%08X ss=%08X'
             % (geo.node, b, st, brg, yst, ycnt, geo.ycnt_of(s), ms, ss))
        dump_state(g, d, geo.node, b)
    return ok, wall_us


def board_conv(g, d, cma, geo, x, csv):
    """一 conv：装载打包→逐块递交→gather→[oc,Ho,Wo] uint8。"""
    npl = cma['buf']
    guard_lo = geo.y_off + geo.stride_slot * geo.NB
    guard_hi = min(guard_lo + GUARD_LEN, cma['len'])
    npl[geo.y_off:guard_hi] = POISON
    for b in range(geo.NB):
        nt, rc = b // geo.RC, b % geo.RC
        oy, s = nt // geo.n_strips, nt % geo.n_strips
        tile = pack_tile(geo, x, oy, s, rc)
        npl[geo.load_off + geo.tll * b:
            geo.load_off + geo.tll * (b + 1)] = tile.reshape(-1)
    if hasattr(npl, 'flush'):
        npl.flush()
    walls = []
    for b in range(geo.NB):
        ok, wus = arm_and_run(g, d, cma, geo, b)
        csv.write('%s,%d,%d,%d,%d,%s,%08X\n'
                  % (geo.node, geo.frame, b, wus,
                     0 if ok else 1, rd(g, A_STATUS) if not ok else 0,
                     rd(g, A_YSTAT) if not ok else 0))
        if not ok:
            return None, walls
        walls.append(wus)
        counts['blocks'] += 1
        if b % 400 == 0 or b == geo.NB - 1:
            emit('SG1 %s f%d b=%d/%d last_wall_us=%d'
                 % (geo.node, geo.frame, b, geo.NB, wus))
    if hasattr(npl, 'flush'):
        npl.flush()
    # gather（紧凑律 byte=r*vc+cv；死行：块内有效行=min(8, oc-8rc)，
    # slot 仍 8 行——末行死字节不取）
    y = np.empty((geo.oc, geo.Ho, geo.Wo), dtype=np.uint8)
    yv = npl[geo.y_off:geo.y_off + geo.stride_slot * geo.NB]
    for b in range(geo.NB):
        nt, rc = b // geo.RC, b % geo.RC
        oy, s = nt // geo.n_strips, nt % geo.n_strips
        vc = geo.vc_of(s)
        rows = min(8, geo.oc - 8 * rc)
        slot = yv[geo.stride_slot * b:
                  geo.stride_slot * b + 8 * vc]
        y[8 * rc:8 * rc + rows, oy, 16 * s:16 * s + vc] = \
            slot[:rows * vc].reshape(rows, vc)
    guard_ok = bool(np.all(npl[guard_lo:guard_hi] == POISON))
    geo.guard_ok = guard_ok
    return y, walls


def main():
    emit('SG0a start bit_sha=%s'
         % hashlib.sha256(open(BIT, 'rb').read()).hexdigest()[:16])

    # ---- 上电正典 CK0-CK6/DB1-DB2（pl_p13_k2304 同式）----
    boot_id = open('/proc/sys/kernel/random/boot_id').read().strip()
    up = open('/proc/uptime').read().split()[0]
    emit('CK0b boot_id=%s uptime=%s' % (boot_id, up))
    svc = subprocess.run(['systemctl', 'is-active', 'ees331-camera'],
                         capture_output=True, text=True).stdout.strip()
    emit('CK0c ees331-camera=%s' % svc)
    if svc == 'active':
        t0 = time.time()
        while time.time() - t0 < 120:
            svc = subprocess.run(['systemctl', 'is-active',
                                  'ees331-camera'], capture_output=True,
                                 text=True).stdout.strip()
            if svc != 'active':
                break
            time.sleep(2)
    emit('CK0d ees331-camera terminal=%s' % svc)
    dri = subprocess.run(['pgrep', '-f', 'camera'], capture_output=True,
                         text=True).stdout.split()
    own = [p for p in dri if p != str(os.getpid())]
    emit('CK0e camera procs=%s' % (own or 'none'))
    results['CK0'] = (svc != 'active')

    os.environ['XILINX_XRT'] = '/usr'
    from pynq import Overlay, MMIO, allocate

    ol = Overlay(BIT, download=False)
    emit('CK1a ip_dict=%s' % sorted(ol.ip_dict.keys()))
    gp = ol.ip_dict.get('u_yolo_gemm', {}).get('phys_addr')
    cp = ol.ip_dict.get('u_yolo_csr', {}).get('phys_addr')
    dp = ol.ip_dict.get('axi_dma_0', {}).get('phys_addr')
    results['CK1'] = (gp == GEMM_BASE) and (cp == CSR_BASE) and \
                     (dp == DMA_BASE)
    emit('CK1b gemm=%s csr=%s dma=%s -> %s'
         % (hex(gp) if gp is not None else None,
            hex(cp) if cp is not None else None,
            hex(dp) if dp is not None else None,
            'PASS' if results['CK1'] else 'FAIL'))
    if not results['CK1']:
        emit('CKz %s hwh_contract' % VERDICT_FAIL); return 1

    def lock_count():
        out = subprocess.run(['dmesg'], capture_output=True,
                             text=True).stdout
        return sum(1 for l in out.splitlines() if 'locked, ref=1' in l)
    pre = lock_count()
    emit('CK2a pre_locks=%d download_begin' % pre)
    ol.download()
    emit('CK2b download_returned')
    st_fpga = open('/sys/class/fpga_manager/fpga0/state').read().strip()
    emit('CK3 state=%s' % st_fpga)
    post = lock_count()
    results['CK4'] = (st_fpga == 'operating') and (post == pre + 1)
    emit('CK4 lock_delta=%d -> %s' % (post - pre,
         'PASS' if results['CK4'] else 'FAIL'))
    if not results['CK4']:
        emit('CKz %s load' % VERDICT_FAIL); return 1

    g = MMIO(GEMM_BASE, 0x10000)
    d = MMIO(DMA_BASE, 0x1000)

    import select
    emit('CK5a sacrificial_first_read_begin')
    r_pipe, w_pipe = os.pipe()
    pid = os.fork()
    if pid == 0:
        try:
            v = g.read(0x00)
            os.write(w_pipe, b'OK %08X' % v)
        except Exception as e:
            os.write(w_pipe, b'FAULT %r' % e)
        os._exit(0)
    ready, _, _ = select.select([r_pipe], [], [], 5.0)
    msg = os.read(r_pipe, 64) if ready else b'TIMEOUT'
    os.close(r_pipe); os.close(w_pipe)
    os.waitpid(pid, 0)
    emit('CK5b first_read=%s' % msg.decode(errors='replace'))
    parts = msg.split()
    results['CK5'] = (len(parts) == 2 and parts[0] == b'OK'
                      and int(parts[1], 16) == EXP_GEMM_ID)
    emit('CK5c GEMM_ID -> %s' % ('PASS' if results['CK5'] else 'FAIL'))
    if not results['CK5']:
        emit('CKz %s gemm_id' % VERDICT_FAIL); return 1

    fd = os.open('/dev/mem', os.O_RDONLY | os.O_SYNC)
    try:
        mm = mmap.mmap(fd, PAGE, mmap.MAP_SHARED, mmap.PROT_READ,
                       offset=0xF8000000)
        try:
            raw = struct.unpack('<I', mm[0x170:0x174])[0]
        finally:
            mm.close()
    finally:
        os.close(fd)
    results['CK6'] = (raw == EXP_FCLK0_RAW)
    emit('CK6 fclk0_raw=0x%08X exp=0x%08X -> %s'
         % (raw, EXP_FCLK0_RAW, 'PASS' if results['CK6'] else 'FAIL'))
    if not results['CK6']:
        emit('CKz %s fclk0' % VERDICT_FAIL); return 1

    ms0, ss0 = d.read(D_MM2S_DMASR), d.read(D_S2MM_DMASR)
    results['DB1'] = ((ms0 & B_HALTED) and (ss0 & B_HALTED) and
                      not (ms0 & B_SGINCLD) and not (ss0 & B_SGINCLD))
    emit('DB1 reset MM2S=%08X S2MM=%08X -> %s'
         % (ms0, ss0, 'PASS' if results['DB1'] else 'FAIL'))
    d.write(D_MM2S_DMACR, B_RS)
    d.write(D_S2MM_DMACR, B_RS)
    t0 = time.time()
    while time.time() - t0 < 2.0:
        ms, ss = d.read(D_MM2S_DMASR), d.read(D_S2MM_DMASR)
        if not (ms & B_HALTED) and not (ss & B_HALTED):
            break
        time.sleep(0.001)
    results['DB2'] = (not (ms & B_HALTED)) and (not (ss & B_HALTED))
    emit('DB2 bringup MM2S=%08X S2MM=%08X -> %s'
         % (ms, ss, 'PASS' if results['DB2'] else 'FAIL'))
    if not (results['DB1'] and results['DB2']):
        emit('CKz %s dma_bringup' % VERDICT_FAIL); return 1

    # ---- SGi：meta/params/CMA ----
    meta = json.load(open(META_F, encoding='utf-8'))
    P = dict(np.load(PARAMS_F))
    keys_ok = set(P.keys()) == set(meta['params_keys'])
    cma_len = int(meta['cma_bytes'])
    npbuf = allocate(shape=(cma_len,), dtype=np.uint8)
    cma_phys = npbuf.device_address
    results['SGi'] = keys_ok and (cma_phys % PAGE == 0)
    emit('SGi keys=%s cma=0x%X len=%d aligned=%s -> %s'
         % ('OK' if keys_ok else 'BAD', cma_phys, cma_len,
            cma_phys % PAGE == 0, 'PASS' if results['SGi'] else 'FAIL'))
    if not results['SGi']:
        emit('CKz %s cma_meta' % VERDICT_FAIL); return 1
    cma = {'buf': npbuf, 'phys': cma_phys, 'len': cma_len}
    npbuf[:] = POISON
    if hasattr(npbuf, 'flush'):
        npbuf.flush()

    stage_e = meta['stage_table'][STAGE]
    descs = meta['seg_descs'][:stage_e['hi']]   # 阶梯=前缀切割
    N_STAGE_CONV = stage_e['n_convs']
    EXP_LUT = stage_e['exp_lut_loads']
    statics = meta['conv_statics']
    geos = {n: Geo(n, s, P) for n, s in statics.items()}
    cur_lut = None          # 帧循环外置一次：LUT 记忆跨帧全程有效
    emit('STG %s [%d,%d) tasks=%d convs=%d heads=%d 锚=%s'
         % (STAGE, stage_e['lo'], stage_e['hi'], stage_e['n_tasks'],
            N_STAGE_CONV, stage_e['includes_heads'],
            ','.join(stage_e['anchors_in_stage'])))

    # ---- 拓扑静态（§B2 取证字段；buf0=canvas 唯一外部种子）----
    def _in_bufs_of(td):
        op_ = td['op']
        if op_ in ('conv', 'maxpool5', 'upsample2', 'heads'):
            return list(td['in_bufs'])
        if op_ == 'view':
            return [td['parent_buf']]
        if op_ == 'add':
            return [td['a_buf'], td['b_buf']]
        if op_ == 'concat':
            return [s_['buf'] for s_ in td['inputs']]
        raise AssertionError(op_)

    producer_node = {0: 'canvas'}
    for td_ in descs:
        if td_['out_buf'] is not None:
            assert td_['out_buf'] not in producer_node, td_['node']
            producer_node[td_['out_buf']] = td_['node']
    consumer_cnt = {}
    for td_ in descs:
        for b_ in _in_bufs_of(td_):
            consumer_cnt[b_] = consumer_cnt.get(b_, 0) + 1
    # 每任务恰一产出（heads 出区）。前缀档 l1..l4 无 heads：产出数=
    # 档内有 out_buf 的任务数；canvas 种子 buf0 恒占一席 → 一般化断言
    # （attempt1 教训：len(descs) 形只在全图 l5 恰好成立）。
    assert len(producer_node) == 1 + sum(
        1 for td_ in descs if td_['out_buf'] is not None)

    # 五 f0 装载锚（node → SHA；仅档前缀内者上板核）
    ANCHORS = {n: s for n, s in meta.get('anchors', {}).items()
               if n in stage_e['anchors_in_stage']}

    def frec(td, fi, op, ref):
        """统一逐任务取证记录的公共字段（§B2；静态字段来自 descs。
        B3-S2 范围界线：镜像 CMA 布局无 arena 复用语义，运行时
        generation/owner 检查属 B3-S3/B4，此处不伪造字段。）"""
        ib = _in_bufs_of(td)
        return {
            'sched_index': int(td['sched_index']), 'node': td['node'],
            'op': op, 'backend': 'gemm' if op == 'conv' else 'software',
            'in_bufs': ib, 'out_buf': td['out_buf'],
            'producer': producer_node.get(ib[0]) if ib else None,
            'consumer_count': consumer_cnt.get(td['out_buf'], 0)
            if td['out_buf'] is not None else 0,
            'shape': [int(v) for v in ref.shape]
            if ref is not None else None,
            'byte_len': int(ref.nbytes) if ref is not None else None,
            'oracle_sha256': meta['ref_sha256'].get(
                'f%d/%s' % (fi, td['node'])),
        }

    csv = open(os.path.join(HERE, 'm3_%s_blocks.csv' % STAGE), 'w')
    csv.write('node,frame,b,wall_us,nerr,status,ystat\n')
    rep = {'stage': STAGE, 'frames': [], 'gates': {}, 'cma_phys': cma_phys,
           'bit_sha': hashlib.sha256(open(BIT, 'rb').read()
                                     ).hexdigest()}
    anchor_done = set()
    try:
        for fi in range(5):
            fr = dict(np.load(os.path.join(HERE, 'refs_f%d.npz' % fi)))
            canvas = fr['canvas']
            x0 = (canvas.astype(np.int16) - 128).astype(np.int8) \
                .transpose(2, 0, 1).copy()
            tensors = {0: x0}   # 唯一外部种子=canvas 帧（seg0 律）
            fres = {'frame': fi, 'tasks': [], 'pass': True}
            t_fr = time.time()
            for td in descs:
                op, node = td['op'], td['node']
                key = 'ref_%d_%s' % (td['sched_index'],
                                     node.replace('.', '_'))
                ref = fr.get(key)          # heads 无参照张量（blob SHA 门）
                if op == 'conv':
                    geo = geos[node]
                    geo.frame = fi
                    if cur_lut != node:
                        if not load_lut(g, geo):
                            fres['pass'] = False
                            break
                        cur_lut = node
                        counts['lut_loads'] += 1
                    y, walls = board_conv(g, d, cma, geo,
                                          tensors[td['in_bufs'][0]], csv)
                    if y is None:
                        fres['pass'] = False
                        break
                    # SGa：档内 f0 装载锚（板上全 NB 装载区 == meta 锚；
                    # prep 已对 conv_packer 全流 + n80 三锚 bin 台账
                    # 证明；cv3.0.1=K720 R2 板证 conv）
                    if fi == 0 and node in ANCHORS and \
                            node not in anchor_done:
                        got = hashlib.sha256(bytes(
                            npbuf[geo.load_off:
                                  geo.load_off + geo.tll * geo.NB]
                            )).hexdigest()
                        ok_a = got == ANCHORS[node]
                        results['SGa:%s' % node] = ok_a
                        anchor_done.add(node)
                        emit('SGa %s loads anchor %s -> %s'
                             % (node, got[:16], 'PASS' if ok_a else 'FAIL'))
                        if not ok_a:
                            fres['pass'] = False
                            break
                    yv8 = y.view(np.int8)
                    nerr = int(np.count_nonzero(yv8 != ref))
                    got_sha = hashlib.sha256(
                        y.tobytes()).hexdigest()
                    wa = np.array(walls) if walls else np.array([0])
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr, 'out_sha256': got_sha,
                        'blocks': int(geo.NB),
                        'guard_ok': bool(geo.guard_ok),
                        'wall_ms': int(walls and
                                       round(sum(walls) / 1e3) or 0),
                        'p50_us': int(np.percentile(wa, 50)),
                        'p95_us': int(np.percentile(wa, 95)),
                        'max_us': int(wa.max())})
                    fres['tasks'].append(rec)
                    if nerr:
                        rec['first_mismatch_offset'] = int(
                            (yv8 != ref).argmax())
                        bad = np.argwhere(yv8 != ref)[0]
                        oc, oy, ox = [int(v) for v in bad]
                        s = ox // 16
                        b = (oy * geo.n_strips + s) * geo.RC + oc // 8
                        emit('SG1 %s f%d nerr=%d first=(oc%d,oy%d,ox%d) '
                             'blk=%d got=%d exp=%d'
                             % (node, fi, nerr, oc, oy, ox, b,
                                int(yv8[oc, oy, ox]), int(ref[oc, oy, ox])))
                        dump_state(g, d, node, b)
                        fres['pass'] = False
                        break
                    if not geo.guard_ok:
                        emit('SG3 %s f%d guard broken' % (node, fi))
                        fres['pass'] = False
                        break
                    tensors[td['out_buf']] = yv8
                elif op == 'view':
                    par = tensors[td['parent_buf']]
                    tensors[td['out_buf']] = par[td['ch'][0]:td['ch'][1]]
                    zero = np.shares_memory(
                        tensors[td['out_buf']], par)
                    nerr = int(np.count_nonzero(
                        tensors[td['out_buf']] != ref))
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr,
                        'out_sha256': hashlib.sha256(
                            np.ascontiguousarray(
                                tensors[td['out_buf']]).tobytes()
                        ).hexdigest(),
                        'zero_copy': bool(zero),
                        'parent_buf': td['parent_buf'],
                        'ch': [int(v) for v in td['ch']]})
                    fres['tasks'].append(rec)
                    if nerr or not zero:
                        rec['first_mismatch_offset'] = int(
                            (tensors[td['out_buf']] != ref).argmax()) \
                            if nerr else None
                        emit('SG4 %s f%d view nerr=%d zero=%s'
                             % (node, fi, nerr, zero))
                        fres['pass'] = False
                        break
                elif op == 'add':
                    a = tensors[td['a_buf']]
                    b_ = tensors[td['b_buf']]
                    qa = req_pair(td['a_scale'] / td['out_scale'])
                    qb = req_pair(td['b_scale'] / td['out_scale'])
                    A_ = rne_shift(a.astype(np.int64) * qa[0], qa[1])
                    B_ = rne_shift(b_.astype(np.int64) * qb[0], qb[1])
                    y = sat_i8(sat_i32(A_ + B_))
                    nerr = int(np.count_nonzero(y != ref))
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr,
                        'out_sha256': hashlib.sha256(
                            np.ascontiguousarray(y).tobytes()).hexdigest()})
                    fres['tasks'].append(rec)
                    if nerr:
                        rec['first_mismatch_offset'] = int(
                            (y != ref).argmax())
                        bad = np.argwhere(y != ref)[0]
                        emit('SG4 %s f%d add nerr=%d first=%s'
                             % (node, fi, nerr, [int(v) for v in bad]))
                        fres['pass'] = False
                        break
                    tensors[td['out_buf']] = y
                elif op == 'concat':
                    parts = []
                    for s_ in td['inputs']:
                        p_ = tensors[s_['buf']]
                        q = req_pair(s_['scale'] / td['out_scale'])
                        parts.append(sat_i8(rne_shift(
                            p_.astype(np.int64) * q[0], q[1])))
                    y = np.concatenate(parts, axis=0)
                    nerr = int(np.count_nonzero(y != ref))
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr,
                        'out_sha256': hashlib.sha256(
                            np.ascontiguousarray(y).tobytes()).hexdigest()})
                    fres['tasks'].append(rec)
                    if nerr:
                        rec['first_mismatch_offset'] = int(
                            (y != ref).argmax())
                        bad = np.argwhere(y != ref)[0]
                        emit('SG4 %s f%d cat nerr=%d first=%s'
                             % (node, fi, nerr, [int(v) for v in bad]))
                        fres['pass'] = False
                        break
                    tensors[td['out_buf']] = y
                elif op == 'maxpool5':
                    y = maxpool5(tensors[td['in_bufs'][0]])
                    nerr = int(np.count_nonzero(y != ref))
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr,
                        'out_sha256': hashlib.sha256(
                            np.ascontiguousarray(y).tobytes()).hexdigest()})
                    fres['tasks'].append(rec)
                    if nerr:
                        rec['first_mismatch_offset'] = int(
                            (y != ref).argmax())
                        bad = np.argwhere(y != ref)[0]
                        emit('SG4 %s f%d mp5 nerr=%d first=%s'
                             % (node, fi, nerr, [int(v) for v in bad]))
                        fres['pass'] = False
                        break
                    tensors[td['out_buf']] = y
                elif op == 'upsample2':
                    y = upsample_nearest2(tensors[td['in_bufs'][0]])
                    nerr = int(np.count_nonzero(y != ref))
                    rec = frec(td, fi, op, ref)
                    rec.update({
                        'nerr': nerr,
                        'out_sha256': hashlib.sha256(
                            np.ascontiguousarray(y).tobytes()).hexdigest()})
                    fres['tasks'].append(rec)
                    if nerr:
                        rec['first_mismatch_offset'] = int(
                            (y != ref).argmax())
                        bad = np.argwhere(y != ref)[0]
                        emit('SG4 %s f%d ups2 nerr=%d first=%s'
                             % (node, fi, nerr, [int(v) for v in bad]))
                        fres['pass'] = False
                        break
                    tensors[td['out_buf']] = y
                elif op == 'heads':
                    # SG4：6 分支按段序拼 blob（板上 conv 输出端到端），
                    # SHA==G0 参照（graph_exec 同律：reg 先 cls 后、
                    # 段内 HEADS_SEG_ORDER 稳定排序）
                    seg_of = {40: '8', 20: '16', 10: '32'}
                    seg_map = {}
                    for grp in ('reg', 'cls'):
                        for e in td[grp]:
                            seg_map[grp + seg_of[e['shape'][2]]] = e['buf']
                    order = ('reg8', 'reg16', 'reg32',
                             'cls8', 'cls16', 'cls32')
                    all_entries = td['reg'] + td['cls']
                    parts_, heads_len = [], 0
                    for k_ in order:
                        buf = seg_map[k_]
                        e = next(x for x in all_entries if x['buf'] == buf)
                        t_ = tensors[buf]
                        assert list(t_.shape) == e['shape'], k_
                        b_ = np.ascontiguousarray(t_).tobytes()
                        heads_len += len(b_)
                        parts_.append(b_)
                    blob = b''.join(parts_)
                    got_h = hashlib.sha256(blob).hexdigest()
                    nerr = 0 if (heads_len == meta['heads_total'] and
                                 got_h == meta['heads_blob_sha256'][
                                     'f%d' % fi]) else 1
                    rec = frec(td, fi, op, None)
                    rec.update({
                        'oracle_sha256': meta['heads_blob_sha256'][
                            'f%d' % fi],
                        'byte_len': int(heads_len),
                        'nerr': nerr, 'out_sha256': got_h,
                        'blob_sha256': got_h, 'blob_len': int(heads_len)})
                    fres['tasks'].append(rec)
                    if nerr:
                        emit('SG4 %s f%d heads blob %dB sha=%s '
                             'exp=%s' % (node, fi, heads_len, got_h[:16],
                                         meta['heads_blob_sha256'][
                                             'f%d' % fi][:16]))
                        fres['pass'] = False
                        break
                else:
                    emit('SG4 op %s 越界（整网程序无此算子）' % op)
                    fres['pass'] = False
                    break
            fres['elapsed_s'] = round(time.time() - t_fr, 1)
            rep['frames'].append(fres)
            emit('SG1 frame%d %s elapsed=%.1fs tasks=%d convs=%d'
                 % (fi, 'PASS' if fres['pass'] else 'FAIL',
                    fres['elapsed_s'], len(fres['tasks']),
                    sum(1 for t in fres['tasks'] if t['op'] == 'conv')))
            if not fres['pass']:
                break
    finally:
        csv.close()

    rep['gates'] = {k: bool(v) for k, v in results.items()}
    rep['totals'] = dict(counts)
    rep['anchors_checked'] = sorted(anchor_done)
    sg1 = all(f.get('pass') for f in rep['frames']) and \
        len(rep['frames']) == 5
    sg3 = all(t.get('guard_ok', True)
              for f in rep['frames'] for t in f['tasks'])
    sg4 = all(t['nerr'] == 0
              for f in rep['frames'] for t in f['tasks']
              if t['op'] in ('view', 'add', 'concat', 'maxpool5',
                             'upsample2', 'heads'))
    sga_all = len(anchor_done) == len(ANCHORS) and \
        all(results.get('SGa:%s' % n, False) for n in ANCHORS)
    allpass = all([results.get(k, False) for k in
                   ['CK0', 'CK1', 'CK4', 'CK5', 'CK6', 'DB1', 'DB2',
                    'SGi']]) and sga_all and sg1 and sg3 and sg4 and \
        counts['timeouts'] == 0 and counts['lut_loads'] == EXP_LUT
    rep['verdict'] = VERDICT_PASS if allpass else VERDICT_FAIL
    json.dump(rep, open(os.path.join(HERE, 'm3_%s_board_report.json' % STAGE),
              'w', encoding='utf-8'), indent=1, ensure_ascii=False)
    emit('SG2 timeouts=%d (0=DMA 无挂死) lut_loads=%d (exp %d)'
         % (counts['timeouts'], counts['lut_loads'], EXP_LUT))
    emit('CKz TOTAL wop=%d rop=%d blocks=%d -> %s'
         % (counts['wop'], counts['rop'], counts['blocks'],
            rep['verdict']))
    return 0 if allpass else 1


if __name__ == '__main__':
    sys.exit(main())
