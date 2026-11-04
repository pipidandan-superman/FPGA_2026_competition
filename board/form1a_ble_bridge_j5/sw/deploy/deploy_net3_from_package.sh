#!/bin/bash
# deploy_net3_from_package.sh -- one-shot deploy of the net3_ps_only_pl_ble_j5 frozen
# package to the EES-331 board. REFERENCES ONLY FILES INSIDE THIS PACKAGE
# (scp sources are all relative to the package root). Full M13 quiesce canon.
#
# Password policy: board password from $BOARD_PW env ONLY (never on disk).
# Usage (Git Bash, from anywhere):
#   export BOARD_PW=<password>
#   bash /e/competition/13_final/net3_ps_only_pl_ble_j5/sw/deploy/deploy_net3_from_package.sh
set -euo pipefail

# Retired historical entry: unsafe host-key policy, fixed credentials helper,
# broad process matching, and unverified J5/mechanical-arm recovery gates.
echo 'RETIRED_ENTRY: review the J5 candidate README and overlay workflow; do not execute this historical script.' >&2
exit 2

: "${BOARD_PW:?BOARD_PW env var must be set (board password)}"
BOARD=xilinx@192.168.240.10
ASKPASS=/e/competition/3_host/pynq/pl_reloader/ssh_askpass.cmd
export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force EES331_SSH_PASSWORD="$BOARD_PW"
O='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
SSH="ssh $O $BOARD"
SCP="scp $O"

PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
B=/home/xilinx/net3_ps_only_pl_ble_j5
echo "PKG=$PKG"

echo "== preflight: board reachable =="
$SSH 'echo BOARD_OK $(hostname) $(date +%T)'

echo "== upload all artifacts (package-internal sources only) =="
$SSH "mkdir -p $B/models"
$SCP "$PKG/sw/board_artifacts/t1_overlay_ble_j5.bit"        "$BOARD":$B/net3_ps_only_pl_ble_j5.bit
$SCP "$PKG/sw/board_artifacts/t1_overlay_ble_j5.hwh"        "$BOARD":$B/net3_ps_only_pl_ble_j5.hwh
$SCP "$PKG/sw/board/t1_gesture_main.py"                 "$BOARD":$B/
$SCP "$PKG/sw/board/t1_ncnn_server_multi"               "$BOARD":$B/
$SCP "$PKG/sw/board/c2_registry.conf"                   "$BOARD":$B/
$SCP "$PKG/sw/board/launch_net3.sh"                     "$BOARD":$B/
$SCP "$PKG/sw/board/vdma_halt.py" "$PKG/sw/board/vdma_halt_check.py" "$PKG/sw/board/btn_probe.py" "$BOARD":$B/
$SCP "$PKG"/models/*                                    "$BOARD":$B/models/
$SSH "chmod +x $B/t1_ncnn_server_multi"

echo "== sha256 verify on board (every file vs package manifest values) =="
( cd "$PKG" && sha256sum -b \
    sw/board_artifacts/t1_overlay_ble_j5.bit \
    sw/board_artifacts/t1_overlay_ble_j5.hwh \
    sw/board/t1_gesture_main.py \
    sw/board/t1_ncnn_server_multi \
    sw/board/c2_registry.conf \
    sw/board/launch_net3.sh \
    sw/board/vdma_halt.py sw/board/vdma_halt_check.py sw/board/btn_probe.py \
    models/* ) > /tmp/net3_manifest_check.txt
$SSH "cd $B && sha256sum -b net3_ps_only_pl_ble_j5.bit net3_ps_only_pl_ble_j5.hwh t1_gesture_main.py t1_ncnn_server_multi c2_registry.conf launch_net3.sh vdma_halt.py vdma_halt_check.py btn_probe.py models/*" > /tmp/net3_board_sums.txt
sed 's# \*\./# #' /tmp/net3_manifest_check.txt | awk '{print $1}' > /tmp/net3_want.txt
awk '{print $1}' /tmp/net3_board_sums.txt > /tmp/net3_got.txt
if diff /tmp/net3_want.txt /tmp/net3_got.txt >/dev/null; then
  echo SHA_VERIFY_PASS
else
  echo "FATAL: sha mismatch host-vs-board"; paste /tmp/net3_want.txt /tmp/net3_got.txt | head; exit 1
fi

echo "== QUIESCE canon 1: stop ees331-camera (stop only, never disable) =="
$SSH "echo $BOARD_PW | sudo -S systemctl stop ees331-camera 2>&1 | grep -v 'password for' || true"
sleep 2
$SSH 'echo cam_state=$(systemctl is-active ees331-camera 2>/dev/null); pgrep -f "camera.p[y]" >/dev/null && echo CAM_PROC_ALIVE || echo CAM_PROC_DEAD'

echo "== kill any running chain (old t1_c2 or net3) =="
$SSH "echo $BOARD_PW | sudo -S pkill -f 't1_gesture_main.*.p[y]' 2>/dev/null || true"
sleep 3
$SSH 'pgrep -fa "t1_gesture_main.*.p[y]" || echo CHAIN_DEAD'

echo "== QUIESCE canon 2: explicit VDMA RS=0 halt =="
$SSH "echo $BOARD_PW | sudo -S env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 $B/vdma_halt.py /home/xilinx/ees331_camera/overlay.bit 2>&1 | grep -a 'VDMA_'"

echo "== QUIESCE canon 3: register-level VDMA halt gate =="
$SSH "echo $BOARD_PW | sudo -S env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 $B/vdma_halt_check.py /home/xilinx/ees331_camera/overlay.bit 2>&1 | grep -a 'VDMA_CHECK'"

echo "== start ncnn multi server (registry preloads all 3 nets) =="
$SSH "pkill -f 't1_ncnn_server_mult[i]' 2>/dev/null || true; sleep 2; \
  nohup setsid $B/t1_ncnn_server_multi 5002 $B/c2_registry.conf > $B/ncnn_server.log 2>&1 < /dev/null & disown; \
  for i in \$(seq 1 30); do grep -q SERVER_READY $B/ncnn_server.log && { echo SERVER_READY_OK; break; }; sleep 1; done; \
  grep -q SERVER_READY $B/ncnn_server.log || { echo FATAL_NO_SERVER_READY; exit 1; }"

echo "== launch net3 chain =="
$SSH "echo $BOARD_PW | sudo -S bash $B/launch_net3.sh 2>&1 | grep -v 'password for' || true"
sleep 30
echo "== verify via separate connection =="
$SSH 'pgrep -fa "t1_gesture_main.*.p[y]" || echo CHAIN_NOT_RUNNING; grep -a -E "PL_LOADED|ENGINE_READY|MODEL_BTN|PREPROC_READY|PL_TEXT_OSD_READY|Traceback|Error|STALLED" /home/xilinx/net3_ps_only_pl_ble_j5/chain.log | tail -12'
echo DEPLOY_NET3_DONE
