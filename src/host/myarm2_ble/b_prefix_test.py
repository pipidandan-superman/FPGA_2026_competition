# b_prefix_test.py - sacrificial-prefix discriminator: does a dummy byte
# absorb the idle-after-first-byte tear so the real frame relays clean?
import time
import serial

PORT = "COM4"
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=0.4)

def trial(payload, label, n=1):
    time.sleep(0.05)
    ser.reset_input_buffer()
    ser.write(payload)
    time.sleep(0.12)
    got = ser.read(256)
    print("%-24s -> %2d bytes %s" % (label, len(got), got.hex(" ")))
    return got

print("--- prefix test on %s ---" % PORT)
FRAME = b"#001PRAD!"
for k in range(4):
    trial(b"X" + FRAME, "X + #001PRAD!")

for k in range(2):
    trial(b"UU" + FRAME, "UU + #001PRAD!")

ser.close()
