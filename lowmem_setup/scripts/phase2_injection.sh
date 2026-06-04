#!/bin/bash
PYTHON=~/fuzzing/cpython/python
TEST=~/fuzzing/lowmem_tests/scripts/harness.py
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
FAIL_MALLOC=~/fuzzing/lowmem_tests/injectors/fail_malloc.so
CRASHES=~/fuzzing/lowmem_tests/crashes
REPORT=~/fuzzing/lowmem_tests/reports/phase2_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }
is_hard_crash() { echo "$1" | grep -qE "Aborted|Segmentation fault|Assertion.*failed|Fatal Python"; }

log "=== Phase 2: Random Injection Testing ===" && log "Date: $(date)" && log ""

# 2A: mmap random failure
log "--- 2A: Random mmap failure ---"
for RATE in 1.0 0.5 0.2 0.1 0.05 0.02 0.01 0.005; do
    for RUN in 1 2 3 4 5; do
        OUT=$(MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
              LD_PRELOAD=$FAIL_MMAP $PYTHON $TEST 2>&1; echo _EXIT_:$?)
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if is_hard_crash "$OUT"; then
            log "*** CRASH: mmap rate=$RATE run=$RUN ***"
            echo "$OUT" > "$CRASHES/phase2_mmap_${RATE}_run${RUN}.log"
        else
            log "  mmap rate=$RATE run=$RUN: exit=$EXIT clean"
        fi
    done
done
log ""

# 2B: malloc random failure
log "--- 2B: Random malloc failure ---"
for RATE in 0.01 0.005 0.001 0.0005; do
    for MIN_SIZE in 0 64 256 1024; do
        for RUN in 1 2 3; do
            OUT=$(MALLOC_FAIL_RATE=$RATE MALLOC_FAIL_MIN_SIZE=$MIN_SIZE \
                  PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
                  LD_PRELOAD=$FAIL_MALLOC $PYTHON $TEST 2>&1; echo _EXIT_:$?)
            EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
            if is_hard_crash "$OUT"; then
                log "*** CRASH: malloc rate=$RATE minsize=$MIN_SIZE run=$RUN ***"
                echo "$OUT" > "$CRASHES/phase2_malloc_${RATE}_min${MIN_SIZE}_run${RUN}.log"
            else
                log "  malloc rate=$RATE minsize=$MIN_SIZE run=$RUN: exit=$EXIT clean"
            fi
        done
    done
done
log ""

# 2C: combined mmap + ulimit
log "--- 2C: Combined mmap + ulimit ---"
for MB in 512 256 128; do
    KB=$((MB * 1024))
    for RATE in 0.1 0.2 0.5; do
        OUT=$(bash -c "ulimit -v $KB; MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 PYTHONFAULTHANDLER=1 \
              LD_PRELOAD=$FAIL_MMAP $PYTHON $TEST 2>&1; echo _EXIT_:\$?")
        EXIT=$(echo "$OUT" | grep "_EXIT_:" | tail -1 | cut -d: -f2)
        if is_hard_crash "$OUT"; then
            log "*** CRASH: combined ${MB}mb mmap=$RATE ***"
            echo "$OUT" > "$CRASHES/phase2_combined_${MB}mb_${RATE}.log"
        else
            log "  combined ${MB}mb mmap=$RATE: exit=$EXIT clean"
        fi
    done
done

log "=== Phase 2 Complete ==="
