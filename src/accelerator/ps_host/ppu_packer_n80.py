#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""ppu_packer_n80.py — PPU canonical packer（F1 主体，M5.0 归位拷出）

母本 = 3_host/yolo_ppu/ppu_packer.py（手势线，只读基线；源 SHA256 =
8FE7A2EA0A4575C3134544002E63A494689994574F992509D16B61AEF4CDD761）。
M5.0 归位适配（其余逐行等价；手势隔离禁令下本拷出仅供 n80 物料）：
  M5-N1 sys.path 手式（同目录 insert）→ accel_bootstrap 边界导入，
        ppu_desc_bundle 解析到 12_yolo_accel/abi（n80 校准版）。
  M5-N2 F1 门 quant_refs/quant_unique 两处手势冻结数（50/31）参数化为
        QUANT_REFS_EXPECT/QUANT_UNIQUE_EXPECT，2026-10-07 首次 n80 打包
        实测同为 50/31（run 2026-10-07_yolo_m5_xsim_run01 F1 PASS）已
        冻结回填为硬门。
        （opcode 直方图 63/16/6/13/3/2/1 与 used[103].out_bytes 常数判据
        已对 n80 成立，不动。）

manifest（六件）→ descriptor.bin / buffer.bin / quant.bin，
以及逆向 unpack（F2 软件后端从 .bin 读取的唯一入口——禁止 JSON 旁路）。

位布局唯一权威 = 手册 v1.1 §4/§4.4/§4.5 + yolo_csr_pkg.sv（冻结基座）。
字序：32-bit 小端（PS 经 AXI-Lite 按字写表，.bin 即字流镜像）。
表几何：desc 128×32 word = 16384 B；buf 128×8 word = 4096 B；
quant 256×4 word = 4096 B。

F1 PASS 门（附录）：
  G1 正向不变量（含手册事实交叉核：唯一 (M,shift) 对数 / 引用数——
      手势母本 31/50；n80 待 M5.1 冻结，见 M5-N2）
  G2 pack→unpack round-trip 逐字段一致 + 重打包逐字节一致
  G3 固定 SHA（三次全新装载打包，三次 SHA 全同）
  G4 ≥17 负向用例全部主机侧拒绝（PackError，不崩溃）
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import struct
import sys
import tempfile
import time
from typing import Dict, List, Optional, Tuple

# M5-N1: boundary import via accel_bootstrap (abi/ on sys.path)
_ROOT = os.path.abspath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), '..'))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)
import accel_bootstrap                                   # noqa: E402,F401
from ppu_desc_bundle import (  # noqa: E402
    BUF_ITEMS, BUF_WORDS, CMA_WINDOW, DESC_ITEMS, DESC_WORDS, HEADS_TOTAL_BYTES,
    PackError, PpuDescBundle, QuantCell, _QuantAssigner, load_bundle, req_pair,
)

# M5-N2: n80 quant invariants — FROZEN 2026-10-07 from first n80 pack
# (v11 manifests, run 2026-10-07_yolo_m5_xsim_run01/out/bundle, F1 PASS):
# measured quant_refs=50 / quant_unique=31, identical to the gesture-frozen
# values (graph topology isomorphic; requant pair census is nc-invariant).
QUANT_REFS_EXPECT = 50
QUANT_UNIQUE_EXPECT = 31

W = struct.Struct("<I")
DESC_BIN_BYTES = DESC_ITEMS * DESC_WORDS * 4
BUF_BIN_BYTES = BUF_ITEMS * BUF_WORDS * 4
QUANT_BIN_BYTES = 256 * 4 * 4


