#!/bin/bash
set -euo pipefail
[ "$(id -u)" = "0" ] || { echo FATAL_ROOT_REQUIRED; exit 1; }
D=${PSPL_ROOT:-$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)}
export PSPL_ROOT="$D"
PY=/usr/local/share/pynq-venv/bin/python3
EXPECTED=${EXPECTED_BIT_SHA256:-72b358ff75a8d1c1bda519da248bd94fb4bdc236dd16fcca36eb4fc1262f7a58}
export EXPECTED_BIT_SHA256="$EXPECTED"
mkdir -p "$D/sw/board_runtime" "$D/evidence"
cp "$D/sw/board_artifacts/hybrid_heads_ic64_fix.bit" "$D/sw/board_artifacts/hybrid_heads_ic64_fix.hwh" "$D/sw/board_runtime/"
ACTUAL=$(sha256sum "$D/sw/board_runtime/hybrid_heads_ic64_fix.bit" | cut -d' ' -f1)
[ "$ACTUAL" = "$EXPECTED" ] || { echo "BIT_IDENTITY_FAIL $ACTUAL"; exit 10; }
echo "BIT_IDENTITY_PASS $ACTUAL"

[ "$(systemctl is-active ees331-camera 2>/dev/null || true)" = "active" ] && {
  echo FATAL_CAMERA_SERVICE_ACTIVE; exit 20; }
pgrep -f 'camera.p[y]' >/dev/null && { echo FATAL_CAMERA_PROCESS_ACTIVE; exit 21; }
pgrep -f 'three_task_main.*.p[y]' >/dev/null && { echo FATAL_MULTITASK_CHAIN_ACTIVE; exit 22; }
pgrep -f 'run_live_gesture7.p[y]' >/dev/null && { echo FATAL_LIVE_TEST_ALREADY_ACTIVE; exit 23; }

: "${CURRENT_BIT:?Set CURRENT_BIT to the matched artifact of the currently loaded overlay}"
export XILINX_XRT=/usr
"$PY" "$D/sw/board/check_vdma_halted.py" --bit "$CURRENT_BIT"

if [ ! -x "$D/sw/board/t1_ncnn_server_hybrid" ] || \
   [ "$D/sw/board/t1_ncnn_server_hybrid.cpp" -nt "$D/sw/board/t1_ncnn_server_hybrid" ]; then
  sh "$D/sw/board/build_hybrid_server.sh"
fi

if nc -z 127.0.0.1 5003 >/dev/null 2>&1; then
  if [ -f "$D/evidence/hybrid_server.pid" ] && kill -0 "$(cat "$D/evidence/hybrid_server.pid")" 2>/dev/null; then
    echo RESIDENT_HYBRID_SERVER_REUSE
  else
    echo FATAL_PORT_5003_NOT_OWNED_BY_HYBRID_SERVER
    echo STOP_THE_EXISTING_NCNN_FLEX_SERVER_FIRST
    exit 24
  fi
else
  "$D/sw/board/t1_ncnn_server_hybrid" 5003 "$D/models/c2_registry.conf" \
    >> "$D/evidence/hybrid_server.log" 2>&1 &
  echo $! > "$D/evidence/hybrid_server.pid"
  sleep 1
  nc -z 127.0.0.1 5003 >/dev/null 2>&1 || { echo FATAL_HYBRID_SERVER_START; exit 25; }
  echo RESIDENT_HYBRID_SERVER_READY
fi

export TB_SETUP_PATH="$D/prog/tb_setup_six_branches.txt"
export SIX_BRANCHES=1
exec "$PY" "$D/sw/board/run_live_gesture7.py" "$@"
