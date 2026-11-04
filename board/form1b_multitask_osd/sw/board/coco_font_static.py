#!/usr/bin/env python3
import time
from pynq import Overlay, MMIO
import t1_gesture_main as base

ol = Overlay('/home/xilinx/multitask_osd/multitask_osd.bit')
cam = base.VdmaCam(ol)
coco = MMIO(0x43C70000, 4096)
pose = MMIO(0x43C80000, 4096)
try:
    for mmio in (coco, pose):
        mmio.write(0x08, 0)
        mmio.write(0x0C, 0)
        mmio.write(0x14, 1)
    rows = [
        (100, 200, 100, 200, 39, 87),
        (300, 420, 150, 300, 0, 93),
    ]
    for i, (l, r, t, b, cls, score) in enumerate(rows):
        base_addr = 0x40 + i * 0x20
        for offset, value in ((0, l), (4, r), (8, t), (0x0C, b)):
            coco.write(base_addr + offset, value)
        coco.write(base_addr + 0x10, cls | (score << 8))
    coco.write(0x0C, len(rows))
    coco.write(0x14, 1)
    time.sleep(1)
    seen = set()
    for sample in range(500):
        value = coco.read(0x38)
        hv = coco.read(0x20)
        key = (value, hv)
        if key not in seen:
            seen.add(key)
            print('COCO_FONT_STATIC', sample, hex(value), hex(hv), flush=True)
finally:
    cam.close()
