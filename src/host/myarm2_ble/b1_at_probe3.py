# Round 3: enter central mode, query state, try scan command variants.
# Passive listening only - no connection, no arm frames.
import serial, serial.tools.list_ports, time, json

LOG = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'
TARGET = '98:EA:A0:21:01:3A'

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s' % port)
s = serial.Serial(port, 9600, timeout=0.1)
time.sleep(0.3); s.reset_input_buffer()
logf = open(LOG, 'a', encoding='utf-8')

def send(cmd, wait_s=1.5, label=''):
    tx = (cmd + '\r\n').encode()
    t0 = time.time()
    s.write(tx)
    buf = b''
    t_end = time.time() + wait_s
    while time.time() < t_end:
        chunk = s.read(512)
        if chunk:
            buf += chunk
            t_end = time.time() + 0.6
    logf.write(json.dumps({'t': time.time(), 'label': label, 'tx': tx.decode('latin1'),
                           'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
    logf.flush()
    hit = ' <<<WEBOTPI>>>' if TARGET.replace(':', '') in buf.hex().upper() or TARGET in buf.decode('latin1', 'replace').upper() else ''
    print('TX %-14r RX %r%s' % (cmd, buf, hit))
    return buf

print('--- round3 central+scan %s ---' % time.strftime('%F %T'))
send('AT+ROLE1'); time.sleep(2.5)
send('AT+ROLE', label='readback_after_switch')
send('AT+STATE', 2.0); send('AT+STATE?', 2.0)
send('AT+INQ', 10.0)
send('AT+DISC', 10.0)
send('AT+DISC?', 10.0)
send('AT+ROLE', label='final_readback')
s.close()
