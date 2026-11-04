#!/usr/bin/env python3
"""In-process PL heads runtime: init once per process, run per frame.

A-knife speed candidate for the live seven-gesture chain
(2026-11-03_pspl_v8n_gesture7_boardprep_run01). Refactor of the frozen
p_structural_heads_resident.py replay driver: identical register map, volume
parsing, patch/JOIN-hole law, FSM per-word busy-poll contract (1 ms -- RTL
drive contract, do not shrink), doorbell sequence and sticky checks -- but
resident in the harness process instead of a per-frame runpy re-execution.

init() once per process: volume parse + JOIN hole gate, layout.json, CMA
arena alloc + poison sentinel verify + gold weights + input plane, shim MMIO
+ /dev/mem narrow-face mmap, probe writers, FSM table load, one-time shadow
demolition check (0.5 s).

run() per frame keeps the board-proven sequence (332 runs / 329 passes with
per-frame soft reset + full replay): soft-reset pulse -> poison model.22
outputs -> write three int8 neck features -> cache flush -> row replay (FSM
tables + config words; doorbells polled at 2 ms) -> sticky check per
doorbell -> invalidate -> read six segments.

No per-frame files: features arrive as in-memory fp32 arrays, segments
return as in-memory bytes. HEADS_DEBUG_FILES=1 also writes the legacy
features/live_segments files for A/B comparability. HEADS_SKIP_FSM_REPLAY=1
tests whether FSM tables survive the soft reset (recovery reloads them; two
consecutive recoveries force reload for the rest of the process).
"""
import ctypes
import hashlib
import io
import json
import mmap
import os
import time

os.environ.setdefault("XILINX_XRT", "/usr")
import numpy as np
from pynq import MMIO, allocate

D = os.environ.get("PSPL_ROOT", os.path.abspath(os.path.join(os.path.dirname(__file__), "../..")))
PROG = os.path.join(D, "prog")
GOLD = os.path.join(D, "gold")
LOGF = os.path.join(D, "evidence", "head_only_run.log")
VOL_PATH = os.environ.get("TB_SETUP_PATH",
                          os.path.join(PROG, "tb_setup_six_branches.txt"))

SHIM = 0x43C00000
RESET_ADDR = 0x43C70000
SHIM_STATUS = 0x3C          # {err[7:0]@8, done@1, busy@0}
SHIM_TICK = 0x54
LD_DATA, LD_SEL, LD_ADDR, LD_LEN = 0x100, 0x104, 0x108, 0x10C
LD_STAT, LD_ERR, LD_CNT = 0x110, 0x114, 0x118
TBL_LIMIT = {0: 256, 1: 256, 2: 640, 3: 8}
TBL_NAME = {0: "PPP", 1: "EDGE", 2: "JOIN", 3: "PAGE"}
ARENA_BASE = 0x10000000
ARENA_PATCH_SPAN = 0x1000000
POISON = 0xA5
BIT_PIN = "d23fd7e15961c3860d287c8ab97ef86dd641f8118705604712d9f86481b52bd0"

if os.environ.get("SIX_BRANCHES") == "1":
    EXPECTED_SEG = ["1", "2", "3", "4", "5", "6"]
    EXPECTED_VALID = [76800, 54000, 19200, 39100, 307200, 625600]
else:
    EXPECTED_SEG = ["1"]
    EXPECTED_VALID = [686700]
EXPECTED_DESC = [0] * len(EXPECTED_SEG)
EXPECTED_RAW = EXPECTED_VALID[:]

FEATURE_NODES = ("model.15", "model.18", "model.21")
FEATURE_SHAPES = {"model.15": (64, 40, 40), "model.18": (128, 20, 20),
                  "model.21": (256, 10, 10)}
FINAL_NODES = {
    "reg8": "model.22.cv2.0.2", "reg16": "model.22.cv2.1.2",
    "reg32": "model.22.cv2.2.2", "cls8": "model.22.cv3.0.2",
    "cls16": "model.22.cv3.1.2", "cls32": "model.22.cv3.2.2",
}

