# Round 7: no buffer resets anywhere; every RX chunk timestamped.
# Phase A: read pending, then AT liveness -> AT mode (link down) vs transparent (link up?)
# Phase B (if AT mode): ROLE check -> fresh INQ scan (parse idx for 98EAA021013A) -> AT+CONN<idx>
# Phase C: continuous listen, $DST:5! at +1s, #004PRAD! at +10s; catch echoes / PDST / +DISC.
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
    """read everything arriving within sec; extend window while data flows"""
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

print('=== round7 %s ===' % time.strftime('%F %T'))
print('-- phase A: pending + AT liveness --')
rx(1.0, 0.5)
tx(b'AT\r\n', 'at:AT')
r = rx(1.5, 0.5)
at_mode = b'OK' in r
print('AT_MODE=%s' % at_mode)

idx = None
if at_mode:
    print('-- phase B: role + fresh scan --')
    tx(b'AT+ROLE\r\n', 'at:ROLE_rd')
    rx(1.5, 0.5)
    tx(b'AT+INQ\r\n', 'at:INQ')
    scan = rx(25.0, 3.0)
    for m in re.finditer(rb'\+INQ:(\d+)\s+0x([0-9A-Fa-f]+)', scan):
        if m.group(2).decode().upper() == TARGET:
            idx = m.group(1).decode()
            print('WEBOTPI_IDX=%s' % idx)
    if idx is None:
        print('VERDICT: WEBOTPI_NOT_IN_SCAN')
        s.close(); raise SystemExit
    tx(('AT+CONN%s\r\n' % idx).encode(), 'at:CONN')
    r = rx(10.0, 1.5)
    if b'Connected' not in r:
        print('VERDICT: CONNECT_FAILED: %r' % r)
        s.close(); raise SystemExit

print('-- phase C: transparent probes, continuous listen --')
time.sleep(1.0)
tx(b'$DST:5!', 'arm:DST5')
allrx = rx(10.0, 1.5)
tx(b'#004PRAD!', 'arm:PRAD_004')
allrx += rx(15.0, 1.5)

if b'PDST' in allrx or b'PDA' in allrx or b'$DST' in allrx or b'PRAD' in allrx:
    print('VERDICT: LINK_DATA_SEEN (echo or reply)')
else:
    print('VERDICT: CONNECTED_BUT_SILENT — cross-vendor transparent pipe dead?')
    # last-resort dialect probes (only meaningful if module actually left AT mode)
    tx(b'AT\r\n', 'at:AT_post')
    r2 = rx(1.5, 0.5)
    print('AT_after_data_probes=%r -> %s' % (r2, 'MODULE_BACK_IN_AT(link dropped)' if b'OK' in r2 else 'STILL_TRANSPARENT(link claimed up)'))
s.close()