# ----------------------------------------------------------------------------
# pack：records → 字流
# ----------------------------------------------------------------------------
def pack_desc(d) -> List[int]:
    ws = [0] * DESC_WORDS
    ws[0] = (d.opcode & 0xFF) | ((d.valid & 1) << 8) | ((d.last & 1) << 9)
    # first/act_en/walk/ownership（w0[10..15]）图算子域恒 0（§4）
    ws[1] = (d.index & 0xFF) | ((d.dep_id & 0xFF) << 8) | ((d.next_id & 0xFFFF) << 16)
    ws[2] = (d.in0 & 0x3FF) | ((d.in1 & 0x3FF) << 10) | ((d.out & 0x3FF) << 20)
    ws[3] = (d.c & 0xFFFF) | ((d.h & 0xFFFF) << 16)
    ws[4] = d.w & 0xFFFF
    ws[5] = (d.prof_in0 & 0xFFFF) | ((d.prof_in1 & 0xFFFF) << 16)
    ws[6] = d.n_seg & 0xFFFF
    ws[7] = d.in0_len & 0xFFFF
    ws[9] = d.mode & 0xFF
    ws[13] = (d.graph_flags & 0xFF) | ((d.n_seg & 0xFF) << 8) | ((d.mode & 0xFF) << 16)
    ws[14] = d.out_bytes & 0xFFFFFFFF
    # w8/w10/w11/w12/w15 保留=0；w16–31 内联段表
    for i, s in enumerate(d.segments):
        if i >= 8:
            raise PackError("desc", "DESC_INVALID", f"seg index {i} >= 8")
        ws[16 + 2 * i] = (s.buf & 0x3FF) | ((s.prof & 0x3FF) << 16)
        ws[17 + 2 * i] = s.nbytes & 0xFFFFFFFF
    return ws


def pack_buf(b) -> List[int]:
    return [
        b.base & 0xFFFFFFFF,
        (b.base >> 32) & 0xFFFFFFFF,                     # 恒 0（loader 校验）
        b.size & 0xFFFFFFFF,
        b.line_stride & 0xFFFFFFFF,
        (b.c & 0xFFFF) | ((b.h & 0xFFFF) << 16),
        (b.w & 0xFFFF) | ((b.scale_id & 0xFF) << 16)
        | ((b.valid & 1) << 24) | ((b.is_view & 1) << 25)
        | ((b.is_input & 1) << 26) | ((b.is_head & 1) << 27),
        (b.producer_desc & 0xFF) | ((b.owner_state & 0xFF) << 8)
        | ((b.generation & 0xFF) << 16),
        b.consumer_count & 0xFF,
    ]


def pack_quant(q) -> List[int]:
    return [q.m & 0xFFFFFFFF, q.shift & 0xFF, 0, 0]


def pack(bundle: PpuDescBundle) -> Dict[str, bytes]:
    def words_bytes(recs, n_items, pack_one, n_words):
        out = bytearray()
        for i in range(n_items):
            r = recs[i] if i < len(recs) else None
            ws = pack_one(r) if r is not None else [0] * n_words
            out += b"".join(W.pack(x) for x in ws)
        return bytes(out)

    return {
        "descriptor.bin": words_bytes(bundle.descs, DESC_ITEMS, pack_desc, DESC_WORDS),
        "buffer.bin": words_bytes(bundle.bufs, BUF_ITEMS, pack_buf, BUF_WORDS),
        "quant.bin": words_bytes(bundle.quant, 256, pack_quant, 4),
    }


# ----------------------------------------------------------------------------
# unpack：字流 → records（F2 软件后端入口；pack 的严格逆）
# ----------------------------------------------------------------------------
def _split(data: bytes, n_items: int, n_words: int) -> List[Optional[List[int]]]:
    if len(data) != n_items * n_words * 4:
        raise PackError("unpack", "DESC_INVALID",
                        f"blob size {len(data)} != {n_items * n_words * 4}")
    out = []
    for i in range(n_items):
        ws = list(struct.unpack_from(f"<{n_words}I", data, i * n_words * 4))
        out.append(ws if any(ws) else None)              # 全零槽 = 未用
    return out


