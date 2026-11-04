# Full transparent-bridge loop test of the AT-09 on the FPGA J5 bench.
# The PC plays BOTH ends at once:
#   dir A (air->uart): bleak write FFE1  -> AT-09 TX pin -> bridge -> COM4
#   dir B (uart->air): COM4 write -> bridge -> AT-09 RX pin -> FFE1 notify
# Both directions pass = the module's BLE<->UART bridge is fully functional
# and whatever failed on the arm is the arm socket path, not this module.
import asyncio
import sys
import time

import serial
import serial.tools.list_ports
from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
MARK_A = b"AIR2UART_QX"
MARK_B = b"UART2AIR_ZZ"


def pick_com4():
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x10C4 and p.pid == 0xEA60:
            return p.device
    return None


async def main():
    port = pick_com4()
    print("[com] CP2103 = %s" % port)
    if not port:
        print("VERDICT: NO_CP2103")
        return 2
    s = serial.Serial(port, 115200, bytesize=8, parity='N', stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()

    notes = []

    def on_notify(_h, data):
        notes.append((round(time.time(), 3), bytes(data)))
        print("[notify] %r" % bytes(data))

    async with BleakClient(TARGET, timeout=12.0) as client:
        print("[link] connected mtu=%s" % client.mtu_size)
        await client.start_notify(FFE1, on_notify)

        # dir A: air -> uart
        await client.write_gatt_char(FFE1, MARK_A, response=False)
        print("[tx air] %r -> watching COM4 3s" % MARK_A)
        t0 = time.time()
        rx_uart = b''
        while time.time() - t0 < 3.0:
            chunk = s.read(256)
            if chunk:
                rx_uart += chunk
        dir_a = MARK_A in rx_uart
        print("[rx uart] %r  dirA=%s" % (rx_uart, dir_a))

        # dir B: uart -> air
        s.write(MARK_B)
        print("[tx uart] %r -> watching notify 3s" % MARK_B)
        await asyncio.sleep(3.0)
        rx_air = b''.join(d for _t, d in notes)
        dir_b = MARK_B in rx_air
        print("[rx air] %r  dirB=%s" % (rx_air, dir_b))

    s.close()
    if dir_a and dir_b:
        print("VERDICT: BLE_UART_BRIDGE_BOTH_WAYS_PASS")
        return 0
    print("VERDICT: %s" % ("BRIDGE_DIR_A_ONLY" if dir_a else
                           ("BRIDGE_DIR_B_ONLY" if dir_b else
                            "BRIDGE_BOTH_DEAD")))
    return 1


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
