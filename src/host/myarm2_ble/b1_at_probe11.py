# Round 11 (FINAL falsification): WeBotPi fresh-boot (user power-cycled arm).
# Confirm ROLE=1/CHAR=FFE1 -> fresh INQ -> CONN -> immediate probes, generous listen.
# Expectation per verdict: still silent (property-level rejection unaffected by GATT cache).
import serial, serial.tools.list_ports, time, json, re

LOG = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'
TARGET = '98EAA021013A'

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s' % port)
s = serial.Serial(port, 9600, timeout=0.1)
logf = open(LOG, 'a', encoding='utf-8')
T0 = time.time()

def rx(sec, quiet_break=1.5):
    buf = b''
    t_end = time.time() + sec
    while time.time() < t_end:
        c = s.read(1024)
        if c:
            buf += c
            print('  [+%.2f] RX %r' % (time.time() - T0, c))
            t_end = time.time() + quiet_break
    if buf:
        logf.write(json.dumps({'t': time.time(), 'label': 'rx',
                               'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
        logf.flush()
    return buf

def tx(data, label):
    s.write(data)
    print('[+%.2f] TX %r (%s)' % (time.time() - T0, data, label))
    logf.write(json.dumps({'t': time.time(), 'label': label, 'tx': data.decode('latin1')}) + '\n')
    logf.flush()

def find_idx(scan):
    for m in re.finditer(rb'\+INQ:(\d+)\s+0x([0-9A-Fa-f]+)', scan):
        if m.group(2).decode().upper() == TARGET:
            return m.group(1).decode()
    return None

print('=== round11 fresh-boot falsification %s ===' % time.strftime('%F %T'))
tx(b'AT\r\n', 'at:AT'); r = rx(1.5, 0.5)
assert b'OK' in r, 'NOT_AT_MODE %r' % r
tx(b'AT+ROLE\r\n', 'at:ROLE_rd'); role = rx(1.5, 0.5)
if b'+ROLE=1' not in role:
    tx(b'AT+ROLE1\r\n', 'at:ROLE1'); rx(3.0, 1.0); time.sleep(2.0)
tx(b'AT+CHAR\r\n', 'at:CHAR_rd'); ch = rx(1.5, 0.5)
if b'FFE1' not in ch:
    tx(b'AT+CHARFFE1\r\n', 'at:CHARFFE1'); rx(3.0, 1.0); time.sleep(2.0)
print('PRE: role=%r char=%r' % (role, ch))

print('-- fresh scan --')
tx(b'AT+INQ\r\n', 'at:INQ')
scan = rx(25.0, 3.0)
idx = find_idx(scan)
print('WEBOTPI_IDX=%s' % idx)
if idx is None:
    print('WEBOTPI_NOT_FOUND_IN_SCAN (arm freshly booted? check it is on)')
    s.close(); raise SystemExit

tx(('AT+CONN%s\r\n' % idx).encode(), 'at:CONN')
r = rx(8.0, 1.5)
if b'Connected' not in r:
    print('CONNECT_FAILED %r' % r)
    s.close(); raise SystemExit

print('-- probes on fresh-boot link --')
time.sleep(0.5)
allrx = b''
for frame, wait in [(b'$DST:5!', 8.0), (b'#000PRAD!', 8.0), (b'#004PRAD!', 12.0)]:
    tx(frame, 'arm:' + frame.decode('latin1'))
    allrx += rx(wait, 1.5)

hits = [k.decode() for k in (b'PDST', b'PDA', b'PRAD', b'DST', b'+DISC') if k in allrx]
if hits:
    print('VERDICT: FRESH_BOOT_DATA_SEEN keywords=%s RAW=%r' % (hits, allrx))
else:
    print('VERDICT: FRESH_BOOT_STILL_SILENT — stale-GATT confounder excluded, TRANSPARENT_FAIL confirmed')
s.close()