def unpack(bins: Dict[str, bytes]) -> PpuDescBundle:
    from ppu_desc_bundle import BufRecord, DescRecord, Seg
    descs: List[Optional] = [None] * DESC_ITEMS
    for i, ws in enumerate(_split(bins["descriptor.bin"], DESC_ITEMS, DESC_WORDS)):
        if ws is None:
            continue
        segs = []
        for k in range(8):
            if ws[16 + 2 * k] or ws[17 + 2 * k]:
                segs.append(Seg(ws[16 + 2 * k] & 0x3FF,
                                (ws[16 + 2 * k] >> 16) & 0x3FF,
                                ws[17 + 2 * k]))
        descs[i] = DescRecord(
            index=i, opcode=ws[0] & 0xFF, valid=(ws[0] >> 8) & 1,
            last=(ws[0] >> 9) & 1, dep_id=(ws[1] >> 8) & 0xFF,
            next_id=(ws[1] >> 16) & 0xFFFF, in0=ws[2] & 0x3FF,
            in1=(ws[2] >> 10) & 0x3FF, out=(ws[2] >> 20) & 0x3FF,
            c=ws[3] & 0xFFFF, h=(ws[3] >> 16) & 0xFFFF, w=ws[4] & 0xFFFF,
            prof_in0=ws[5] & 0xFFFF, prof_in1=(ws[5] >> 16) & 0xFFFF,
            n_seg=ws[6] & 0xFFFF, in0_len=ws[7] & 0xFFFF,
            mode=ws[9] & 0xFF,
            graph_flags=ws[13] & 0xFF, out_bytes=ws[14], segments=segs,
        )
    bufs: List[Optional] = [None] * BUF_ITEMS
    for i, ws in enumerate(_split(bins["buffer.bin"], BUF_ITEMS, BUF_WORDS)):
        if ws is None:
            continue
        bufs[i] = BufRecord(
            index=i, base=ws[0] | (ws[1] << 32), size=ws[2], line_stride=ws[3],
            c=ws[4] & 0xFFFF, h=(ws[4] >> 16) & 0xFFFF, w=ws[5] & 0xFFFF,
            scale_id=(ws[5] >> 16) & 0xFF, valid=(ws[5] >> 24) & 1,
            is_view=(ws[5] >> 25) & 1, is_input=(ws[5] >> 26) & 1,
            is_head=(ws[5] >> 27) & 1, producer_desc=ws[6] & 0xFF,
            owner_state=(ws[6] >> 8) & 0xFF, generation=(ws[6] >> 16) & 0xFF,
            consumer_count=ws[7] & 0xFF,
        )
    quant: List[Optional] = [None] * 256
    for i, ws in enumerate(_split(bins["quant.bin"], 256, 4)):
        if ws is None:
            continue
        quant[i] = QuantCell(ws[0], ws[1] & 0xFF)
    return PpuDescBundle(descs=descs, bufs=bufs, quant=quant)


# ----------------------------------------------------------------------------
# F1 门
# ----------------------------------------------------------------------------
def _invariants(b: PpuDescBundle) -> List[str]:
    """正向不变量 + 手册事实交叉核。返回违例列表（空=过）。"""
    bad: List[str] = []
    used = [d for d in b.descs if d is not None]
    ub = [x for x in b.bufs if x is not None]
    if len(used) != 104 or len(ub) != 104:
        bad.append(f"counts desc={len(used)} buf={len(ub)} != 104/104")
    ops: Dict[int, int] = {}
    for d in used:
        ops[d.opcode] = ops.get(d.opcode, 0) + 1
    want = {0x01: 63, 0x10: 16, 0x11: 6, 0x12: 13, 0x13: 3, 0x14: 2, 0x15: 1}
    if ops != want:
        bad.append(f"opcode histogram {ops} != {want}")
    lasts = [d.index for d in used if d.last]
    if lasts != [103]:
        bad.append(f"last holders {lasts} != [103]")
    if used[103].opcode != 0x15 or used[103].out_bytes != HEADS_TOTAL_BYTES:
        bad.append("desc103 not heads/HEADS_TOTAL_BYTES")
    # 手册 §2.1/§4.1 事实：quant 引用数 / 唯一 (M,shift) 对数。
    # M5-N2: 手势母本冻结值 50/31；n80 值待 M5.1 首包实测后冻结回填
    # QUANT_REFS_EXPECT/QUANT_UNIQUE_EXPECT（None = 只报告不硬门）。
    if QUANT_REFS_EXPECT is not None and \
            b.meta.get("quant_refs") != QUANT_REFS_EXPECT:
        bad.append(f"quant refs {b.meta.get('quant_refs')} != {QUANT_REFS_EXPECT}")
    if QUANT_UNIQUE_EXPECT is not None and \
            b.meta.get("quant_unique") != QUANT_UNIQUE_EXPECT:
        bad.append(f"quant unique {b.meta.get('quant_unique')} != {QUANT_UNIQUE_EXPECT}")
    # quant[0] = 同尺度捷径恒等对
    q0 = b.quant[0]
    if q0 is None or (q0.m, q0.shift) != (1 << 30, 30):
        bad.append("quant[0] not identity (2^30,30)")
    # 全部引用的 profile 已装载且非零字
    for d in used:
        for pid in ([d.prof_in0, d.prof_in1]
                    + [s.prof for s in d.segments]):
            if pid and (pid >= 256 or b.quant[pid] is None):
                bad.append(f"desc{d.index} profile {pid} unloaded")
    # w14 与 out 缓冲 size 一致（heads 例外=149100）
    for d in used:
        if d.opcode == 0x15:
            continue
        ob = b.bufs[d.out]
        if ob is None or ob.size != d.out_bytes:
            bad.append(f"desc{d.index} w14 {d.out_bytes} != out size")
    # CMA 窗内（§4.3.6）
    for x in ub:
        if not (CMA_WINDOW[0] <= x.base and x.base + x.size <= CMA_WINDOW[1]):
            bad.append(f"buf{x.index} outside CMA window")
    # view 零搬移别名（手册 §1/§3/§4.1；F2 run01 立）：二进制级复查——
    # out base − parent base 必须是 H·W 的非负整数倍且切片不越父通道
    for d in used:
        if d.opcode != 0x10:
            continue
        ob, pb = b.bufs[d.out], b.bufs[d.in0]
        delta, hw = ob.base - pb.base, d.h * d.w
        if delta < 0 or delta % hw or delta // hw + d.c > pb.c:
            bad.append(f"desc{d.index} view alias broken (delta=0x{delta:X}, "
                       f"c0={delta // hw}, C={d.c}, parentC={pb.c})")
    return bad


