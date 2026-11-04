# DX-BT311-10C02S arrival bench, phase 1: baud autolock + dialect survey.
# Bench wiring (see prep run01 README): carrier board exposes ONLY the
# 3.6-6V LDO-input VCC pin -> VCC and GND both come from the STM32 expansion
# board's spare 5V rail (user-designated); ONLY RX/TX cross to the FPGA
# (RX<-J5-32/U21, TX->J5-31/T21). Grounds of the two boards common through
# the PC's dual USB links during bench; standalone deployment needs one
# extra GND dupont between the boards.
# FPGA runs the archived J5 bridge bit (ble_uart_debug_top_j5_20261005.bit) so the
# PC reaches the module through COM4 (CP2103 on J8 upper socket).
# Dialect per official serial guide V1.1: no '=' in commands, replies "+CMD=param"
# then "OK"; errors are "ERROR=101..104". Default 9600 8N1 slave named BT311
# (the in-hand WeBotPi unit likely carries 115200 from its arm deployment).
# Usage: D:\work\Python\python.exe dxbt311_phase1_dialect.py [--port COM4]
import json
import sys
import time

import serial

PORT = "COM4"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

# Official default first; the rest cover a module that shipped pre-configured.
BAUDS = (9600, 115200, 57600, 38400, 19200, 4800, 2400)

log = open("dxbt311_phase1_events.jsonl", "a", encoding="utf-8")


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


def tx_rx(s, cmd, wait=1.0):
    s.write(cmd + b"\r\n")
    r = rd(s, wait)
    ev("cmd", cmd=cmd.decode(), rx_hex=r.hex(), rx=r.decode("ascii", "replace"))
    return r


locked = None
for baud in BAUDS:
    s = serial.Serial(PORT, baud, bytesize=8, parity="N", stopbits=1, timeout=0.02)
    time.sleep(0.2)
    s.reset_input_buffer()
    r = tx_rx(s, b"AT", wait=1.0)
    if b"OK" in r:
        locked = baud
        ev("baud_locked", baud=baud)
        print("BAUD_LOCKED=%d" % baud)
        break
    s.close()

if locked is None:
    ev("verdict", result="DX311_PHASE1_NO_AT")
    print("VERDICT: DX311_PHASE1_NO_AT (no OK at any candidate baud)")
    sys.exit(1)

# Survey: identity + role + master-relevant state (queries are bare commands).
survey = {
    "version": tx_rx(s, b"AT+VERSION"),
    "laddr": tx_rx(s, b"AT+LADDR"),
    "role": tx_rx(s, b"AT+ROLE"),
    "name": tx_rx(s, b"AT+NAME"),
    "baud": tx_rx(s, b"AT+BAUD"),
    "muuid": tx_rx(s, b"AT+MUUID"),
    "timeinq": tx_rx(s, b"AT+TIMEINQ"),
}

# Undocumented-on-this-vendor probes kept out of the pass criteria; they only
# help map dialect drift if the shipped firmware differs from the guide.
def role_val(r):
    # "+ROLE=0" or "+ROLE=1" anywhere in the reply
    if b"+ROLE=0" in r:
        return 0
    if b"+ROLE=1" in r:
        return 1
    return None


rv = role_val(survey["role"])
ok_count = sum(1 for r in survey.values() if b"OK" in r or b"=" in r)
plus_count = sum(1 for r in survey.values() if r.startswith(b"+"))
ev("survey_result", role=rv, ok_count=ok_count, plus_count=plus_count)

s.close()

# Pass = AT ack + dialect shape (+CMD= replies) + a definite role value.
if rv is not None and plus_count >= 3:
    ev("verdict", result="DX311_DIALECT_PASS", role=rv, baud=locked)
    print("VERDICT: DX311_DIALECT_PASS (role=%d baud=%d)" % (rv, locked))
    print("NEXT: dxbt311_phase2_master.py --port %s" % PORT)
else:
    ev("verdict", result="DX311_DIALECT_ODD", role=rv, baud=locked)
    print("VERDICT: DX311_DIALECT_ODD (role=%s plus=%d) - inspect events jsonl" % (rv, plus_count))
