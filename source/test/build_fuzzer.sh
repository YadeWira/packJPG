#!/usr/bin/env bash
# Build the libFuzzer harness for packJPG v4.0.
#
# Requirements: clang++ with libFuzzer (ships with clang 6+). Outputs
# ./pjg_decode_fuzzer. Run as:
#   ./pjg_decode_fuzzer -max_len=1048576 corpus_seeds/ [-max_total_time=900]

set -eu

SRC_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_BIN="${SRC_DIR}/test/pjg_decode_fuzzer"
CXX="${CXX:-clang++}"

FLAGS=(
    -std=c++17
    -O1
    -g
    -DUNIX
    -DBUILD_LIB
    -fsanitize=fuzzer,address,undefined
    -fno-omit-frame-pointer
    -I"${SRC_DIR}"
)

SOURCES=(
    "${SRC_DIR}/packjpg.cpp"
    "${SRC_DIR}/aricoder.cpp"
    "${SRC_DIR}/bitops.cpp"
    "${SRC_DIR}/test/pjg_decode_fuzzer.cpp"
)

echo "[fuzzer] building with ${CXX}"
"${CXX}" "${FLAGS[@]}" "${SOURCES[@]}" -lpthread -o "${OUT_BIN}"

echo "[fuzzer] built ${OUT_BIN}"
