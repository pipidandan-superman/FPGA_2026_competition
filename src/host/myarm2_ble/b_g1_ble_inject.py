# G1 foreign-frame injector: send ONE read-only PRAD over the PC->AT-09
# ->STM32 UART3->servo-bus path while the FPGA bridge listens on COM4.
# NO motion frame is sent by this script (read-only position query).
# Outcomes: COM4 hears the frame  -> STM32 TX still on the net, ABORT
#           COM4 silent + notify -> STM32 alive but off the net, SAFE
#           connect fails        -> STM32 board / AT-09 unpowered
import asyncio
import sys

from bleak import BleakClient, BleakScanner

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"


async def main():
    print("[scan] looking for AT-09 %s ..." % TARGET)
    dev = await BleakScanner.find_device_by_address(TARGET, timeout=8.0)
    if dev is None:
        print("INJECT_RESULT: BLE_NOT_FOUND (arm board or AT-09 unpowered?)")
        return 3
    notes = []

    def on_notify(_h, data):
        notes.append(data)
        print("[notify] %r" % data)

    async with BleakClient(dev, timeout=10.0) as client:
        print("[link] connected")
        await client.start_notify(FFE1, on_notify)
        await client.write_gatt_char(FFE1, b"#001PRAD!", response=False)
        print("[tx] #001PRAD! sent (read-only)")
        await asyncio.sleep(2.5)
    echo = any(b"PRAD" in n for n in notes)
    if echo:
        print("INJECT_RESULT: FRAME_RELAYED (STM32 alive, frame went out)")
        return 0
    print("INJECT_RESULT: CONNECTED_NO_ECHO")
    return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
