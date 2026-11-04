"""PC-side BLE link test: connect to the module, exchange frames on FFE1.

Chain: PC writes payload to FFE1 -> module UART -> FPGA ble_uart_0 RX ring ->
board script replies ACK[<payload>] -> module UART <- FPGA TX -> notify to PC.

Success = every round's payload comes back inside an ACK[...] notification.
Windows bleak; run with D:\\work\\Python\\python.exe.
"""
import argparse
import asyncio
import json
import time
from pathlib import Path

from bleak import BleakClient


def pick_char(services):
    """FFE0/FFE1 first; else any characteristic with notify."""
    fallback = None
    for s in services:
        su = str(s.uuid).lower()
        for c in s.characteristics:
            cu = str(c.uuid).lower()
            props = [str(p).lower() for p in c.properties]
            if "ffe0" in su and "ffe1" in cu:
                return c, "ffe1"
            if fallback is None and "notify" in props:
                fallback = c
    return fallback, "fallback"


def payload_received(rx_concat, payload):
    """Board ACKs each UART burst chunk separately (ACK[chunk] per chunk),
    so a long payload comes back as several ACK[...] fragments. Strip the
    wrappers and check the payload reassembles."""
    stripped = rx_concat.replace(b"ACK[", b"").replace(b"]", b"")
    return payload in stripped or payload in rx_concat


async def safe_write(client, char, data, prefer_response):
    """Try the preferred write mode, fall back to the other once."""
    last = None
    for response in (prefer_response, not prefer_response):
        try:
            await client.write_gatt_char(char, data, response=response)
            return response
        except Exception as exc:  # WinRT E_INVALIDARG on wrong mode, busy
            last = exc
            await asyncio.sleep(0.2)
    raise last


async def amain(args):
    events = []
    rx_buf = bytearray()
    rx_log = []

    def on_notify(sender, data):
        nonlocal rx_buf
        rec = dict(t=round(time.time(), 3), hex=data.hex())
        rx_log.append(rec)
        events.append(dict(kind="notify", **rec))
        rx_buf.extend(data)
        print("[notif] %d B %s" % (len(data), data.hex()))

    async with BleakClient(args.address, timeout=args.connect_timeout) as client:
        print("[link] connected: %s  mtu=%s" % (args.address, client.mtu_size))
        events.append(dict(kind="connect", t=round(time.time(), 3),
                           address=args.address, mtu=client.mtu_size))
        char, how = pick_char(client.services)
        if char is None:
            print("[fail] no usable characteristic (ffe1 or notify)")
            print("PC_BLE_LINK_FAIL")
            return 2
        print("[link] characteristic %s (%s) props=%s"
              % (char.uuid, how, [str(p) for p in char.properties]))
        events.append(dict(kind="char", t=round(time.time(), 3),
                           uuid=str(char.uuid), picked=how,
                           props=[str(p) for p in char.properties]))
        await client.start_notify(char, on_notify)
        props = [str(p).lower() for p in char.properties]
        prefer_response = "write" in props

        rounds = []
        for i in range(args.rounds):
            payload = ("PC_LINK_R%d_%s" % (i, "P" * (8 + 8 * i))).encode()
            rx_buf.clear()
            events.append(dict(kind="tx", t=round(time.time(), 3),
                               round=i, hex=payload.hex()))
            used = None
            for pos in range(0, len(payload), args.chunk):
                piece = payload[pos:pos + args.chunk]
                used = await safe_write(client, char, piece, prefer_response)
                await asyncio.sleep(args.chunk_gap)
            print("[tx] round %d: %d B in %d chunks (response=%s)"
                  % (i, len(payload),
                     (len(payload) + args.chunk - 1) // args.chunk, used))
            deadline = time.monotonic() + args.round_timeout
            got = False
            while time.monotonic() < deadline:
                if payload_received(bytes(rx_buf), payload):
                    got = True
                    break
                await asyncio.sleep(0.1)
            rounds.append(dict(round=i, payload_hex=payload.hex(),
                               response_mode=used, got=got))
            events.append(dict(kind="round", t=round(time.time(), 3),
                               round=i, got=got))
            print("[round %d] %s" % (i, "PASS" if got else "FAIL"))
            await asyncio.sleep(0.3)
        await client.stop_notify(char)

    ok = all(r["got"] for r in rounds) and rounds
    report = dict(t=round(time.time(), 3), address=args.address,
                  rounds=rounds, notifications=rx_log, verdict_ok=bool(ok))
    Path(args.out).write_text(json.dumps(report, indent=1), encoding="utf-8")
    Path(args.out + ".events.jsonl").write_text(
        "\n".join(json.dumps(e) for e in events) + "\n", encoding="utf-8")
    print("[link] rounds %d/%d PASS -> %s"
          % (sum(1 for r in rounds if r["got"]), len(rounds), args.out))
    print("PC_BLE_LINK_PASS" if ok else "PC_BLE_LINK_FAIL")
    return 0 if ok else 1


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--address", required=True)
    ap.add_argument("--rounds", type=int, default=3)
    ap.add_argument("--round-timeout", type=float, default=4.0)
    ap.add_argument("--connect-timeout", type=float, default=15.0)
    ap.add_argument("--chunk", type=int, default=20,
                    help="write chunk size; MTU-3 at default MTU 23")
    ap.add_argument("--chunk-gap", type=float, default=0.08,
                    help="seconds between chunks (module UART pacing)")
    ap.add_argument("--out", default="pc_link.json")
    args = ap.parse_args()
    return asyncio.run(amain(args))


if __name__ == "__main__":
    raise SystemExit(main())
