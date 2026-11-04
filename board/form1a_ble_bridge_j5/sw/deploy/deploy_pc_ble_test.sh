#!/bin/bash
# Deploy only the J5 PC<->FPGA BLE test. Never launches gesture/arm control.
set -euo pipefail
: "${BOARD_PW:?BOARD_PW env var must be set (board password)}"
BOARD=xilinx@192.168.240.10
ASKPASS=/e/competition/3_host/pynq/pl_reloader/ssh_askpass.cmd
export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force EES331_SSH_PASSWORD="$BOARD_PW"
O='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
SSH="ssh $O $BOARD"
SCP="scp $O"
PKG="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
B=/home/xilinx/net3_ps_only_pl_ble_j5

$SSH 'echo BOARD_OK $(hostname) $(date +%T)'
$SSH "mkdir -p $B"
$SCP "$PKG/sw/board_artifacts/t1_overlay_ble_j5.bit" "$BOARD":$B/net3_ps_only_pl_ble_j5.bit
$SCP "$PKG/sw/board_artifacts/t1_overlay_ble_j5.hwh" "$BOARD":$B/net3_ps_only_pl_ble_j5.hwh
$SCP "$PKG/sw/board/ble_driver.py" "$PKG/sw/board/b2_board_ble_run.py" "$BOARD":$B/
$SCP "$PKG/sw/board/vdma_halt.py" "$PKG/sw/board/vdma_halt_check.py" "$BOARD":$B/

( cd "$PKG" && sha256sum -b \
  sw/board_artifacts/t1_overlay_ble_j5.bit \
  sw/board_artifacts/t1_overlay_ble_j5.hwh \
  sw/board/ble_driver.py sw/board/b2_board_ble_run.py \
  sw/board/vdma_halt.py sw/board/vdma_halt_check.py ) > /tmp/j5_pc_ble_want.txt
$SSH "cd $B && sha256sum -b net3_ps_only_pl_ble_j5.bit net3_ps_only_pl_ble_j5.hwh ble_driver.py b2_board_ble_run.py vdma_halt.py vdma_halt_check.py" > /tmp/j5_pc_ble_got.txt
if ! diff /tmp/j5_pc_ble_want.txt /tmp/j5_pc_ble_got.txt; then
  echo "FATAL: board SHA mismatch"; exit 1
fi
echo SHA_VERIFY_PASS

# M13 quiesce before any overlay download.
$SSH "echo $BOARD_PW | sudo -S systemctl stop ees331-camera 2>&1 | grep -v 'password for' || true"
$SSH "echo $BOARD_PW | sudo -S pkill -f 't1_gesture_main.*.p[y]' 2>/dev/null || true"
$SSH "echo $BOARD_PW | sudo -S pkill -f 'b2_board_ble_run.*.p[y]' 2>/dev/null || true"
sleep 3
$SSH "echo $BOARD_PW | sudo -S env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 $B/vdma_halt.py /home/xilinx/ees331_camera/overlay.bit"
$SSH "echo $BOARD_PW | sudo -S env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 $B/vdma_halt_check.py /home/xilinx/ees331_camera/overlay.bit"

# Config mode downloads the new bit and checks CSR/AT/ROLE0 only. No arm protocol.
$SSH "echo $BOARD_PW | sudo -S env XILINX_XRT=/usr /usr/local/share/pynq-venv/bin/python3 -u $B/b2_board_ble_run.py --bit $B/net3_ps_only_pl_ble_j5.bit --mode config --events $B/pc_ble_config_events.jsonl"
echo PC_BLE_TEST_DEPLOY_DONE
