# COM6 (ttyPS0 console) liveness probe per M13 forensics playbook:
# frozen kernel = zero echo; alive = shell responds.
import serial, time, sys

port = 'COM6'
try:
    s = serial.Serial(port, 115200, timeout=0.2)
except Exception as e:
    print('OPEN_FAIL', e); sys.exit(1)

s.reset_input_buffer()
s.write(b'\r\n')
time.sleep(0.5)
r1 = s.read(256)
s.write(b'echo ALIVE_$((6*7)); uptime; cat /sys/class/fpga_manager/fpga0/state\r\n')
time.sleep(1.5)
r2 = s.read(1024)
s.close()
print('ECHO_PROBE_BYTES=%d' % len(r1))
print(repr(r1))
print('CMD_PROBE_BYTES=%d' % len(r2))
print(r2.decode('utf-8', 'replace'))
print('VERDICT:', 'ALIVE' if (b'ALIVE_42' in r2 or len(r2) > 20) else 'FROZEN_OR_SILENT')
