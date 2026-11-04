# FPGA-side WeBotPi (DX-BT311 master) MOTION demo - authorized 2026-10-08.
# Transport: PC COM4 -> J5 transparent bridge (JTAG-loaded bench bit) ->
# DX-BT311 98eaa0210214 (master, ROLE1+BIND stored) -> air ->
# original WeBotPi 98eaa021013a (arm socket slave) -> UART3 -> STM32 ->
# servo bus. The FPGA passes the bytes in this bench form; the autonomous
# on-board form (B2 axi_ble_uart) comes later.
# Motion envelope copied verbatim from the 2026-10-05 validated
# b_pc_motion_demo.py: servo 001 (upper arm), +/-80 counts @ T500
# (160 counts/s, manual small-travel rule), tolerance +/-10, clamp 600-2400.
# Sequence: PRAD -> +80 move -> back -> PRAD verify. STM32 echoes every TX
# frame; the servo answer is the clean '#NNNPdddd!' after the echo.
# Usage: D:\work\Python\python.exe dxbt311_motion_demo.py [--port COM4]
import json
import re
import sys
import time

import serial

PORT = "COM4"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

SID = 1        # servo 001 = upper arm, proven good in the 10-03 recheck
DELTA = 80     # small travel (recheck: 80@T400/500 precise)
T_MS = 500     # small-travel rule T<=500; 80/0.5s = 160 counts/s
LOG = (r"E:\competition\4_metrics\logs"
       r"\2026-10-08_dxbt311_dual_webotpi_pass_run01\dxbt311_motion_events.jsonl")

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
    print("[tx] %-20r -> %r" % (frame, r))
    return r


def parse_pos(buf, sid):
    m = re.search(rb"#%03dP(\d{4})!" % sid, buf)
    return int(m.group(1)) if m else None


print("--- DX311 FPGA-side motion demo %s servo=%03d delta=%d T=%d ---" %
      (time.strftime("%F %T"), SID, DELTA, T_MS))
ev("session", sid=SID, delta=DELTA, t_ms=T_MS)

s = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1,
                  timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

# 0) link alive (BIND auto-reconnects if the link dropped since --verify)
pos0 = None
for attempt in range(3):
    r = send(s, b"#%03dPRAD!" % SID, 2.0)
    pos0 = parse_pos(r, SID)
    if pos0 is not None:
        break
    time.sleep(2.0)
print("[read] current pos = %s" % pos0)
ev("read_pos", pos=pos0)
if pos0 is None:
    print("VERDICT: DX311_MOTION_NO_READBACK")
    ev("verdict", v="DX311_MOTION_NO_READBACK")
    s.close()
    sys.exit(1)

tgt = min(max(pos0 + DELTA, 600), 2400)
if not (600 <= tgt <= 2400):
    print("[abort] target %d out of safe range" % tgt)
    ev("abort", target=tgt)
    s.close()
    sys.exit(1)

# 1) small move forward, then an INDEPENDENT position read while stopped
# there (the motion-frame echo is STM32-made and proves nothing about the
# servo - manual trap list; the mid PRAD is the real execution proof)
send(s, b"#%03dP%04dT%04d!" % (SID, tgt, T_MS), T_MS / 1000.0 + 1.5)
r = send(s, b"#%03dPRAD!" % SID, 2.0)
moved = parse_pos(r, SID)
print("[moved] mid pos = %s (target %d)" % (moved, tgt))
ev("mid_pos", pos=moved, target=tgt)

# 2) back to original
send(s, b"#%03dP%04dT%04d!" % (SID, pos0, T_MS), T_MS / 1000.0 + 1.5)

# 3) verify
r = send(s, b"#%03dPRAD!" % SID, 2.0)
posf = parse_pos(r, SID)
print("[final] pos = %s (start %s)" % (posf, pos0))
ev("final_pos", pos=posf, start=pos0)
s.close()

ok = (moved is not None and abs(moved - tgt) <= 10 and posf is not None
      and abs(posf - pos0) <= 10)
v = "DX311_MOTION_PASS" if ok else "DX311_MOTION_CHECK"
print("VERDICT: %s  (start=%s mid=%s final=%s)" % (v, pos0, moved, posf))
ev("verdict", v=v, start=pos0, mid=moved, final=posf)
sys.exit(0 if ok else 1)
