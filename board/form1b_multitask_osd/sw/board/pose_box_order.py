#!/usr/bin/env python3
from pynq import MMIO
m = MMIO(0x43C80000, 4096)
m.write(0x08, 2)
m.write(0x0C, 1)
for offset, value in ((0x44, 260), (0x48, 90), (0x4C, 270), (0x50, 88), (0x40, 400)):
    m.write(offset, value)
m.write(0x14, 1)
for offset in (0x30, 0x34, 0x38, 0x20):
    print(f'POSE_BOX_ORDER {offset:#x}={m.read(offset):#x}', flush=True)
