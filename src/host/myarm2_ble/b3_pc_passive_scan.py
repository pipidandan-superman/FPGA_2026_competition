# Passive BLE scan: list advertising devices with names, 8s window.
import asyncio
from bleak import BleakScanner

async def main():
    devs = await BleakScanner.discover(timeout=8.0)
    for d in sorted(devs, key=lambda x: x.address or ""):
        print("%s  %s" % (d.address, d.name))

asyncio.run(main())
