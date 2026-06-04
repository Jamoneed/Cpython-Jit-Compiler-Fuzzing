#!/bin/bash
# Phase 3 — Systematic Allocator Walk
# REQUIRES: jit.c patched first (see PHASE3_PATCH.md) and CPython rebuilt.

PYTHON=~/fuzzing/cpython/python
TEST=~/fuzzing/lowmem_tests/scripts/harness.py
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase3_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

# Sanity check: verify the patch is active
TEST_OUT=$(JIT_ALLOC_FAIL_AFTER=1 PYTHON_JIT=1 $PYTHON -c "
def hot():
    for i in range(300): pass
hot()
" 2>&1)
if ! echo "$TEST_OUT" | grep -q "\[jit_alloc\]"; then
    echo "ERROR: JIT_ALLOC_FAIL_AFTER env var has no effect."
    echo "You must patch ~/fuzzing/cpython/Python/jit.c first."
    echo "See PHASE3_PATCH.md for instructions, then rebuild CPython."
    exit 1
fi

log "=== Phase 3: Systematic JIT Allocator Walk ===" && log "Date: $(date)" && log ""

for N in $(seq 1 100); do
    OUT=$(JIT_ALLOC_FAIL_AFTER=$N PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
          $PYTHON $TEST 2>&1; echo _EXIT_:$?)
    EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)

    if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed|Fatal Python"; then
        log "*** HARD CRASH at N=$N ***"
        echo "$OUT" > "$CRASHES/phase3_alloc_N${N}.log"

        NOJIT_EXIT=$(PYTHON_JIT=0 $PYTHON $TEST > /dev/null 2>&1; echo $?)
        log "  Without JIT: exit=$NOJIT_EXIT"
        [ "$NOJIT_EXIT" = "0" ] && log "  *** CONFIRMED JIT-SPECIFIC BUG ***"
    else
        log "  N=$N: exit=$EXIT graceful"
    fi
done

log "=== Phase 3 Complete ==="
