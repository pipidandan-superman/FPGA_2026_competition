#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""pl_m5.py — M5 板级混合 backend 驱动：V2.4（conv GEMM 路径 + PPU 岛图算子阶梯）

移植律（replan §7 + 计划 prancy-brewing-sloth）：
  conv 面 = pl_m3.py 板证律逐字转录（rne_shift/sat_i8/sat_i32/req_pair/
    maxpool5/upsample_nearest2/Geo/pack_tile/dump_state/load_lut/_mm2s_seg/
    wait_pend_clear/arm_and_run/board_conv/emit 共 16 单元；上板前由
    rehearse_m5_driver 以「inspect 源码同一性 + 315 全装载流行为等价」
    双锁证明转录无损）。
  PPU 面 = pl_v23b_v24bit.py 板证时序（/dev/mem 牺牲探针→YOL2 身份→
    CMA（download 后分配）→CSR 缺省先于表（CTRL=0x1/DMA_CFG/head base/
    DESC_CFG=0/FRAME_ID=0）→三表窗口装载逐字回读→CTRL=0x5→DONE_COUNT/
    RESULT_SEQ 轮询→ring 六字门→结果面三字门→invalidate→ACK 先于
    RING_TAIL）+ tb_ppu_f7 程序紧凑律（满表载入→原地紧凑 slot s←
    A[PROG[s]]→buf 表 w6 producer 同域重编：段内 orig→slot、任务外→
    0xFF 外部标记=loader 步 5 明确豁免）。

M5 段律（新面；每段=一次 v23b 式完整帧，规避未证明的帧中段追加）：
  图程序按 sched 序切「极大连续 PPU 段」（段界=conv/view/software 等
  CPU 任务）；段间 CPU 任务先执行（其产物已入 arena）；每段在 PPU 空闲
  （前段已 ack）时：desc 窗重写 [0,n)（末槽 w0|=bit9 段尾；TB/v23b 正典
  的 COUNT=TAIL=n 单帧形状）→ buf 表 w6 producer 逐条 RMW 重编（本段
  orig→slot、其余→0xFF；RMW 保留 walker 变迁后的 owner/generation 字节，
  与 v23b 五帧同表不重置的板证先例一致）→ arena.flush()（CPU 脏行下行）
  → FRAME_ID/COUNT/TAIL → CTRL=0x5 → 轮询 → ring/结果面门 →
  arena.invalidate()（PL 写后 CPU 读前）→ ACK→RING_TAIL。跨段生产者
  一律 0xFF：数据已在 arena，与 v23b 预载同类（外部生产合同）。

阶梯（计划 §板级阶梯；每档全图 104 任务×5 帧，判据恒为 == M3 golden
  逐字节）：l0 PPU 空转（表装载+身份门；控制组=V2.4 conv 回归+全图
  software backend、张量入 CMA）；l1 +add 6；l2 +mp5 3+ups2 2；
  l3 +concat 13；l4 +heads 1 → 25 引擎任务全 PPU + 16 view 别名
  （CPU numpy 零拷贝切片，arena 视图，零字节搬移）。

张量 ABI：图张量全量入 CMA graph arena（buffer_table base_off=共享
  ABI；w0 += delta（mod 2^32）补丁映射模型窗→实 phys）；view 出区=
  CPU 别名（PPU 消费方按 buf 表别名基址直读父区字节，与 CPU 切片同
  字节）；heads 出区=独立 head 缓冲（HEAD_BASE 寄存器指实 phys）。
  conv 镜像 CMA（m3_meta cma_bytes）与 graph arena 分立分配；conv
  gather 产物由 CPU 抄写入 arena 出区（桥）。

板上判据（每档）：CK0-CK6/DB1-DB2 上电正典（pl_m3 逐字）+ PK1 PPU
  牺牲探针/身份/版本 + PK2 双 arena 对齐 + PK3 三表装载回读（含段间
  重写回读）+ SGi/STG/SGa/SG1/SG3/SG4/SGl（M3 同律；SG1 含 arena 抄写
  后二次逐位）+ PPG 段门（DONE/SEQ/ring 六字/结果面三字/ack 位，逐段）
  → BOARD_M5_L{n}_PASS。

