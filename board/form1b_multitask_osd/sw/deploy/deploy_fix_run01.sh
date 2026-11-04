#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

# Deploy 2026-11-02 fix run: font-fixed BIT (task_coco/task_pose_osd odd-row
# bit-range fix) + margin-gated immediate gesture display (net3-parity).
# Follows the proven 2026-11-01_three_task_net3_run01/scripts/deploy_three_task.sh
# credential channel (BOARD_PW -> EES331_SSH_PASSWORD -> ssh_askpass.cmd).
set -euo pipefail
: "${BOARD_PW:?BOARD_PW env var must be set}"
BOARD=xilinx@192.168.240.10
RUN=/e/competition/4_metrics/logs/2026-11-02_multitask_fix_run01
CAND=$RUN/candidate
PSD=$RUN/ps
D=/home/xilinx/multitask_osd
export EES331_SSH_PASSWORD="$BOARD_PW"
export SSH_ASKPASS=/e/competition/3_host/pynq/pl_reloader/ssh_askpass.cmd
export SSH_ASKPASS_REQUIRE=force
O='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10'
SSH="ssh $O $BOARD"
SCP="scp $O"

echo '== pre state =='
$SSH 'echo BOARD_OK; cat /proc/sys/kernel/random/boot_id; pgrep -fa "three_task_main.*.p[y]|t1_ncnn_server" || true'

echo '== stop current chain (SIGTERM -> handler closes VDMA/camera) =='
$SSH "echo $BOARD_PW | sudo -S pkill -f 'three_task_main.*.p[y]' 2>/dev/null || true; sleep 4; pgrep -fa 'three_task_main.*.p[y]' || echo CHAIN_STOPPED"

echo '== backup board copies + swap bit + ps script =='
$SSH "cp $D/three_task_main_split.py $D/three_task_main_split.py.bak_streak 2>/dev/null || true; cp $D/multitask_osd.bit $D/multitask_osd.bit.bak_dbf4501c 2>/dev/null || true; sha256sum $D/multitask_osd.bit $D/three_task_main_split.py"
$SCP "$CAND/multitask_osd.bit" "$PSD/three_task_main_split.py" "$BOARD":$D/
$SSH "sha256sum $D/multitask_osd.bit $D/three_task_main_split.py"

echo '== relaunch chain (launch_board.sh guards camera service) =='
$SSH "echo $BOARD_PW | sudo -S bash $D/launch_board.sh 2>&1 | grep -v 'password for'" | tee "$RUN/board_relaunch.log"
sleep 35
$SSH 'tail -30 /home/xilinx/multitask_osd/chain.log' | tee "$RUN/board_chain_initial.log"
echo FIX_DEPLOY_DONE
