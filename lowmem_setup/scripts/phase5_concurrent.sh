#!/bin/bash
PYTHON=~/fuzzing/cpython/python
FT_PYTHON=~/fuzzing/cpython_freethreaded/python
TEST=~/fuzzing/lowmem_tests/scripts/concurrent_stress.py
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase5_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

log "=== Phase 5: Concurrent Stress ===" && log "Date: $(date)" && log ""

for RATE in 0.3 0.1 0.05 0.01; do
    for MB in 512 256; do
        KB=$((MB * 1024))
        for RUN in $(seq 1 5); do
            OUT=$(bash -c "ulimit -v $KB; MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
                  LD_PRELOAD=$FAIL_MMAP $PYTHON $TEST 2>&1; echo _EXIT_:\$?")
            EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
            if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
                log "*** CRASH: debug conc rate=$RATE ${MB}MB run=$RUN ***"
                echo "$OUT" > "$CRASHES/phase5_debug_conc_${RATE}_${MB}mb_run${RUN}.log"
            elif echo "$OUT" | grep -q "still alive"; then
                log "*** DEADLOCK: rate=$RATE ${MB}MB run=$RUN ***"
                echo "$OUT" > "$CRASHES/phase5_deadlock_${RATE}_${MB}mb_run${RUN}.log"
            else
                log "  rate=$RATE ${MB}MB run=$RUN: exit=$EXIT clean"
            fi
        done
    done
done

# Free-threaded build
log "" && log "--- Free-threaded build ---"
if [ ! -x "$FT_PYTHON" ]; then
    log "  SKIP: $FT_PYTHON not found"
else
    for RATE in 0.3 0.1 0.05; do
        for RUN in $(seq 1 5); do
            OUT=$(MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
                  LD_PRELOAD=$FAIL_MMAP $FT_PYTHON $TEST 2>&1; echo _EXIT_:$?)
            EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
            if echo "$OUT" | grep -qE "Aborted|Segmentation fault|Assertion.*failed"; then
                log "*** CRASH: ft conc rate=$RATE run=$RUN ***"
                echo "$OUT" > "$CRASHES/phase5_ft_conc_${RATE}_run${RUN}.log"
            else
                log "  ft rate=$RATE run=$RUN: exit=$EXIT clean"
            fi
        done
    done
fi

log "=== Phase 5 Complete ==="
