"""accel_paths.py - 12_yolo_accel single source of frozen-input paths (M4.2).

All n80 frozen inputs live permanently in 4_metrics run dirs (read-only
evidence); this module is the ONLY place that maps them, so boundary code
never hard-codes absolute paths again.  Every path is WT-relative and
resolved at import time; callers use `import accel_paths as AP`.

M4 v1 rule: outputs of any gate run go to a NEW run dir under 4_metrics,
never back into the frozen inputs referenced here.
"""

import os

HERE = os.path.dirname(os.path.abspath(__file__))          # 12_yolo_accel
WT = os.path.dirname(HERE)                                  # E:/competition
LOGS = os.path.join(WT, '4_metrics', 'logs')

# ---- frozen input run dirs (M0/M1/M2 lineage) ----
DRY = os.path.join(LOGS, '2026-10-05_yolov8n80_toolchain_dryrun_run01')
GEXT = os.path.join(LOGS, '2026-10-06_yolo_p2_g0ext_n80_run01')
F2RUN = os.path.join(LOGS, '2026-10-06_yolo_p2_f2replay_n80_run01')
K720R2 = os.path.join(LOGS, '2026-10-06_yolo_k720_r2_realconv_run01')
M3PRE = os.path.join(LOGS, '2026-10-06_yolo_m3_pre_n80_run01')
M3BOARD = os.path.join(LOGS, '2026-10-06_yolo_m3_board_run01')
CAPTURE = os.path.join(LOGS, '2026-10-05_object_calib_capture_run01')

# ---- canon manifest set (v1.1 layout, sole legal execution input) ----
V11 = os.path.join(
    LOGS, '2026-10-06_yolo_m3_manifests_v11_run01',
    'out', 'p2_manifests_n80_v11')

# ---- derived frozen-input points used across the chain ----
ROM = os.path.join(DRY, 'out', 'quant_n80')            # W8A8 deploy packs
DRY_SCRIPTS = os.path.join(DRY, 'scripts')             # intref_yolov8 etc.
ANCHOR_DIR = os.path.join(M3PRE, 'anchors')            # five-anchor bins
BIT_SRC = os.path.join(K720R2, 'payload')              # proven bitstream dir
PYNQ = os.path.join(WT, '2_fpga', '3_yolo_zynq', 'pynq')  # yolo_pkg imports

# ---- proven baselines for M4 equivalence gates ----
M3_BOARD_PACK = os.path.join(M3BOARD, 'board_pack')    # 13-payload canon
RUN04_BIT = os.path.join(
    LOGS, '2026-09-20_yolo_p1_3_run04_v23_bitstream',
    'display_test_wrapper.bit')                        # V2.3 canon bit

# ---- venv for quant/compile (CPU-locked) ----
VENV_PY = os.path.join(
    LOGS, '2026-09-21_model_env_rebuild_run03', 'venv',
    'Scripts', 'python.exe')
