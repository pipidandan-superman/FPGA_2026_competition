#!/usr/bin/env python3
# btn_probe.py -- live-read t1_model_btn CSRs via /dev/mem (no PYNQ).
# Prints a line only when any register changes. Run: sudo python3 btn_probe.py [secs]
import struct, mmap, time, sys

SECS = float(sys.argv[1]) if len(sys.argv) > 1 else 30.0
f = open('/dev/mem', 'r+b', buffering=0)
mm = mmap.mmap(f.fileno(), 64, offset=0x43C60000)
def r(a):
    return struct.unpack('<I', mm[a:a+4])[0]

t0 = time.time()
last = None
print("probe_start SECS=%.0f" % SECS, flush=True)
while time.time() - t0 < SECS:
    v = (r(0x00), r(0x04), r(0x08))
    if v != last:
        print("ID=%08X MODEL=%d PRESSES=%d" % v, flush=True)
        last = v
    time.sleep(0.2)
print("probe_end", flush=True)
