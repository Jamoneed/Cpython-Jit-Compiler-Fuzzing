#!/bin/bash
PYTHON=~/fuzzing/cpython/python
FT_PYTHON=~/fuzzing/cpython_freethreaded/python
TEST=~/fuzzing/lowmem_tests/scripts/invalidation_stress.py
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase6_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 6: Trace Invalidation Racing ===" && log "Date: $(date)" && log ""

for RATE in 0.05 0.1 0.2; do
    for RUN in $(seq 1 5); do
        OUT=$(MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
              LD_PRELOAD=$FAIL_MMAP $PYTHON $TEST 2>&1; echo _EXIT_:$?)
        if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
            log "*** CRASH debug rate=$RATE run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase6_inval_debug_${RATE}_run${RUN}.log"
        else
            log "  debug rate=$RATE run=$RUN: clean"
        fi

        if [ ! -x "$FT_PYTHON" ]; then
            log "  SKIP ft: $FT_PYTHON not found"
        else
            OUT=$(MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
                  LD_PRELOAD=$FAIL_MMAP $FT_PYTHON $TEST 2>&1; echo _EXIT_:$?)
            if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
                log "*** CRASH ft rate=$RATE run=$RUN ***"
                echo "$OUT" > "$CRASHES/phase6_inval_ft_${RATE}_run${RUN}.log"
            else
                log "  ft rate=$RATE run=$RUN: clean"
            fi
        fi
    done
done

log "=== Phase 6 Complete ==="
