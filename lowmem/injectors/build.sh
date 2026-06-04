#!/bin/bash
# Build the LD_PRELOAD fault injector shared libraries
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"

gcc -shared -fPIC -o "$DIR/fail_mmap.so" "$DIR/fail_mmap.c" -ldl
echo "Built fail_mmap.so"

gcc -shared -fPIC -o "$DIR/fail_malloc.so" "$DIR/fail_malloc.c" -ldl
echo "Built fail_malloc.so"
