#!/bin/bash
# launch_net3.sh -- net3_ps_only_pl_ble_j5 board-side chain launcher.
# PL BLE is enabled by default through J5 V13 (RX) / W13 (TX), 9600 8N1.
#
# PASSWORD POLICY: no password in this file. Run as:
#   echo "$BOARD_PW" | sudo -S bash /home/xilinx/net3_ps_only_pl_ble_j5/launch_net3.sh
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo "FATAL: must run as root"; exit 1; }

D=/home/xilinx/net3_ps_only_pl_ble_j5
CAM_STATE=$(systemctl is-active ees331-camera 2>/dev/null || true)
[ "$CAM_STATE" = "active" ] && { echo "FATAL: ees331-camera active -- quiesce first"; exit 1; }
pgrep -f "camera.p[y]" >/dev/null && { echo "FATAL: camera.py alive -- quiesce first"; exit 1; }

nohup setsid env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 "$D/t1_gesture_main.py" \
  --bit "$D/net3_ps_only_pl_ble_j5.bit" \
  --onnx "$D/models/nanodet-plus-m_320-gesture7-v65-cv2.onnx" \
  --ncnn-param "$D/models/nanodet-plus-m_320-gesture7-v65.ncnn.param" \
  --ncnn-bin "$D/models/nanodet-plus-m_320-gesture7-v65.ncnn.bin" \
  --engine ncnn --model 0 --rotate-secs 0 \
  --score 0.55 --conf 0.55 --debounce 2 --min-margin 0.2 \
  > "$D/chain.log" 2>&1 < /dev/null &
disown
echo "CHAIN_LAUNCHED pid=$!"
