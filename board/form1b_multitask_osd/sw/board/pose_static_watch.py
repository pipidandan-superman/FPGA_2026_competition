#!/usr/bin/env python3
import json
import time
from pynq import Overlay, MMIO
import t1_gesture_main as base

ol = Overlay('/home/xilinx/multitask_osd/multitask_osd.bit')
cam = base.VdmaCam(ol)
coco = MMIO(0x43C70000, 4096)
pose = MMIO(0x43C80000, 4096)
try:
    for mmio in (coco, pose):
        mmio.write(0x08, 2)
        mmio.write(0x0C, 0)
        mmio.write(0x14, 1)
    for offset, value in ((0x40, 100), (0x44, 260), (0x48, 90), (0x4C, 270), (0x50, 88)):
        pose.write(offset, value)
    points = {0: (170, 100, 90), 5: (150, 140, 90), 6: (190, 140, 90),
              11: (140, 220, 90), 12: (200, 220, 90), 16: (320, 240, 90)}
    for k, (x, y, conf) in points.items():
        addr = 0x54 + k * 0x0C
        pose.write(addr, x)
        pose.write(addr + 4, y)
        pose.write(addr + 8, conf)
    pose.write(0x0C, 1)
    pose.write(0x14, 1)
    time.sleep(1)
    hits = 0
    for sample in range(2000):
        rows = {}
        for offset in (0x18, 0x1C, 0x28, 0x2C):
            rows[hex(offset)] = hex(pose.read(offset))
        if rows['0x28'] != '0x0':
            hits += 1
            print('POSE_LABEL_HIT', sample, json.dumps(rows), flush=True)
        if sample == 0:
            print('POSE_LABEL_WATCH_START', json.dumps(rows), flush=True)
    print('POSE_LABEL_HITS', hits, flush=True)
finally:
    cam.close()
