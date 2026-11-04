# Discriminator: does READ return the module's AT answer, or merely the last
# written GATT value (pure echo)? Write a non-AT payload and read back.
import asyncio
import sys

from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"


async def main():
    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected")
        for payload in (b"ZZ", b"AT\r\n", b"Q"):
            await client.write_gatt_char(FFE1, payload, response=False)
            await asyncio.sleep(0.8)
            val = await client.read_gatt_char(FFE1)
            print("write %-8r -> read %r" % (payload, bytes(val)))
        print("If read==written bytes for all: pure value echo, air-AT dead.")
        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
