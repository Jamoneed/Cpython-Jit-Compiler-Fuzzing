#!/bin/bash
PYTHON=~/fuzzing/cpython/python
TEST=~/fuzzing/lowmem_tests/scripts/harness.py
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase10_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 10: libfiu Precise Fault Injection ===" && log "Date: $(date)" && log ""

if ! which fiu-run &>/dev/null; then
    log "ERROR: fiu-run not found. Install with: sudo apt-get install -y libfiu-dev fiu-utils"
    exit 1
fi

# 10A: mmap failures
log "--- 10A: libfiu mmap ---"
for PROB in 0.5 0.2 0.1 0.05; do
    for RUN in 1 2 3; do
        OUT=$(fiu-run -x \
              -c "enable_random name=posix/mm/mmap,probability=$PROB" \
              $PYTHON $TEST 2>&1; echo _EXIT_:$?)
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
            log "*** CRASH: libfiu mmap prob=$PROB run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase10_libfiu_mmap_${PROB}_run${RUN}.log"
        else
            log "  prob=$PROB run=$RUN: exit=$EXIT clean"
        fi
    done
done
log ""

# 10B: malloc failures
log "--- 10B: libfiu malloc ---"
for PROB in 0.001 0.005 0.01; do
    for RUN in 1 2 3; do
        OUT=$(fiu-run -x \
              -c "enable_random name=libc/mm/malloc,probability=$PROB" \
              $PYTHON $TEST 2>&1; echo _EXIT_:$?)
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
            log "*** CRASH: libfiu malloc prob=$PROB run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase10_libfiu_malloc_${PROB}_run${RUN}.log"
        else
            log "  prob=$PROB run=$RUN: exit=$EXIT clean"
        fi
    done
done

log "=== Phase 10 Complete ==="
