"""accel_bootstrap.py - boundary sys.path bootstrap for 12_yolo_accel.

Import side effect: puts the tree root and all boundary module dirs on
sys.path so the flat legacy module names (graph_exec_n80, conv_packer_n80,
ppu_desc_bundle, intref_yolov8, ...) resolve inside the new tree instead of
their historical 4_metrics run dirs.

Usage at the top of any entry script or library module that used to carry
run-dir sys.path hacks:

    import os, sys
    _ROOT = os.path.abspath(os.path.join(os.path.dirname(
        os.path.abspath(__file__)), '..'))
    if _ROOT not in sys.path:
        sys.path.insert(0, _ROOT)
    import accel_bootstrap  # noqa: F401  boundary dirs on sys.path

Modules living directly in the tree root may simply `import accel_bootstrap`.
"""

import os
import sys

ROOT = os.path.dirname(os.path.abspath(__file__))

for _sub in ('abi', 'tools', 'ps_host', 'yolo_gemm', 'yolo_head'):
    _p = os.path.join(ROOT, _sub)
    if _p not in sys.path:
        sys.path.insert(0, _p)
