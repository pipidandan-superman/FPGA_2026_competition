# B3 gate 0: AT-09 bench configuration probe (manual MyArm2 section 8, three steps).
# Wired bench only: USB-TTL adapter -> AT-09 (CC2541, same OEM family as MLT-BT05 v6.1).
# Steps: dialect confirm (AT->OK) -> role confirm (+ROLE=0) -> AT+BAUD8 -> verify AT at 115200.
# MLT dialect lessons baked in (B1/B2): no '=' forms, ROLE-class replies '+ROLE=x' not OK,
#   accept non-ERROR as success; ROLE/BAUD changes may briefly reboot the stack.
# SAFETY: COM1 (native RS232, +/-12V) is refused - TTL module would fry. EES-331 FT2232
#   (0403:6010) and camera UART (2BDF:02B2) are excluded from auto-detect.
# Wiring: USB-TTL 5V -> AT-09 VCC (LDO baseboard only, 3.6-6V printed on pcb),
#   GND<->GND, TTL TX->AT-09 RX, TTL RX->AT-09 TX (crossed).
# Verify LDO out = 3.3V with a multimeter BEFORE plugging signal lines (manual section 8 step 3).
import serial, serial.tools.list_ports, time, json, sys, os, argparse

LOG_DIR = r'E:\competition\4_metrics\logs\2026-10-04_myarm2_b3_at09_bench_run01'

TTL_VIDS = {0x1A86, 0x10C4, 0x067B, 0x0403, 0x303A}   # CH340/CP210x/PL2303/FTDI/ESP-hidden
EXCLUDE = {(0x0403, 0x6010), (0x2BDF, 0x02B2)}         # EES-331 FT2232, camera composite

def pick_port(want):
    cands = []
    for p in serial.tools.list_ports.comports():
        if p.vid is None:
            continue
        if (p.vid, p.pid) in EXCLUDE:
            print('SKIP  %-6s excluded device VID_%04X PID_%04X' % (p.device, p.vid, p.pid))
            continue
        if p.vid in TTL_VIDS:
            cands.append((p.device, p.vid, p.pid, p.serial_number))
    for c in cands:
        print('CAND  %-6s VID_%04X PID_%04X SN=%s' % c)
    if want:
        return want
    if len(cands) == 1:
        return cands[0][0]
    print('PORT_AMBIGUOUS_OR_MISSING (use --port COMx)')
    return None

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', help='explicit COM port, overrides auto-detect')
    ap.add_argument('--dialect-only', action='store_true',
                    help='probe AT/VERSION/NAME/ROLE only, do not change baud')
    args = ap.parse_args()

    port = pick_port(args.port)
    if not port:
        sys.exit(2)
    if port.upper() == 'COM1':
        print('REFUSED: COM1 is native RS232 (+/-12V) - would destroy a TTL module')
        sys.exit(2)

    os.makedirs(LOG_DIR, exist_ok=True)
    logf = open(os.path.join(LOG_DIR, 'at09_bench_events.jsonl'), 'a', encoding='utf-8')

    def session(baud):
        s = serial.Serial(port, baud, bytesize=8, parity='N', stopbits=1, timeout=0.1)
        time.sleep(0.3)
        s.reset_input_buffer()
        return s

    def send(s, cmd, wait_s=1.5):
        tx = (cmd + '\r\n').encode()
        t0 = time.time()
        s.write(tx)
        buf = b''
        t_end = time.time() + wait_s
        while time.time() < t_end:
            chunk = s.read(512)
            if chunk:
                buf += chunk
                t_end = time.time() + 0.4
        ev = {'t': round(time.time(), 3), 'baud': s.baudrate,
              'tx': tx.decode('latin1'), 'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}
        logf.write(json.dumps(ev, ensure_ascii=False) + '\n'); logf.flush()
        print('[%7.3f @%-6d] TX %-12r RX %r' % (time.time() - t0, s.baudrate, cmd, buf))
        return buf

    def log(**kw):
        logf.write(json.dumps(dict(t=round(time.time(), 3), **kw), ensure_ascii=False) + '\n')
        logf.flush()

    print('--- B3 AT-09 bench start %s  port=%s ---' % (time.strftime('%F %T'), port))
    log(event='start', port=port)
    s = session(9600)

    r_at    = send(s, 'AT')
    r_ver   = send(s, 'AT+VERSION')
    r_name  = send(s, 'AT+NAME')
    r_role  = send(s, 'AT+ROLE')
    at_ok   = b'OK' in r_at
    role0   = (b'+ROLE=0' in r_role) or (b'ROLE=0' in r_role and b'ERROR' not in r_role)
    log(at_ok=at_ok, role0=role0,
        version=r_ver.decode('latin1').strip(), name=r_name.decode('latin1').strip())

    if not at_ok:
        s.close(); logf.close()
        print('VERDICT: B3_AT09_AT_DEAD (check wiring/power/baud, then retry)')
        return 1
    if not role0:
        r_fix = send(s, 'AT+ROLE0')
        role0 = (b'+ROLE=0' in r_fix) or (b'ERROR' not in r_fix)
        log(role_fix_attempt=True, role0=role0)

    if args.dialect_only or not role0:
        s.close(); logf.close()
        v = 'B3_AT09_DIALECT_PASS' if role0 else 'B3_AT09_ROLE_UNCONFIRMED'
        print('VERDICT:', v)
        return 0 if role0 else 1

    # step 3: baud -> 115200, then verify on a fresh 115200 session
    r_baud = send(s, 'AT+BAUD8')
    baud_ok_cmd = (b'OK' in r_baud) or (b'+BAUD=8' in r_baud) or (b'ERROR' not in r_baud)
    s.close()
    time.sleep(1.5)                       # stack may reboot on setting change (B1 lesson)
    s2 = session(115200)
    r_at2 = send(s2, 'AT')
    s2.close()
    at115 = b'OK' in r_at2
    log(baud_cmd_ok=baud_ok_cmd, at_115200=at115)

    verdict = 'B3_AT09_BENCH_PASS' if (role0 and at115) else 'B3_AT09_BAUD_FAIL'
    logf.write(json.dumps({'t': time.time(), 'verdict': verdict}) + '\n'); logf.close()
    print('VERDICT:', verdict)
    return 0 if verdict == 'B3_AT09_BENCH_PASS' else 1

if __name__ == '__main__':
    sys.exit(main())
