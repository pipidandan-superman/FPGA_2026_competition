# Round 2: exact 09-12 read syntax (no '?'), then ROLE setter variants with readback.
import serial, serial.tools.list_ports, time, json, os

LOG = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s' % port)

s = serial.Serial(port, 9600, timeout=0.1)
time.sleep(0.3); s.reset_input_buffer()
logf = open(LOG, 'a', encoding='utf-8')

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
            t_end = time.time() + 0.4
    logf.write(json.dumps({'t': time.time(), 'tx': tx.decode('latin1'),
                           'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
    logf.flush()
    print('TX %-14r RX %r' % (cmd, buf))
    return buf

print('--- round2 %s ---' % time.strftime('%F %T'))
# 09-12 exact read syntax
send('AT+ROLE'); send('AT+TYPE'); send('AT+BAUD'); send('AT+VERSION')
# setter variants, readback after each
send('AT+ROLE=1'); send('AT+ROLE')
send('AT+ROLE1');  send('AT+ROLE')
# restore attempt + final read
send('AT+ROLE=0'); send('AT+ROLE0'); send('AT+ROLE')
s.close()
