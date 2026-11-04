# Round 8: after module reset. (a) dialect intel reads (bare form), (b) ROLE,
# (c) fresh INQ scan 30s -> is WeBotPi still ADVERTISING?
#   absent  -> link in round5 was REAL both ends -> transparent layer = cross-vendor dead.
#   present -> half-open/false connect -> reconnect fresh idx + immediate probes.
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

print('=== round8 %s ===' % time.strftime('%F %T'))
time.sleep(3.0)   # module boot after PL reset pulse
tx(b'AT\r\n', 'at:AT'); r = rx(1.5, 0.5)
assert b'OK' in r, 'MODULE_NOT_IN_AT_MODE: %r' % r

print('-- dialect intel (bare reads) --')
for cmd in ['AT+VERSION', 'AT+NAME', 'AT+UUID', 'AT+SERV', 'AT+CHAR', 'AT+MODE', 'AT+MTU', 'AT+TYPE']:
    tx((cmd + '\r\n').encode(), 'at:' + cmd); rx(1.2, 0.4)

print('-- role --')
tx(b'AT+ROLE\r\n', 'at:ROLE_rd'); role = rx(1.5, 0.5)
if b'+ROLE=1' not in role:
    tx(b'AT+ROLE1\r\n', 'at:ROLE1'); rx(2.5, 0.8)

print('-- fresh scan 30s --')
tx(b'AT+INQ\r\n', 'at:INQ')
scan = rx(30.0, 4.0)
idx = None
for m in re.finditer(rb'\+INQ:(\d+)\s+0x([0-9A-Fa-f]+)', scan):
    if m.group(2).decode().upper() == TARGET:
        idx = m.group(1).decode()
        print('WEBOTPI_IDX=%s' % idx)

if idx is None:
    print('VERDICT: WEBOTPI_NOT_ADVERTISING -> link WAS real both ends; transparent layer cross-vendor DEAD')
    print('B1 = CONNECT_PASS / TRANSPARENT_FAIL -> path B (HC-05)')
else:
    print('-- WeBotPi still advertising -> round5 connect was half-open; reconnect --')
    tx(('AT+CONN%s\r\n' % idx).encode(), 'at:CONN')
    r = rx(8.0, 1.5)
    if b'Connected' in r:
        time.sleep(0.3)
        tx(b'$DST:5!', 'arm:DST5_fast')
        allrx = rx(8.0, 1.5)
        tx(b'#004PRAD!', 'arm:PRAD_fast')
        allrx += rx(10.0, 1.5)
        print('DATA_SEEN=%s' % any(k in allrx for k in (b'PDST', b'PDA', b'DST', b'PRAD', b'+DISC')))
        print('RAW=%r' % allrx)
    else:
        print('CONNECT_FAILED this time: %r' % r)
s.close()
