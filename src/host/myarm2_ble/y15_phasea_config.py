# Y15 Phase A: configure the on-board MLT for hardware-master bring-up.
# Runs against the CANON bridge bitstream (y15_jtag_load_canon.tcl): module
# boots SLAVE (Y15 floats), AT control plane alive on COM4 (CP2103).
# Configures AT+BAND <arm-side AT-09 MAC> so that, once the MASTER variant
# bitstream is flashed (Y15 high -> P0_6 hardware master), the module
# auto-reconnects to the arm on power-up and runs master transparent.
# Dialect lessons baked in (B1/B2/B3): no '=' forms, ROLE/IMME-class replies
# '+ROLE=x' not OK, accept non-ERROR as accepted, stack may reboot ~1-2s
# after ROLE changes.
# SAFETY: COM1 (native RS232 +/-12V) refused; FT2232/camera UART excluded.
import argparse
import json
import sys
import time

import serial
import serial.tools.list_ports

TTL_VIDS = {0x1A86, 0x10C4, 0x067B, 0x0403, 0x303A}   # CH340/CP210x/PL2303/FTDI/ESP
EXCLUDE = {(0x0403, 0x6010), (0x2BDF, 0x02B2)}         # EES-331 FT2232, camera composite
BAUDS = (9600, 115200)


def pick_port(want):
    cands = []
    for p in serial.tools.list_ports.comports():
        if p.vid is None or (p.vid, p.pid) in EXCLUDE or p.vid not in TTL_VIDS:
            continue
        cands.append(p.device)
    print("candidates: %s" % ",".join(cands) if cands else "no TTL candidates")
    if want:
        return want
    if len(cands) == 1:
        return cands[0]
    print("PORT_AMBIGUOUS_OR_MISSING (use --port COMx)")
    return None


class Log:
    def __init__(self, path):
        self.f = open(path, "a", encoding="utf-8")

    def __call__(self, kind, **kw):
        ev = {"t": round(time.time(), 3), "kind": kind}
        ev.update(kw)
        self.f.write(json.dumps(ev, ensure_ascii=True) + "\n")
        self.f.flush()
        return ev


def session(port, baud):
    s = serial.Serial(port, baud, bytesize=8, parity="N", stopbits=1, timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()
    return s


def send(s, cmd, wait_s=1.8, log=None):
    tx = (cmd + "\r\n").encode()
    s.write(tx)
    buf = b""
    t_end = time.time() + wait_s
    while time.time() < t_end:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            t_end = time.time() + 0.4
    print("[@%-6d] TX %-22r RX %r" % (s.baudrate, cmd, buf))
    if log:
        log("at", cmd=cmd, rx_hex=buf.hex())
    return buf


def ok(reply):
    return bool(reply) and b"OK" in reply


def accepted(reply):
    return bool(reply) and b"ERROR" not in reply


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", default="COM4")
    ap.add_argument("--mac", default="D0B5C28DEB49",
                    help="arm-side AT-09 MAC for AT+BAND")
    ap.add_argument("--events", default="y15_phaseA_events.jsonl")
    args = ap.parse_args()

    port = pick_port(args.port)
    if not port or port.upper() == "COM1":
        print("REFUSED_OR_MISSING port=%r" % port)
        return 2
    log = Log(args.events)
    log("session", argv=sys.argv)

    # -- baud autodetect: the bridge has no baud logic, COM4 must match module.
    # Two tries per baud: the first AT can land inside the module boot window
    # (bridge READY at ~1.1s after JTAG config, stack boot after that).
    ser = None
    baud = None
    for b in BAUDS:
        for attempt in range(2):
            s = session(port, b)
            r = send(s, "AT", log=log)
            if ok(r):
                ser, baud = s, b
                break
            s.close()
            time.sleep(1.0)
        if ser is not None:
            break
    if ser is None:
        log("verdict", result="PHASEA_AT_DEAD_BOTH_BAUDS")
        print("VERDICT: PHASEA_AT_DEAD_BOTH_BAUDS (module not in AT mode? "
              "canon bit flashed? bridge powered?)")
        return 1
    log("baud_lock", baud=baud)
    print("baud locked: %d" % baud)

    # -- readbacks
    r_ver = send(ser, "AT+VERSION", log=log)
    r_role = send(ser, "AT+ROLE", log=log)
    r_imme = send(ser, "AT+IMME", log=log)

    # -- IMME must be 0 (boot straight into transparent, not command-wait)
    imme0 = b"+IMME=0" in r_imme or (b"IMME" not in r_imme and accepted(r_imme))
    if not imme0:
        send(ser, "AT+IMME0", log=log)
        time.sleep(1.2)
        r_imme2 = send(ser, "AT+IMME", log=log)
        imme0 = b"+IMME=0" in r_imme2 or accepted(r_imme2)

    # -- clear any stale binding, then bind the arm-side AT-09
    send(ser, "AT+CLRBAND", log=log)
    time.sleep(0.8)
    band_cmd = "AT+BAND" + args.mac.upper()
    r_band = send(ser, band_cmd, wait_s=2.5, log=log)
    band_ok = accepted(r_band)
    role_bumped = False
    if not band_ok:
        # fallback per B3: BAND may only be accepted in master role
        print("[fallback] BAND rejected in current role -> ROLE1 -> retry")
        r_r1 = send(ser, "AT+ROLE1", log=log)
        role_bumped = accepted(r_r1)
        time.sleep(2.5)                       # stack reboot window (B1 lesson)
        send(ser, "AT", log=log)
        r_band = send(ser, band_cmd, wait_s=2.5, log=log)
        band_ok = accepted(r_band)
        if role_bumped:
            send(ser, "AT+ROLE0", log=log)    # BAND persists; restore B2 canon
            time.sleep(2.0)

    # -- final liveness
    r_alive = send(ser, "AT", log=log)
    alive = ok(r_alive)
    ser.close()

    verdict = "PHASEA_CONFIG_PASS" if (alive and band_ok and imme0) \
        else "PHASEA_CONFIG_FAIL"
    log("verdict", result=verdict, baud=baud, band_ok=band_ok,
        imme0=imme0, alive=alive, role_bumped=role_bumped)
    print("VERDICT: %s (baud=%d band_ok=%s imme0=%s alive=%s role_bumped=%s)"
          % (verdict, baud, band_ok, imme0, alive, role_bumped))
    print("NEXT: flash master variant (y15_jtag_load_master.tcl); module "
          "power-cycles into hardware-master + BAND autoconnect")
    return 0 if verdict == "PHASEA_CONFIG_PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
