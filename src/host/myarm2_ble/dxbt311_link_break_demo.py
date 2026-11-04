# Live link-break demonstration, user-requested 2026-10-08.
# Proves the servo data's ONLY path is the 0214->013a BLE radio link:
#   act 1: PRAD over the live link          -> servo answer expected
#   act 2: AT+DISC cuts the radio link      -> +Disconnect>> expected
#   act 3: PRAD with the link down          -> NO servo answer (dead air)
#   act 4: BIND auto-reconnect (or CONA if DISC does not trigger it)
#          then PRAD again                  -> servo answer returns
# The judge line for "servo answer" is the real-data pattern
# '#001P<digits>!' - an AT-state UART echo of our own frame does not count.
# Usage: D:\work\Python\python.exe dxbt311_link_break_demo.py [--port COM4]
import json
import re
import sys
import time

import serial

PORT = "COM4"
MAC = "98EAA021013A"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

LOG = (r"E:\competition\4_metrics\logs"
       r"\2026-10-08_dxbt311_dual_webotpi_pass_run01\dxbt311_link_break_events.jsonl")
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
    print("   [tx] %-24r -> %r" % (frame, r))
    return r


def answered(buf):
    return re.search(rb"#001P\d{4}!", buf) is not None


print("--- link-break demo %s ---" % time.strftime("%F %T"))
ev("session", mac=MAC)
s = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1,
                  timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

print("[act 1] baseline: PRAD over the live link")
a1 = answered(send(s, b"#001PRAD!", 2.5))
print("   servo answer seen: %s" % a1)
ev("act1", answered=a1)

print("[act 2] cut the radio link: AT+DISC (retry x3 with idle gaps -")
print("        the transparent-state escape is timing-sensitive: worked")
print("        19:26, silently forwarded 19:40)")
cut = False
for attempt in range(3):
    time.sleep(1.5)
    s.reset_input_buffer()
    r = send(s, b"AT+DISC", 6.0)
    if b"Disconnect" in r:
        cut = True
        break
    print("   attempt %d: no +Disconnect (rx=%r)" % (attempt + 1, r))
print("   link cut: %s" % cut)
ev("act2", cut=cut)
if not cut:
    print("ABORT: escape refused; use the physical variant (pull 0214 VCC)")
    ev("verdict", v="LINK_BREAK_DEMO_DISC_REFUSED")
    s.close()
    sys.exit(1)

print("[act 3] PRAD with the link down (twice, immediately)")
dead = True
for i in range(2):
    if answered(send(s, b"#001PRAD!", 2.0)):
        dead = False
        break
print("   dead air confirmed: %s" % dead)
ev("act3", dead=dead)

print("[act 4] rebuild: watch BIND auto-reconnect (<=20 s), else CONA")
buf = b""
conn = None
t0 = time.time()
while time.time() - t0 < 20.0:
    c = rd(s, 1.0)
    if c:
        buf += c
        print("   [rx] %r" % c)
        ev("watch_rx", rx=c.decode("ascii", "replace"))
        if b"Connected" in c:
            conn = "auto"
            break
how = None
if conn == "auto":
    how = "BIND auto-reconnect"
else:
    print("   no auto-reconnect after DISC -> manual AT+CONA rebuild")
    s.write(b"AT+CONA" + MAC.encode() + b"\r\n")
    ev("cmd", cmd="AT+CONA" + MAC)
    t0 = time.time()
    while time.time() - t0 < 30.0:
        c = rd(s, 1.0)
        if c:
            buf += c
            print("   [rx] %r" % c)
            ev("conn_rx", rx=c.decode("ascii", "replace"))
            if b"Connected" in c:
                conn = "cona"
                break
    how = "manual CONA" if conn else None
print("   rebuilt via: %s" % how)
ev("act4", rebuilt=how)

time.sleep(1.0)
s.reset_input_buffer()
print("[final] PRAD again on the rebuilt link")
a4 = answered(send(s, b"#001PRAD!", 2.5))
print("   servo answer seen: %s" % a4)
ev("final", answered=a4)
s.close()

ok = a1 and cut and dead and conn and a4
v = "LINK_BREAK_DEMO_PASS" if ok else "LINK_BREAK_DEMO_INCOMPLETE"
print("VERDICT: %s (alive=%s cut=%s dead=%s rebuilt=%s alive_again=%s)" %
      (v, a1, cut, dead, how, a4))
ev("verdict", v=v, alive=a1, cut=cut, dead=dead, rebuilt=how, alive_again=a4)
sys.exit(0 if ok else 1)
