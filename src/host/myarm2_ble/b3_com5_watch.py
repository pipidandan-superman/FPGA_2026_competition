# Passive UART1 (CH340) watcher: logs every byte the arm's STM32 emits with
# timestamps while another party (board MLT) drives the BLE link. The STM32
# dual-sends all echoes/replies on UART1, so COM5 is a side door into what the
# BLE link actually delivered to UART3.
import argparse
import serial
import serial.tools.list_ports
import time


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--secs', type=float, default=90.0)
    ap.add_argument('--out', default=None)
    args = ap.parse_args()

    port = None
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x1A86:
            port = p.device
    print('[ch340] %s watching %.0fs' % (port, args.secs), flush=True)
    if not port:
        return 2
    s = serial.Serial(port, 115200, bytesize=8, parity='N', stopbits=1,
                      timeout=0.1)
    s.setDTR(False)
    s.setRTS(False)
    time.sleep(0.3)
    s.reset_input_buffer()

    fh = open(args.out, 'a', encoding='utf-8') if args.out else None
    t0 = time.time()
    total = 0
    while time.time() - t0 < args.secs:
        c = s.read(256)
        if c:
            total += len(c)
            line = '[%6.2f] %r' % (time.time() - t0, c)
            print(line, flush=True)
            if fh:
                fh.write(line + '\n')
                fh.flush()
    s.close()
    print('[done] %d bytes total' % total, flush=True)
    return 0


if __name__ == '__main__':
    main()
