#!/bin/sh
# Retired historical entry: fixed author paths and unverified ownership gates.
echo 'RETIRED_ENTRY: see package build/README.md and the overlay workflow.' >&2
exit 2

set -eu
D=/home/xilinx/PSPL_YOLOV8N_RESIDENT
mkdir -p "$D/evidence" "$D/features" "$D/live_segments"
if [ ! -x "$D/sw/board/t1_ncnn_server_hybrid" ]; then
    sh "$D/sw/board/build_hybrid_server.sh"
fi
if ! nc -z 127.0.0.1 5003 >/dev/null 2>&1; then
    "$D/sw/board/t1_ncnn_server_hybrid" 5003 "$D/models/c2_registry.conf" \
        >> "$D/evidence/hybrid_server.log" 2>&1 &
    echo $! > "$D/evidence/hybrid_server.pid"
    sleep 1
fi
if [ ! -f "$D/live_input.npy" ]; then
    /usr/local/share/pynq-venv/bin/python3 "$D/sw/board/prepare_live_input.py"
fi
bash "$D/sw/board/run_resident.sh"