Usage (board pack dir): python3 pl_m5.py <l0|l1|l2|l3|l4> [tag]
PC 侧（rehearse_m5_driver.py）导入本模块：argv 不在导入期解析（与
pl_m3 的导入期档断言不同，属 M5 设计点——纯函数面供彩排复用）。
"""
import os, sys, time, hashlib, subprocess, mmap, struct, json, math
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
BIT = os.path.join(HERE, 'yolo_v24_m5.bit')

# ---- 板上包内输入（自包含律；PC 彩排经 P.update() 重绑定） ----
P = {
    'meta':   os.path.join(HERE, 'm3_meta.json'),
    'params': os.path.join(HERE, 'm3_params.npz'),
    'refs':   os.path.join(HERE, 'refs_f%d.npz'),
    'hex_desc': os.path.join(HERE, 'desc_table_A.hex'),
    'hex_buf':  os.path.join(HERE, 'buf_table_A.hex'),
    'hex_qt':   os.path.join(HERE, 'quant_table_A.hex'),
    'v11_buf':  os.path.join(HERE, 'buffer_table.json'),   # 板上包自包含合同
}

STAGES = ('l0', 'l1', 'l2', 'l3', 'l4')        # M5 阶梯（计划 §板级阶梯）
ENGINE_CLASSES = ('add', 'maxpool5', 'upsample2', 'concat', 'heads')
BACKEND_RAMP = {                                # 档 → PPU 上的算子类集合
    'l0': set(),
    'l1': {'add'},
    'l2': {'add', 'maxpool5', 'upsample2'},
    'l3': {'add', 'maxpool5', 'upsample2', 'concat'},
    'l4': {'add', 'maxpool5', 'upsample2', 'concat', 'heads'},
}
EXPECT_PROG = {'l0': 0, 'l1': 6, 'l2': 11, 'l3': 24, 'l4': 25}   # 档内程序任务数（v11 宇宙）
EXPECT_ENG_TOTAL = 25                            # 引擎任务全集（三重锁）

tag = 'm5'
VERDICT_STAGES = STAGES

GEMM_BASE, CSR_BASE, DMA_BASE = 0x43C00000, 0x43C10000, 0x40400000
PPU_BASE = 0x43C20000                           # V2.4 岛（abi/address_map.md）
EXP_GEMM_ID = 0x20260919
EXP_FCLK0_RAW = 0x00200500            # run25 正典：真 100 MHz
EXP_PPU_ID = 0x594F4C32               # "YOL2"（yolo_csr_pkg YOLO_ID_VALUE）
EXP_PPU_VERSION = 0x0300

# ---- GEMM CSR map（合同 §9；pl_m3 逐字）----
A_ID, A_CTRL, A_STATUS = 0x00, 0x04, 0x08
A_GEOM, A_ROWVAL, A_NMASK, A_JOBCFG, A_LDGRP = 0x0C, 0x10, 0x14, 0x18, 0x1C
A_P_BIAS, A_P_M, A_P_SH, A_PCTL = 0x20, 0x24, 0x28, 0x2C
A_LDSTAT, A_LDLEN, A_LUTD = 0x3C, 0x40, 0x44
A_YSTAT = 0x48
A_BRGSTAT, A_STALLCNT = 0x54, 0x58
# ---- DMA map（pl_m3 逐字）----
D_MM2S_DMACR, D_MM2S_DMASR, D_MM2S_SA, D_MM2S_LEN = 0x00, 0x04, 0x18, 0x28
D_S2MM_DMACR, D_S2MM_DMASR, D_S2MM_DA, D_S2MM_LEN = 0x30, 0x34, 0x48, 0x58
B_RS = 0x1
B_HALTED, B_IDLE, B_SGINCLD = 0x1, 0x2, 0x8
B_ERRS = 0x70
B_IOC_IRQ, B_ERR_IRQ = 0x1000, 0x4000
PAGE = 0x1000

# ---- PPU CSR map（yolo_csr_pkg.sv 冻结权威；rehearse X6 对 pkg 逐项核）----
PA_ID, PA_VERSION = 0x000, 0x004
PA_CTRL, PA_STATUS, PA_ERROR_STATUS, PA_ERROR_INFO = 0x010, 0x014, 0x018, 0x01C
PA_FRAME_ID = 0x028
PA_HEAD_BASE_LO, PA_HEAD_BASE_HI = 0x040, 0x044
PA_HEAD_BYTES, PA_HEAD_FORMAT = 0x04C, 0x050
PA_RESULT_SEQ, PA_RESULT_FRAME_ID, PA_RESULT_ACK = 0x054, 0x058, 0x060
PA_RESULT_RING_HEAD, PA_RESULT_RING_TAIL = 0x064, 0x068
PA_DESC_CFG, PA_DESC_BASE, PA_DESC_COUNT = 0x100, 0x104, 0x108
PA_DESC_HEAD, PA_DESC_TAIL, PA_DESC_DOORBELL = 0x10C, 0x110, 0x114
PA_DESC_DONE_COUNT = 0x11C
PA_DMA_CFG = 0x200
W_DESC, W_BUF, W_QT, W_LUT, W_RING = 0x1000, 0x3000, 0x4000, 0x5000, 0x6000
PPU_DMA_CFG_DEFAULT = (4 << 27) | (4 << 24) | 100    # wr_os=4 rd_os=4 tmo=100

# ---- 打包宇宙常数（ppu_desc_bundle / ppu_packer_n80 合同）----
ARENA_BASE_MODEL = 0x10000000            # buffer_table cma_window 下界
DESC_WORDS, BUF_WORDS, QT_WORDS = 32, 8, 4
DESC_ITEMS, BUF_ITEMS, QT_ITEMS = 128, 128, 256
OPCODE = {'conv': 0x01, 'view': 0x10, 'add': 0x11, 'concat': 0x12,
          'maxpool5': 0x13, 'upsample2': 0x14, 'heads': 0x15}
OP_OF = {v: k for k, v in OPCODE.items()}
PRODUCER_EXTERNAL = 0xFF

POISON = 0xA5
MASKED_LANE = 0xA5
GUARD_LEN = 0x10000
results = {}
counts = {'wop': 0, 'rop': 0, 'blocks': 0, 'timeouts': 0, 'lut_loads': 0,
          'ppu_wop': 0, 'ppu_rop': 0, 'segs': 0}


# ======================================================================
# conv 面十六单元：pl_m3.py 逐字转录（rehearse X1 源码同一性锁的对象）
# ======================================================================
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


# ======================================================================
# 纯表律：hex 装载 / 字段解码 / 阶段程序与段打包（PC+板共用）
# ======================================================================
def load_hex_words(path):
    """$readmemh 同式：空白分隔 32 位字流 → np.uint32 数组。"""
    txt = open(path).read().split()
    return np.array([int(t, 16) for t in txt], dtype=np.uint32)


def dec_desc(ws):
    """32 字描述符 → 字段（ppu_packer_n80 pack_desc 逆；rehearse 对
    v11 JSON 逐项核对）。"""
    return {
        'opcode': ws[0] & 0xFF, 'valid': (ws[0] >> 8) & 1,
        'last': (ws[0] >> 9) & 1,
        'index': ws[1] & 0xFF, 'dep_id': (ws[1] >> 8) & 0xFF,
        'next_id': (ws[1] >> 16) & 0xFF,
        'in0': ws[2] & 0x3FF, 'in1': (ws[2] >> 10) & 0x3FF,
        'out': (ws[2] >> 20) & 0x3FF,
        'c': ws[3] & 0xFFFF, 'h': ws[3] >> 16, 'w': ws[4] & 0xFFFF,
        'prof_in0': ws[5] & 0xFFFF, 'prof_in1': ws[5] >> 16,
        'n_seg': ws[6], 'in0_len': ws[7], 'mode': ws[9],
        'out_bytes': ws[14],
        'segs': [{'buf': ws[16 + 2 * i] & 0x3FF,
                  'prof': (ws[16 + 2 * i] >> 16) & 0xFF,
                  'nbytes': ws[17 + 2 * i]}
                 for i in range(ws[6])],
    }


def dec_quant_cell(ws4):
    """4 字 quant 单元 → (m_signed, shift)（pack_quant 逆；f7prep
    sgn32 同式：m 以 32 位有符号解释）。"""
    m, s = int(ws4[0]), int(ws4[1]) & 0xFF
    if m >= (1 << 31):
        m -= (1 << 32)
    return m, s


def build_stage_plan(descs, A_words, stage, buf_words):
    """阶段程序/段规划（tb_ppu_f7 紧凑律的逐段化）。

    返回 dict：
      prog      程序任务 id 列表（sched 序）
      segments  段列表；每段 {'ids', 'tds', 'words'(32n, 末槽 bit9),
                'prod'(128 项 producer 字节), 'sum_w14', 'has_heads'}
    段=程序任务在 sched 序上的极大连续游程（段界=CPU 任务）。
    words 律：非末槽 w0 清 bit9、末槽置 bit9（每段自成完整帧；l4 末段
    =heads 槽原生 bit9，置位幂等）；其余 31 字逐字照录 A 表。
    prod 律：producer 字节读 **buf_words**（buf 表 w6 低字节=该 buf
    唯一生产任务 desc_id；rehearse R2 独立复算锁）——在 ids 内→段内
    槽位，否则 0xFF 外部（空槽 104-127 残留字节经 ids≤103 门自落
    0xFF；input buf0 原生 0xFF）。"""
    ramp = BACKEND_RAMP[stage]
    prog = [td['desc_id'] for td in descs if td['op'] in ramp]
    segs = []
    cur = []
    for td in descs:
        if td['op'] in ramp:
            cur.append(td)
        elif cur:
            segs.append(cur)
            cur = []
    if cur:
        segs.append(cur)
    bundles = []
    for tds in segs:
        ids = [td['desc_id'] for td in tds]
        n = len(ids)
        words = []
        for j, di in enumerate(ids):
            ws = [int(x) for x in A_words[32 * di:32 * di + 32]]
            ws[0] &= ~(1 << 9) if j < n - 1 else 0xFFFFFFFF
            if j == n - 1:
                ws[0] |= (1 << 9)
            words.extend(ws)
        prod = []
        for b in range(BUF_ITEMS):
            orig = int(buf_words[8 * b + 6]) & 0xFF
            if orig != PRODUCER_EXTERNAL and orig in ids:
                prod.append(ids.index(orig))
            else:
                prod.append(PRODUCER_EXTERNAL)
        sum_w14 = sum(int(A_words[32 * di + 14]) for di in ids)
        bundles.append({
            'ids': ids, 'tds': tds, 'words': words, 'prod': prod,
            'sum_w14': sum_w14,
            'has_heads': any(td['op'] == 'heads' for td in tds)})
    return {'prog': prog, 'segments': bundles}


def patch_buf_words(buf_words, delta, n_entries):
    """w0 基址补丁（v23b 律：模型基 + delta，mod 2^32；仅表内实条目）。"""
    bw = buf_words.copy()
    for b in range(n_entries):
        bw[8 * b] = np.uint32((int(bw[8 * b]) + delta) & 0xFFFFFFFF)
    return bw


def apply_w6_remap(buf_words, prod):
    """整表 w6 producer 重编（新表或 RMW 同式：保留 [31:8] 字节）。"""
    bw = buf_words.copy()
    for b in range(BUF_ITEMS):
        w6 = int(bw[8 * b + 6])
        bw[8 * b + 6] = np.uint32((w6 & 0xFFFFFF00) | prod[b])
    return bw


# ======================================================================
# 软件图算子律（pl_m3 帧循环同式；arena 视图进出）
# ======================================================================
def sw_add(a, b_, td):
    qa = req_pair(td['a_scale'] / td['out_scale'])
    qb = req_pair(td['b_scale'] / td['out_scale'])
    A_ = rne_shift(a.astype(np.int64) * qa[0], qa[1])
    B_ = rne_shift(b_.astype(np.int64) * qb[0], qb[1])
    return sat_i8(sat_i32(A_ + B_))


def sw_concat(parts, td):
    outs = []
    for p_, s_ in zip(parts, td['inputs']):
        q = req_pair(s_['scale'] / td['out_scale'])
        outs.append(sat_i8(rne_shift(p_.astype(np.int64) * q[0], q[1])))
    return np.concatenate(outs, axis=0)


def heads_blob(td, tensor_of):
    """6 分支按段序拼 blob（pl_m3 heads 支同式：reg 先 cls 后、段内
    HEADS_SEG_ORDER 稳定排序）。tensor_of(buf)→int8 [C,H,W]。"""
    seg_of = {40: '8', 20: '16', 10: '32'}
    seg_map = {}
    for grp in ('reg', 'cls'):
        for e in td[grp]:
            seg_map[grp + seg_of[e['shape'][2]]] = e['buf']
    order = ('reg8', 'reg16', 'reg32', 'cls8', 'cls16', 'cls32')
    all_entries = td['reg'] + td['cls']
    parts_, heads_len = [], 0
    for k_ in order:
        buf = seg_map[k_]
        e = next(x for x in all_entries if x['buf'] == buf)
        t_ = tensor_of(buf)
        assert list(t_.shape) == e['shape'], k_
        b_ = np.ascontiguousarray(t_).tobytes()
        heads_len += len(b_)
        parts_.append(b_)
    return b''.join(parts_), heads_len


# ======================================================================
# arena 视图 ABI（图张量共享内存合同）
# ======================================================================
class Arena(object):
    """图 arena 之上的张量视图合同（板=pynq CMA；PC=ndarray）。

    view(buf) → int8 [C,H,W] 视图；write(buf, y) → 字节抄写入区并返回
    视图（M5 律：任务产物一律经 arena 字节，CPU 侧张量=arena 视图，
    混合 backend 的单一事实源）。"""

    def __init__(self, arr, bufs):
        self.a = arr
        self.bufs = bufs

    def view(self, bid):
        ent = self.bufs[bid]
        o, n = ent['base_off'], ent['size']
        c, h, w = ent['shape']
        assert c * h * w == n, bid
        return self.a[o:o + n].view(np.int8).reshape(c, h, w)

    def write(self, bid, y):
        ent = self.bufs[bid]
        o, n = ent['base_off'], ent['size']
        assert y.size * y.itemsize == n, bid
        self.a[o:o + n] = np.ascontiguousarray(y).view(np.uint8).reshape(-1)
        return self.view(bid)

    def raw(self, bid, nbytes=None):
        ent = self.bufs[bid]
        o = ent['base_off']
        n = ent['size'] if nbytes is None else nbytes
        return bytes(self.a[o:o + n])

    def write_raw(self, bid, blob):
        ent = self.bufs[bid]
        o, n = ent['base_off'], ent['size']
        assert len(blob) <= n, bid
        self.a[o:o + len(blob)] = np.frombuffer(blob, dtype=np.uint8)
        return self.view(bid)


# ======================================================================
# 混合帧循环（PC/板共用骨架；hooks 注入执行面）
# ======================================================================
class Ctx(object):
    pass


def _frec(ctx, td, fi, op, ref):
    """逐任务取证记录公共字段（§B2 + M5 backend 字段）。"""
    backend = ('gemm' if op == 'conv' else
               'ppu' if op in ctx.ramp else 'software')
    return {
        'sched_index': int(td['sched_index']), 'node': td['node'],
        'op': op, 'backend': backend,
        'in_bufs': list(td['in_bufs']), 'out_buf': td['out_buf'],
        'shape': [int(v) for v in ref.shape] if ref is not None else None,
        'byte_len': int(ref.nbytes) if ref is not None else None,
        'oracle_sha256': ctx.meta['ref_sha256'].get(
            'f%d/%s' % (fi, td['node'])),
    }


def run_frames(ctx):
    """五帧混合 backend 主循环（M5 律）。

    ctx 需携带：stage/ramp/arena(Arena)/headb(或 None)/descs/geos/
    bufs/meta/ANCHORS/csv/segments(段束)/hooks/exp_lut/refs 加载器。
    hooks 合同：conv(node,geo,x,fi)→y|None；ppu_segment(k,bundle)→bool；
    pre_flush()/post_invalidate(has_heads)（缓存维护面，PC=空）。"""
    descs, arena = ctx.descs, ctx.arena
    tensors = {}
    for fi in range(5):
        fr = dict(np.load(ctx.refs_pat % fi))
        canvas = fr['canvas']
        x0 = (canvas.astype(np.int16) - 128).astype(np.int8) \
            .transpose(2, 0, 1).copy()
        arena.a[:] = POISON
        ctx.hooks.pre_flush()
        tensors.clear()
        tensors[0] = arena.write(0, x0)      # 唯一外部种子=canvas（seg0 律）
        fres = {'frame': fi, 'tasks': [], 'segs': [], 'pass': True}
        t_fr = time.time()
        seg_i = 0
        pend = False                          # 当前处于 PPU 连续游程中
        pend_ids = []                         # 游程任务 id（段结构自证）

        def flush_seg():
            nonlocal seg_i, pend, fres
            bd = ctx.segments[seg_i]
            assert bd['ids'] == pend_ids, \
                ('segment mismatch', seg_i, bd['ids'], pend_ids)
            t_sg = time.time()
            ok = ctx.hooks.ppu_segment(seg_i, bd)
            srec = {'seg': seg_i, 'ids': bd['ids'], 'n': len(bd['ids']),
                    'sum_w14': bd['sum_w14'], 'ok': bool(ok),
                    'elapsed_ms': int((time.time() - t_sg) * 1e3)}
            fres['segs'].append(srec)
            counts['segs'] += 1
            seg_i += 1
            pend = False
            del pend_ids[:]
            if not ok:
                emit('PPG f%d seg%d FAIL ids=%s' % (fi, seg_i - 1,
                                                     bd['ids']))
                fres['pass'] = False
                return
            # 段内任务取证（invalidate 已由 hooks 完成；视图=post-PL 字节）
            for td in bd['tds']:
                op, node = td['op'], td['node']
                key = 'ref_%d_%s' % (td['sched_index'], node.replace('.', '_'))
                if op == 'heads':
                    blob, hlen = heads_blob(td, lambda b_: tensors[b_])
                    hb = ctx.headb
                    got = bytes(hb[:hlen])
                    got_h = hashlib.sha256(got).hexdigest()
                    exp_h = ctx.meta['heads_blob_sha256']['f%d' % fi]
                    nerr = int(np.count_nonzero(
                        np.frombuffer(got, np.uint8) !=
                        np.frombuffer(blob, np.uint8))) \
                        if hb is not None else (0 if
                        hashlib.sha256(blob).hexdigest() == exp_h else 1)
                    rec = _frec(ctx, td, fi, op, None)
                    rec.update({
                        'oracle_sha256': exp_h, 'byte_len': int(hlen),
                        'nerr': nerr, 'blob_sha256': got_h,
                        'blob_len': int(hlen)})
                    fres['tasks'].append(rec)
                    if nerr:
                        emit('SG4 %s f%d heads ppu blob %dB nerr=%d'
                             % (node, fi, hlen, nerr))
                        fres['pass'] = False
                    continue
                ref = fr.get(key)
                v = arena.view(td['out_buf'])
                tensors[td['out_buf']] = v
                nerr = int(np.count_nonzero(v != ref))
                rec = _frec(ctx, td, fi, op, ref)
                rec.update({
                    'nerr': nerr,
                    'out_sha256': hashlib.sha256(
                        np.ascontiguousarray(v).tobytes()).hexdigest()})
                fres['tasks'].append(rec)
                if nerr:
                    rec['first_mismatch_offset'] = int((v != ref).argmax())
                    bad = np.argwhere(v != ref)[0]
                    emit('SG4 %s f%d %s(ppu) nerr=%d first=%s'
                         % (node, fi, op, nerr, [int(q) for q in bad]))
                    fres['pass'] = False

        for td in descs:
            op, node = td['op'], td['node']
            key = 'ref_%d_%s' % (td['sched_index'], node.replace('.', '_'))
            ref = fr.get(key)          # heads 无参照张量（blob SHA 门）
            if op in ctx.ramp:          # PPU backend：并入当前游程
                pend = True
                pend_ids.append(td['desc_id'])
                continue
            if pend:                    # 段界：先冲当前游程
                flush_seg()
                if not fres['pass']:
                    break
            if op == 'conv':
                geo = ctx.geos[node]
                geo.frame = fi
                y = ctx.hooks.conv(node, geo, tensors[td['in_bufs'][0]], fi)
                if y is None:
                    fres['pass'] = False
                    break
                # SGa：档内 f0 装载锚（板上 conv 镜像装载区；M3 同律）
                if fi == 0 and node in ctx.ANCHORS and \
                        node not in ctx.anchor_done:
                    if ctx.npbuf is not None:
                        got = hashlib.sha256(bytes(
                            ctx.npbuf[geo.load_off:
                                      geo.load_off + geo.tll * geo.NB]
                        )).hexdigest()
                        ok_a = got == ctx.ANCHORS[node]
                        results['SGa:%s' % node] = ok_a
                        ctx.anchor_done.add(node)
                        emit('SGa %s loads anchor %s -> %s'
                             % (node, got[:16], 'PASS' if ok_a else 'FAIL'))
                        if not ok_a:
                            fres['pass'] = False
                            break
                    else:
                        ctx.anchor_done.add(node)
                yv8 = y.view(np.int8)
                nerr = int(np.count_nonzero(yv8 != ref))
                rec = _frec(ctx, td, fi, op, ref)
                rec.update({
                    'nerr': nerr, 'blocks': int(geo.NB),
                    'guard_ok': bool(getattr(geo, 'guard_ok', False))})
                if nerr:
                    rec['first_mismatch_offset'] = int((yv8 != ref).argmax())
                    bad = np.argwhere(yv8 != ref)[0]
                    oc, oy, ox = [int(v_) for v_ in bad]
                    s = ox // 16
                    b = (oy * geo.n_strips + s) * geo.RC + oc // 8
                    emit('SG1 %s f%d nerr=%d first=(oc%d,oy%d,ox%d) '
                         'blk=%d got=%d exp=%d'
                         % (node, fi, nerr, oc, oy, ox, b,
                            int(yv8[oc, oy, ox]), int(ref[oc, oy, ox])))
                    fres['tasks'].append(rec)
                    fres['pass'] = False
                    break
                if not getattr(geo, 'guard_ok', False):
                    emit('SG3 %s f%d guard broken' % (node, fi))
                    fres['tasks'].append(rec)
                    fres['pass'] = False
                    break
                # M5 桥：gather 产物抄入 graph arena（共享 ABI 出区）
                v = arena.write(td['out_buf'], y)
                anerr = int(np.count_nonzero(v != ref))
                rec['arena_nerr'] = anerr
                rec['out_sha256'] = hashlib.sha256(
                    np.ascontiguousarray(v).tobytes()).hexdigest()
                tensors[td['out_buf']] = v
                fres['tasks'].append(rec)
                if anerr:
                    emit('SG1 %s f%d arena bridge nerr=%d' % (node, fi, anerr))
                    fres['pass'] = False
                    break
            elif op == 'view':
                par = tensors[td['parent_buf']]
                tensors[td['out_buf']] = par[td['ch'][0]:td['ch'][1]]
                zero = np.shares_memory(tensors[td['out_buf']], par)
                nerr = int(np.count_nonzero(tensors[td['out_buf']] != ref))
                rec = _frec(ctx, td, fi, op, ref)
                rec.update({
                    'nerr': nerr,
                    'out_sha256': hashlib.sha256(np.ascontiguousarray(
                        tensors[td['out_buf']]).tobytes()).hexdigest(),
                    'zero_copy': bool(zero),
                    'parent_buf': td['parent_buf'],
                    'ch': [int(v_) for v_ in td['ch']]})
                fres['tasks'].append(rec)
                if nerr or not zero:
                    emit('SG4 %s f%d view nerr=%d zero=%s'
                         % (node, fi, nerr, zero))
                    fres['pass'] = False
                    break
            elif op in ('add', 'concat', 'maxpool5', 'upsample2'):
                if op == 'add':
                    y = sw_add(tensors[td['a_buf']], tensors[td['b_buf']], td)
                elif op == 'concat':
                    y = sw_concat([tensors[s_['buf']] for s_ in td['inputs']],
                                  td)
                elif op == 'maxpool5':
                    y = maxpool5(tensors[td['in_bufs'][0]])
                else:
                    y = upsample_nearest2(tensors[td['in_bufs'][0]])
                v = arena.write(td['out_buf'], y)
                tensors[td['out_buf']] = v
                nerr = int(np.count_nonzero(v != ref))
                rec = _frec(ctx, td, fi, op, ref)
                rec.update({
                    'nerr': nerr,
                    'out_sha256': hashlib.sha256(
                        np.ascontiguousarray(v).tobytes()).hexdigest()})
                fres['tasks'].append(rec)
                if nerr:
                    rec['first_mismatch_offset'] = int((v != ref).argmax())
                    bad = np.argwhere(v != ref)[0]
                    emit('SG4 %s f%d %s(sw) nerr=%d first=%s'
                         % (node, fi, op, nerr, [int(q) for q in bad]))
                    fres['pass'] = False
                    break
            elif op == 'heads':
                blob, hlen = heads_blob(td, lambda b_: tensors[b_])
                got_h = hashlib.sha256(blob).hexdigest()
                nerr = 0 if (hlen == ctx.meta['heads_total'] and
                             got_h == ctx.meta['heads_blob_sha256'][
                                 'f%d' % fi]) else 1
                rec = _frec(ctx, td, fi, op, None)
                rec.update({
                    'oracle_sha256': ctx.meta['heads_blob_sha256']['f%d' % fi],
                    'byte_len': int(hlen), 'nerr': nerr,
                    'blob_sha256': got_h, 'blob_len': int(hlen)})
                fres['tasks'].append(rec)
                if nerr:
                    emit('SG4 %s f%d heads blob %dB sha=%s exp=%s'
                         % (node, fi, hlen, got_h[:16],
                             ctx.meta['heads_blob_sha256']['f%d' % fi][:16]))
                    fres['pass'] = False
                    break
            else:
                emit('SG4 op %s 越界（整网程序无此算子）' % op)
                fres['pass'] = False
                break
        if fres['pass'] and pend:
            flush_seg()                  # 帧尾游程
        fres['elapsed_s'] = round(time.time() - t_fr, 1)
        ctx.rep['frames'].append(fres)
        emit('FRAME f%d %s elapsed=%.1fs tasks=%d segs=%d'
             % (fi, 'PASS' if fres['pass'] else 'FAIL', fres['elapsed_s'],
                len(fres['tasks']), len(fres['segs'])))
        if not fres['pass']:
            break
    return all(f.get('pass') for f in ctx.rep['frames']) and \
        len(ctx.rep['frames']) == 5


# ======================================================================
# 板上 hooks：conv=pl_m3 律；PPU 段=v23b+TB 段律
# ======================================================================
class BoardHooks(object):
    def __init__(self, g, d, cma, csv):
        self.g, self.d, self.cma, self.csv = g, d, cma, csv
        self.cur_lut = None
        self.p = None                  # PPU MMIO（bind_ppu 注入）
        self.arena_arr = None
        self.headb = None
        self.seg_ctr = 0

    # ---- conv：LUT 记忆跨帧 + board_conv（pl_m3 帧循环 conv 支同律）----
    def conv(self, node, geo, x, fi):
        if self.cur_lut != node:
            if not load_lut(self.g, geo):
                return None
            self.cur_lut = node
            counts['lut_loads'] += 1
        return board_conv(self.g, self.d, self.cma, geo, x, self.csv)[0]

    # ---- 缓存维护面 ----
    def pre_flush(self):
        if hasattr(self.arena_arr, 'flush'):
            self.arena_arr.flush()

    def post_invalidate(self, has_heads):
        if hasattr(self.arena_arr, 'invalidate'):
            self.arena_arr.invalidate()
        if has_heads and hasattr(self.headb, 'invalidate'):
            self.headb.invalidate()

    # ---- PPU 段律（每段=一次 v23b 式完整帧）----
    def p_rd(self, a):
        counts['ppu_rop'] += 1
        return self.p.read(a)

    def p_wr(self, a, v):
        counts['ppu_wop'] += 1
        self.p.write(a, int(v) & 0xFFFFFFFF)

    def ppu_segment(self, k, bd):
        p, n = self.p, len(bd['ids'])
        words = bd['words']
        # 表更新（PPU 空闲=前段已 ack；E_CODE_TABLE_RUN 规避）
        for w in range(32 * n):
            self.p_wr(W_DESC + 4 * w, words[w])
        bad = sum(1 for w in range(32 * n)
                  if self.p_rd(W_DESC + 4 * w) != words[w])
        if bad:
            emit('PK3 f-seg%d desc rewrite bad_rb=%d' % (k, bad))
            return False
        for b in range(BUF_ITEMS):
            cur = self.p_rd(W_BUF + 4 * (8 * b + 6))
            tgt = (int(cur) & 0xFFFFFF00) | bd['prod'][b]
            if tgt != int(cur):
                self.p_wr(W_BUF + 4 * (8 * b + 6), tgt)
                if self.p_rd(W_BUF + 4 * (8 * b + 6)) != tgt:
                    emit('PK3 seg%d w6 buf%d readback' % (k, b))
                    return False
        self.pre_flush()                       # CPU 脏行下行（本段输入）
        sc = self.seg_ctr
        self.p_wr(PA_FRAME_ID, sc)
        self.p_wr(PA_DESC_COUNT, n)
        self.p_wr(PA_DESC_TAIL, n)
        t0 = time.time()
        self.p_wr(PA_CTRL, 0x5)                # enable + start_frame
        done = 0
        while time.time() - t0 < 30.0:
            done = self.p_rd(PA_DESC_DONE_COUNT) & 0xFFFF
            if done == n:
                break
        seq = 0
        t1 = time.time()
        while time.time() - t1 < 10.0:
            seq = self.p_rd(PA_RESULT_SEQ)
            if seq == sc + 1:
                break
        e = self.p_rd(PA_ERROR_STATUS)
        ent = sc & 31
        r_fid = self.p_rd(W_RING + 64 * ent + 0)
        r_seq = self.p_rd(W_RING + 64 * ent + 4)
        r_hb = self.p_rd(W_RING + 64 * ent + 8)
        r_byt = self.p_rd(W_RING + 64 * ent + 16)
        r_fl = self.p_rd(W_RING + 64 * ent + 40)
        dhead = self.p_rd(PA_DESC_HEAD) & 0xFFFF
        ring_ok = (r_fid == sc and r_seq == sc + 1 and
                   r_byt == bd['sum_w14'] and (r_fl & 1) == 1 and
                   dhead == n and e == 0)
        rf_seq = self.p_rd(PA_RESULT_FRAME_ID)
        rf_bytes = self.p_rd(PA_HEAD_BYTES)
        rf_head = self.p_rd(PA_RESULT_RING_HEAD) & 0xFF
        face_ok = (rf_seq == sc and rf_bytes == bd['sum_w14'] and
                   rf_head == (sc + 1) & 0xFF)
        self.post_invalidate(bd['has_heads'])
        self.p_wr(PA_RESULT_ACK, 0x1)          # ack 先于尾针（v23b 律）
        self.p_wr(PA_RESULT_RING_TAIL, (sc + 1) & 0xFF)
        time.sleep(0.01)
        ack_bit = (self.p_rd(PA_STATUS) >> 7) & 1   # v23b 律：记录不设门
        self.seg_ctr += 1
        ok = bool(done == n and seq == sc + 1 and ring_ok and face_ok)
        rep_seg = ctx_segs_rec(self, k, bd, sc, done, seq, e,
                               (r_fid, r_seq, r_hb, r_byt, r_fl, dhead),
                               (rf_seq, rf_bytes, rf_head), ack_bit, ok)
        return ok


def ctx_segs_rec(hooks, k, bd, sc, done, seq, e, ring, face, ack_bit, ok):
    """段证据落 rep（失败路径附 v23b dump_face 同式取证）。"""
    rec = {'seg': k, 'global': sc, 'n': len(bd['ids']), 'ids': bd['ids'],
           'sum_w14': bd['sum_w14'], 'done': done, 'seq': seq,
           'err_status': '0x%X' % e,
           'ring': {'fid': ring[0], 'seq': ring[1], 'hb_lo': '0x%X' % ring[2],
                    'bytes': ring[3], 'flags': '0x%X' % ring[4],
                    'desc_head': ring[5]},
           'face': {'fid': face[0], 'bytes': face[1], 'rhead': face[2]},
           'ack_bit': ack_bit, 'ok': ok}
    if not ok:
        ei = hooks.p_rd(PA_ERROR_INFO)
        rec['dump'] = {
            'status': '0x%08X' % hooks.p_rd(PA_STATUS),
            'err_info': '0x%08X' % ei,
            'err_decode': {'port': (ei >> 24) & 0xFF,
                           'desc_id': (ei >> 16) & 0xFF,
                           'op': (ei >> 8) & 0xFF, 'code': ei & 0xFF},
            'dbg0': '0x%08X' % hooks.p_rd(0x7000),
            'ring_raw': ['0x%08X' % hooks.p_rd(W_RING + 64 * (sc & 31) +
                                               4 * i) for i in range(16)],
            'desc_current': hooks.p_rd(0x118)}
    if hasattr(hooks, 'seg_recs'):
        hooks.seg_recs.append(rec)
    return rec


# ======================================================================
# 板上 main
# ======================================================================
def main():
    global tag
    stage = sys.argv[1] if len(sys.argv) > 1 else 'l4'
    assert stage in STAGES, stage
    tag = (sys.argv[2] if len(sys.argv) > 2 else 'm5_' + stage)
    VERDICT_PASS = 'BOARD_M5_%s_PASS' % stage.upper()
    VERDICT_FAIL = 'BOARD_M5_%s_FAIL' % stage.upper()
    emit('SG0a start bit_sha=%s'
         % hashlib.sha256(open(BIT, 'rb').read()).hexdigest()[:16])

    # ---- 上电正典 CK0-CK6/DB1-DB2（pl_m3 逐字）----
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
    pp = next((v.get('phys_addr') for v in ol.ip_dict.values()
               if v.get('phys_addr') == PPU_BASE), None)
    results['CK1'] = (gp == GEMM_BASE) and (cp == CSR_BASE) and \
                     (dp == DMA_BASE)
    emit('CK1b gemm=%s csr=%s dma=%s -> %s'
         % (hex(gp) if gp is not None else None,
            hex(cp) if cp is not None else None,
            hex(dp) if dp is not None else None,
            'PASS' if results['CK1'] else 'FAIL'))
    if not results['CK1']:
        emit('CKz %s hwh_contract' % VERDICT_FAIL); return 1
    results['PK1a'] = (pp == PPU_BASE)
    emit('PK1a ppu_ip=%s -> %s' % (hex(pp) if pp is not None else None,
                                    'PASS' if results['PK1a'] else 'FAIL'))
    if not results['PK1a']:
        emit('CKz %s ppu_hwh_contract' % VERDICT_FAIL); return 1

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

    # ---- PK1：PPU 牺牲探针 + 身份（v23b 律）----
    probe = ("import mmap,os,sys\n"
             "fd=os.open('/dev/mem',os.O_RDONLY|os.O_SYNC)\n"
             "mm=mmap.mmap(fd,4096,mmap.MAP_SHARED,mmap.PROT_READ,"
             "offset=0x43C20000)\n"
             "print('%08X'%(int.from_bytes(mm[0:4],'little'),))\n"
             "mm.close()\n")
    try:
        pr = subprocess.run([sys.executable, '-c', probe],
                            capture_output=True, text=True, timeout=20)
        pid_ok = pr.stdout.strip().endswith('%08X' % EXP_PPU_ID)
    except subprocess.TimeoutExpired:
        pid_ok = False
        pr = None
    p = MMIO(PPU_BASE, 0x10000)
    v_id, v_ver = p.read(PA_ID), p.read(PA_VERSION)
    results['PK1'] = bool(pid_ok and v_id == EXP_PPU_ID and
                          v_ver == EXP_PPU_VERSION)
    emit('PK1 probe=%s id=%08X ver=%08X -> %s'
         % (pr.stdout.strip() if pr else 'TIMEOUT', v_id, v_ver,
            'PASS' if results['PK1'] else 'FAIL'))
    if not results['PK1']:
        emit('CKz %s ppu_identity' % VERDICT_FAIL); return 1

    # ---- SGi：meta/params/conv CMA（pl_m3 律）----
    meta = json.load(open(P['meta'], encoding='utf-8'))
    Par = dict(np.load(P['params']))
    keys_ok = set(Par.keys()) == set(meta['params_keys'])
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

    # ---- PK2：graph arena + head（download 后分配；v23b 律）----
    # 板上包自包含合同：buffer_table.json（v11 母本拷贝）随包携带，
    # base_off/shape/arena_total=共享 ABI 的唯一板上来源。
    v11_buf = json.load(open(P['v11_buf'], encoding='utf-8'))
    bufs = v11_buf['entries']
    arena_need = max(b['base_off'] + b['size'] for b in bufs)
    arena_size = (arena_need + PAGE - 1) // PAGE * PAGE
    head_size = (int(meta['heads_total']) + PAGE - 1) // PAGE * PAGE
    arena = allocate(shape=(arena_size,), dtype=np.uint8)
    headb = allocate(shape=(head_size,), dtype=np.uint8)
    a_phys, h_phys = arena.device_address, headb.device_address
    delta = a_phys - ARENA_BASE_MODEL
    results['PK2'] = bool(a_phys % PAGE == 0 and h_phys % PAGE == 0 and
                          delta % PAGE == 0 and
                          arena_size <= int(v11_buf['arena_total']))
    emit('PK2 arena=0x%X(%d B ≤ arena_total=%d) head=0x%X delta=+0x%X '
         '-> %s' % (a_phys, arena_size, v11_buf['arena_total'], h_phys,
                    delta, 'PASS' if results['PK2'] else 'FAIL'))
    if not results['PK2']:
        emit('CKz %s graph_cma' % VERDICT_FAIL); return 1
    arena[:] = POISON
    headb[:] = POISON
    if hasattr(arena, 'flush'):
        arena.flush()

    # ---- CSR 缺省先于表（TB cfg_csr_default 次序）----
    p.write(PA_CTRL, 0x1)
    p.write(PA_DMA_CFG, PPU_DMA_CFG_DEFAULT)
    p.write(PA_HEAD_BASE_LO, h_phys)
    p.write(PA_HEAD_BASE_HI, 0x0)
    p.write(PA_HEAD_FORMAT, 0x0)
    p.write(PA_DESC_CFG, 0x0)
    p.write(PA_FRAME_ID, 0)

    # ---- 阶段规划 + 三表装载（PK3）----
    A_words = load_hex_words(P['hex_desc'])
    buf_words = load_hex_words(P['hex_buf'])
    qt_words = load_hex_words(P['hex_qt'])
    assert len(A_words) == DESC_ITEMS * DESC_WORDS
    assert len(buf_words) == BUF_ITEMS * BUF_WORDS
    assert len(qt_words) == QT_ITEMS * QT_WORDS
    descs = meta['seg_descs']
    plan = build_stage_plan(descs, A_words, stage, buf_words)
    assert len(plan['prog']) == EXPECT_PROG[stage], \
        (stage, len(plan['prog']))
    ramp = BACKEND_RAMP[stage]
    emit('STG %s ramp=%s prog=%d segs=%d '
         '(engine total universe=%d)' % (stage, sorted(ramp),
                                         len(plan['prog']),
                                         len(plan['segments']),
                                         EXPECT_ENG_TOTAL))
    buf_patched = patch_buf_words(buf_words, delta, len(bufs))
    buf0 = apply_w6_remap(buf_patched,
                          plan['segments'][0]['prod']
                          if plan['segments'] else
                          [PRODUCER_EXTERNAL] * BUF_ITEMS)
    p.write(PA_DESC_BASE, 0)
    bad = 0
    seg0_words = plan['segments'][0]['words'] if plan['segments'] else []
    for i in range(len(seg0_words)):
        p.write(W_DESC + 4 * i, int(seg0_words[i]))
    for i in range(len(seg0_words)):
        if p.read(W_DESC + 4 * i) != int(seg0_words[i]):
            bad += 1
    results['PK3a'] = (bad == 0)
    emit('PK3a desc seg0 words=%d bad_rb=%d -> %s'
         % (len(seg0_words), bad, 'PASS' if results['PK3a'] else 'FAIL'))
    if not results['PK3a']:
        emit('CKz %s desc_load' % VERDICT_FAIL); return 1
    for i in range(len(buf_words)):
        p.write(W_BUF + 4 * i, int(buf0[i]))
    bad = 0
    for i in range(len(buf_words)):
        if p.read(W_BUF + 4 * i) != int(buf0[i]):
            bad += 1
    results['PK3b'] = (bad == 0)
    emit('PK3b buf words=%d bad_rb=%d -> %s'
         % (len(buf_words), bad, 'PASS' if results['PK3b'] else 'FAIL'))
    if not results['PK3b']:
        emit('CKz %s buf_load' % VERDICT_FAIL); return 1
    for i in range(len(qt_words)):
        p.write(W_QT + 4 * i, int(qt_words[i]))
    bad = 0
    for i in range(len(qt_words)):
        if p.read(W_QT + 4 * i) != int(qt_words[i]):
            bad += 1
    results['PK3c'] = (bad == 0)
    emit('PK3c qt words=%d bad_rb=%d -> %s'
         % (len(qt_words), bad, 'PASS' if results['PK3c'] else 'FAIL'))
    if not results['PK3c']:
        emit('CKz %s qt_load' % VERDICT_FAIL); return 1

    # ---- 帧循环（混合骨架 + 板上 hooks）----
    hooks = BoardHooks(g, d, cma, open(os.path.join(
        HERE, 'm5_%s_blocks.csv' % stage), 'w'))
    hooks.csv.write('node,frame,b,wall_us,nerr,status,ystat\n')
    hooks.p = p
    hooks.arena_arr = arena
    hooks.headb = headb
    hooks.seg_recs = []
    geos = {n: Geo(n, s, Par) for n, s in meta['conv_statics'].items()}
    ctx = Ctx()
    ctx.stage, ctx.ramp = stage, ramp
    ctx.arena = Arena(arena, bufs)
    ctx.headb = headb
    ctx.descs, ctx.geos, ctx.bufs, ctx.meta = descs, geos, bufs, meta
    ctx.ANCHORS = {n: s for n, s in meta.get('anchors', {}).items()}
    ctx.anchor_done = set()
    ctx.csv = hooks.csv
    ctx.segments = plan['segments']
    ctx.hooks = hooks
    ctx.npbuf = npbuf
    ctx.refs_pat = P['refs']
    ctx.rep = {'stage': stage, 'frames': [], 'gates': {},
               'segments_meta': [
                   {'ids': bd['ids'], 'sum_w14': bd['sum_w14']}
                   for bd in plan['segments']],
               'cma_phys': cma_phys, 'arena_phys': a_phys,
               'head_phys': h_phys, 'delta': delta,
               'bit_sha': hashlib.sha256(
                   open(BIT, 'rb').read()).hexdigest()}
    EXP_LUT = meta['stage_table']['l5']['exp_lut_loads']
    try:
        frames_ok = run_frames(ctx)
    finally:
        hooks.csv.close()
    ctx.rep['seg_evidence'] = hooks.seg_recs

    # ---- 判定 ----
    ctx.rep['gates'] = {k: bool(v) for k, v in results.items()}
    ctx.rep['totals'] = dict(counts)
    ctx.rep['anchors_checked'] = sorted(ctx.anchor_done)
    sga_all = len(ctx.anchor_done) == len(ctx.ANCHORS) and \
        all(results.get('SGa:%s' % n, False) for n in ctx.ANCHORS)
    sg3 = all(t.get('guard_ok', True)
              for f in ctx.rep['frames'] for t in f['tasks'])
    sg4 = all(t['nerr'] == 0
              for f in ctx.rep['frames'] for t in f['tasks']
              if t['op'] in ('view', 'add', 'concat', 'maxpool5',
                             'upsample2', 'heads'))
    ppg = all(s.get('ok') for f in ctx.rep['frames'] for s in f['segs'])
    exp_segs_per_frame = len(plan['segments'])
    seg_count_ok = all(len(f['segs']) == exp_segs_per_frame
                       for f in ctx.rep['frames'])
    allpass = all([results.get(k, False) for k in
                   ['CK0', 'CK1', 'PK1a', 'CK4', 'CK5', 'CK6', 'DB1', 'DB2',
                    'SGi', 'PK1', 'PK2', 'PK3a', 'PK3b', 'PK3c']]) and \
        sga_all and frames_ok and sg3 and sg4 and ppg and seg_count_ok and \
        counts['timeouts'] == 0 and counts['lut_loads'] == EXP_LUT
    ctx.rep['verdict'] = VERDICT_PASS if allpass else VERDICT_FAIL
    json.dump(ctx.rep, open(os.path.join(HERE, 'm5_%s_board_report.json'
                                         % stage), 'w', encoding='utf-8'),
              indent=1, ensure_ascii=False)
    emit('SG2 timeouts=%d lut_loads=%d (exp %d) segs=%d (per frame %d)'
         % (counts['timeouts'], counts['lut_loads'], EXP_LUT,
            counts['segs'], exp_segs_per_frame))
    emit('CKz TOTAL wop=%d rop=%d ppu_wop=%d ppu_rop=%d blocks=%d -> %s'
         % (counts['wop'], counts['rop'], counts['ppu_wop'],
            counts['ppu_rop'], counts['blocks'], ctx.rep['verdict']))
    return 0 if allpass else 1


if __name__ == '__main__':
    sys.exit(main())
