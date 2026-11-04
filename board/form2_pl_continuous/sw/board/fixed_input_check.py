#!/usr/bin/env python3
"""Load the pinned form2 overlay and run the 21/21 fixed-input golden check.

The caller must first stop other hardware owners and halt the active VDMA.
This script never starts the camera stream and always releases its buffers.
"""
import os
from pathlib import Path
import runpy

from camera import Camera, log

ROOT = Path(__file__).resolve().parents[2]
BIT = ROOT / 'net3_pl_hp_rebalance.bit'
EXPECTED = {
    '.bit': 'c1015749f5f6b190fae483cddaeb4dc1d18c300ba752a7cf3a6bd927893957b8',
    '.hwh': '7b0d7c315af715acc11dd08152b36b9106a03958108f80faa9fca07b61ca1873',
}


def main():
    for name in ('LIVE_INPUT', 'LIVE_HEADS_OUT', 'LIVE_ARENA_INPUT_OUT'):
        os.environ.pop(name, None)
    camera = None
    try:
        camera = Camera(BIT, EXPECTED)
        runpy.run_path(str(Path(__file__).with_name('p_d1_live_run_continuous.py')),
                       run_name='__main__')
    except SystemExit as exc:
        if int(exc.code or 0) != 0:
            raise
        log('FORM2_FIXED_INPUT_CHECK_PASS', golden_planes='21/21')
    finally:
        if camera is not None:
            camera.close()


if __name__ == '__main__':
    main()
