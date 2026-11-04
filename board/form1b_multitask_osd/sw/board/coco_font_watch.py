#!/usr/bin/env python3
import json
from pynq import MMIO

m = MMIO(0x43C70000, 4096)
seen = set()
for sample in range(500):
    value = m.read(0x38)
    hv = m.read(0x20)
    key = (value, hv)
    if key not in seen:
        seen.add(key)
        print('COCO_FONT', json.dumps({'sample': sample, 'font38': hex(value), 'hv20': hex(hv)}), flush=True)
