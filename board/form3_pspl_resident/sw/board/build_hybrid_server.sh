#!/bin/sh
set -eu
D=${PSPL_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)}
NCNN_SOURCE=${NCNN_SOURCE:-/home/xilinx/ncnn_build}
NCNN_BUILD=${NCNN_BUILD:-$NCNN_SOURCE/build_neon2}
SRC="$D/sw/board/t1_ncnn_server_hybrid.cpp"
OUT="$D/sw/board/t1_ncnn_server_hybrid"
g++ -O2 -mfpu=neon -mfloat-abi=hard -fopenmp "$SRC" \
    -I"$NCNN_SOURCE/src" \
    -I"$NCNN_BUILD/src" \
    "$NCNN_BUILD/src/libncnn.a" \
    -lpthread -o "$OUT"
echo HYBRID_SERVER_BUILD_PASS "$OUT"
