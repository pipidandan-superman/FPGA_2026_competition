"""B2 board runner: PL BLE block config + transparent echo loop.

Modes:
  config : overlay load -> CSR identity -> AT probe -> AT+ROLE0 (module was
           left ROLE=1 central by B1) -> soft restart -> AT re-probe
  echo   : overlay load -> echo loop for N seconds: RX ring bytes are
           replied as ACK[<bytes>] frames, every event logged to JSONL
  both   : config then echo in one process (one PL download)

Board-only (pynq). Pure ASCII. Run with /usr/local/share/pynq-venv/bin/python3.
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


def probe(d, cmd):
    reply = d.at_command(cmd)
    print("[at] %-12r -> %r" % (cmd, reply))
    return reply


def do_config(ov):
    d = BleDriver.from_overlay(ov)
    failures = 0
    d.wait_bt_ready(3.0)
    print("[pass] CSR identity + bt_ready")
    r1 = probe(d, b"AT")
    if EXPECT_OK not in r1:
        failures += 1
        print("[fail] AT probe before role change")
    r2 = probe(d, b"AT+ROLE0")
    time.sleep(0.3)
    if not r2 or b"ERROR" in r2:
        failures += 1
        print("[fail] AT+ROLE0 not accepted")
    elapsed = d.soft_restart(4.0)
    print("[info] soft_restart %.2fs" % elapsed)
    r3 = probe(d, b"AT")
    if EXPECT_OK not in r3:
        failures += 1
        print("[fail] AT probe after restart")
    st = d.status()
    print("[info] status %r" % st)
    print("B2_BOARD_CONFIG_FAIL" if failures else "B2_BOARD_CONFIG_PASS")
    return failures == 0


def do_echo(ov, seconds, ev_path):
    d = BleDriver.from_overlay(ov)
    d.wait_bt_ready(3.0)
    print("[echo] window=%ds events=%s" % (seconds, ev_path))
    deadline = time.monotonic() + seconds
    rx_frames = tx_frames = rx_bytes = tx_bytes = 0
    last_beat = time.monotonic()
    while True:
        now = time.monotonic()
        if now >= deadline:
            break
        data = d.recv(timeout=0.2)
        if data:
            reply = b"ACK[" + data + b"]"
            info = d.send_frame(reply)
            rx_frames += 1
            tx_frames += 1
            rx_bytes += len(data)
            tx_bytes += len(reply)
            log_event(ev_path, "exchange", rx_hex=data.hex(), tx_hex=reply.hex())
            print("[echo] rx %d B -> tx %d B" % (len(data), len(reply)))
        if now - last_beat >= 5.0:
            last_beat = now
            st = d.status()
            log_event(ev_path, "beat", rx_prod=st["rx_prod"],
                      rx_cons=st["rx_cons"], dropped=st["rx_dropped"],
                      frm_err=st["rx_frm_err"])
    st = d.status()
    log_event(ev_path, "final", rx_frames=rx_frames, tx_frames=tx_frames,
              rx_bytes=rx_bytes, tx_bytes=tx_bytes,
              dropped=st["rx_dropped"], frm_err=st["rx_frm_err"])
    print("[echo] done rx_frames=%d tx_frames=%d rx_bytes=%d tx_bytes=%d "
          "dropped=%d frm_err=%d" % (rx_frames, tx_frames, rx_bytes, tx_bytes,
                                     st["rx_dropped"], st["rx_frm_err"]))
    print("B2_BOARD_ECHO_DONE")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bit", required=True)
    ap.add_argument("--mode", choices=("config", "echo", "both"), default="both")
    ap.add_argument("--seconds", type=int, default=90)
    ap.add_argument("--events", default="b2_board_events.jsonl")
    args = ap.parse_args()

    ev_path = Path(args.events).resolve()
    if ev_path.exists():
        ev_path.unlink()

    ov = load_overlay(Path(args.bit).resolve())
    if args.mode in ("config", "both"):
        if not do_config(ov):
            if args.mode == "both":
                print("[abort] config failed, skipping echo")
            sys.exit(1)
    if args.mode in ("echo", "both"):
        do_echo(ov, args.seconds, ev_path)
    # drop MMIO reference cleanly before process exit
    del ov
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
