"""B3 board runner: OTA link test, board MLT (central) -> AT-09 (peripheral).

One invocation = one overlay download = one step list (--steps a,b:c,d).
Dialect lessons baked in (B1/B2): no '=' forms, non-ERROR = accepted,
ROLE change reboots module stack ~1.5s, ROLE persists across power cycle,
NEVER send AT after a successful CONN (bytes go transparent over the air).

Steps:
  at          probe AT, expect OK
  version     AT+VERSION
  name        AT+NAME
  roleq       AT+ROLE -> +ROLE=x readout
  role1       AT+ROLE1 + 2s settle + AT liveness + roleq
  role0       AT+ROLE0 + roleq
  inq[:sec]   AT+INQ, capture arg sec (default 8), dump raw scan bytes
  conn[:n]    AT+CONN<n> (default 0), capture 6s
  watch[:sec] watch RX ring arg sec (default 20), dump chunks + 5s beats, no TX
  send:TEXT   send ASCII TEXT, capture 3s reply window
  sendhex:HH  send hex bytes, capture 3s reply window
  restart     CSR soft_restart + AT verify

Log: append JSONL (given by --events) + stdout. Pure ASCII. Board only.
"""
import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from ble_driver import BleDriver

EXPECT_OK = b"OK"


def log_event(path, kind, **kw):
    event = {"t": round(time.time(), 3), "kind": kind}
    event.update(kw)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(event, ensure_ascii=True) + "\n")
    return event


def load_overlay(bit):
    from pynq import Overlay
    started = time.time()
    ov = Overlay(str(bit))
    print("[overlay] downloaded %.2fs" % (time.time() - started))
    return ov


