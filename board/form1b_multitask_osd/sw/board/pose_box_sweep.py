#!/usr/bin/env python3
from pynq import MMIO
m = MMIO(0x43C80000, 4096)
m.write(0x08, 2)
m.write(0x0C, 1)
for value in (100, 200, 300, 400, 639):
    m.write(0x40, value)
    m.write(0x44, 260)
    m.write(0x48, 90)
    m.write(0x4C, 270)
    m.write(0x50, 88)
    m.write(0x14, 1)
    print(f'POSE_BOX_SWEEP write={value} debug30={m.read(0x30):#x}', flush=True)
