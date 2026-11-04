# DX-BT311-10C02S post-PASS persistent setup: AT+BIND + auto-reconnect verify.
# Run --set ONLY after DX311_MASTER_FULL_LOOP_PASS (order iron rule from the
# 10-05 ruling: CONA one-shot zero-storage first, BIND persistence only after
# the PASS verdict - this avoids recreating the MLT ROLE1+BAND steal trap).
# The module may still be connected/transparent from phase2: the official
# guide gives AT+DISC as the transparent-state escape, used to regain the
# parser. DX BIND semantics per guide: auto-reconnect on disconnect AND on
# power-up. Reconnect-after-DISC may or may not trigger while in AT mode;
# the authoritative deployment test is --verify after a module VCC power
# cycle, which speaks only transparent frames (no parser races).
# Usage: D:\work\Python\python.exe dxbt311_bind.py --set [--port COM4] [--mac 98EAA021013A]
#        D:\work\Python\python.exe dxbt311_bind.py --verify [--port COM4]
import json
import re
import sys
import time

import serial

PORT = "COM4"
MAC = "98EAA021013A"
MODE = None
args = sys.argv[1:]
if "--set" in args:
    MODE = "set"
if "--verify" in args:
    MODE = "verify"
if "--port" in args:
    PORT = args[args.index("--port") + 1]
if "--mac" in args:
    MAC = args[args.index("--mac") + 1].replace(":", "").upper()

log = open("dxbt311_bind_events.jsonl", "a", encoding="utf-8")


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

if MODE == "set":
    # Step 1: escape transparent mode if the phase2 link is still up
    r = tx_rx(s, b"AT+DISC", wait=8.0)
    disc = b"Disconnect" in r
    print("DISC: %s raw=%r" % (disc, r))
    if not disc:
        r2 = tx_rx(s, b"AT")
        if b"OK" not in r2:
            print("VERDICT: BIND_NO_PARSER (neither DISC escape nor plain AT)")
            ev("verdict", result="BIND_NO_PARSER")
            s.close()
            sys.exit(1)
    # Step 2: store the bind
    r = tx_rx(s, b"AT+BIND" + MAC.encode())
    ok = (b"OK" in r) or (b"BIND" in r)
    print("BIND: %r -> %s" % (r, ok))
    if not ok:
        print("VERDICT: BIND_SET_FAIL")
        ev("verdict", result="BIND_SET_FAIL")
        s.close()
        sys.exit(2)
    # Step 3: watch for auto-reconnect right after DISC (optional behavior)
    buf = b""
    t0 = time.time()
    conn = None
    while time.time() - t0 < 45.0:
        c = rd(s, 1.0)
        if c:
            buf += c
            ev("reconn_rx", at=round(time.time() - t0, 1), rx=c.decode("ascii", "replace"))
            if b"Connected" in c:
                conn = round(time.time() - t0, 1)
                break
    print("RECONNECT after DISC: %s raw=%r" % (conn, buf))
    if conn is None:
        print("NOTE: no reconnect after DISC - power-cycle module VCC, then run --verify")
        ev("verdict", result="BIND_SET_RECONNECT_UNSEEN")
        s.close()
        sys.exit(3)

if MODE == "verify":
    # Power-cycle path: the module auto-reconnects on its own; speak only
    # transparent frames. Retry PRAD until the link answers.
    conn = None
    t0 = time.time()
    while time.time() - t0 < 30.0:
        c = rd(s, 1.0)
        if c:
            ev("watch_rx", at=round(time.time() - t0, 1), rx=c.decode("ascii", "replace"))
            if b"Connected" in c:
                conn = round(time.time() - t0, 1)
                break
    print("WATCH: %s" % conn)

hits = 0
if MODE == "verify" and conn is None:
    # link may already have been up before we opened the port: try frames anyway
    pass
if MODE == "set" and conn is None:
    s.close()
    sys.exit(3)

# Transparent round-trip proof on the (auto-)reconnected link
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
    ev("verdict", result="BIND_RECONNECT_FULL_LOOP_PASS", hits=hits)
    print("VERDICT: BIND_RECONNECT_FULL_LOOP_PASS (%d/3 frames answered)" % hits)
    print("NEXT: on-board integration (B2 axi_ble_uart @0x43C10000)")
else:
    ev("verdict", result="BIND_RECONNECT_CONNECT_ONLY", hits=hits)
    print("VERDICT: BIND_RECONNECT_CONNECT_ONLY (hits=%d/3)" % hits)
    sys.exit(4)
