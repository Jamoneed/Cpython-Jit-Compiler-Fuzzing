#!/bin/bash
PYTHON=~/fuzzing/cpython/python
TEST=~/fuzzing/lowmem_tests/scripts/harness.py
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase1_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 1: ulimit Threshold Mapping ===" && log "Date: $(date)" && log ""

for MB in 4096 2048 1024 512 256 128 96 64 48 32 24 16; do
    KB=$((MB * 1024)); log "--- Testing ${MB}MB ---"

    JIT_OUT=$(bash -c "ulimit -v $KB; PYTHON_JIT=1 PYTHONFAULTHANDLER=1 $PYTHON $TEST 2>&1; echo _EXIT_:\$?" 2>&1)
    JIT_EXIT=$(echo "$JIT_OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
    JIT_CRASH=$(echo "$JIT_OUT" | grep -cE "Aborted|Segmentation fault|Assertion.*failed|Fatal Python")

    NOJIT_OUT=$(bash -c "ulimit -v $KB; PYTHON_JIT=0 PYTHONFAULTHANDLER=1 $PYTHON $TEST 2>&1; echo _EXIT_:\$?" 2>&1)
    NOJIT_EXIT=$(echo "$NOJIT_OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
    NOJIT_CRASH=$(echo "$NOJIT_OUT" | grep -cE "Aborted|Segmentation fault|Assertion.*failed|Fatal Python")

    log "JIT=1: exit=$JIT_EXIT hard_crash=$JIT_CRASH"
    log "JIT=0: exit=$NOJIT_EXIT hard_crash=$NOJIT_CRASH"

    if [ "$JIT_CRASH" -gt 0 ] && [ "$NOJIT_CRASH" -eq 0 ]; then
        log "*** BUG CANDIDATE: JIT crashes, no-JIT passes at ${MB}MB ***"
        echo "$JIT_OUT" > "$CRASHES/phase1_jit_crash_${MB}mb.log"
    fi

    log ""
done

log "=== Phase 1 Complete ==="
