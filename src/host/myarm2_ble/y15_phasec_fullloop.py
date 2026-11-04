# Y15 Phase C: hardware-master transparent FULL LOOP test over COM4.
# Prereq: master variant bitstream flashed (y15_jtag_load_master.tcl),
# module power-cycled into hardware-master + AT+BAND autoconnect, arm-side
# AT-09 + STM32 + servo 001 powered (listen for the servo lock sound).
# Path under test (the ONLY unproven link in the whole chain):
#   PC COM4 -> CP2103 -> A16/A17 bridge -> MLT UART -> [air, MASTER GATT
#   write] -> AT-09 -> STM32 UART3 -> servo bus -> reply back the same way.
# Frame canon (10-05): '#' servo-bus frames, NO line ending, parse on '!'.
# STM32 echoes every '#' frame first (zx_uart_send_str, UART1+UART3), then
# the servo reply arrives: #001PRAD! -> #001P1498! (position count).
# Evidence layers: echo = forward path alive; #001P<digits>! = full loop.
import argparse
import json
import re
import sys
import time

import serial
import serial.tools.list_ports

TTL_VIDS = {0x1A86, 0x10C4, 0x067B, 0x0403, 0x303A}
EXCLUDE = {(0x0403, 0x6010), (0x2BDF, 0x02B2)}
REPLY_RE = re.compile(rb"#001P(\d+)!")     # servo answer, TX frame cannot match


class Log:
    def __init__(self, path):
        self.f = open(path, "a", encoding="utf-8")

    def __call__(self, kind, **kw):
        ev = {"t": round(time.time(), 3), "kind": kind}
        ev.update(kw)
        self.f.write(json.dumps(ev, ensure_ascii=True) + "\n")
        self.f.flush()
        return ev


def pick_port(want):
    cands = [p.device for p in serial.tools.list_ports.comports()
             if p.vid in TTL_VIDS and (p.vid, p.pid) not in EXCLUDE]
    if want:
        return want
    return cands[0] if len(cands) == 1 else None


def observe(s, secs, log, phase):
    buf = b""
    t0 = time.time()
    last_beat = t0
    while time.time() - t0 < secs:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            print("[%s +%.1fs] %r" % (phase, time.time() - t0, chunk))
            log("rx", phase=phase, rx_hex=chunk.hex())
        if time.time() - last_beat >= 5.0:
            last_beat = time.time()
            print("[%s] ... %.0fs total=%dB" % (phase, time.time() - t0,
                                                len(buf)))
    return buf


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM4")
    ap.add_argument("--baud", type=int, default=9600,
                    help="MUST match the Phase A locked baud")
    ap.add_argument("--watch", type=float, default=30.0,
                    help="passive post-flash watch window for the BAND "
                         "autoconnect (default 30s)")
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--frame", default="#001PRAD!")
    ap.add_argument("--motion", action="store_true",
                    help="opt-in smoke: 001 -> 1580 -> 1500 @T500 (160 "
                         "counts/s, above the 150 rule), then PRAD verify")
    ap.add_argument("--events", default="y15_phaseC_events.jsonl")
    args = ap.parse_args()

    port = pick_port(args.port)
    if not port or port.upper() == "COM1":
        print("REFUSED_OR_MISSING port=%r" % port)
        return 2
    log = Log(args.events)
    log("session", argv=sys.argv)
    s = serial.Serial(port, args.baud, bytesize=8, parity="N", stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()

    # -- phase 1: watch the autoconnect happen (banner/noise or silence)
    print("=== watch %.0fs @%d (BAND autoconnect window) ==="
          % (args.watch, args.baud))
    banner = observe(s, args.watch, log, "watch")

    # -- phase 2: PRAD round-trips
    frame = args.frame.encode()
    echo_seen = False
    full_seen = False
    pos_last = None
    for i in range(args.rounds):
        s.reset_input_buffer()
        s.write(frame)
        print("--- round %d TX %r ---" % (i + 1, frame))
        log("tx", round=i + 1, tx_hex=frame.hex())
        rx = observe(s, 8.0, log, "round%d" % (i + 1))
        if frame in rx:
            echo_seen = True
        m = REPLY_RE.search(rx)
        if m:
            full_seen = True
            pos_last = int(m.group(1))
        time.sleep(1.0)

    verdict = ("Y15_FULL_LOOP_PASS" if full_seen else
               "Y15_FORWARD_ONLY" if echo_seen else
               "Y15_AIR_DEAD")

    # -- optional motion smoke (needs arm power, rule: |err| <= 10 counts)
    motion = None
    if args.motion and verdict != "Y15_AIR_DEAD":
        for mv in ("#001P1580T500!", "#001P1500T500!"):
            s.reset_input_buffer()
            s.write(mv.encode())
            print("--- motion TX %r (wait 1.2s) ---" % mv)
            log("tx", motion=mv)
            observe(s, 1.2, log, "motion")
            time.sleep(0.6)
        s.reset_input_buffer()
        s.write(frame)
        log("tx", motion_readback=True)
        rx = observe(s, 5.0, log, "motion_verify")
        m = REPLY_RE.search(rx)
        motion = bool(m) and abs(int(m.group(1)) - 1500) <= 10
        if m:
            print("motion readback: %d (target 1500)" % int(m.group(1)))

    s.close()
    log("verdict", result=verdict, echo_seen=echo_seen, full_seen=full_seen,
        pos_last=pos_last, motion_ok=motion, banner_hex=banner.hex())
    print("VERDICT: %s (echo=%s full=%s pos=%s motion=%s)"
          % (verdict, echo_seen, full_seen, pos_last, motion))
    if verdict == "Y15_AIR_DEAD":
        print("split: run b3_com5_watch.py on COM5 (STM32 UART1 dual-send "
              "port, single instance only, DTR/RTS suppressed in that "
              "script) - COM5 loud = air segment dead, COM5 silent = "
              "master GATT write never happened")
    return 0 if verdict == "Y15_FULL_LOOP_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
