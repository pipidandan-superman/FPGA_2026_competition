#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

# Deploy 2026-11-03 gesture display-gate fix (net3 parity: immediate show,
# margin guard only for thumb classes at 0.15). PS-only: same v3 BIT
# c910f8ce stays loaded; only three_task_main_split.py changes.
# Suppression evidence saved first: ps/board_chain_gate_suppression_1103.log
set -euo pipefail
: "${BOARD_PW:?BOARD_PW env var must be set}"
BOARD=xilinx@192.168.240.10
RUN=/e/competition/4_metrics/logs/2026-11-02_multitask_fix_run01
PSD=$RUN/ps
D=/home/xilinx/multitask_osd
export EES331_SSH_PASSWORD="$BOARD_PW"
export SSH_ASKPASS=/e/competition/3_host/pynq/pl_reloader/ssh_askpass.cmd
export SSH_ASKPASS_REQUIRE=force
O='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
SSH="ssh $O $BOARD"
SCP="scp $O"

echo '== pre state =='
$SSH 'pgrep -fa "three_task_main.*.p[y]|t1_ncnn_server" || true'

echo '== stop current chain (SIGTERM -> handler closes VDMA/camera) =='
$SSH "echo $BOARD_PW | sudo -S pkill -f 'three_task_main.*.p[y]' 2>/dev/null || true; sleep 4; pgrep -fa 'three_task_main.*.p[y]' || echo CHAIN_STOPPED"

echo '== backup board ps script (gate era) + swap =='
$SSH "cp $D/three_task_main_split.py $D/three_task_main_split.py.bak_gate1103 2>/dev/null || true; sha256sum $D/three_task_main_split.py"
$SCP "$PSD/three_task_main_split.py" "$BOARD":$D/
$SSH "sha256sum $D/three_task_main_split.py"
sha256sum "$PSD/three_task_main_split.py"

echo '== relaunch chain =='
$SSH "echo $BOARD_PW | sudo -S bash $D/launch_board.sh 2>&1 | grep -v 'password for'" | tee "$RUN/board_relaunch_gatefix.log" || true
sleep 35
$SSH 'tail -20 /home/xilinx/multitask_osd/chain.log' | tee "$RUN/board_chain_gatefix.log" || true

echo '== switch live task to gesture (1) for visual check =='
$SSH "echo $BOARD_PW | sudo -S sh -c 'echo 1 > $D/model_select'"
sleep 12
$SSH 'tail -8 /home/xilinx/multitask_osd/chain.log' | tee -a "$RUN/board_chain_gatefix.log"
echo GATE_FIX_DEPLOY_DONE
