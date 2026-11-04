# Round 6: board-generated reply probe $DST:5! (zero displacement, proves TX+RX),
# then retry read-only PRAD for a true servo readback.
import serial, serial.tools.list_ports, time, json

LOG = r'E:\competition\4_metrics\logs\2026-09-30_myarm2_ble_probe_run01\..\2026-10-01_myarm2_b1_mlt_central_run01\at_probe_events.jsonl'

port = None
for p in serial.tools.list_ports.comports():
    if p.vid == 0x10C4 and p.pid == 0xEA60:
        port = p.device
assert port, 'CP210X_NOT_FOUND'
print('PORT=%s' % port)
s = serial.Serial(port, 9600, timeout=0.1)
time.sleep(0.3); s.reset_input_buffer()
logf = open(LOG, 'a', encoding='utf-8')

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
    logf.write(json.dumps({'t': time.time(), 'label': label,
                           'tx': tx_bytes.decode('latin1'),
                           'rx_hex': buf.hex(), 'rx_ascii': buf.decode('latin1')}) + '\n')
    logf.flush()
    return buf

print('--- round6 board-reply probe %s ---' % time.strftime('%F %T'))
r1 = send_raw(b'$DST:5!', 6.0, 'arm:DST5_board_probe')
if b'PDST' in r1:
    print('*** BOARD_REPLY_SEEN: TX+RX both alive through BLE link ***')
    time.sleep(2.0)
    r2 = send_raw(b'#000PRAD!', 6.0, 'arm:PRAD_000_retry')
    if b'PDA' in r2:
        print('*** SERVO_READBACK: full transparent link VERIFIED ***')
    else:
        send_raw(b'#004PRAD!', 6.0, 'arm:PRAD_004')
else:
    print('NO_BOARD_REPLY: TX or RX path dead — module-side investigation needed')
s.close()
