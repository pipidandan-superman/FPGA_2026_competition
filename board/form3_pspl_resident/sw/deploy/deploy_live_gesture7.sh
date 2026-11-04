#!/bin/bash
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

# Upload only: no service stop, overlay download, or board application launch.
set -euo pipefail
: "${BOARD_PW:?BOARD_PW env var must be set}"
BOARD=xilinx@192.168.240.10
ASKPASS=/e/competition/3_host/pynq/pl_reloader/ssh_askpass.cmd
export SSH_ASKPASS="$ASKPASS" SSH_ASKPASS_REQUIRE=force EES331_SSH_PASSWORD="$BOARD_PW"
O='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'
SSH="ssh $O $BOARD"
SCP="scp $O"
RUN="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PKG=/e/competition/13_final/PSPL_YOLOV8N_RESIDENT
B=/home/xilinx/PSPL_YOLOV8N_RESIDENT

$SSH 'echo BOARD_OK $(hostname)'
$SSH "mkdir -p $B/evidence $B/features $B/live_segments $B/sw/board"
$SCP -r "$PKG/sw" "$PKG/prog" "$PKG/gold" "$PKG/models" "$BOARD":$B/
$SCP "$RUN/candidate/sw/board/run_live_gesture7.py" \
     "$RUN/candidate/sw/board/pl_heads_runtime.py" \
     "$RUN/candidate/sw/board/hybrid_pipeline_resident.py" \
     "$RUN/candidate/sw/board/run_live_gesture7.sh" \
     "$RUN/candidate/sw/board/build_hybrid_server.sh" \
     "$RUN/candidate/sw/board/t1_ncnn_server_hybrid.cpp" \
     "$RUN/candidate/sw/board/check_vdma_halted.py" \
     "$RUN/candidate/sw/board/t1_gesture_main.py" "$BOARD":$B/sw/board/
# Registry MUST carry no trailing newline: the server parser reads it into the
# ncnn output blob name ("output0\n" -> find_blob_index_by_name fails).
$SCP "$RUN/candidate/sw/models/c2_registry.conf" "$BOARD":$B/models/
$SSH "chmod +x $B/sw/board/*.sh; mkdir -p $B/sw/board_runtime; cp $B/sw/board_artifacts/hybrid_heads_ic64_fix.bit $B/sw/board_artifacts/hybrid_heads_ic64_fix.hwh $B/sw/board_runtime/"
ACTUAL=$($SSH "sha256sum $B/sw/board_runtime/hybrid_heads_ic64_fix.bit" | cut -d' ' -f1)
EXPECTED=72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58
[ "$ACTUAL" = "$EXPECTED" ] || { echo FATAL_REMOTE_BIT_SHA_MISMATCH; exit 1; }
echo SHA_VERIFY_PASS
echo DEPLOY_ONLY_NO_BOARD_RECONFIG
