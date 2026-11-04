# b_fight_discriminator.py - after STM32 exit from the servo net:
# is the FPGA echo now byte-perfect?
import time
import serial

PORT = "COM4"
BAUD = 115200

ser = serial.Serial(PORT, BAUD, timeout=0.4)

def trial(payload, label):
    time.sleep(0.05)
    ser.reset_input_buffer()
    ser.write(payload)
    time.sleep(0.12)
    got = ser.read(256)
    print("%-24s -> %2d bytes %s" % (label, len(got), got.hex(" ")))
    return got

print("--- post-STM32-exit echo test on %s ---" % PORT)

ok = True
# single isolated bytes (were 60%%+ torn before)
for k in range(4):
    got = trial(b"U", "single U")
    ok = ok and got == b"U"

# real frames, one write (gapless)
FRAME = b"#001PRAD!"
for k in range(3):
    got = trial(FRAME, "#001PRAD! onewrite")
    ok = ok and got == FRAME

# frame with sacrificial prefix
for k in range(2):
    got = trial(b"X" + FRAME, "X + frame")
    ok = ok and got == b"X" + FRAME

print("ECHO_%s" % ("CLEAN" if ok else "STILL_DIRTY"))
ser.close()
