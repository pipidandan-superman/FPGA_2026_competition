#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

# Deploy 2026-11-03 font-base fix: ASCII-indexed osd_font32.hex baked into BIT
# b698378f + unchanged PS logic (only BIT_SHA256 constant bump).
# Same proven channel as deploy_fix_run01.sh (BOARD_PW -> EES331_SSH_PASSWORD
# -> ssh_askpass.cmd). Backs up the 621e3121-era board copies first.
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

echo '== backup board copies (621e3121 era) + swap bit + ps script =='
$SSH "cp $D/three_task_main_split.py $D/three_task_main_split.py.bak_v2 2>/dev/null || true; cp $D/multitask_osd.bit $D/multitask_osd.bit.bak_621e3121 2>/dev/null || true; sha256sum $D/multitask_osd.bit $D/three_task_main_split.py"
$SCP "$CAND/multitask_osd.bit" "$PSD/three_task_main_split.py" "$BOARD":$D/
$SSH "sha256sum $D/multitask_osd.bit $D/three_task_main_split.py"

echo '== relaunch chain =='
$SSH "echo $BOARD_PW | sudo -S bash $D/launch_board.sh 2>&1 | grep -v 'password for'" | tee "$RUN/board_relaunch_v2.log"
sleep 35
$SSH 'tail -30 /home/xilinx/multitask_osd/chain.log' | tee "$RUN/board_chain_v2.log"
echo FIX_V2_DEPLOY_DONE
