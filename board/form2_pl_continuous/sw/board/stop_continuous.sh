#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -euo pipefail
B=/home/xilinx/PL_YOLOV8N_CONTINUOUS
[ "$(id -u)" = "0" ] || { echo "FATAL: run as root"; exit 1; }
echo stop > "$B/continuous/phase"
for _ in $(seq 1 30); do
  if ! pgrep -f "continuous_gesture.p[y]" >/dev/null; then break; fi
  sleep 1
done
env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 "$B/sw/board/vdma_halt.py" "$B/net3_pl_hp_rebalance.bit"
tail -n 8 "$B/continuous/service.log" || true
echo CONTINUOUS_STOPPED
