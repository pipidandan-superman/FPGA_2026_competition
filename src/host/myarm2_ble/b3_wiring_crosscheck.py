# Cross-check: while PC<->AT-09 BLE link is up (notify armed), drive the arm
# from its CH340 UART1 with a servo read frame and listen over the air.
# CH340 side should show echo + servo reply (10-03 recheck path, known good).
# Air side: any bytes (garbage or clean) => AT-09 RX pin is wired to UART3.
# Total air silence is weak evidence (CC2541 drops framing-error bytes).
import asyncio
import sys
import time

import serial.tools.list_ports
from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
FRAME = b"$1PRAD!"


def find_ch340():
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x1A86:
            return p.device, p.description
    return None, None


async def main():
    port, desc = find_ch340()
    print("[ch340] %s (%s)" % (port, desc))
    if not port:
        print("VERDICT: CH340_NOT_FOUND")
        return 2

    s = serial.Serial(port, 115200, bytesize=8, parity="N", stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()

    air = []

    def on_notify(_h, data):
        air.append((round(time.time(), 3), data))
        print("[air] %r" % data)

    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[ble] connected mtu=%s" % client.mtu_size)
        await client.start_notify(FFE1, on_notify)

        s.write(FRAME)
        print("[ch340 tx] %r" % FRAME)
        t0 = time.time()
        wired = b""
        while time.time() - t0 < 8.0:
            chunk = s.read(256)
            if chunk:
                wired += chunk
            await asyncio.sleep(0.05)
        s.close()
        print("[ch340 rx] %r" % wired)
        print("[air total] %d notification(s)" % len(air))
        v = "B3_WIRING_CONFIRMED" if air else "B3_AIR_SILENT_WEAK"
        print("VERDICT: %s" % v)
        return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
