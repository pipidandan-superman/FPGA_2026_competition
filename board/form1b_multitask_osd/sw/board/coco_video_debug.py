#!/usr/bin/env python3
import json
from pynq import MMIO

m = MMIO(0x43C70000, 4096)
rows = {}
for offset in (0x00, 0x08, 0x0C, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38):
    rows[hex(offset)] = hex(m.read(offset))
print('COCO_VIDEO_DEBUG', json.dumps(rows), flush=True)