DOORBELL_POLL_S = 0.002     # doorbell done-poll (was 0.05 in the frozen driver)
RESET_FAST_S = float(os.environ.get("HEADS_RESET_MS", "5")) / 1000.0
RESET_SLOW_S = 0.05
DEBUG_FILES = os.environ.get("HEADS_DEBUG_FILES") == "1"

_RT = None


class HeadsRuntimeError(RuntimeError):
    pass


_logf = None


def log(m):
    global _logf
    line = "[%s] %s" % (time.strftime("%H:%M:%S"), m)
    print(line, flush=True)
    if _logf is not None:
        _logf.write(line + "\n")
    try:
        with open("/dev/console", "a") as c:
            c.write(line + "\n")
            c.flush()
    except Exception:
        pass


def load_hex_bin(fn):
    with io.open(fn, encoding="ascii", errors="replace") as f:
        return bytes.fromhex("".join(f.read().split()))


def parse_volume(path):
    rows = []
    segs = []
    with io.open(path, encoding="utf-8", errors="replace") as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith("#"):
                continue
            p = ln.split()
            k = p[0]
            if k in ("W", "P"):
                rows.append((k, int(p[1], 16), int(p[2], 16), ln))
            elif k == "S":
                if len(p) == 4:
                    segs.append((p[1], int(p[2]), int(p[3]), int(p[2])))
                elif len(p) == 5:
                    segs.append((p[1], int(p[2]), int(p[3]), int(p[4])))
                else:
                    raise ValueError("S row malformed: " + ln)
            elif k in ("M", "T", "R", "H"):
                rows.append((k, None, None, ln))
    if os.environ.get("SIX_BRANCHES") == "1":
        expected_count = 6
    else:
        expected_count = 1
    if len(segs) != expected_count:
        raise ValueError("Unexpected segment count %d" % len(segs))
    for i, got in enumerate(segs):
        expected = (EXPECTED_SEG[i], EXPECTED_VALID[i],
                    EXPECTED_DESC[i], EXPECTED_RAW[i])
        if got != expected:
            raise ValueError("S v1 DB%d mismatch got=%r expected=%r"
                             % (i + 1, got, expected))
    return rows, segs


def extract_fsm_groups(rows):
    """E9->EA groups in volume order: (sel, cursor, [values])."""
    groups = []
    cur = None
    for (k, a, v, raw) in rows:
        if k == "W" and a == 0xE9:
            if cur:
                groups.append(cur)
            cur = ((v >> 10) & 3, v & 0x3FF, [])
        elif k == "W" and a == 0xEA:
            if cur is not None:
                cur[2].append(v)
        else:
            if cur:
                groups.append(cur)
                cur = None
    if cur:
        groups.append(cur)
    return groups


def join_hole_scan(groups):
    hits = []
    for (sel, cursor, words) in groups:
        if sel != 2:
            continue
        for j in range(len(words)):
            if (cursor + j) % 32 >= 20:
                hits.append(cursor + j)
    return hits


