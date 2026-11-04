# b_gap_sweep.py - discriminate which relay hop corrupts the echo.
# Sends N back-to-back bytes (0x55) with configurable inter-frame gap,
# prints exactly what came back. Pure ASCII per PS5.1 rule.
import time
import serial

PORT = "COM4"
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=0.4)
ser.reset_input_buffer()

def trial(nbytes, gap_s, label):
    time.sleep(0.05)
    ser.reset_input_buffer()
    payload = bytes([0x55]) * nbytes
    if nbytes == 1:
        ser.write(payload)
    else:
        for i in range(nbytes):
            ser.write(bytes([0x55]))
            if gap_s > 0 and i < nbytes - 1:
                time.sleep(gap_s)
    time.sleep(0.12)
    got = ser.read(256)
    expect = nbytes
    ok = len(got) == expect and all(b == 0x55 for b in got)
    print("%-22s n=%d gap=%6.3fs -> got %2d bytes %s %s" %
          (label, nbytes, gap_s, len(got),
           got.hex(" "), "OK" if ok else "BAD"))
    return ok

print("--- gap sweep on %s ---" % PORT)
# single bytes: no gapless stress at all
for k in range(3):
    trial(1, 0.0, "single byte")

# small groups with generous gaps
trial(2, 0.02, "pair, 20ms gap")
trial(9, 0.02, "frame len, 20ms gap")

# shrink the gap toward back-to-back
for gap_ms in (10.0, 5.0, 2.0, 1.0, 0.5):
    trial(9, gap_ms / 1000.0, "9B shrink gap")

# true back-to-back via a single write
time.sleep(0.05)
ser.reset_input_buffer()
ser.write(bytes([0x55]) * 9)
time.sleep(0.12)
got = ser.read(256)
print("%-22s -> got %2d bytes %s" %
      ("9B one write", len(got), got.hex(" ")))

ser.close()