def _write_manifests(tmp: str, g: dict, d: dict, bf: dict) -> str:
    for name, obj in (("graph_manifest.json", g), ("descriptor_table.json", d),
                      ("buffer_table.json", bf)):
        with open(os.path.join(tmp, name), "w", encoding="utf-8") as f:
            json.dump(obj, f, ensure_ascii=False, indent=1)
    return tmp


def _load_dicts(manifest_dir: str) -> Tuple[dict, dict, dict]:
    j = lambda n: json.load(open(os.path.join(manifest_dir, n), encoding="utf-8"))
    return j("graph_manifest.json"), j("descriptor_table.json"), j("buffer_table.json")


def _negative_cases() -> List[Tuple[str, object]]:
    """(名称, mutate(g,d,bf) -> None|'direct')；direct=返回可调用异常测试。"""
    def m_unknown_op(g, d, bf): d["entries"][0]["op"] = "gelu"
    def m_last_ne_frameend(g, d, bf): d["entries"][5]["last"] = 1
    def m_two_last(g, d, bf):
        e = d["entries"][0]; e["last"] = e["frame_end"] = 1
    def m_no_last(g, d, bf):
        e = d["entries"][103]; e["last"] = e["frame_end"] = 0
    def m_heads_out_nonnull(g, d, bf): d["entries"][103]["out_buf"] = 90
    def m_conv_out_null(g, d, bf): d["entries"][0]["out_buf"] = None
    def m_in0_missing(g, d, bf): d["entries"][0]["in_bufs"] = [200]
    def m_out_missing(g, d, bf): d["entries"][0]["out_buf"] = 200
    def m_concat_sum(g, d, bf):
        for e in d["entries"]:
            if e["op"] == "concat":
                bf["entries"][e["out_buf"]]["size"] += 1
                return
    def m_concat_9seg(g, d, bf):
        for e in d["entries"]:
            if e["op"] == "concat":
                e["inputs"] = (e["inputs"] * 9)[:9]
                return
    def m_view_c1_over(g, d, bf):
        for e in d["entries"]:
            if e["op"] == "view":
                e["ch"] = [0, 999]; return
    def m_view_alias_broken(g, d, bf):
        for e in d["entries"]:
            if e["op"] == "view":
                bf["entries"][e["out_buf"]]["base_off"] += 64
                return
    def m_view_empty(g, d, bf):
        for e in d["entries"]:
            if e["op"] == "view":
                e["ch"] = [8, 8]; return
    def m_chw_gt_size(g, d, bf): bf["entries"][1]["size"] -= 1
    def m_stride_lt_w(g, d, bf): bf["entries"][1]["line_stride"] = 1
    def m_base_off_window(g, d, bf): bf["entries"][1]["base_off"] = 0x20000000
    def m_dep_future(g, d, bf): d["entries"][1]["deps"] = [50]
    def m_producer_future(g, d, bf): bf["entries"][1]["producer_task"] = 50
    def m_buf_count_over(g, d, bf):
        import copy as _c
        for i in range(25):
            c = _c.deepcopy(bf["entries"][0]); c["id"] = 104 + i
            bf["entries"].append(c)
    def m_dup_desc_id(g, d, bf): d["entries"][1]["desc_id"] = 0
    def m_dup_buf_id(g, d, bf):
        import copy as _c
        bf["entries"].append(_c.deepcopy(bf["entries"][0]))

    def t_quant_overflow():
        qa = _QuantAssigner()
        for i in range(300):                              # >255 唯一对
            qa.id_of(1.0 + i * 1e-6, 1.0)
        return None

    return [
        ("unknown_op", m_unknown_op), ("last_ne_frame_end", m_last_ne_frameend),
        ("two_last_holders", m_two_last), ("no_last_holder", m_no_last),
        ("heads_out_nonnull", m_heads_out_nonnull),
        ("conv_out_null", m_conv_out_null), ("in0_not_registered", m_in0_missing),
        ("out_not_registered", m_out_missing), ("concat_segsum_ne_size", m_concat_sum),
        ("concat_9_segments", m_concat_9seg), ("view_c1_gt_parentC", m_view_c1_over),
        ("view_alias_broken", m_view_alias_broken), ("view_empty_slice", m_view_empty), ("chw_gt_size", m_chw_gt_size),
        ("line_stride_lt_W", m_stride_lt_w), ("base_off_out_cma", m_base_off_window),
        ("dep_in_future", m_dep_future), ("producer_desc_ge_id", m_producer_future),
        ("buffer_count_gt_128", m_buf_count_over), ("dup_desc_id", m_dup_desc_id),
        ("dup_buf_id", m_dup_buf_id), ("quant_overflow_direct", t_quant_overflow),
    ]


