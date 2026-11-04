#!/usr/bin/env python3
import json
import time
from pynq import MMIO

coco = MMIO(0x43C70000, 4096)
pose = MMIO(0x43C80000, 4096)
for mmio in (coco, pose):
    mmio.write(0x08, 2)
    mmio.write(0x0C, 0)
    mmio.write(0x14, 1)
for offset, value in ((0x40, 100), (0x44, 260), (0x48, 90), (0x4C, 270), (0x50, 88)):
    pose.write(offset, value)
points = {0: (170, 100, 90), 5: (150, 140, 90), 6: (190, 140, 90),
          11: (140, 220, 90), 12: (200, 220, 90), 16: (320, 240, 90)}
for k, (x, y, conf) in points.items():
    base = 0x54 + k * 0x0C
    pose.write(base, x)
    pose.write(base + 4, y)
    pose.write(base + 8, conf)
pose.write(0x0C, 1)
pose.write(0x14, 1)
time.sleep(1)
for _ in range(12):
    rows = {}
    for offset in (0x08, 0x0C, 0x10, 0x18, 0x1C, 0x20, 0x24, 0x28, 0x2C, 0x30, 0x34, 0x38):
        rows[hex(offset)] = hex(pose.read(offset))
    print('POSE_STATIC_DEBUG', json.dumps(rows), flush=True)
    time.sleep(0.1)
