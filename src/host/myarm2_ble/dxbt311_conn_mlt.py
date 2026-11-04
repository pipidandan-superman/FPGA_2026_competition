# Control-plane-only master test: WeBotPi(DX-BT311, J5/COM4, ROLE=1) connects
# to the BOARD MLT (88:4A:EA:8D:C3:29, slave, advertising). No servo frames:
# the board MLT's UART (Y13/AA13) floats in the J5 build, so data-plane
# results here are inconclusive BY DESIGN - this run answers only
# "can the module act as master and establish a connection" (CONA -> banner),
# then releases with AT+DISC and verifies the link dropped.
# Usage: D:\work\Python\python.exe dxbt311_conn_mlt.py [--port COM4]
import json
import sys
import time

import serial

PORT = "COM4"
MLT = "884AEA8DC329"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

log = open("dxbt311_conn_mlt_events.jsonl", "a", encoding="utf-8")


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


s = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1, timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

if b"OK" not in tx_rx(s, b"AT"):
    print("VERDICT: NO_AT")
    sys.exit(1)
r = tx_rx(s, b"AT+ROLE")
print("ROLE: %r" % r)
if b"+ROLE=1" not in r:
    tx_rx(s, b"AT+ROLE1")
    time.sleep(6.0)
    r = tx_rx(s, b"AT+ROLE")
    print("ROLE after set: %r" % r)

# connect to the board MLT (one-shot CONA, nothing stored)
s.write(b"AT+CONA" + MLT.encode() + b"\r\n")
ev("cmd", cmd="AT+CONA" + MLT)
buf = b""
t0 = time.time()
connected_at = None
while time.time() - t0 < 60.0:
    c = rd(s, 1.0)
    if c:
        buf += c
        ev("conn_rx", at=round(time.time() - t0, 1), rx=c.decode("ascii", "replace"))
        # check accumulated buf: the banner may split across serial reads
        if b"Connected" in buf and connected_at is None:
            connected_at = round(time.time() - t0, 1)
            break
print("CONNECT: %s raw=%r" % (connected_at, buf))

if connected_at is None:
    ev("verdict", result="MLT_CONNECT_FAIL", raw=buf.decode("ascii", "replace"))
    print("VERDICT: MLT_CONNECT_FAIL")
    s.close()
    sys.exit(2)

# hold 3 s, then documented disconnect (transparent-mode UART-side escape)
time.sleep(3.0)
r = tx_rx(s, b"AT+DISC", wait=3.0)
print("DISC: %r" % r)
time.sleep(1.0)
r_at = tx_rx(s, b"AT")
s.close()

if b"OK" in r_at or b"+ROLE" in r:
    ev("verdict", result="DX311_MASTER_CONTROL_PLANE_PASS", connect_at=connected_at,
       disc=r.decode("ascii", "replace"))
    print("VERDICT: DX311_MASTER_CONTROL_PLANE_PASS "
          "(connect@%ss, DISC reply seen, AT alive after)" % connected_at)
else:
    ev("verdict", result="DX311_MASTER_CONNECTED_BUT_SWALLOWED",
       disc=r.decode("ascii", "replace"))
    print("VERDICT: DX311_MASTER_CONNECTED_BUT_SWALLOWED - MLT-trap shape; "
          "power-cycle module + dxbt311_cleanup.py")
