# Air-AT variant battery: some BT05-family builds answer AT via READ on FFE1
# or want bare frames without CRLF. Try all cheap variants before declaring
# air-config dead. No BAUD write unless a variant shows an AT response.
import asyncio
import sys
import time

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"


async def try_read(client, tag):
    try:
        val = await client.read_gatt_char(FFE1)
        print("[read:%s] %r" % (tag, bytes(val)))
        return bytes(val)
    except Exception as exc:
        print("[read:%s] failed: %r" % (tag, exc))
        return b""


async def main():
    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        r0 = await try_read(client, "initial")

        got = bytearray()

        def on_notify(_h, data):
            got.extend(data)
            print("[notify] %r" % data)

        await client.start_notify(FFE1, on_notify)

        variants = [
            ("bare-noCRLF", b"AT"),
            ("crlf", b"AT\r\n"),
            ("lf", b"AT\n"),
        ]
        for tag, payload in variants:
            got.clear()
            await client.write_gatt_char(FFE1, payload, response=False)
            await asyncio.sleep(1.2)
            rd = await try_read(client, tag)
            print("[variant:%s] notify=%r read=%r" % (tag, bytes(got), rd))
            if got or (rd and rd != r0):
                print("AIR_AT_ALIVE_VARIANT=%s" % tag)
                return 0
        print("VERDICT: AIR_AT_ALL_VARIANTS_DEAD")
        return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
