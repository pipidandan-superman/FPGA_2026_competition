# DX-BT311-10C02S cleanup: restore factory slave state (ROLE=0, no BIND).
# Trap being defended against (MLT precedent, DX semantics documented):
# a master with a stored BIND auto-connects after every power-up, and a
# connected module may swallow UART bytes silently. DX offers two documented
# escapes the MLT lacked: AT+DISC works in transparent mode from the UART
# side, and AT+CLEAR wipes the binding.
# Mode A (default): try parser-first cleanup directly.
# Mode B (--race <seconds>): if mode A is swallowed, spam AT+CLEAR every 80 ms
#   while the module power-cycles (pull the VCC dupont / reflash via JTAG);
#   parser-alive window after boot races the BIND auto-connect, exactly the
#   validated y15_cleanup_race.py method (one-shot hit at 26.7 s there).
# Usage: D:\work\Python\python.exe dxbt311_cleanup.py [--port COM4] [--baud 115200] [--race 90]
# --baud added 2026-10-06: the in-hand WeBotPi runs 115200 (arm UART3 / phase1);
# new-purchase units come up at the 9600 factory default.
import json
import sys
import time

import serial

PORT = "COM4"
BAUD = 9600
args = sys.argv[1:]
if "--port" in args:
    PORT = args[args.index("--port") + 1]
if "--baud" in args:
    BAUD = int(args[args.index("--baud") + 1])
RACE = float(args[args.index("--race") + 1]) if "--race" in args else None

log = open("dxbt311_cleanup_events.jsonl", "a", encoding="utf-8")


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


s = serial.Serial(PORT, BAUD, bytesize=8, parity="N", stopbits=1, timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

alive = b"OK" in tx_rx(s, b"AT")

if not alive and RACE is not None:
    ev("race_start", dur=RACE)
    print("RACE: spamming AT+CLEAR for %.0fs - power-cycle the module NOW"
          " (pull VCC dupont, wait 2s, reseat)" % RACE)
    t0 = time.time()
    last_tx = 0.0
    while time.time() - t0 < RACE:
        if time.time() - last_tx >= 0.08:
            s.write(b"AT+CLEAR\r\n")
            last_tx = time.time()
        c = s.read(512)
        if c:
            ev("race_rx", at=round(time.time() - t0, 2), rx=c.decode("ascii", "replace"))
            if b"OK" in c or b"=" in c:
                alive = True
                break
    alive = alive or (b"OK" in tx_rx(s, b"AT"))

if alive:
    # order: disconnect first (frees transparent engine), then wipe, then role
    tx_rx(s, b"AT+DISC", wait=2.0)
    tx_rx(s, b"AT+CLEAR", wait=2.0)
    tx_rx(s, b"AT+ROLE0", wait=2.0)
    time.sleep(6.0)  # role change auto-restarts the module
    r_at = tx_rx(s, b"AT")
    r_role = tx_rx(s, b"AT+ROLE")
    s.close()
    if b"+ROLE=0" in r_role:
        print("VERDICT: DX311_RESTORED_SLAVE (AT=%r ROLE=%r)" % (r_at, r_role))
        ev("verdict", result="DX311_RESTORED_SLAVE")
    else:
        print("VERDICT: DX311_ROLE_VERIFY_ODD (AT=%r ROLE=%r) - if empty, retry:"
              " role-change stack reboot swallows one command sometimes" % (r_at, r_role))
        ev("verdict", result="DX311_ROLE_VERIFY_ODD",
           at=r_at.decode("ascii", "replace"), role=r_role.decode("ascii", "replace"))
else:
    s.close()
    print("VERDICT: DX311_CLEANUP_SILENT - module UART swallowed; use --race 90"
          " and power-cycle during the spam window")
    ev("verdict", result="DX311_CLEANUP_SILENT")
