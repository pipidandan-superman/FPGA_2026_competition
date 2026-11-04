# Exhaustive air-side probe of the AT-09 while it sits on the arm socket.
# Enumerate every service/characteristic, subscribe every notifier, then send
# the servo read frame with BOTH write modes. If anything at all comes back on
# any characteristic, the arm-side UART path (at least one direction) is alive.
import asyncio
import sys
import time

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FRAME = b"$1PRAD!"


async def main():
    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        svcs = client.services
        rx_seen = []

        for s in svcs:
            print("[svc] %s" % s.uuid)
            for c in s.characteristics:
                print("    [chr] %s props=%s" % (c.uuid, sorted(c.properties)))
                if "notify" in c.properties:
                    def mk(u):
                        async def on(_h, data, u=u):
                            rx_seen.append((u, data))
                            print("    [notify %s] %r" % (u[-8:], data))
                        return on
                    try:
                        await client.start_notify(c.uuid, mk(c.uuid))
                        print("    [sub] notify armed")
                    except Exception as exc:
                        print("    [sub] FAILED %r" % exc)

        for mode in (False, True):
            tag = "write-no-resp" if not mode else "write-resp"
            try:
                await client.write_gatt_char(
                    "0000ffe1-0000-1000-8000-00805f9b34fb",
                    FRAME, response=mode)
                print("[tx %s] %r ok" % (tag, FRAME))
            except Exception as exc:
                print("[tx %s] FAILED %r" % (tag, exc))
            await asyncio.sleep(5.0)

        print("[summary] %d notification(s) total" % len(rx_seen))
        print("VERDICT: %s" %
              ("AIR_ARM_ONEWAY_OR_ALIVE" if rx_seen else "AIR_ARM_TOTAL_SILENT"))
        return 0 if rx_seen else 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
