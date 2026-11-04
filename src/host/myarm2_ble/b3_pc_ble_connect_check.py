# Minimal PC-BLE connection check for the AT-09 (any bench position).
# Scan by MAC -> connect -> read FFE1 -> clean disconnect.
import asyncio
import sys

from bleak import BleakClient, BleakScanner

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"


async def main():
    print("[scan] looking %.0fs for %s" % (10.0, TARGET))
    dev = await BleakScanner.find_device_by_address(TARGET, timeout=10.0)
    if dev is None:
        print("VERDICT: NOT_ADVERTISING")
        return 1
    print("[scan] found: %s" % dev.name)
    async with BleakClient(dev, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        try:
            val = await client.read_gatt_char(FFE1)
            print("[read ffe1] %r" % bytes(val))
        except Exception as exc:
            print("[read ffe1] %r" % exc)
    print("VERDICT: PC_BLE_CONNECT_PASS")
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