def run_gate(manifest_dir: str, out_dir: str, arena_base: int) -> dict:
    os.makedirs(out_dir, exist_ok=True)
    t0 = time.time()
    report: dict = {"gate": "F1", "manifest_dir": manifest_dir,
                    "arena_base": f"0x{arena_base:08X}", "stages": {}}

    # G1 正向装载 + 不变量 -------------------------------------------------
    b1 = load_bundle(manifest_dir, arena_base)
    inv = _invariants(b1)
    report["stages"]["G1_invariants"] = {"violations": inv, "pass": not inv}
    if inv:
        report["verdict"] = "FAIL"; return report

    # G2 round-trip --------------------------------------------------------
    bins1 = pack(b1)
    b2 = unpack(bins1)
    diffs = b1.semantic_equal(b2)
    repack = pack(b2)
    bit_same = all(repack[k] == bins1[k] for k in bins1)
    report["stages"]["G2_roundtrip"] = {
        "field_diffs": diffs[:20], "repack_bit_identical": bit_same,
        "pass": (not diffs) and bit_same,
    }
    if diffs or not bit_same:
        report["verdict"] = "FAIL"; return report

    # G3 固定 SHA（三次全新装载）------------------------------------------
    shas = []
    for _ in range(3):
        bx = load_bundle(manifest_dir, arena_base)
        gx = pack(bx)
        shas.append({k: hashlib.sha256(v).hexdigest() for k, v in gx.items()})
    det = all(s == shas[0] for s in shas[1:])
    report["stages"]["G3_fixed_sha"] = {"runs": shas, "identical": det, "pass": det}
    if not det:
        report["verdict"] = "FAIL"; return report

    # G4 负向门 ------------------------------------------------------------
    g0, d0, bf0 = _load_dicts(manifest_dir)
    results = []
    with tempfile.TemporaryDirectory() as tmp:
        # 对照组：未变异 + 跳过 SHA 复核必须成功（防门架自身全拒）
        _write_manifests(tmp, copy.deepcopy(g0), copy.deepcopy(d0), copy.deepcopy(bf0))
        try:
            load_bundle(tmp, arena_base, verify_sha=False)
            results.append(("__control_unmutated__", "loaded(OK)"))
        except Exception as e:
            results.append(("__control_unmutated__", f"REJECTED: {e}"))
        for name, mut in _negative_cases():
            g, d, bf = copy.deepcopy(g0), copy.deepcopy(d0), copy.deepcopy(bf0)
            try:
                if name == "quant_overflow_direct":
                    mut()
                    results.append((name, "NOT-REJECTED")); continue
                mut(g, d, bf)
                _write_manifests(tmp, g, d, bf)
                load_bundle(tmp, arena_base, verify_sha=False)
                results.append((name, "NOT-REJECTED"))
            except PackError as e:
                results.append((name, f"rejected: {e}"))
            except Exception as e:                        # 崩溃 = 门失败
                results.append((name, f"CRASH: {type(e).__name__}: {e}"))
    n_rej = sum(1 for _, r in results if r.startswith("rejected"))
    n_bad = sum(1 for _, r in results if r.startswith(("NOT-REJECTED", "CRASH"))
                and _ != "__control_unmutated__")
    all_results = dict(results)
    ctrl_ok = all_results.get("__control_unmutated__") == "loaded(OK)"
    report["stages"]["G4_negative"] = {
        "cases": {k: v for k, v in results if k != "__control_unmutated__"},
        "control_unmutated": ctrl_ok,
        "n_rejected": n_rej, "n_cases": len(results) - 1,
        "pass": ctrl_ok and n_bad == 0 and n_rej >= 17,
    }
    if not report["stages"]["G4_negative"]["pass"]:
        report["verdict"] = "FAIL"; return report

    # 交付物落盘 ------------------------------------------------------------
    for fname, data in bins1.items():
        with open(os.path.join(out_dir, fname), "wb") as f:
            f.write(data)
    report["artifacts"] = {
        k: {"bytes": len(v), "sha256": hashlib.sha256(v).hexdigest()}
        for k, v in bins1.items()
    }
    report["meta"] = {k: v for k, v in b1.meta.items() if k != "manifest_sha"}
    report["meta"]["manifest_sha"] = b1.meta.get("manifest_sha", {})
    report["verdict"] = "PASS"
    report["elapsed_s"] = round(time.time() - t0, 3)
    return report


