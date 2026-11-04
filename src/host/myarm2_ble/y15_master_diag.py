# Y15 master-mode diagnostics: the module answered ERROR to '#' frames and
# still advertises -> query its actual state over COM4 in one session.
import sys
import time

import serial

CMDS = [
    "AT",
    "AT+ROLE",
    "AT+BAND",          # bare query attempt (undocumented)
    "AT+IMME",
    "AT+HELP",
    "AT+INQ",           # master-only command: slave should ERROR (v6.1 "(M)")
]


def send(s, cmd, wait_s=2.5):
    s.write((cmd + "\r\n").encode())
    buf = b""
    t_end = time.time() + wait_s
    while time.time() < t_end:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            t_end = time.time() + 0.5
    print("[TX %-16r] RX %r" % (cmd, buf))
    return buf


def main():
    s = serial.Serial("COM4", 9600, bytesize=8, parity="N", stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()
    for c in CMDS:
        if c == "AT+INQ":
            # scan runs long; watch 10s
            s.write((c + "\r\n").encode())
            t0 = time.time()
            buf = b""
            while time.time() - t0 < 10.0:
                chunk = s.read(512)
                if chunk:
                    buf += chunk
            print("[TX %-16r] RX %r" % (c, buf))
        else:
            send(s, c)
    s.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
