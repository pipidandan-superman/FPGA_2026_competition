# B3 air-config: configure the arm-side AT-09 (D0:B5:C2:8D:EB:49, name BT05)
# from the PC over BLE GATT, no wires. Family contract (B2-proven on the
# board MLT): service FFE0, characteristic FFE1 = write+notify, one central.
# Probe mode (default): AT / AT+VERSION / AT+NAME / AT+ROLE over the air.
# --apply: additionally AT+BAUD8 (UART -> 115200) + AT re-probe, ONLY if the
# plain AT probe answered OK in this same run. Log JSONL + stdout.
import argparse
import asyncio
import json
import sys
import time
from pathlib import Path

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
FFE0 = "0000ffe0-0000-1000-8000-00805f9b34fb"
LOG_DIR = r"E:\competition\4_metrics\logs\2026-10-04_myarm2_b3_at09_air_config_run01"


def log(path, kind, **kw):
    ev = {"t": round(time.time(), 3), "kind": kind}
    ev.update(kw)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(json.dumps(ev, ensure_ascii=True) + "\n")
    return ev


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true",
                    help="after a live AT probe, send AT+BAUD8 + re-probe")
    args = ap.parse_args()

    out = Path(LOG_DIR)
    out.mkdir(parents=True, exist_ok=True)
    ev = out / "air_config_events.jsonl"

    rx_buf = bytearray()
    write_with_response = True

    def on_notify(_handle, data):
        rx_buf.extend(data)
        print("[notify] +%dB %r" % (len(data), bytes(data)))

    async def safe_write(client, data):
        # WinRT: wrong write mode for the char's properties -> protocol
        # error; try with-response then without, remember what worked (B2
        # pc_link_ble.py canon).
        nonlocal write_with_response
        for response in (write_with_response, not write_with_response):
            try:
                await client.write_gatt_char(FFE1, data, response=response)
                write_with_response = response
                return
            except Exception as exc:
                print("[write] mode response=%s failed: %r" % (response, exc))
                await asyncio.sleep(0.2)
        raise RuntimeError("both write modes rejected")

    async def send(client, cmd, wait_s=1.5):
        rx_buf.clear()
        payload = (cmd + "\r\n").encode()
        await safe_write(client, payload)
        t0 = time.time()
        while time.time() - t0 < wait_s and not rx_buf:
            await asyncio.sleep(0.05)
        await asyncio.sleep(0.3)
        reply = bytes(rx_buf)
        print("[at] %-12r -> %r" % (cmd, reply))
        log(ev, "at", cmd=cmd, rx_hex=reply.hex())
        return reply

    print("--- B3 air-config %s  target %s ---" % (time.strftime("%F %T"),
                                                   TARGET))
    log(ev, "session", target=TARGET, apply=args.apply)
    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected, mtu=%s" % client.mtu_size)
        log(ev, "connected", mtu=client.mtu_size)
        chars = [str(c.uuid) for s in client.services for c in s.characteristics]
        print("[gatt] %s" % chars)
        log(ev, "gatt", services=chars)
        if FFE1 not in chars:
            print("VERDICT: B3_AIR_FFE1_MISSING")
            log(ev, "verdict", v="B3_AIR_FFE1_MISSING")
            return 1
        for s in client.services:
            for c in s.characteristics:
                if str(c.uuid).lower() == FFE1:
                    print("[gatt] FFE1 props=%s handles %04X->%04X"
                          % (c.properties, c.handle,
                             (c.handle + 1) if c.handle else 0))
                    log(ev, "ffe1_props", props=[str(p) for p in c.properties],
                        handle=c.handle)
        await client.start_notify(FFE1, on_notify)

        r_at = await send(client, "AT")
        at_ok = b"OK" in r_at
        await send(client, "AT+VERSION")
        await send(client, "AT+NAME")
        await send(client, "AT+ROLE")

        if not at_ok:
            print("VERDICT: B3_AIR_AT_SILENT (firmware ignores air-side AT)")
            log(ev, "verdict", v="B3_AIR_AT_SILENT")
            return 1
        if not args.apply:
            print("VERDICT: B3_AIR_AT_ALIVE (re-run with --apply to set baud)")
            log(ev, "verdict", v="B3_AIR_AT_ALIVE")
            return 0

        r_baud = await send(client, "AT+BAUD8", wait_s=2.5)
        log(ev, "baud8", rx_hex=r_baud.hex())
        await asyncio.sleep(1.5)
        r_at2 = await send(client, "AT")
        ok2 = b"OK" in r_at2
        v = "B3_AIR_CONFIG_PASS" if ok2 else "B3_AIR_BAUD_UNCONFIRMED"
        print("VERDICT: %s" % v)
        log(ev, "verdict", v=v, baud8_reply=r_baud.hex(), at_after=r_at2.hex())
        return 0 if ok2 else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
