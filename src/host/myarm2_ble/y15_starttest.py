# Y15 fallback: software master + IMME1 command-mode + AT+START engage.
# The one untested matrix cell from B3: START was only ever sent in IMME0
# transparent states (eaten as data) or unconnected (ERROR). IMME1 keeps
# the AT parser alive AFTER connection, so AT+START can be delivered as a
# real command to a CONNECTED master. If the engine engages, '#001PRAD!'
# should round-trip to the arm.
# Flow: ROLE1 -> IMME1 -> BAND bind -> RESET (both take effect) -> watch
# autoconnect (command-wait may suspend it) -> CONA direct connect ->
# wait Connected -> AT+START -> send #001PRAD! x3 -> verdict.
import json
import re
import sys
import time

import serial

MAC = "D0B5C28DEB49"
REPLY_RE = re.compile(rb"#001P(\d+)!")


def logf(path):
    def log(kind, **kw):
        ev = {"t": round(time.time(), 3), "kind": kind}
        ev.update(kw)
        with open(path, "a", encoding="utf-8") as f:
            f.write(json.dumps(ev, ensure_ascii=True) + "\n")
    return log


def send(s, cmd, wait_s=2.5, log=None, label=None):
    s.write((cmd + "\r\n").encode())
    buf = b""
    t_end = time.time() + wait_s
    while time.time() < t_end:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            t_end = time.time() + 0.5
    print("[TX %-22r] RX %r" % (label or cmd, buf))
    if log:
        log("at", cmd=cmd, rx_hex=buf.hex())
    return buf


def watch(s, secs, log=None, label="watch"):
    t0 = time.time()
    buf = b""
    while time.time() - t0 < secs:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            print("[%s +%.1fs] %r" % (label, time.time() - t0, chunk))
            if log:
                log("rx", phase=label, rx_hex=chunk.hex())
    return buf


def main():
    log = logf("y15_starttest_events.jsonl")
    s = serial.Serial("COM4", 9600, bytesize=8, parity="N", stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()
    log("session", argv=sys.argv)

    r = send(s, "AT", log=log)
    if b"OK" not in r:
        print("VERDICT: AT_DEAD")
        return 1

    send(s, "AT+ROLE1", wait_s=2.0, log=log)
    time.sleep(2.5)                      # stack reboot window
    send(s, "AT", log=log)
    r_band = send(s, "AT+BAND" + MAC, wait_s=2.5, log=log)
    send(s, "AT+IMME1", wait_s=2.0, log=log)
    send(s, "AT+RESET", wait_s=1.0, log=log)
    time.sleep(2.5)                      # reboot with ROLE1+IMME1+BAND
    send(s, "AT", log=log)

    # autoconnect watch: command-wait may or may not run BAND autoconnect
    buf = watch(s, 20.0, log=log, label="autoconn")
    connected = b"Connected" in buf

    if not connected:
        send(s, "AT+CONA" + MAC, wait_s=3.0, log=log)
        buf = watch(s, 30.0, log=log, label="cona")
        connected = b"Connected" in buf

    print("connected=%s" % connected)
    log("link", connected=connected)
    if not connected:
        print("VERDICT: Y15_STARTTEST_NO_CONN")
        return 1

    # connected, still command mode (IMME1): deliver START as a real command
    time.sleep(1.0)
    r_start = send(s, "AT+START", wait_s=3.0, log=log)
    print("START -> %r" % r_start)
    time.sleep(1.0)

    full = False
    pos = None
    for i in range(3):
        s.reset_input_buffer()
        s.write(b"#001PRAD!")
        log("tx", round=i + 1, tx_hex=b"#001PRAD!".hex())
        rx = watch(s, 8.0, log=log, label="round%d" % (i + 1))
        m = REPLY_RE.search(rx)
        if m:
            full = True
            pos = int(m.group(1))
        time.sleep(1.0)

    verdict = "Y15_MASTER_START_FULL_LOOP_PASS" if full else \
              ("Y15_START_OK_DATA_STILL_DEAD" if b"ERROR" not in r_start
               else "Y15_START_REJECTED")
    log("verdict", result=verdict, start_reply_hex=r_start.hex(), pos=pos)
    print("VERDICT: %s (pos=%s)" % (verdict, pos))
    return 0 if full else 1


if __name__ == "__main__":
    sys.exit(main())
