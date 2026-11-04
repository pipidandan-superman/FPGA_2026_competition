#!/bin/sh
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -eu
D=/home/xilinx/PSPL_YOLOV8N_RESIDENT
cd "$D"
EXPECTED=72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58
ACTUAL=$(sha256sum sw/board_artifacts/hybrid_heads_ic64_fix.bit | cut -d' ' -f1)
[ "$ACTUAL" = "$EXPECTED" ] || { echo "BIT_IDENTITY_FAIL $ACTUAL"; exit 10; }
echo "BIT_IDENTITY_PASS $ACTUAL"
export XILINX_XRT=/usr
export TB_SETUP_PATH="$D/prog/tb_setup_six_branches.txt"
export SIX_BRANCHES=1
/usr/local/share/pynq-venv/bin/python3 -c 'from pynq import Overlay; o=Overlay("sw/board_artifacts/hybrid_heads_ic64_fix.bit"); o.download(); print("RESIDENT_OVERLAY_DOWNLOAD_PASS")'
/usr/local/share/pynq-venv/bin/python3 -c 'from pynq import MMIO; import time; r=MMIO(0x43C70000,0x10000); r.write(0,0); time.sleep(0.05); r.write(0,1); time.sleep(0.05); m=MMIO(0x43C00000,0x1000); m.write(0x114,0); print("INDEPENDENT_INFERENCE_RESET_PASS")'
/usr/local/share/pynq-venv/bin/python3 "$D/sw/board/run_resident.py"
