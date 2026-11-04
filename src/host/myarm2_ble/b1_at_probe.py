# B1 gate probe: MLT-BT05 central-role capability test via CP210x COM port.
# Chain: PC COM(VID_10C4) -> CP2103 -> PL bridge -> MLT-BT05 (9600 8N1).
# Sequence per manual B1: AT -> AT+ROLE? -> AT+ROLE=1 -> AT+ROLE? ->
#   (if accepted) AT+DISC? scan probe -> restore AT+ROLE=0 (unless --keep-role).
# All I/O logged as JSONL + printed. Pure module-level probing: no arm frames.
import serial, serial.tools.list_ports, time, json, sys, os, argparse

LOG_DIR = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01'

def find_cp210x():
    for p in serial.tools.list_ports.comports():
        if p.vid == 0x10C4 and p.pid == 0xEA60:
            return p.device, p.serial_number
    return None, None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--keep-role', action='store_true',
                    help='skip the final AT+ROLE=0 restore (for follow-on link test)')
    ap.add_argument('--scan', action='store_true',
                    help='run AT+DISC? discovery probe when ROLE=1 accepted')
    args = ap.parse_args()

    port, sn = find_cp210x()
    if not port:
        print('CP210X_NOT_FOUND'); sys.exit(2)
    print('PORT=%s SN=%s' % (port, sn))
    os.makedirs(LOG_DIR, exist_ok=True)
    logf = open(os.path.join(LOG_DIR, 'at_probe_events.jsonl'), 'a', encoding='utf-8')

    s = serial.Serial(port, 9600, bytesize=8, parity='N', stopbits=1, timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()

    def send(cmd, wait_s=1.5):
        tx = (cmd + '\r\n').encode()
        t0 = time.time()
        s.write(tx)
        buf = b''
        t_end = time.time() + wait_s
        while time.time() < t_end:
            chunk = s.read(512)
            if chunk:
                buf += chunk
                t_end = time.time() + 0.4   # extend on traffic
        ev = {'t': round(time.time(), 3), 'tx': tx.decode('latin1'),
              'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}
        logf.write(json.dumps(ev, ensure_ascii=False) + '\n'); logf.flush()
        print('[%7.3f] TX %-14r RX %r' % (time.time() - t0, cmd, buf))
        return buf

    print('--- B1 sequence start %s ---' % time.strftime('%F %T'))
    r1 = send('AT')
    r2 = send('AT+ROLE?')
    r3 = send('AT+ROLE=1')
    r4 = send('AT+ROLE?')
    role_now = (b'ROLE=1' in r4) or (b'ROLE=1' in r3 and b'ERROR' not in r3)
    verdict = 'B1_STAGE1_UNKNOWN'
    if b'OK' in r1 or b'OK' in r2:
        if role_now:
            verdict = 'B1_ROLE1_ACCEPTED'
            if args.scan:
                send('AT+DISC?', wait_s=8.0)
                send('AT+INQ', wait_s=3.0)
        else:
            verdict = 'B1_ROLE1_REJECTED'
    else:
        verdict = 'B1_AT_DEAD'

    if not args.keep_role:
        send('AT+ROLE=0')
        send('AT+ROLE?')
    s.close()
    logf.write(json.dumps({'t': time.time(), 'verdict': verdict}) + '\n'); logf.close()
    print('VERDICT:', verdict)
    return 0 if verdict != 'B1_AT_DEAD' else 1

if __name__ == '__main__':
    sys.exit(main())
