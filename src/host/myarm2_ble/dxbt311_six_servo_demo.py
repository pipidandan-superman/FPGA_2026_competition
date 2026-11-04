# FPGA-side WeBotPi link: sequential small-range motion for ALL SIX servos
# (ID 0-5), user-authorized 2026-10-08. Transport identical to
# dxbt311_motion_demo.py (COM4 -> J5 bridge -> DX master 98eaa0210214 ->
# air -> arm slave 98eaa021013a -> UART3 -> servo bus).
# Envelope per manual small-travel rule: +/-80 counts @ T500 = 160 counts/s.
# Gripper 005 special handling (three overcurrent lockups on record,
# measured stroke [1033,1765]): target clamped to [1133,1665] (100-count
# inset); flips direction if already at the clamp edge.
# Per servo: PRAD -> +80 (clamped) -> mid PRAD (independent execution
# proof - the motion-frame echo is STM32-made) -> back -> final PRAD,
# tolerance +/-10 on both legs.
# Usage: D:\work\Python\python.exe dxbt311_six_servo_demo.py [--port COM4]
import json
import re
import sys
import time

import serial

PORT = "COM4"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

SIDS = [0, 1, 2, 3, 4, 5]
DELTA = 80
T_MS = 500
GRIP = 5
GRIP_LO, GRIP_HI = 1133, 1665   # 100-count inset inside stroke [1033,1765]
GEN_LO, GEN_HI = 600, 2400
TOL = 10
LOG = (r"E:\competition\4_metrics\logs"
       r"\2026-10-08_dxbt311_dual_webotpi_pass_run01\dxbt311_six_servo_events.jsonl")

log = open(LOG, "a", encoding="utf-8")


def ev(kind, **kw):
    e = {"t": round(time.time(), 3), "kind": kind}
    e.update(kw)
    log.write(json.dumps(e, ensure_ascii=True) + "\n")
    log.flush()


def rd(s, secs):
    buf = b""
    t0 = time.time()
    while time.time() - t0 < secs:
        c = s.read(512)
        if c:
            buf += c
    return buf


def send(s, frame, listen_s):
    s.write(frame)
    r = rd(s, listen_s)
    ev("frame", tx=frame.decode(), rx=r.decode("ascii", "replace"))
    print("   [tx] %-20r -> %r" % (frame, r))
    return r


def parse_pos(buf, sid):
    m = re.search(rb"#%03dP(\d{4})!" % sid, buf)
    return int(m.group(1)) if m else None


def read_pos(s, sid):
    for _ in range(3):
        r = send(s, b"#%03dPRAD!" % sid, 2.0)
        p = parse_pos(r, sid)
        if p is not None:
            return p
        time.sleep(1.5)
    return None


print("--- DX311 six-servo sequential demo %s delta=%d T=%d ---" %
      (time.strftime("%F %T"), DELTA, T_MS))
ev("session", sids=SIDS, delta=DELTA, t_ms=T_MS)

s = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1,
                  timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

results = {}
for sid in SIDS:
    lo, hi = (GRIP_LO, GRIP_HI) if sid == GRIP else (GEN_LO, GEN_HI)
    print("[servo %03d]" % sid)
    pos0 = read_pos(s, sid)
    if pos0 is None:
        print("   NO READBACK - skip")
        ev("servo_skip", sid=sid, reason="no_readback")
        results[sid] = "NO_READBACK"
        continue
    tgt = min(max(pos0 + DELTA, lo), hi)
    if abs(tgt - pos0) < 20:            # at clamp edge -> flip direction
        tgt = min(max(pos0 - DELTA, lo), hi)
    print("   pos0=%d target=%d" % (pos0, tgt))
    ev("servo_start", sid=sid, pos0=pos0, target=tgt)

    send(s, b"#%03dP%04dT%04d!" % (sid, tgt, T_MS), T_MS / 1000.0 + 1.5)
    mid = parse_pos(send(s, b"#%03dPRAD!" % sid, 2.0), sid)
    send(s, b"#%03dP%04dT%04d!" % (sid, pos0, T_MS), T_MS / 1000.0 + 1.5)
    fin = parse_pos(send(s, b"#%03dPRAD!" % sid, 2.0), sid)

    ok = (mid is not None and abs(mid - tgt) <= TOL and fin is not None
          and abs(fin - pos0) <= TOL)
    results[sid] = "PASS" if ok else "CHECK"
    print("   mid=%s final=%s -> %s" % (mid, fin, results[sid]))
    ev("servo_result", sid=sid, pos0=pos0, target=tgt, mid=mid, final=fin,
       verdict=results[sid])
    time.sleep(1.0)

s.close()
npass = sum(1 for v in results.values() if v == "PASS")
v = "DX311_SIX_SERVO_PASS" if npass == len(SIDS) else "DX311_SIX_SERVO_PARTIAL"
print("VERDICT: %s (%d/%d) %s" % (v, npass, len(SIDS), results))
ev("verdict", v=v, npass=npass, results=results)
sys.exit(0 if npass == len(SIDS) else 1)