def hexdump_lines(buf):
    out = []
    for off in range(0, len(buf), 16):
        chunk = buf[off:off + 16]
        hexs = " ".join("%02x" % b for b in chunk)
        text = "".join(chr(b) if 32 <= b < 127 else "." for b in chunk)
        out.append("  %04x  %-47s  %s" % (off, hexs, text))
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bit", required=True)
    ap.add_argument("--steps", required=True,
                    help="comma list, e.g. at,roleq,role1,inq:8,conn:0,watch:20")
    ap.add_argument("--events", default="b3_events.jsonl")
    args = ap.parse_args()

    ev_path = Path(args.events).resolve()
    log_event(ev_path, "session", argv=sys.argv)

    ov = load_overlay(Path(args.bit).resolve())
    d = BleDriver.from_overlay(ov)
    d.wait_bt_ready(3.0)
    print("[pass] CSR identity + bt_ready")

    def at(cmd, wait=2.0):
        reply = d.at_command(cmd, timeout=wait)
        print("[at] %-12r -> %r" % (cmd, reply))
        log_event(ev_path, "at", cmd=cmd.decode("latin1"),
                  rx_hex=reply.hex())
        return reply

    verdict = []
    for raw in args.steps.split(","):
        step = raw.split(":", 1)
        name, sarg = step[0], (step[1] if len(step) > 1 else None)

        if name == "at":
            r = at(b"AT")
            verdict.append("at:" + ("OK" if EXPECT_OK in r else "DEAD"))

        elif name == "version":
            at(b"AT+VERSION", wait=2.0)

        elif name == "name":
            at(b"AT+NAME", wait=2.0)

        elif name == "help":
            at(b"AT+HELP", wait=4.0)

        elif name == "laddr":
            at(b"AT+LADDR", wait=2.0)

        elif name == "uuid":
            at(b"AT+UUID", wait=2.0)

        elif name == "char":
            at(b"AT+CHAR", wait=2.0)

        elif name == "type":
            at(b"AT+TYPE", wait=2.0)

        elif name == "state":
            at(b"AT+STATE", wait=2.0)

        elif name == "start":
            # v6.1 help: "System start working" - master transparent enable?
            at(b"AT+START", wait=3.0)

        elif name == "waitconn":
            # block until the module prints Connected (CONA needs ~15-25s)
            secs = float(sarg) if sarg else 30.0
            print("[waitconn] up to %ds for Connected event" % secs)
            t0 = time.time()
            buf = b""
            up = False
            while time.time() - t0 < secs:
                data = d.recv(timeout=0.5)
                if data:
                    buf += data
                    print("[waitconn] %r" % data)
                    log_event(ev_path, "rx", rx_hex=data.hex(),
                              phase="waitconn")
                    if b"Connected" in buf:
                        up = True
                        break
            if up:
                time.sleep(1.0)
            print("[waitconn] %s after %.1fs" %
                  ("UP" if up else "TIMEOUT", time.time() - t0))
            log_event(ev_path, "waitconn", up=up)
            verdict.append("waitconn:%s" % ("UP" if up else "TO"))

        elif name == "imme":
            at(b"AT+IMME", wait=2.0)

        elif name == "imme1":
            # v6.1: boot into command-wait; transparent starts at AT+START
            r = at(b"AT+IMME1")
            ok = bool(r) and b"ERROR" not in r
            verdict.append("imme1:" + ("ACCEPTED" if ok else "REJECTED"))
            time.sleep(1.0)
            at(b"AT+IMME")

        elif name == "imme0":
            at(b"AT+IMME0")
            time.sleep(1.0)
            at(b"AT+IMME")

        elif name == "reset":
            # software reboot, then wait for the stack to come back
            at(b"AT+RESET", wait=1.0)
            time.sleep(2.5)
            r = at(b"AT")
            verdict.append("reset:" + ("OK" if EXPECT_OK in r else "DEAD"))

        elif name == "show":
            at(b"AT+SHOW", wait=3.0)

        elif name == "band":
            # vendor V4.4 doc: bind slave MAC for master auto-reconnect
            mac = (sarg or "").strip().upper()
            at(("AT+BAND" + mac).encode(), wait=2.0)

        elif name == "clrband":
            at(b"AT+CLRBAND", wait=2.0)

        elif name == "cona":
            # vendor V4.4 doc: connect direct by MAC, no scan index dance
            mac = (sarg or "").strip().upper()
            cmd = ("AT+CONA" + mac).encode()
            d.send_frame(cmd + b"\r\n")
            t0 = time.time()
            rbuf = d.recv(timeout=8.0)
            while time.time() - t0 < 10.0:
                more = d.recv(timeout=0.6)
                if not more:
                    break
                rbuf += more
            print("[cona] %r -> %d bytes:" % (cmd, len(rbuf)))
            if rbuf:
                print(hexdump_lines(rbuf))
            log_event(ev_path, "cona", cmd=cmd.decode("latin1"),
                      rx_hex=rbuf.hex())
            verdict.append("cona:%dB" % len(rbuf))

        elif name == "roleq":
            at(b"AT+ROLE", wait=2.0)

        elif name == "role1":
            r = at(b"AT+ROLE1")
            ok = bool(r) and b"ERROR" not in r
            verdict.append("role1:" + ("ACCEPTED" if ok else "REJECTED"))
            time.sleep(2.0)
            r2 = at(b"AT")
            if EXPECT_OK not in r2:
                print("[warn] AT quiet after ROLE1 (stack reboot), retry")
                time.sleep(2.0)
                at(b"AT")
            at(b"AT+ROLE")

        elif name == "role0":
            r = at(b"AT+ROLE0")
            ok = bool(r) and b"ERROR" not in r
            verdict.append("role0:" + ("ACCEPTED" if ok else "REJECTED"))
            time.sleep(1.0)
            at(b"AT+ROLE")

        elif name == "inq":
            wait_s = float(sarg) if sarg else 8.0
            d.send_frame(b"AT+INQ\r\n")
            t0 = time.time()
            buf = d.recv(timeout=1.0)
            # scan results arrive seconds after the header: honour the full
            # window, only bail early after 2.5s of silence once past half of it
            while time.time() - t0 < wait_s:
                idle = time.time() - t0 >= wait_s / 2
                more = d.recv(timeout=2.5 if idle else 0.5)
                if not more and idle:
                    break
                buf += more
            print("[inq] %d bytes in %.1fs:" % (len(buf), time.time() - t0))
            if buf:
                print(hexdump_lines(buf))
            log_event(ev_path, "inq", rx_hex=buf.hex(),
                      seconds=round(time.time() - t0, 2))
            verdict.append("inq:%dB" % len(buf))

        elif name == "connmac":
            # rescan (up to 3 rounds, RF makes the target intermittent), match
            # arg MAC (12 hex digits) against +INQ lines, connect by the index
            # this scan assigned. Never guess an index.
            import re
            mac = (sarg or "").strip().lower()
            idx = None
            for attempt in range(3):
                d.send_frame(b"AT+INQ\r\n")
                t0 = time.time()
                buf = d.recv(timeout=1.0)
                while time.time() - t0 < 14.0:
                    idle = time.time() - t0 >= 7.0
                    more = d.recv(timeout=2.5 if idle else 0.5)
                    if not more and idle:
                        break
                    buf += more
                print("[connmac] scan round %d: %d bytes" %
                      (attempt + 1, len(buf)))
                if buf:
                    print(hexdump_lines(buf))
                log_event(ev_path, "connmac_scan", attempt=attempt + 1,
                          rx_hex=buf.hex())
                m = re.search(r"\+INQ:(\d+)\s+0x([0-9A-Fa-f]{12})",
                              buf.decode("latin1"))
                if m and m.group(2).lower() == mac:
                    idx = m.group(1)
                else:
                    # fall back: any listing whose MAC equals target (all)
                    for mm in re.finditer(r"\+INQ:(\d+)\s+0x([0-9A-Fa-f]{12})",
                                          buf.decode("latin1")):
                        if mm.group(2).lower() == mac:
                            idx = mm.group(1)
                            break
                if idx is not None:
                    break
                time.sleep(2.0)
            if idx is None:
                print("[connmac] TARGET_NOT_IN_SCAN %s - NOT connecting" % mac)
                log_event(ev_path, "connmac_abort", mac=mac)
                verdict.append("connmac:NOT_FOUND")
                continue
            print("[connmac] target %s = scan index %s" % (mac, idx))
            cmd = ("AT+CONN%s" % idx).encode()
            d.send_frame(cmd + b"\r\n")
            t0 = time.time()
            rbuf = d.recv(timeout=6.0)
            while True:
                more = d.recv(timeout=0.6)
                if not more:
                    break
                rbuf += more
            print("[connmac] reply %d bytes:" % len(rbuf))
            if rbuf:
                print(hexdump_lines(rbuf))
            log_event(ev_path, "connmac_conn", idx=idx, rx_hex=rbuf.hex())
            verdict.append("connmac%s:%dB" % (idx, len(rbuf)))

        elif name == "watch":
            secs = float(sarg) if sarg else 20.0
            print("[watch] %ds ring watch (no TX)" % secs)
            deadline = time.monotonic() + secs
            last_beat = time.monotonic()
            total = 0
            while time.monotonic() < deadline:
                data = d.recv(timeout=0.2)
                if data:
                    total += len(data)
                    print("[watch] +%dB %r" % (len(data), data))
                    log_event(ev_path, "rx", rx_hex=data.hex())
                if time.monotonic() - last_beat >= 5.0:
                    last_beat = time.monotonic()
                    st = d.status()
                    log_event(ev_path, "beat", rx_prod=st["rx_prod"],
                              rx_cons=st["rx_cons"], dropped=st["rx_dropped"],
                              frm_err=st["rx_frm_err"])
                    print("[beat] prod=%d cons=%d drop=%d frm=%d" %
                          (st["rx_prod"], st["rx_cons"], st["rx_dropped"],
                           st["rx_frm_err"]))
            verdict.append("watch:%dB" % total)

        elif name == "send":
            payload = (sarg or "B3-LINK").encode("latin1")
            info = d.send_frame(payload)
            print("[send] %dB %r %.3fs" % (len(payload), payload,
                                           info["elapsed"]))
            log_event(ev_path, "tx", tx_hex=payload.hex())
            r = d.recv(timeout=3.0)
            while True:
                more = d.recv(timeout=0.5)
                if not more:
                    break
                r += more
            if r:
                print("[send] reply %r" % r)
                log_event(ev_path, "rx", rx_hex=r.hex())
            verdict.append("send:%dB,reply:%dB" % (len(payload), len(r)))

        elif name == "sendhex":
            payload = bytes.fromhex(sarg or "")
            info = d.send_frame(payload)
            print("[sendhex] %dB %s" % (len(payload), payload.hex()))
            log_event(ev_path, "tx", tx_hex=payload.hex())
            r = d.recv(timeout=3.0)
            while True:
                more = d.recv(timeout=0.5)
                if not more:
                    break
                r += more
            if r:
                print("[sendhex] reply %r" % r)
                log_event(ev_path, "rx", rx_hex=r.hex())
            verdict.append("sendhex:%dB,reply:%dB" % (len(payload), len(r)))

        elif name == "restart":
            elapsed = d.soft_restart(4.0)
            print("[info] soft_restart %.2fs" % elapsed)
            r = at(b"AT")
            verdict.append("restart:%s" %
                           ("OK" if EXPECT_OK in r else "DEAD"))

        else:
            print("[skip] unknown step %r" % name)

    print("B3_STEPS_DONE %s" % ",".join(verdict))
    log_event(ev_path, "done", verdict=verdict)
    del ov
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
