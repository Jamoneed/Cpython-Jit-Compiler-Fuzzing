#!/bin/bash
PYTHON=~/fuzzing/cpython/python
TEST=~/fuzzing/lowmem_tests/scripts/trace_exhaustion.py
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase4_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 4: Trace Cache Exhaustion ===" && log "Date: $(date)" && log ""

# 4A: Baseline
log "--- 4A: Baseline ---"
OUT=$(PYTHON_JIT=1 PYTHONFAULTHANDLER=1 $PYTHON $TEST 2>&1; echo _EXIT_:$?)
EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
log "Baseline: exit=$EXIT"
echo "$OUT" | grep -qE "Aborted|Segmentation fault" && echo "$OUT" > "$CRASHES/phase4_baseline.log"

# 4B: Exhaustion + mmap injection
log "" && log "--- 4B: Exhaustion + mmap injection ---"
for RATE in 0.1 0.2 0.5; do
    for RUN in 1 2 3; do
        OUT=$(MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
              LD_PRELOAD=$FAIL_MMAP $PYTHON $TEST 2>&1; echo _EXIT_:$?)
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
            log "*** CRASH: exhaustion mmap=$RATE run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase4_exhaust_mmap${RATE}_run${RUN}.log"
        else
            log "  rate=$RATE run=$RUN: exit=$EXIT clean"
        fi
    done
done

# 4C: Exhaustion + ulimit
log "" && log "--- 4C: Exhaustion + ulimit ---"
for MB in 512 256 128; do
    KB=$((MB * 1024))
    OUT=$(bash -c "ulimit -v $KB; PYTHON_JIT=1 PYTHONFAULTHANDLER=1 $PYTHON $TEST 2>&1; echo _EXIT_:\$?")
    EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
    if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
        log "*** CRASH: exhaustion ${MB}MB ***"
        echo "$OUT" > "$CRASHES/phase4_exhaust_${MB}mb.log"
    else
        log "  ${MB}MB: exit=$EXIT clean"
    fi
done

log "=== Phase 4 Complete ==="
