#!/bin/sh
# Native ARMv7 build; requires the target's matching ncnn headers/static library.
set -eu
D=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
NCNN_SOURCE=${NCNN_SOURCE:-/home/xilinx/ncnn_build}
NCNN_BUILD=${NCNN_BUILD:-$NCNN_SOURCE/build_neon2}
OUT=${FLEX_OUTPUT:-$D/t1_ncnn_server_flex.rebuilt}
g++ -O2 -mfpu=neon -mfloat-abi=hard -fopenmp "$D/t1_ncnn_server_flex.cpp" \
    -I"$NCNN_SOURCE/src" -I"$NCNN_BUILD/src" \
    "$NCNN_BUILD/src/libncnn.a" -lpthread -o "$OUT"
sha256sum "$D/t1_ncnn_server_flex.cpp" "$NCNN_BUILD/src/libncnn.a" "$OUT"
echo FLEX_SERVER_BUILD_PASS "$OUT"
