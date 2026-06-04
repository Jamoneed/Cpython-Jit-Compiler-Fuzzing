#!/bin/bash
PYTHON=~/fuzzing/cpython/python
FAIL_MMAP=~/fuzzing/lowmem_tests/injectors/fail_mmap.so
REPORT=~/fuzzing/lowmem_tests/reports/phase11_$(date +%Y%m%d_%H%M%S).txt

log() { echo "$1" | tee -a "$REPORT"; }

BENCH=$(cat << 'EOF'
import time, sys
def hot():
    x = 0
    for i in range(300): x += i
    return x
for _ in range(10): hot()  # warm up
start = time.perf_counter()
for _ in range(1000): hot()
print(f"{time.perf_counter()-start:.4f}", file=sys.stderr)
EOF
)

log "=== Phase 11: Performance Under Memory Pressure ===" && log "Date: $(date)" && log ""

JIT_BASE=$(echo "$BENCH" | PYTHON_JIT=1 $PYTHON /dev/stdin 2>&1 | tail -1)
NOJIT_BASE=$(echo "$BENCH" | PYTHON_JIT=0 $PYTHON /dev/stdin 2>&1 | tail -1)
log "Baseline JIT=1:  ${JIT_BASE}s"
log "Baseline JIT=0:  ${NOJIT_BASE}s"
log ""

for RATE in 0.01 0.05 0.1 0.2 0.5; do
    log "--- mmap fail rate: $RATE ---"
    JIT_T=$(echo "$BENCH" | MMAP_FAIL_RATE=$RATE PYTHON_JIT=1 \
            LD_PRELOAD=$FAIL_MMAP $PYTHON /dev/stdin 2>&1 | tail -1)
    NOJIT_T=$(echo "$BENCH" | MMAP_FAIL_RATE=$RATE PYTHON_JIT=0 \
              LD_PRELOAD=$FAIL_MMAP $PYTHON /dev/stdin 2>&1 | tail -1)
    log "  JIT=1: ${JIT_T}s   JIT=0: ${NOJIT_T}s"

    python3 -c "
jit=float('${JIT_T}' or 0); nojit=float('${NOJIT_T}' or 0)
if jit and nojit:
    ratio=jit/nojit
    if ratio>1.2: print(f'  *** JIT is {ratio:.2f}x SLOWER at rate $RATE (possible thrashing) ***')
    elif ratio<0.8: print(f'  JIT is {1/ratio:.2f}x faster')
    else: print(f'  Similar (ratio={ratio:.2f})')
" 2>/dev/null | tee -a "$REPORT"
    log ""
done

log "=== Phase 11 Complete ==="
