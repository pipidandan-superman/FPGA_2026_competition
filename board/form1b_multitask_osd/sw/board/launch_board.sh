#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -euo pipefail
[ "$(id -u)" = "0" ] || { echo FATAL_ROOT_REQUIRED; exit 1; }
D=/home/xilinx/multitask_osd
M=/home/xilinx/three_task/models
[ "$(systemctl is-active ees331-camera 2>/dev/null || true)" = "active" ] && { echo FATAL_CAMERA_ACTIVE; exit 1; }
pgrep -f "camera.p[y]" >/dev/null && { echo FATAL_CAMERA_PROCESS; exit 1; }
export XILINX_XRT=/usr
nohup setsid /usr/local/share/pynq-venv/bin/python3 "$D/three_task_main_split.py" \
  --bit "$D/multitask_osd.bit" \
  --ncnn-addr 127.0.0.1:5002 \
  --ncnn-param "$M/nanodet_coco_320.param" \
  --ncnn-bin "$M/nanodet_coco_320.bin" \
  --ncnn-param-sha de3ce3a8cbb3e9bfdae9b2c65338a5f924a3a8493b587a774496c17afd614c2d \
  --ncnn-bin-sha 4a5c68c058a6a70f94e66e2483c98a1ae16568dc628e4258e8be12b45082b2eb \
  --c2psa-weights "$M/c2psa_weights.npz" \
  --c2psa-sha 669de125d30c3df48781821749931dbf7f9fbedfcb7b3578665465163ac32363 \
  --model 0 --model-select "$D/model_select" \
  --score 0.55 --new-task-score 0.25 --nms 0.6 \
  --evidence "$D/evidence_live" > "$D/chain.log" 2>&1 < /dev/null &
disown
echo MULTITASK_OSD_CHAIN_LAUNCHED pid=$!
