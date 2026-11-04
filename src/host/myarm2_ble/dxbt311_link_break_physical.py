# Physical link-break demonstration, user-requested 2026-10-08.
# Context: the AT+DISC transparent-state escape is swallowed on a
# BIND-auto-reconnected link (3x retry, all silent) while it worked on a
# CONA-established link earlier the same day - recorded as a deployment
# fact: no AT route to disconnect in the deployed state.
# This variant kills the TRANSMITTER instead: the script sends #001PRAD!
# every ~1.5 s for 100 s and records the alive/dead timeline while the
# user pulls the 0214 VCC dupont for ~3 s and re-plugs it. NO connect
# command is ever sent - recovery can only be the stored BIND
# auto-reconnect.
# PASS = alive -> dead -> alive transitions all observed in the window.
# Usage: D:\work\Python\python.exe dxbt311_link_break_physical.py [--port COM4]
import json
import re
import sys
import time

import serial

PORT = "COM4"
if "--port" in sys.argv:
    PORT = sys.argv[sys.argv.index("--port") + 1]

WINDOW = 100.0
LOG = (r"E:\competition\4_metrics\logs"
       r"\2026-10-08_dxbt311_dual_webotpi_pass_run01\dxbt311_link_break_events.jsonl")
log = open(LOG, "a", encoding="utf-8")


def ev(kind, **kw):
    e = {"t": round(time.time(), 3), "kind": kind}
    e.update(kw)
    log.write(json.dumps(e, ensure_ascii=True) + "\n")
    log.flush()


print("--- physical link-break demo %s ---" % time.strftime("%F %T"))
print("ACTION: pull the 0214 VCC dupont for ~3 s, then re-plug.")
print("        (window %d s, PRAD every ~1.5 s, no connect commands)" % WINDOW)
ev("session", window=WINDOW)
s = serial.Serial(PORT, 115200, bytesize=8, parity="N", stopbits=1,
                  timeout=0.02)
time.sleep(0.2)
s.reset_input_buffer()

samples = []
t0 = time.time()
last = None
n = 0
while time.time() - t0 < WINDOW:
    s.write(b"#001PRAD!")
    buf = b""
    tt = time.time()
    while time.time() - tt < 1.3:
        c = s.read(512)
        if c:
            buf += c
    alive = re.search(rb"#001P\d{4}!", buf) is not None
    at = round(time.time() - t0, 1)
    samples.append((at, alive))
    ev("sample", at=at, alive=alive, rx=buf.decode("ascii", "replace")[:60])
    if alive != last:
        print("[%6.1fs] %s" % (at, "ALIVE (servo answering)" if alive
                               else "DEAD  (no servo answer)"))
        last = alive
    n += 1
    if n % 10 == 0:
        print("[%6.1fs] ... (still %s)" % (at, "alive" if alive else "dead"))
s.close()

# transitions
dead_seen = alive_seen = False
first_dead = first_alive = None
for at, a in samples:
    if not a:
        dead_seen = True
        first_dead = first_dead or at
    if dead_seen and a:
        alive_seen = True
        first_alive = first_alive or at
pre_alive = samples and samples[0][1]

ok = pre_alive and dead_seen and alive_seen
v = "PHYSICAL_BREAK_DEMO_PASS" if ok else "PHYSICAL_BREAK_DEMO_INCOMPLETE"
print("timeline: alive-at-start=%s first-dead=%s first-alive-again=%s" %
      (pre_alive, first_dead, first_alive))
print("VERDICT: %s (%d samples)" % (v, len(samples)))
ev("verdict", v=v, samples=len(samples), pre_alive=pre_alive,
   first_dead=first_dead, first_alive_again=first_alive)
sys.exit(0 if ok else 1)
