# Round 4: start INQ scan then listen passively for 60s (no interrupting commands).
import serial, serial.tools.list_ports, time, json, sys

LOG = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'
TARGET_BE = '98EAA021013A'   # 98:EA:A0:21:01:3A as written
TARGET_LE = '3A0121A0EA98'   # byte-reversed

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s  listen=60s' % port)
s = serial.Serial(port, 9600, timeout=0.1)
time.sleep(0.3); s.reset_input_buffer()
logf = open(LOG, 'a', encoding='utf-8')

def log(tag, buf):
    logf.write(json.dumps({'t': time.time(), 'label': tag,
                           'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
    logf.flush()

s.write(b'AT+INQ\r\n')
t0 = time.time()
head = s.read(64)
print('HEAD:', head)
log('inq_head', head)

buf = b''
while time.time() - t0 < 60:
    chunk = s.read(1024)
    if chunk:
        buf += chunk
        sys.stdout.write(chunk.decode('latin1'))
        sys.stdout.flush()
log('inq_listen_60s', buf)
hexu = buf.hex().upper()
asciiu = buf.decode('latin1').upper()
hit = TARGET_BE in hexu or TARGET_LE in hexu or '98:EA:A0:21:01:3A' in asciiu
print('\n--- LISTEN DONE, WEBOTPI_%s ---' % ('FOUND' if hit else 'NOT_FOUND'))
s.close()