# ----------------------------------------------------------------------------
# CLI
# ----------------------------------------------------------------------------
def main() -> int:
    try:
        sys.stdout.reconfigure(encoding="utf-8")
    except Exception:
        pass
    ap = argparse.ArgumentParser(description="PPU canonical packer (F1)")
    ap.add_argument("mode", choices=("pack", "gate"))
    ap.add_argument("--manifests", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--arena-base", default="0x10000000")
    ap.add_argument("--report", default=None)
    args = ap.parse_args()
    arena = int(args.arena_base, 0)
    os.makedirs(args.out, exist_ok=True)

    if args.mode == "pack":
        b = load_bundle(args.manifests, arena)
        bins = pack(b)
        for fname, data in bins.items():
            open(os.path.join(args.out, fname), "wb").write(data)
        print(json.dumps({k: hashlib.sha256(v).hexdigest() for k, v in bins.items()},
                         indent=1))
        return 0

    rep = run_gate(args.manifests, args.out, arena)
    rp = args.report or os.path.join(args.out, "f1_gate_report.json")
    with open(rp, "w", encoding="utf-8") as f:
        json.dump(rep, f, ensure_ascii=False, indent=1)
    print(f"F1 GATE: {rep['verdict']}")
    for k, v in rep["stages"].items():
        print(f"  {k}: {'PASS' if v['pass'] else 'FAIL'}")
    if rep.get("artifacts"):
        for k, v in rep["artifacts"].items():
            print(f"  {k}: {v['bytes']} B sha256={v['sha256'][:16]}…")
    print(f"  report: {rp}")
    return 0 if rep["verdict"] == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
