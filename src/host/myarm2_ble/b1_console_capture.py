# Live COM6 (ttyPS0 console) capture with timestamps -> evidence dir.
# Run in background BEFORE any fpga_manager load retry: if the board freezes
# again, the last console line is preserved on the PC side (M13 lesson:
# board-side nohup logs die in page cache on a hard freeze).
import serial, time, sys, os

OUT = r'E:\competition\4_metrics\logs\2026-10-01_myarm2_b1_mlt_central_run01\com6_capture.log'

s = serial.Serial('COM6', 115200, timeout=0.1)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
f = open(OUT, 'ab', buffering=0)
print('capturing COM6 ->', OUT, flush=True)
t0 = time.time()
while True:
    try:
        b = s.read(4096)
        if b:
            f.write(('[%8.2f] ' % (time.time() - t0)).encode() + b + b'\n')
    except KeyboardInterrupt:
        break
    except Exception as e:
        print('ERR', e, flush=True)
        time.sleep(1)
