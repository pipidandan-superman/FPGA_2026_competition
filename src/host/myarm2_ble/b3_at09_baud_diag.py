# B3 baud-persistence diagnosis: after the AT-09 power-cycled (bench->arm->bench),
# which baud does its UART answer AT on? 9600 = BAUD8 did NOT persist (factory
# revert explains arm-side silence); 115200 = persisted (arm socket wiring
# becomes the prime suspect). Diagnosis only, writes nothing.
import argparse
import json
import os
import serial
import time

LOG_DIR = r'E:\competition\4_metrics\logs\2026-10-04_myarm2_b3_at09_bench_run01'


def probe(port, baud):
    s = serial.Serial(port, baud, bytesize=8, parity='N', stopbits=1,
                      timeout=0.1)
    time.sleep(0.3)
    s.reset_input_buffer()
    replies = []
    for _ in range(2):
        s.write(b'AT\r\n')
        buf = b''
        t_end = time.time() + 1.2
        while time.time() < t_end:
            chunk = s.read(256)
            if chunk:
                buf += chunk
                t_end = time.time() + 0.4
        replies.append(buf)
        if b'OK' in buf:
            break
        time.sleep(0.3)
    s.close()
    return replies


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--port', required=True)
    args = ap.parse_args()

    os.makedirs(LOG_DIR, exist_ok=True)
    logf = open(os.path.join(LOG_DIR, 'at09_baud_diag.jsonl'), 'a',
                encoding='utf-8')

    print('--- B3 AT-09 baud persistence diag %s port=%s ---'
          % (time.strftime('%F %T'), args.port))
    results = {}
    for baud in (9600, 115200):
        reps = probe(args.port, baud)
        alive = any(b'OK' in r for r in reps)
        results[baud] = {'alive': alive, 'replies': [r.hex() for r in reps]}
        print('[%-6d] alive=%s replies=%r' % (baud, alive, reps))
        logf.write(json.dumps({'t': time.time(), 'baud': baud,
                               'alive': alive,
                               'replies': [r.hex() for r in reps]}) + '\n')
        logf.flush()
        if alive:
            break
        time.sleep(0.5)

    if results[9600]['alive']:
        v = 'BAUD_REVERTED_TO_9600'
    elif results[115200]['alive']:
        v = 'BAUD_PERSISTED_115200'
    else:
        v = 'AT_DEAD_BOTH_BAUDS'
    logf.write(json.dumps({'t': time.time(), 'verdict': v}) + '\n')
    logf.close()
    print('VERDICT:', v)
    return 0


if __name__ == '__main__':
    main()
