# FPGA direct servo-bus control bench probe (light servo_bridge_top bit).
# PC -> COM4 (J8-upper CP2103) -> FPGA uart_rx -> T21 half-duplex pad
# -> servo chain. Everything the pad hears comes back on COM4:
# the electrical echo of our own frame FIRST, then the servo reply.
#   --listen N    G1: silent listen for N s (foreign-traffic detector;
#                 any frame heard = STM32 still on the net -> ABORT)
#   (default)     G3: send #001PRAD! and require the real servo reply
#   --move        G4: authorized small motion 1500-base +80 @T500 and
#                 return, then PRAD verify (small-travel rule T<=500,
#                 >=150 counts/s; 80/0.5s = 160 counts/s)
# Wiring preconditions (see checklist): STM32 off the signal net,
# servo V+ fed externally, common GND via J5-33.
import argparse
import json
import re
import sys
import time
from pathlib import Path

import serial  # D:\work\Python pyserial

PORT_DEFAULT = "COM4"
BAUD = 115200
LOG_DIR = r"E:\competition\4_metrics\logs\2026-10-05_fpga_servo_bridge_run01"
SID = 1
DELTA = 80
T_MS = 500


def log(path, kind, **kw):
    ev = {"t": round(time.time(), 3), "kind": kind}
    ev.update(kw)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, ensure_ascii=True) + "\n")
    return ev


def parse_pos(events, sid):
    pat = re.compile(r"#%03dP(\d{4})!" % sid)
    for e in reversed(events):
        m = pat.search(e.get("ascii", ""))
        if m:
            return int(m.group(1))
    return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default=PORT_DEFAULT)
    ap.add_argument("--listen", type=float, default=0.0,
                    help="G1: just listen this many seconds")
    ap.add_argument("--move", action="store_true",
                    help="G4: authorized small motion + return")
    args = ap.parse_args()

    out = Path(LOG_DIR)
    out.mkdir(parents=True, exist_ok=True)
    ev = out / "fpga_servo_events.jsonl"
    events = []

    ser = serial.Serial(args.port, BAUD, timeout=0.1)
    print("--- fpga servo bridge probe port=%s baud=%d ---" %
          (args.port, BAUD))
    log(ev, "session", port=args.port, baud=BAUD,
        listen=args.listen, move=args.move)

    def drain(label, seconds):
        t_end = time.time() + seconds
        while time.time() < t_end:
            data = ser.read(256)
            if data:
                rec = {"t": round(time.time(), 3), "hex": data.hex(),
                       "ascii": data.decode("latin1")}
                events.append(rec)
                print("[%s] %r" % (label, data))
                log(ev, "rx", **rec)

    def send(frame, listen_s):
        print("[tx] %r" % frame)
        log(ev, "tx", frame=frame.decode())
        ser.reset_input_buffer()
        ser.write(frame)
        drain("rx", listen_s)

    try:
        if args.listen > 0:
            print("--- G1: silent listen %.1f s ---" % args.listen)
            drain("g1", args.listen)
            heard = [e["ascii"] for e in events if e["ascii"].strip()]
            v = "G1_FOREIGN_TRAFFIC_SEEN" if heard else "G1_SILENT"
            print("VERDICT: %s (%d frames heard)" % (v, len(heard)))
            log(ev, "verdict", v=v, heard=heard)
            return 0 if not heard else 2

        # G3: read position through the FPGA bridge
        send(b"#%03dPRAD!" % SID, 2.0)
        pos0 = parse_pos(events, SID)
        print("[read] servo %03d pos = %s" % (SID, pos0))
        log(ev, "read_pos", pos=pos0)
        if pos0 is None:
            print("VERDICT: FPGA_SERVO_NO_REPLY")
            log(ev, "verdict", v="FPGA_SERVO_NO_REPLY")
            return 1
        print("VERDICT: FPGA_SERVO_PRAD_PASS (pos=%d)" % pos0)
        log(ev, "verdict", v="FPGA_SERVO_PRAD_PASS", pos=pos0)

        if not args.move:
            return 0

        # G4: authorized small motion, then back, then verify
        tgt = min(max(pos0 + DELTA, 600), 2400)
        if not (600 <= tgt <= 2400):
            print("[abort] target %d out of safe range" % tgt)
            return 1
        events.clear()
        send(b"#%03dP%04dT%04d!" % (SID, tgt, T_MS),
             T_MS / 1000.0 + 1.5)
        moved = parse_pos(events, SID) or tgt
        print("[moved] mid pos = %s (target %d)" % (moved, tgt))
        log(ev, "mid_pos", pos=moved, target=tgt)

        events.clear()
        send(b"#%03dP%04dT%04d!" % (SID, pos0, T_MS),
             T_MS / 1000.0 + 1.5)

        events.clear()
        send(b"#%03dPRAD!" % SID, 2.0)
        posf = parse_pos(events, SID)
        print("[final] pos = %s (start %s)" % (posf, pos0))
        log(ev, "final_pos", pos=posf, start=pos0)

        ok = (posf is not None and abs(posf - pos0) <= 10
              and abs(moved - tgt) <= 10)
        v = "FPGA_MOTION_PASS" if ok else "FPGA_MOTION_CHECK"
        print("VERDICT: %s (start=%s mid=%s final=%s)" %
              (v, pos0, moved, posf))
        log(ev, "verdict", v=v, start=pos0, mid=moved, final=posf)
        return 0 if ok else 1
    finally:
        ser.close()


if __name__ == "__main__":
    sys.exit(main())
