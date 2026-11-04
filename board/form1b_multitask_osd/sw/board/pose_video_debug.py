#!/usr/bin/env python3
import json
from pynq import MMIO

m = MMIO(0x43C80000, 4096)
rows = {}
for offset in (0x00, 0x08, 0x0C, 0x10, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C):
    rows[hex(offset)] = hex(m.read(offset))
print('POSE_VIDEO_DEBUG', json.dumps(rows), flush=True)
