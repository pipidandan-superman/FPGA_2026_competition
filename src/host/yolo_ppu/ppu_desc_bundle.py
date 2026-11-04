#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ppu_desc_bundle.py — PPU 描述符束 canonical record（F1 第一步产物）

依据（唯一权威，逐位照抄不得发明）：
  1_docs/yolo_ppu_design_manual_20260918.md（v1.1，46dac577）
    §2.1 req_pair / rne_shift 公共原语（软件计算合同，逐字转录）
    §4   描述符 ABI word0–31 逐位终版
    §4.1 opcode 分配（0x01=CONV 归 GEMM 线；0x10–0x15=VIEW..HEADS）
    §4.4 manifest → 位域映射（编译器 packing 规范）
    §4.5 buffer 表 word0–7 逐位布局
    §8   heads 装配布局（reg8/16/32→cls8/16/32 段序，149100 B）
  2_fpga/3_yolo_zynq/rtl/ps_axi_pl/yolo_csr_pkg.sv（冻结基座：128×32 desc /
    128×8 buf / 256×4 word quant；w0/1/2/14 注释）

F1 边界：纯主机侧；不建 ppu_top、不改 walker/pkg/五算子核；conv（opcode 0x01）
的 word3–13 解释归 GEMM 线（手册 §4），本 packer 一律填 0。

F1 期间裁定的填充决策（手册未逐字规定处，全部在此登记，改动手册前不得擅改）：
  D-F1a heads 的 w2 in0 = 段表首项（§4 word2 括号"主输入/段表首项"），即 §8
       段序的第 0 段 reg8 的 buffer——不是 manifest in_bufs[0]（cls8）。
  D-F1b conv 描述符 w3–13 = 0、段表 = 0、w5 = 0（conv 逐 OC M/shift 走 GEMM 线
       DMA 通道，不占 quant 表，§4.1）；w14 = out buffer 字节数。
  D-F1c maxpool5/upsample2 的 w5 = 0（profile 0 同尺度捷径，引擎不 requant）。
  D-F1d w13 graph flags：bit0 恒 1（in_place 禁止）；bit1 仅 concat 置 1
       （同尺度捷径许可）；N_seg/模式字镜像按 §4 word13。
  D-F1e buffer owner_state 初值：外部输入=2(READY)，图缓冲=0(FREE)
       （方案 A PL 只读不推进，§3；PL 唯一硬校验是 producer_desc，§4.3.5）。
  D-F1f is_head 恒 0：本图 104 项 buffer 无 head 区（heads 输出走 HEAD_BASE
       不入 buffer 表；§4.4"输入/head 区"中的 head 区无实例）。
  D-F1g arena_base 为装载期参数（CMA 实配地址），打包时显式传入；canonical
       基准值 = 0x10000000（CMA 窗起点），固定 SHA 以该值为准。
