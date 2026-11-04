# B3 dual-port discriminator matrix. Source-code weapon: zx_uart_send_str()
# dual-sends every STM32 reply/echo on UART3 (BT socket) AND UART1 (CH340 USB).
#   test W: drive #001PRAD! wired on UART1 -> watch UART1 echo+reply + air
#   test A: drive #001PRAD! over the air  -> watch UART1 echo+reply + air
# W.uart=STM32 alive | W.air=return path alive | A.uart=forward path alive
import asyncio
import sys
import time

import serial
import serial.tools.list_ports
from bleak import BleakClient

TARGET = "D0:B5:C2:8D:EB:49"
FFE1 = "0000ffe1-0000-1000-8000-00805f9b34fb"
FRAME = b"#001PRAD!"   # '#' servo-bus frame: parse_action echoes it via
                       # zx_uart_send_str (UART1+UART3) even with no servo


def find_ch340():
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x1A86:
            return p.device
    return None


async def observe(s, secs, air):
    t0 = time.time()
    wired = b''
    while time.time() - t0 < secs:
        c = s.read(256)
        if c:
            wired += c
        await asyncio.sleep(0.05)
    return wired


async def main():
    port = find_ch340()
    print("[ch340] %s" % port)
    if not port:
        print("VERDICT: NO_CH340")
        return 2
    s = serial.Serial(port, 115200, bytesize=8, parity='N', stopbits=1,
                      timeout=0.1)
    s.setDTR(False)   # some boards wire CH340 DTR/RTS to MCU RESET/BOOT0:
    s.setRTS(False)   # pyserial asserts both at open, holding STM32 in reset
    time.sleep(0.5)
    s.reset_input_buffer()

    air = []

    def on_notify(_h, data):
        air.append(bytes(data))
        print("[air ] + %r" % bytes(data))

    async with BleakClient(TARGET, timeout=15.0) as client:
        print("[ble ] connected mtu=%s" % client.mtu_size)
        await client.start_notify(FFE1, on_notify)

        # ---- test W: wired UART1 drive
        s.reset_input_buffer()
        del air[:]
        s.write(FRAME)
        print("[W tx] wired  %r" % FRAME)
        w_uart = await observe(s, 6.0, air)
        w_air = list(air)
        print("[W rx] uart1=%r  air_notifs=%d" % (w_uart, len(w_air)))
        await asyncio.sleep(2.0)

        # ---- test A: air drive
        s.reset_input_buffer()
        del air[:]
        await client.write_gatt_char(FFE1, FRAME, response=False)
        print("[A tx] air    %r" % FRAME)
        a_uart = await observe(s, 6.0, air)
        a_air = list(air)
        print("[A rx] uart1=%r  air_notifs=%d" % (a_uart, len(a_air)))

    s.close()

    Wu = b'!' in w_uart          # STM32 answered on UART1
    Wa = bool(w_air)             # reply also surfaced over the air
    Au = b'!' in a_uart          # air frame reached STM32, it replied UART1
    Aa = bool(a_air)             # full air round-trip

    print("matrix: W.uart=%s W.air=%s | A.uart=%s A.air=%s"
          % (Wu, Wa, Au, Aa))
    if not Wu:
        v = "STM32_ALIVE_FAIL"
    elif Aa:
        v = "FULL_LOOP_PASS"
    elif Au:
        v = "FORWARD_OK_RETURN_BROKEN"
    elif Wa:
        v = "RETURN_OK_FORWARD_BROKEN"
    else:
        v = "BOTH_DIRECTIONS_BROKEN_AT_SOCKET"
    print("VERDICT: %s" % v)
    return 0


if __name__ == "__main__":
    sys.exit(asyncio.run(main()))