def init():
    """Build the resident runtime state once. Idempotent."""
    global _RT, _logf
    if _RT is not None:
        return _RT
    os.makedirs(os.path.join(D, "evidence"), exist_ok=True)
    _logf = open(LOGF, "a", buffering=1)
    log("=== RESIDENT RUNTIME INIT (in-process heads, manual-paged S v1) ===")
    vol_sha = hashlib.sha256(open(VOL_PATH, "rb").read()).hexdigest()
    log("BIT_PIN=%s FIXED_VOL=%s" % (BIT_PIN, vol_sha))

    rows, segs = parse_volume(VOL_PATH)
    fsm_groups = extract_fsm_groups(rows)
    holes = join_hole_scan(fsm_groups)
    if holes:
        log("JOIN_HOLE_GATE_FAIL addrs=%s -- refuse to drive" % holes[:16])
        raise HeadsRuntimeError("JOIN hole gate failed")
    n_words = sum(len(g[2]) for g in fsm_groups)
    log("VOLUME parsed rows=%d FSM groups=%d words=%d segs=%s; JOIN_HOLE_GATE_PASS"
        % (len(rows), len(fsm_groups), n_words, [s[0] for s in segs]))

    layout = json.load(open(os.path.join(PROG, "layout.json")))
    heads = layout["heads_region"]
    arena_len = (heads["off"] + heads["size"] + 0xFFF) & ~0xFFF
    log("ARENA model span=0x%X heads@0x%X+%d" % (arena_len, heads["off"], heads["size"]))

    npbuf = allocate(shape=(int(arena_len),), dtype=np.uint8)
    a_phys = int(npbuf.device_address)
    delta = (a_phys - ARENA_BASE) & 0xFFFFFFFF
    log("L0 CMA_ALLOC phys=0x%08X len=0x%X delta=0x%08X" % (a_phys, arena_len, delta))
    npbuf[:] = POISON
    for (so, ln) in [(0, 4096), (arena_len // 2, 4096), (arena_len - 4096, 4096)]:
        if not all(int(b) == POISON for b in npbuf[so:so + ln][:512]):
            log("PREFILL_VERIFY_FAIL sentinel@0x%X not pure 0xA5" % so)
            raise HeadsRuntimeError("arena prefill verify failed")
    log("PREFILL_VERIFY_PASS (3 sentinel slices x 512B spot)")

    n_load = 0
    for k, b in layout["buffers"].items():
        if b["kind"] == "input":
            data = load_hex_bin(os.path.join(GOLD, "x_image.hex"))
            if len(data) != b["size"]:
                raise HeadsRuntimeError("x_image size mismatch")
            npbuf[b["off"]:b["off"] + b["size"]] = np.frombuffer(data, np.uint8)
            n_load += 1
    for node, c in layout["convs"].items():
        data = load_hex_bin(os.path.join(GOLD, "w_%s.hex" % node))
        if len(data) != c["w_bytes"]:
            raise HeadsRuntimeError("w size mismatch %s" % node)
        npbuf[c["wbase_off"]:c["wbase_off"] + c["w_bytes"]] = \
            np.frombuffer(data, np.uint8)
        n_load += 1
    npbuf.flush()
    log("L0 LOAD done planes=%d (weights resident for process lifetime)" % n_load)

    feature_bufs = {}
    for node in FEATURE_NODES:
        buf = next(b for b in layout["buffers"].values()
                   if b.get("producer") == node + ".cv2")
        feature_bufs[node] = (buf["off"], buf["size"])
    poison_list = [(b["off"], b["size"]) for b in layout["buffers"].values()
                   if (b.get("producer") or "").startswith("model.22")]
    segment_bufs = {}
    for name, node in FINAL_NODES.items():
        b = next(b for b in layout["buffers"].values()
                 if b.get("producer") == node)
        segment_bufs[name] = (b["off"], b["size"])

    shim = MMIO(SHIM, 0x1000)
    reset = MMIO(RESET_ADDR, 0x10000)
    fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
    m = mmap.mmap(fd, 0x2000, mmap.MAP_SHARED,
                  mmap.PROT_WRITE | mmap.PROT_READ, offset=SHIM & ~0xFFF)
    _wb = (ctypes.c_uint8 * 4096).from_buffer(m, 0)
    _de_low16 = (ctypes.c_uint16 * 1).from_buffer(m, 0xDE)

    def de_write32(value):
        low = value & 0xFFFF
        high = (value >> 16) & 0xFFFF
        _de_low16[0] = low
        if _de_low16[0] != low:
            raise HeadsRuntimeError("DE low-half readback mismatch")
        shim.write(0xEC, high)
        if (shim.read(0xEC) & 0xFFFF) != high:
            raise HeadsRuntimeError("EC high-half readback mismatch")

    def w_narrow(a, v):
        if a == 0xEE:
            _wb[a] = (v >> 16) & 0xFF
            time.sleep(0.002)
            if _wb[a] != ((v >> 16) & 0xFF):
                raise HeadsRuntimeError("narrow EE readback mismatch")
            return True
        if a == 0xDE:
            de_write32(v)
            time.sleep(0.002)
            return True
        return False

    rt = {
        "rows": rows, "segs": segs, "fsm_groups": fsm_groups,
        "npbuf": npbuf, "delta": delta, "shim": shim, "reset": reset,
        "feature_bufs": feature_bufs, "poison_list": poison_list,
        "segment_bufs": segment_bufs, "fsm_stats": {"groups": 0, "words": 0,
                                                    "patched": 0},
        "fsm_loaded": False, "force_fsm_reload": False,
        "consecutive_recoveries": 0, "frames": 0,
        "_w_narrow": w_narrow,
    }
    _RT = rt

    def patch(v):
        v &= 0xFFFFFFFF
        if ARENA_BASE <= v < ARENA_BASE + ARENA_PATCH_SPAN:
            return (v + delta) & 0xFFFFFFFF
        return v
    rt["patch"] = patch

    def poll_busy_low(timeout_s=10.0):
        t0 = time.time()
        while True:
            st = shim.read(LD_STAT)
            if st & 0x1:
                if time.time() - t0 > timeout_s:
                    return False
                time.sleep(0.001)
                continue
            return True

    def poll_done(timeout_s=10.0):
        t0 = time.time()
        while True:
            st = shim.read(LD_STAT)
            if st & 0x2:
                return True
            if time.time() - t0 > timeout_s:
                return False
            time.sleep(0.001)

    def fsm_flush(pending):
        if not pending:
            return True
        sel, cursor, words = pending
        if sel == 2:
            for j in range(len(words)):
                if (cursor + j) % 32 >= 20:
                    log("JOIN_HOLE_GATE_FAIL flush-time addr=%d -- abort"
                        % (cursor + j))
                    return False
        if cursor + len(words) > TBL_LIMIT[sel]:
            log("FSM_RANGE_FAIL tbl=%s cursor=%d n=%d limit=%d"
                % (TBL_NAME[sel], cursor, len(words), TBL_LIMIT[sel]))
            return False
        shim.write(LD_SEL, sel)
        shim.write(LD_ADDR, cursor)
        shim.write(LD_LEN, len(words))
        for w in words:
            vv = patch(w)
            if vv != w:
                rt["fsm_stats"]["patched"] += 1
            if not poll_busy_low():
                log("FSM_BUSY_TIMEOUT tbl=%s cursor=%d" % (TBL_NAME[sel], cursor))
                return False
            shim.write(LD_DATA, vv)
            rt["fsm_stats"]["words"] += 1
        if not poll_done():
            log("FSM_DONE_TIMEOUT tbl=%s cursor=%d n=%d"
                % (TBL_NAME[sel], cursor, len(words)))
            return False
        er = shim.read(LD_ERR)
        cn = shim.read(LD_CNT)
        rt["fsm_stats"]["groups"] += 1
        if er != 0:
            log("FSM_LOAD_ERR tbl=%s cursor=%d cnt=%d err=0x%X"
                % (TBL_NAME[sel], cursor, cn, er))
            return False
        return True
    rt["fsm_flush"] = fsm_flush

    # Pre-doorbell pass in init: FSM tables + config words, stop at first
    # doorbell row, then the one-time shadow demolition check.
    ok = _walk(stop_before_doorbell=True, fsm_reload=True, do_shadow=False,
               stats={"doorbells": 0, "walls": []})
    if not ok:
        raise HeadsRuntimeError("init pre-doorbell replay failed")
    rt["fsm_loaded"] = True
    shim.write(0x138, 0x00000000)     # demolished alias arm check (once)
    time.sleep(0.5)
    st = shim.read(SHIM_STATUS)
    if (st & 1) or ((st >> 8) & 0xFF):
        log("SHADOW_DEMOLITION_FAIL STATUS=0x%08X -- refuse to drive" % st)
        raise HeadsRuntimeError("shadow demolition check failed")
    log("SHADOW_DEMOLITION_PASS (0x138 write inert)")
    log("RESIDENT_RUNTIME_INIT_PASS phys=0x%08X poison_buffers=%d "
        "segments=%d feature_sizes=%s"
        % (a_phys, len(poison_list), len(segment_bufs),
           [feature_bufs[n][1] for n in FEATURE_NODES]))
    return rt


def _poll_shim_done(timeout_s, poll_s):
    shim = _RT["shim"]
    t0 = time.time()
    t0_ticks = shim.read(SHIM_TICK)
    while True:
        st = shim.read(SHIM_STATUS)
        err = (st >> 8) & 0xFF
        if err:
            return (False, st, time.time() - t0, t0_ticks, shim.read(SHIM_TICK),
                    "err=0x%02X" % err)
        if (st >> 1) & 1:
            return (True, st, time.time() - t0, t0_ticks, shim.read(SHIM_TICK),
                    "done")
        if time.time() - t0 > timeout_s:
            return (False, st, time.time() - t0, t0_ticks, shim.read(SHIM_TICK),
                    "timeout")
        time.sleep(poll_s)


def _sticky_ok():
    shim = _RT["shim"]
    e1 = (shim.read(SHIM_STATUS) >> 8) & 0xFF
    ler = shim.read(LD_ERR)
    return e1 == 0 and ler == 0


def _walk(stop_before_doorbell=False, fsm_reload=True, do_shadow=False,
          stats=None):
    """Literal row replay. Returns True on full success."""
    rt = _RT
    rows, segs, shim = rt["rows"], rt["segs"], rt["shim"]
    patch, fsm_flush, w_narrow = rt["patch"], rt["fsm_flush"], rt["_w_narrow"]
    pending = None
    doorbell_n = 0
    seg_i = 0
    for (k, a, v, raw) in rows:
        if k in ("M", "T", "R", "H"):
            continue
        if k != "W":
            continue                      # P rows: structural-heads path has none live
        if a == 0xE9:
            if pending is not None:
                if fsm_reload and not fsm_flush(pending):
                    return False
                pending = None
            pending = [(v >> 10) & 3, v & 0x3FF, []]
            continue
        if a == 0xEA:
            if pending is not None:
                pending[2].append(v)
                continue
            log("L2 FAIL EA without E9; fail-closed stop")
            return False
        if pending is not None:
            if fsm_reload and not fsm_flush(pending):
                return False
            pending = None
        vv = patch(v)
        if a % 4 == 0:
            if a == 0x38:
                if stop_before_doorbell:
                    return True
                doorbell_n += 1
                exp = segs[seg_i] if seg_i < len(segs) else ("?", 0, 0, 0)
                shim.write(a, vv)         # fire, THEN poll
                ok, st, wall, t0c, t1c, why = _poll_shim_done(300.0,
                                                              DOORBELL_POLL_S)
                ticks = (t1c - t0c) & 0xFFFFFFFF
                log("L3 DOORBELL #%d result=%s status=0x%08X wall=%.2fs ticks=%d "
                    "(seg=%s exp_valid=%d)"
                    % (doorbell_n, why, st, wall, ticks, exp[0], exp[1]))
                if stats is not None:
                    stats["doorbells"] = doorbell_n
                    stats["walls"].append(round(wall, 3))
                if not ok:
                    rt["last_fail"] = "doorbell #%d %s" % (doorbell_n, why)
                    return False
                if not _sticky_ok():
                    rt["last_fail"] = "sticky err after doorbell #%d" % doorbell_n
                    log("L4 FAIL sticky err after doorbell #%d" % doorbell_n)
                    return False
                seg_i += 1
            else:
                shim.write(a, vv)
        else:
            if not w_narrow(a, vv):
                log("W:0x%02X=0x%08X UNDELIVERABLE (unexpected address class)"
                    % (a, vv))
                return False
    if pending is not None and fsm_reload and not fsm_flush(pending):
        return False
    if not stop_before_doorbell and not _sticky_ok():
        rt["last_fail"] = "final sticky"
        log("L4 FAIL final sticky")
        return False
    return True


def _soft_reset(settle_s):
    rt = _RT
    rt["reset"].write(0, 0)
    time.sleep(settle_s)
    rt["reset"].write(0, 1)
    time.sleep(settle_s)
    rt["shim"].write(LD_ERR, 0)


def run(features):
    """One frame. features: [model.15, model.18, model.21] fp32 flat arrays
    (from request_hybrid). Returns (segments{name:bytes}, stats)."""
    rt = init()
    npbuf = rt["npbuf"]
    t0 = time.perf_counter()
    if len(features) != 3:
        raise HeadsRuntimeError("expected three neck features")

    _soft_reset(RESET_FAST_S)

    for off, size in rt["poison_list"]:
        npbuf[off:off + size] = POISON
    from hybrid_client import (FEATURE_SCALES, quantize_feature)
    for node, feat in zip(FEATURE_NODES, features):
        off, size = rt["feature_bufs"][node]
        shape = FEATURE_SHAPES[node]
        if feat.size != int(np.prod(shape)):
            raise HeadsRuntimeError("feature size mismatch %s: %d"
                                    % (node, feat.size))
        q = quantize_feature(feat.reshape(1, *shape),
                             FEATURE_SCALES[FEATURE_NODES.index(node)])
        if len(q.tobytes()) != size:
            raise HeadsRuntimeError("quantized feature size mismatch %s" % node)
        npbuf[off:off + size] = np.frombuffer(q.tobytes(), np.uint8)
    npbuf.flush()
    t_prep = time.perf_counter()

    stats = {"doorbells": 0, "walls": [], "recovered": False,
             "fsm_reload": True}
    skip_fsm = (os.environ.get("HEADS_SKIP_FSM_REPLAY") == "1"
                and rt["fsm_loaded"] and not rt["force_fsm_reload"])
    stats["fsm_reload"] = not skip_fsm
    ok = _walk(stop_before_doorbell=False, fsm_reload=not skip_fsm,
               do_shadow=False, stats=stats)
    if not ok:
        log("FRAME_FAIL %s -- recovery: slow reset + full FSM replay + retry"
            % rt.get("last_fail", "?"))
        _soft_reset(RESET_SLOW_S)
        stats2 = {"doorbells": 0, "walls": [], "recovered": True,
                  "fsm_reload": True}
        ok = _walk(stop_before_doorbell=False, fsm_reload=True,
                   do_shadow=False, stats=stats2)
        if not ok:
            rt["consecutive_recoveries"] += 1
            log("RECOVERY_FAIL %s (streak=%d)"
                % (rt.get("last_fail", "?"), rt["consecutive_recoveries"]))
            if rt["consecutive_recoveries"] >= 2:
                rt["force_fsm_reload"] = True
                log("FSM_RELOAD_FORCED_ON (two consecutive recovery failures)")
            raise HeadsRuntimeError(
                "structural heads PL execution failed: %s"
                % rt.get("last_fail", "?"))
        rt["fsm_loaded"] = True
        rt["consecutive_recoveries"] += 1
        if rt["consecutive_recoveries"] >= 2:
            rt["force_fsm_reload"] = True
            log("FSM_RELOAD_FORCED_ON (frequent recoveries: tables likely "
                "wiped by soft reset)")
        stats.update(stats2)
        stats["recovered"] = True
    else:
        rt["consecutive_recoveries"] = 0
        if skip_fsm:
            rt["fsm_loaded"] = True
    t_door = time.perf_counter()

    npbuf.invalidate()
    segments = {}
    for name, (off, size) in rt["segment_bufs"].items():
        data = npbuf[off:off + size].tobytes()
        segments[name] = data
        if DEBUG_FILES:
            out_dir = os.environ.get("LIVE_HEADS_DIR",
                                     os.path.join(D, "live_segments"))
            os.makedirs(out_dir, exist_ok=True)
            with open(os.path.join(out_dir, name + ".bin"), "wb") as f:
                f.write(data)
        log("LIVE_SEGMENT_EXPORT name=%s bytes=%d sha256=%s"
            % (name, len(data), hashlib.sha256(data).hexdigest()))
    log("LIVE_C1_C2_PASS; six segments read in-process (doorbells=%d "
        "wall_sum=%.2fs fsm_reload=%s)"
        % (stats["doorbells"], sum(stats["walls"]), stats["fsm_reload"]))
    rt["frames"] += 1
    stats["prep_ms"] = round((t_prep - t0) * 1000.0, 3)
    stats["replay_ms"] = round((t_door - t_prep) * 1000.0, 3)
    stats["seg_ms"] = round((time.perf_counter() - t_door) * 1000.0, 3)
    stats["pl_driver_ms"] = round((time.perf_counter() - t0) * 1000.0, 3)
    stats["frames_so_far"] = rt["frames"]
    return segments, stats
