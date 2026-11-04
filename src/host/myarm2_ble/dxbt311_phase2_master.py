# DX-BT311-10C02S arrival bench, phase 2: MASTER full-loop verdict.
# The one capability the whole purchase hinges on: does the DX master, after
# connecting, actually perform GATT client writes over the air (the MLT v6.1
# master data plane was triple-confirmed dead - connection holds, UART bytes
# silently swallowed, peer sees zero writes).
# Target: arm-side AT-09 D0:B5:C2:8D:EB:49 (slave, FFE0/FFE1 quad-property,
# ROLE=0, UART 115200 persisted - irrelevant for the air link).
# PRECONDITIONS (10-04 lesson): arm servo power ON (listen for the lock sound),
# AT-09 powered and advertising. Frame iron rule: servo read = "#001PRAD!"
# ('#'+3-digit ID), never "$1PRAD!".
# Order is deliberate: CONA (one-shot, nothing stored) BEFORE any BIND test,
# so a dead master path cannot leave a stored auto-steal state behind.
# Usage: D:\work\Python\python.exe dxbt311_phase2_master.py [--port COM4] [--mac D0B5C28DEB49]
import json
import re
import sys
import time

import serial

PORT = "COM4"
MAC = "D0B5C28DEB49"
args = sys.argv[1:]
if "--port" in args:
    PORT = args[args.index("--port") + 1]
if "--mac" in args:
    MAC = args[args.index("--mac") + 1].replace(":", "").upper()

log = open("dxbt311_phase2_events.jsonl", "a", encoding="utf-8")


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


def tx_rx(s, cmd, wait=1.5):
    s.write(cmd + b"\r\n")
    r = rd(s, wait)
    ev("cmd", cmd=cmd.decode(), rx=r.decode("ascii", "replace"))
    return r


# Step 0: parser alive? (autolock 115200 first - the in-hand WeBotPi unit
# carries 115200 from its arm deployment; factory default is 9600)
s = None
for baud in (115200, 9600):
    s = serial.Serial(PORT, baud, bytesize=8, parity="N", stopbits=1,
                      timeout=0.02)
    time.sleep(0.2)
    s.reset_input_buffer()
    r = tx_rx(s, b"AT")
    if b"OK" in r:
        ev("baud_locked", baud=baud)
        print("BAUD_LOCKED=%d" % baud)
        break
    s.close()
    s = None
if b"OK" not in r:
    print("VERDICT: DX311_NO_AT (run dxbt311_phase1_dialect.py first)")
    ev("verdict", result="DX311_NO_AT")
    sys.exit(1)

# Step 1: master role (auto-restart per guide; give it 6 s)
r = tx_rx(s, b"AT+ROLE1")
time.sleep(6.0)
r = tx_rx(s, b"AT+ROLE")
if b"+ROLE=1" not in r:
    print("VERDICT: DX311_ROLE1_FAILED rx=%r" % r)
    ev("verdict", result="DX311_ROLE1_FAILED", rx=r.decode("ascii", "replace"))
    sys.exit(1)
print("ROLE=1 confirmed")

# Step 2: scan (capture raw list; format to be learned on real hardware)
r = tx_rx(s, b"AT+INQ", wait=12.0)
ev("inq_raw", rx=r.decode("ascii", "replace"))
print("INQ: %r" % r)
seen = MAC.encode() in r
if not seen:
    # not fatal: guide also allows direct CONA; keep going but record it
    ev("warn", note="target MAC not seen in INQ list")

# Step 3: direct connect by MAC (one-shot, nothing stored). MLT CONA took
# 15-25 s; give DX 60 s before calling it dead.
s.write(b"AT+CONA" + MAC.encode() + b"\r\n")
ev("cmd", cmd="AT+CONA" + MAC)
buf = b""
t0 = time.time()
connected_at = None
while time.time() - t0 < 60.0:
    c = rd(s, 1.0)
    if c:
        buf += c
        ev("conn_rx", at=round(time.time() - t0, 1), rx=c.decode("ascii", "replace"))
        if b"Connected" in c and connected_at is None:
            connected_at = round(time.time() - t0, 1)
    if connected_at is not None:
        break
print("CONNECT: %s (at %ss) raw=%r" % (connected_at, connected_at, buf))

if connected_at is None:
    print("VERDICT: DX311_MASTER_CONNECT_FAIL")
    ev("verdict", result="DX311_MASTER_CONNECT_FAIL", raw=buf.decode("ascii", "replace"))
    s.close()
    sys.exit(2)

# Step 4: THE verdict - transparent servo read over the air.
# Arm echo path (proven with PC central): "#001PRAD!" -> "#001P<digits>!".
time.sleep(1.0)
s.reset_input_buffer()
hits = 0
reply = b""
for i in range(3):
    s.write(b"#001PRAD!")
    ev("tx_frame", i=i)
    r = rd(s, 3.0)
    reply += r
    ev("frame_rx", i=i, rx=r.decode("ascii", "replace"))
    if re.search(rb"#001P\d+!", r):
        hits += 1
s.close()

if hits >= 2:
    print("VERDICT: DX311_MASTER_FULL_LOOP_PASS (%d/3 frames answered)" % hits)
    ev("verdict", result="DX311_MASTER_FULL_LOOP_PASS", hits=hits)
    print("NEXT (persistent setup only after this PASS): AT+BIND%s + power-cycle"
          " reconnect check, then on-board integration" % MAC)
else:
    print("VERDICT: DX311_MASTER_DATA_PLANE_DEAD (hits=%d/3) - MLT-style silent"
          " swallow; capture evidence, module line closes, ESP32 remains" % hits)
    ev("verdict", result="DX311_MASTER_DATA_PLANE_DEAD", hits=hits,
       reply=reply.decode("ascii", "replace"))
    print("CLEANUP: D:\\work\\Python\\python.exe dxbt311_cleanup.py --port %s" % PORT)
    sys.exit(3)
