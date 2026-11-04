# Round 5: connect to WeBotPi (scan idx 2 / addr 98EAA021013A), then verify the
# transparent link with a READ-ONLY PRAD query (zero arm motion).
import serial, serial.tools.list_ports, time, json, sys

LOG = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'
ADDR = '98EAA021013A'

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s' % port)
s = serial.Serial(port, 9600, timeout=0.1)
time.sleep(0.3); s.reset_input_buffer()
logf = open(LOG, 'a', encoding='utf-8')

def log(tag, tx, buf):
    logf.write(json.dumps({'t': time.time(), 'label': tag, 'tx': tx,
                           'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
    logf.flush()

def send_raw(tx_bytes, wait_s, label):
    print('TX %r (wait %.1fs)' % (tx_bytes, wait_s))
    s.write(tx_bytes)
    buf = b''
    t_end = time.time() + wait_s
    while time.time() < t_end:
        chunk = s.read(1024)
        if chunk:
            buf += chunk
            t_end = time.time() + 0.8
    print('  RX %r' % buf)
    log(label, tx_bytes.decode('latin1'), buf)
    return buf

def at(cmd, wait_s=8.0):
    return send_raw((cmd + '\r\n').encode(), wait_s, 'at:' + cmd)

print('--- round5 connect+PRAD %s ---' % time.strftime('%F %T'))
r = at('AT+CON2', 10.0)
if b'ERROR' in r:
    r = at('AT+CONN2', 10.0)
if b'ERROR' in r:
    r = at('AT+CON' + ADDR, 10.0)
if b'ERROR' in r:
    r = at('AT+CONA' + ADDR, 10.0)

connected = b'ERROR' not in r
print('CONNECT_STATE:', 'TRYING/LINKED' if connected else 'ALL_VARIANTS_ERROR')

if connected:
    time.sleep(2.0)
    s.reset_input_buffer()
    # READ-ONLY position query, exact arm frame syntax, no CRLF
    resp = send_raw(b'#000PRAD!', 4.0, 'arm:PRAD_000')
    if b'PDA' in resp:
        print('*** LINK_VERIFIED: arm PRAD reply crossed the BLE link ***')
    else:
        # one retry after pacing pause (uart1_get_ok gating on arm side)
        time.sleep(2.0)
        resp2 = send_raw(b'#004PRAD!', 4.0, 'arm:PRAD_004')
        if b'PDA' in resp2:
            print('*** LINK_VERIFIED on retry (servo 004) ***')
s.close()
