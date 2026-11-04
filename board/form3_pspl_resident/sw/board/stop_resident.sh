#!/bin/sh
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -eu
D=/home/xilinx/PSPL_YOLOV8N_RESIDENT
if [ -f "$D/evidence/hybrid_server.pid" ]; then
    PID=$(cat "$D/evidence/hybrid_server.pid")
    kill "$PID" 2>/dev/null || true
    rm -f "$D/evidence/hybrid_server.pid"
fi
echo RESIDENT_SERVER_STOPPED
