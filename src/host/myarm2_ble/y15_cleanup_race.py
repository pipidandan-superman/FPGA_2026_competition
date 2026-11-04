# Race the BAND-autoconnect window: spam AT+CLRBAND across a JTAG reflash.
# Module boots with ROLE1+BAND stored -> autoconnect fires ~2.1s after boot;
# once connected, UART bytes are swallowed silently (tonight's triple-confirmed
# master data-plane death). Parser is alive from ~1.1s post-boot, so a CLRBAND
# landing in that ~1s window kills the steal for this and every future boot.
# Follow-ups (IMME0/ROLE0) fire immediately after an ack; if the in-flight
# autoconnect still completes, a second power cycle finishes the cleanup.
import json
import sys
import time

import serial

DUR = float(sys.argv[1]) if len(sys.argv) > 1 else 90.0
log = open("y15_cleanup_race_events.jsonl", "a", encoding="utf-8")


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


s = serial.Serial("COM4", 9600, bytesize=8, parity="N", stopbits=1, timeout=0.02)
s.reset_input_buffer()
ev("race_start", dur=DUR)

t0 = time.time()
last_tx = 0.0
ok_at = None
connected_at = None
while time.time() - t0 < DUR:
    if time.time() - last_tx >= 0.08:
        s.write(b"AT+CLRBAND\r\n")
        last_tx = time.time()
    c = s.read(512)
    if c:
        ev("rx", at=round(time.time() - t0, 2), rx_hex=c.hex())
        if connected_at is None and b"Connected" in c:
            connected_at = round(time.time() - t0, 2)
            ev("connected_banner", at=connected_at)
        if ok_at is None and (b"OK" in c or b"+Set" in c or b"BAND" in c):
            ok_at = round(time.time() - t0, 2)
            ev("clrband_reply", at=ok_at, rx_hex=c.hex())
            break

if ok_at is not None:
    # parser alive: squeeze the restore commands in before any in-flight
    # autoconnect completes
    for cmd in (b"AT+IMME0\r\n", b"AT+ROLE0\r\n"):
        s.write(cmd)
        ev("tx", cmd=cmd.decode())
        r = rd(s, 1.2)
        ev("rx_restore", cmd=cmd.decode(), rx_hex=r.hex())
    time.sleep(2.5)  # stack reboot window after ROLE change
    v1 = rd(s, 0.1)
    s.write(b"AT\r\n")
    r_at = rd(s, 1.5)
    s.write(b"AT+ROLE\r\n")
    r_role = rd(s, 1.5)
    ev("verify", at=r_at.hex(), role=r_role.hex())
    print("AT->%r ROLE->%r" % (r_at, r_role))

s.close()
verdict = ("RACE_RESTORED" if ok_at is not None and b"OK" in r_at
           else "RACE_CLRBAND_LANDED_RECONNECTED" if ok_at is not None
           else "RACE_LOST_CONNECTED" if connected_at is not None
           else "RACE_SILENT")
ev("verdict", result=verdict, ok_at=ok_at, connected_at=connected_at)
print("VERDICT: %s (clrband_ack_at=%s connected_banner_at=%s)"
      % (verdict, ok_at, connected_at))
