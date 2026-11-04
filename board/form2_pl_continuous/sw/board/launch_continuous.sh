#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -euo pipefail
B=/home/xilinx/PL_YOLOV8N_CONTINUOUS
[ "$(id -u)" = "0" ] || { echo "FATAL: run as root"; exit 1; }
mkdir -p "$B/continuous"
if pgrep -f "continuous_gesture.p[y]" >/dev/null; then
  echo stop > "$B/continuous/phase"
  sleep 3
fi
env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 "$B/sw/board/vdma_halt.py" "$B/net3_pl_hp_rebalance.bit"
echo run > "$B/continuous/phase"
nohup setsid env XILINX_XRT=/usr PYTHONPATH="$B/sw/board" \
  /usr/local/share/pynq-venv/bin/python3 -u "$B/sw/board/continuous_gesture.py" \
  > "$B/continuous/service.log" 2>&1 < /dev/null &
echo "CONTINUOUS_LAUNCHED pid=$!"
