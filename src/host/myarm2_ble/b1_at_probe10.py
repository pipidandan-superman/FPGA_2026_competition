# Round 10: CHAR=FFE2 (set in round9, setter DID accept). Readback w/ retry,
# fresh INQ -> CONN -> $DST:5!/#004PRAD! probes; restore CHAR=FFE1 at end.
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

print('=== round10 %s ===' % time.strftime('%F %T'))
tx(b'AT\r\n', 'at:AT'); r = rx(1.5, 0.5)
assert b'OK' in r, 'NOT_AT_MODE %r' % r

print('-- CHAR readback (retry x2, module mini-restarts after change) --')
cur = b''
for attempt in range(2):
    tx(b'AT+CHAR\r\n', 'at:CHAR_rd')
    cur = rx(2.5, 0.8)
    if b'FFE' in cur:
        break
    time.sleep(2.0)
print('CHAR_NOW=%r' % cur)
if b'FFE2' not in cur:
    tx(b'AT+CHARFFE2\r\n', 'at:CHARFFE2_set')
    rx(3.0, 1.0)
    time.sleep(2.0)
    tx(b'AT+CHAR\r\n', 'at:CHAR_rd2')
    cur = rx(2.5, 0.8)
    print('CHAR_AFTER_RESET=%r' % cur)

print('-- fresh scan + connect --')
tx(b'AT+INQ\r\n', 'at:INQ')
scan = rx(25.0, 3.0)
idx = find_idx(scan)
print('WEBOTPI_IDX=%s' % idx)
allrx = b''
if idx is not None:
    tx(('AT+CONN%s\r\n' % idx).encode(), 'at:CONN')
    r = rx(8.0, 1.5)
    if b'Connected' in r:
        time.sleep(0.5)
        tx(b'$DST:5!', 'arm:DST5')
        allrx = rx(8.0, 1.5)
        tx(b'#004PRAD!', 'arm:PRAD_004')
        allrx += rx(12.0, 1.5)
        print('DATA_SEEN=%s RAW=%r' % (any(k in allrx for k in (b'PDST', b'PDA', b'DST', b'PRAD', b'+DISC')), allrx))
    else:
        print('CONNECT_FAILED %r' % r)

print('-- restore CHAR=FFE1 --')
tx(b'AT+CHARFFE1\r\n', 'at:CHARFFE1_restore')
rx(3.0, 1.0)
s.close()
