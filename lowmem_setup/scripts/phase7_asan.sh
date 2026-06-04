#!/bin/bash
ASAN_PYTHON=~/fuzzing/cpython_asan/python
TEST=~/fuzzing/lowmem_tests/scripts/harness.py
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase7_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 7: ASAN Under Memory Pressure ===" && log "Date: $(date)" && log ""

for RATE in 0.05 0.1 0.2 0.5; do
    for RUN in 1 2 3; do
        log "--- ASAN rate=$RATE run=$RUN ---"
        OUT=$(MMAP_FAIL_RATE=$RATE \
              ASAN_OPTIONS="detect_leaks=0:abort_on_error=1" \
              PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
              LD_PRELOAD=$FAIL_MMAP \
              $ASAN_PYTHON $TEST 2>&1; echo _EXIT_:$?)
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if echo "$OUT" | grep -qE "Aborted|Segmentation fault|ERROR: AddressSanitizer|Assertion.*failed"; then
            log "*** CRASH/ASAN: rate=$RATE run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase7_asan_${RATE}_run${RUN}.log"
        else
            log "  exit=$EXIT clean"
        fi
    done
done

log "=== Phase 7 Complete ==="