"""

from __future__ import annotations

import hashlib
import json
import math
import os
from dataclasses import dataclass, field
from typing import List, Optional, Tuple

# ----------------------------------------------------------------------------
# 表几何（pkg 冻结）
# ----------------------------------------------------------------------------
DESC_ITEMS, DESC_WORDS = 128, 32
BUF_ITEMS, BUF_WORDS = 128, 8
QUANT_ITEMS, QUANT_WORDS = 256, 4

CMA_WINDOW = (0x10000000, 0x20000000)   # EES-331 PL 可见 CMA 窗 [lo, hi)
HEADS_OUT_NULL = 0x3FF                   # §4 word2 out 空编码
PRODUCER_EXTERNAL = 0xFF                 # §4.5 w6 外部输入
OWNER_FREE, OWNER_PRODUCING, OWNER_READY, OWNER_CONSUMING = 0, 1, 2, 3

OPCODE = {                               # §4.1（v1.1 冻结）
    "conv": 0x01, "view": 0x10, "add": 0x11, "concat": 0x12,
    "maxpool5": 0x13, "upsample2": 0x14, "heads": 0x15,
}
ENGINE_OPS = ("view", "add", "concat", "maxpool5", "upsample2", "heads")

# §8 heads 装配布局：段序 reg8/16/32→cls8/16/32（manifest 键 → (形状, 字节)）
HEADS_SEG_ORDER = ("reg8", "reg16", "reg32", "cls8", "cls16", "cls32")
HEADS_LAYOUT = {
    "reg8":  ((64, 40, 40), 102400), "reg16": ((64, 20, 20), 25600),
    "reg32": ((64, 10, 10), 6400),   "cls8":  ((7, 40, 40), 11200),
    "cls16": ((7, 20, 20), 2800),    "cls32": ((7, 10, 10), 700),
}
HEADS_TOTAL_BYTES = 149100              # §8 已核验


class PackError(Exception):
    """主机侧装载校验失败（§4.3 的主机侧前移 + 编译期不变量）。

    code 对齐 pkg E_CODE_* 语义域：DESC_INVALID=0x01 / ADDR_REGION=0x14 …
    附编译期专属码 0x40+（manifest 结构类，RTL 永远看不到）。
    """

    RTL_CODES = {
        "DESC_INVALID": 0x01, "ADDR_ALIGN": 0x13, "ADDR_REGION": 0x14,
    }

    def __init__(self, scope: str, code: str, detail: str):
        self.scope, self.code, self.detail = scope, code, detail
        num = self.RTL_CODES.get(code, 0x40)
        super().__init__(f"[{scope}] {code}(0x{num:02X}): {detail}")


# ----------------------------------------------------------------------------
# §2.1 公共原语（逐字转录）
# ----------------------------------------------------------------------------
def req_pair(r: float) -> Tuple[int, int]:
    """r = f·2^e (f∈[0.5,1)) → (M=RNE(f·2^31), shift=31−e)；
    shift>62 → (0,0) 死通道。"""
    if r <= 0.0:
        return (0, 0)
    f, e = math.frexp(r)                 # 精确分解，无舍入
    m = int(round(f * (1 << 31)))        # float64 乘 2^31 精确；round=RNE
    shift = 31 - e
    if shift > 62:
        return (0, 0)
    assert (1 << 30) <= m < (1 << 31), f"M out of [2^30,2^31): {m}"
    return (m, shift)


IDENTITY_PAIR = req_pair(1.0)            # (2^30, 30)，保留 profile 0（§2.1 已核验）


# ----------------------------------------------------------------------------
# canonical records（pack 与 unpack 共用；round-trip 比较的就是这些字段）
# ----------------------------------------------------------------------------
@dataclass
class Seg:
    buf: int            # 段 i buffer id（10 bit）
    prof: int           # 段 i quant profile id（10 bit）
    nbytes: int         # 段 i 字节长度（32 bit）


@dataclass
class DescRecord:
    index: int          # 描述符槽位 = desc_id
    opcode: int         # §4.1
    valid: int          # w0[8]
    last: int           # w0[9]
    dep_id: int         # w1[15:8]  = max(deps)，无依赖 0
    next_id: int        # w1[31:16] = index+1，末项 0xFFFF
    in0: int            # w2[9:0]
    in1: int            # w2[19:10]（add 专用，其余 0）
    out: int            # w2[29:20]（heads=0x3FF）
    c: int              # w3[15:0]
    h: int              # w3[31:16]
    w: int              # w4[15:0]
    prof_in0: int       # w5[15:0]
    prof_in1: int       # w5[31:16]（add 专用）
    n_seg: int          # w6[15:0]
    in0_len: int        # w7[15:0]（view=切片字节；0=按 C·H·W 推导）
    mode: int           # w9[7:0]（maxpool5/upsample2 恒 0）
    graph_flags: int    # w13[7:0]（bit0 恒 1；bit1 concat）
    out_bytes: int      # w14（pkg 冻结，walker 累计）
    segments: List[Seg] = field(default_factory=list)   # w16–31 内联段表（≤8）


@dataclass
class BufRecord:
    index: int          # buffer id 槽位
    base: int           # w0/w1（64 bit，arena_base+base_off；高 32 位恒 0）
    size: int           # w2
    line_stride: int    # w3
    c: int              # w4[15:0]
    h: int              # w4[31:16]
    w: int              # w5[15:0]
    scale_id: int       # w5[23:16]（诊断用，恒 0）
    valid: int          # w5[24]
    is_view: int        # w5[25]
    is_input: int       # w5[26]
    is_head: int        # w5[27]（本图恒 0，D-F1f）
    producer_desc: int  # w6[7:0]（外部输入=0xFF）
    owner_state: int    # w6[15:8]（D-F1e）
    generation: int     # w6[23:16]
    consumer_count: int # w7[7:0]


@dataclass
class QuantCell:
    m: int              # w0（int32；死通道 (0,0)）
    shift: int          # w1（低 8 位有效）


@dataclass
class PpuDescBundle:
    descs: List[Optional[DescRecord]]    # 长度 128，未用槽 None（全零字）
    bufs: List[Optional[BufRecord]]      # 长度 128
    quant: List[Optional[QuantCell]]     # 长度 256，未用槽 None（全零字）
    meta: dict = field(default_factory=dict)   # counts / arena_base / 源 SHA 等

    # -- 比较（round-trip 语义门用；逐字段、无浮点容差） ----------------------
    def semantic_equal(self, other: "PpuDescBundle") -> List[str]:
        diffs: List[str] = []
        for name, a_list, b_list in (("desc", self.descs, other.descs),
                                     ("buf", self.bufs, other.bufs),
                                     ("quant", self.quant, other.quant)):
            if len(a_list) != len(b_list):
                diffs.append(f"{name}: length {len(a_list)}!={len(b_list)}")
                continue
            for i, (a, b) in enumerate(zip(a_list, b_list)):
                if (a is None) != (b is None):
                    diffs.append(f"{name}[{i}]: presence {a is None}!={b is None}")
                elif a is not None:
                    da, db = a.__dict__, b.__dict__
                    for k in da:
                        if k in ("segments",):
                            sa = [tuple(vars(s).values()) for s in da[k]]
                            sb = [tuple(vars(s).values()) for s in db[k]]
                            if sa != sb:
                                diffs.append(f"{name}[{i}].segments: {sa}!={sb}")
                        elif da[k] != db[k]:
                            diffs.append(f"{name}[{i}].{k}: {da[k]}!={db[k]}")
        return diffs


# ----------------------------------------------------------------------------
# manifest → records（§4.4 唯一映射 + 全部不变量校验）
# ----------------------------------------------------------------------------
class _QuantAssigner:
    """(M,shift) 对 → profile id。profile 0 = 同尺度捷径恒等对（保留）。
    其余按描述符遍历序首次出现分配（确定性）。"""

    def __init__(self) -> None:
        self.cells: List[Optional[QuantCell]] = [None] * QUANT_ITEMS
        self.cells[0] = QuantCell(*IDENTITY_PAIR)
        self._ids: dict = {}
        self.refs = 0   # (M,shift) 引用总数（手册事实：50）

    def id_of(self, scale_in: float, scale_out: float) -> int:
        pair = req_pair(scale_in / scale_out)
        self.refs += 1
        if pair not in self._ids:
            if len(self._ids) + 1 >= QUANT_ITEMS:
                raise PackError("quant", "DESC_INVALID",
                                f"quant profile overflow >{QUANT_ITEMS - 1}")
            self._ids[pair] = 1 + len(self._ids)
            self.cells[self._ids[pair]] = QuantCell(*pair)
        return self._ids[pair]

    @property
    def unique_pairs(self) -> int:
        return len(self._ids)


def _buf_shape(buf, bid: int, bufs_by_id: dict, what: str) -> Tuple[int, int, int]:
    e = bufs_by_id.get(bid)
    if e is None:
        raise PackError("desc", "DESC_INVALID",
                        f"{what}: buffer id {bid} not registered")
    c, h, w = e["shape"]
    return c, h, w


def load_bundle(manifest_dir: str, arena_base: int = 0x10000000,
                verify_sha: bool = True) -> PpuDescBundle:
    """六 manifest → PpuDescBundle。任何违例抛 PackError（主机侧拒绝）。
    verify_sha=False 仅用于负向变异用例（变异必然破坏子 manifest SHA）。"""
    j = lambda n: json.load(open(os.path.join(manifest_dir, n), "r", encoding="utf-8"))
    graph, dtab, btab = j("graph_manifest.json"), j("descriptor_table.json"), j("buffer_table.json")

    if graph.get("verdict") != "PASS" or graph.get("errors"):
        raise PackError("graph", "DESC_INVALID", "graph_manifest not PASS")
    # 子 manifest SHA 复核（对 F0 封存链条）
    if verify_sha:
        for fname, want in graph["sub_manifest_sha256"].items():
            p = os.path.join(manifest_dir, fname)
            got = hashlib.sha256(open(p, "rb").read()).hexdigest()
            if got != want:
                raise PackError("graph", "DESC_INVALID",
                                f"sub-manifest SHA mismatch {fname}: {got}!={want}")

    # ---------------- buffer 侧（§4.5） ----------------
    entries = btab["entries"]
    if len(entries) > BUF_ITEMS:
        raise PackError("buf", "DESC_INVALID",
                        f"buffer count {len(entries)} > {BUF_ITEMS}")
    bufs: List[Optional[BufRecord]] = [None] * BUF_ITEMS
    bufs_by_id: dict = {}
    for e in entries:
        bid = e["id"]
        if bid in bufs_by_id:
            raise PackError("buf", "DESC_INVALID", f"duplicate buffer id {bid}")
        c, h, w = e["shape"]
        size, stride = e["size"], e["line_stride"]
        if min(c, h, w) <= 0:
            raise PackError("buf", "DESC_INVALID",
                            f"buf[{bid}] shape zero/negative {e['shape']}")
        if c * h * w > size:
            raise PackError("buf", "DESC_INVALID",
                            f"buf[{bid}] C·H·W={c*h*w} > size={size}")
        if stride < w:
            raise PackError("buf", "DESC_INVALID",
                            f"buf[{bid}] line_stride {stride} < W {w}")
        base = arena_base + e["base_off"]
        if (base >> 32) != 0:
            raise PackError("buf", "ADDR_REGION",
                            f"buf[{bid}] base high word != 0 (0x{base:X})")
        if not (CMA_WINDOW[0] <= base and base + size <= CMA_WINDOW[1]):
            raise PackError("buf", "ADDR_REGION",
                            f"buf[{bid}] [0x{base:X},+{size}) outside CMA window")
        is_input = 1 if e["producer"] == "input" else 0
        rec = BufRecord(
            index=bid, base=base, size=size, line_stride=stride,
            c=c, h=h, w=w, scale_id=0, valid=1,
            is_view=1 if e["is_view_out"] else 0, is_input=is_input, is_head=0,
            producer_desc=(PRODUCER_EXTERNAL if is_input else int(e["producer_task"])),
            owner_state=(OWNER_READY if is_input else OWNER_FREE),   # D-F1e
            generation=int(e["generation"]), consumer_count=len(e["consumers"]),
        )
        bufs[bid], bufs_by_id[bid] = rec, e

    # ---------------- descriptor 侧（§4 + §4.4） ----------------
    dents = dtab["entries"]
    if len(dents) > DESC_ITEMS:
        raise PackError("desc", "DESC_INVALID",
                        f"descriptor count {len(dents)} > {DESC_ITEMS}")
    quant = _QuantAssigner()
    descs: List[Optional[DescRecord]] = [None] * DESC_ITEMS
    seen_ids, last_holders = set(), []
    for e in dents:
        did = e["desc_id"]
        if did in seen_ids:
            raise PackError("desc", "DESC_INVALID", f"duplicate desc_id {did}")
        seen_ids.add(did)
        op = e["op"]
        if op not in OPCODE:
            raise PackError("desc", "DESC_INVALID", f"unknown op '{op}' (desc {did})")
        if e["last"] != e["frame_end"]:
            raise PackError("desc", "DESC_INVALID",
                            f"desc {did} last={e['last']} != frame_end={e['frame_end']}")
        if e["last"]:
            last_holders.append(did)

        out_buf, oc, oh, ow = e["out_buf"], 0, 0, 0
        in0 = in1 = prof_in0 = prof_in1 = in0_len = 0
        segs: List[Seg] = []
        n_seg, gflags = 1, 0x01                          # bit0 恒 1（D-F1d）

        if op == "conv":
            # D-F1b：w3–13 全 0；in0/out/w14 照公共规则
            if e["out_region"] != "graph_buf" or out_buf is None:
                raise PackError("desc", "DESC_INVALID",
                                f"conv desc {did} needs graph_buf out")
            in0 = e["in_bufs"][0]
            oc, oh, ow = _buf_shape(None, out_buf, bufs_by_id, f"conv {did} out")
        elif op == "view":
            parent = e["parent_buf"]
            c0, c1 = e["ch"]
            pc, ph, pw = _buf_shape(None, parent, bufs_by_id, f"view {did} parent")
            if not (0 <= c0 < c1 <= pc):
                raise PackError("desc", "DESC_INVALID",
                                f"view {did} ch [{c0},{c1}) vs parent C {pc}")
            in0, oc, oh, ow = parent, c1 - c0, ph, pw
            slice_bytes = (c1 - c0) * ph * pw            # v1.1.1：w7 恒 0，
            # 切片字节按 w3/w4 的 C·H·W 推导；与 out 缓冲 size 的一致性在此
            # 主机侧不变量保证（16 位 w7 装不下 102400 B 级切片，卷首勘误）
            out_buf = e["out_buf"]
            vb = bufs_by_id.get(out_buf)
            if vb is None or vb["size"] != slice_bytes or tuple(vb["shape"]) != (oc, oh, ow):
                raise PackError("desc", "DESC_INVALID",
                                f"view {did} out buffer mismatch vs slice")
            # v1.1 别名不变量（F2 run01 立）：view out 必须是父内纯地址别名
            # base+c0·H·W（手册 §1"buffer 表别名，PL 零搬移"/§3"不新增 DDR
            # 存储"/§4.1"别名已在装载期完成"）——独立占位即数据流断裂
            pb = bufs_by_id[parent]
            if vb["base_off"] != pb["base_off"] + c0 * ph * pw:
                raise PackError(
                    "desc", "DESC_INVALID",
                    f"view {did} alias violated: out base_off "
                    f"{vb['base_off']} != parent {pb['base_off']} "
                    f"+ c0·H·W {c0 * ph * pw}（零搬移别名，手册 §1/§3/§4.1）")
        elif op == "add":
            in0, in1 = e["a_buf"], e["b_buf"]
            out_buf = e["out_buf"]
            ac = _buf_shape(None, in0, bufs_by_id, f"add {did} a")
            bc = _buf_shape(None, in1, bufs_by_id, f"add {did} b")
            gc = _buf_shape(None, out_buf, bufs_by_id, f"add {did} out")
            if not (ac == bc == gc):                     # §1：a/b/out 同形
                raise PackError("desc", "DESC_INVALID",
                                f"add {did} shape mismatch {ac}/{bc}/{gc}")
            oc, oh, ow = ac
            prof_in0 = quant.id_of(e["a_scale"], e["out_scale"])
            prof_in1 = quant.id_of(e["b_scale"], e["out_scale"])
        elif op == "concat":
            out_buf = e["out_buf"]
            oc, oh, ow = _buf_shape(None, out_buf, bufs_by_id, f"concat {did} out")
            inputs = e["inputs"]
            if not (2 <= len(inputs) <= 8):              # §4：内联 8 段容量
                raise PackError("desc", "DESC_INVALID",
                                f"concat {did} N_seg={len(inputs)} not in [2,8]")
            n_seg, gflags = len(inputs), 0x01 | 0x02     # bit1 同尺度捷径许可
            total = 0
            for s in inputs:
                sc, sh, sw = _buf_shape(None, s["buf"], bufs_by_id,
                                        f"concat {did} seg")
                if (sh, sw) != (oh, ow):
                    raise PackError("desc", "DESC_INVALID",
                                    f"concat {did} seg shape {(sh,sw)} != out {(oh,ow)}")
                nbytes = sc * sh * sw
                if nbytes <= 0:
                    raise PackError("desc", "DESC_INVALID",
                                    f"concat {did} zero-length segment")
                segs.append(Seg(s["buf"], quant.id_of(s["scale"], e["out_scale"]), nbytes))
                total += nbytes
            if total != bufs_by_id[out_buf]["size"]:     # §4.3.8
                raise PackError("desc", "DESC_INVALID",
                                f"concat {did} Σseg={total} != out size "
                                f"{bufs_by_id[out_buf]['size']}")
            in0 = segs[0].buf                             # §4 word2：段表首项
            prof_in0 = segs[0].prof
        elif op in ("maxpool5", "upsample2"):
            in0 = e["in_bufs"][0]
            out_buf = e["out_buf"]
            oc, oh, ow = _buf_shape(None, out_buf, bufs_by_id, f"{op} {did} out")
        elif op == "heads":
            if e["out_buf"] is not None or e["out_region"] != "heads_out":
                raise PackError("desc", "DESC_INVALID",
                                f"heads {did} must have null out_buf/heads_out")
            out_buf = None
            n_seg = 6
            # §8 段序 reg8/16/32→cls8/16/32；profile 域=0（恒等拷贝不读 quant 表）
            # manifest 结构：e["reg"]=[reg8,reg16,reg32]、e["cls"]=[cls8,cls16,cls32]
            if len(e.get("reg", [])) != 3 or len(e.get("cls", [])) != 3:
                raise PackError("desc", "DESC_INVALID",
                                f"heads {did} reg/cls != 3+3 segments")
            for key, s in zip(HEADS_SEG_ORDER, list(e["reg"]) + list(e["cls"])):
                want_shape, want_bytes = HEADS_LAYOUT[key]
                if tuple(s["shape"]) != want_shape:
                    raise PackError("desc", "DESC_INVALID",
                                    f"heads {did} {key} shape {s['shape']} != "
                                    f"§8 {want_shape}")
                c0 = bufs_by_id.get(s["buf"])
                if c0 is None or tuple(c0["shape"]) != want_shape \
                        or c0["size"] != want_bytes:
                    raise PackError("desc", "DESC_INVALID",
                                    f"heads {did} {key} buffer mismatch vs §8")
                segs.append(Seg(s["buf"], 0, want_bytes))
            if sum(s.nbytes for s in segs) != HEADS_TOTAL_BYTES:
                raise PackError("desc", "DESC_INVALID", "heads Σseg != 149100")
            in0 = segs[0].buf                             # D-F1a：段表首项=reg8

        # 公共校验：buffer 存在性 / 依赖序（§4.3.3、§4.3.5 主机侧前移）
        for tag, bid in (("in0", in0), ("in1", in1), ("out", -1 if out_buf is None else out_buf)):
            if tag == "out" and out_buf is None:
                continue
            if bid not in bufs_by_id:
                raise PackError("desc", "DESC_INVALID",
                                f"desc {did} {tag} buffer {bid} not registered")
        deps = e.get("deps", [])
        dep_id = max(deps) if deps else 0
        for d in deps:
            if d >= did:
                raise PackError("desc", "DESC_INVALID",
                                f"desc {did} dep {d} not in past (order contract)")
        for tag, bid in (("in0", in0), ("in1", in1)):
            if tag == "in1" and in1 == 0:
                continue
            be = bufs_by_id[bid]
            pd = 0xFF if be["producer"] == "input" else be["producer_task"]
            if pd != 0xFF and pd >= did:
                raise PackError("desc", "DESC_INVALID",
                                f"desc {did} {tag} producer_desc {pd} >= desc_id")

        out_bytes = (HEADS_TOTAL_BYTES if op == "heads"
                     else bufs_by_id[out_buf]["size"])
        descs[did] = DescRecord(
            index=did, opcode=OPCODE[op], valid=1, last=1 if e["last"] else 0,
            dep_id=dep_id, next_id=0xFFFF if e["last"] else did + 1,
            in0=in0, in1=in1,
            out=(HEADS_OUT_NULL if op == "heads" else out_buf),
            c=oc, h=oh, w=ow, prof_in0=prof_in0, prof_in1=prof_in1,
            n_seg=n_seg, in0_len=in0_len, mode=0,
            graph_flags=gflags, out_bytes=out_bytes, segments=segs,
        )

    if len(last_holders) != 1:
        raise PackError("desc", "DESC_INVALID",
                        f"last holders {last_holders} != exactly one")

    meta = dict(graph["counts"])
    meta.update(n_buffers=len(entries), arena_base=arena_base,
                quant_unique=quant.unique_pairs, quant_refs=quant.refs,
                manifest_sha=graph["sub_manifest_sha256"])
    return PpuDescBundle(descs=descs, bufs=bufs, quant=quant.cells, meta=meta)
