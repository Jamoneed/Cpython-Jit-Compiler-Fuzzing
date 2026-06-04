#!/bin/bash
# Low-Memory JIT Stress Testing — One-Shot Setup
# Run this from your WSL2 machine as the hameed user.
# Prerequisites: CPython builds at ~/fuzzing/cpython, cpython_asan, cpython_freethreaded
#                lafleur venv at ~/fuzzing/lafleur_venv
set -e

FUZZING=~/fuzzing
LOWMEM=$FUZZING/lowmem_tests

echo "=============================="
echo "Low-Memory JIT Setup"
echo "=============================="

# ── 1. Verify prerequisites ──────────────────────────────────────────────────
echo ""
echo "=== Verifying prerequisites ==="

MISSING=0
check() {
    if [ -e "$1" ]; then echo "  OK: $1"
    else echo "  MISSING: $1"; MISSING=1; fi
}

check $FUZZING/cpython/python
check $FUZZING/cpython_asan/python
check $FUZZING/cpython_freethreaded/python
check $FUZZING/lafleur_venv/bin/activate

if [ $MISSING -eq 1 ]; then
    echo ""
    echo "ERROR: Prerequisites missing. Fix above before continuing."
    echo "Tip: cpython_freethreaded is only needed for phases 5+6."
    echo "     You can proceed without it by removing FT_PYTHON blocks from those scripts."
    exit 1
fi

# Quick functional checks
echo ""
echo "=== Functional checks ==="
PYTHON_JIT=1 $FUZZING/cpython/python -c "import sys; print('JIT build OK, jit =', sys._jit)" || { echo "JIT check FAILED"; exit 1; }
$FUZZING/cpython/python -c "import sys; print('debug =', hasattr(sys,'gettotalrefcount'))"
ASAN_OPTIONS="detect_leaks=0" $FUZZING/cpython_asan/python -c "print('ASAN build OK')" || { echo "ASAN check FAILED"; exit 1; }
bash -c "ulimit -v 524288; echo 'ulimit OK'"

# ── 2. Directory structure ────────────────────────────────────────────────────
echo ""
echo "=== Creating directory structure ==="
mkdir -p $LOWMEM/{results,crashes,injectors,scripts,seeds,reports,labeille_results}
echo "Created $LOWMEM"

# ── 3. Build injectors ────────────────────────────────────────────────────────
echo ""
echo "=== Building injectors ==="

cat > $LOWMEM/injectors/fail_mmap.c << 'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sys/mman.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
static void *(*real_mmap)(void*, size_t, int, int, int, off_t) = NULL;
static double fail_rate = 0.0;
static long fail_after = -1;
static long exec_mmap_count = 0;
static long fail_count = 0;
static int initialized = 0;
static void init() {
    if (initialized) return;
    initialized = 1;
    srand(time(NULL));
    real_mmap = dlsym(RTLD_NEXT, "mmap");
    char *rate = getenv("MMAP_FAIL_RATE");
    if (rate) fail_rate = atof(rate);
    char *after = getenv("MMAP_FAIL_AFTER");
    if (after) fail_after = atol(after);
    fprintf(stderr, "[fail_mmap] rate=%.4f fail_after=%ld\n", fail_rate, fail_after);
}
void *mmap(void *addr, size_t length, int prot, int flags, int fd, off_t offset) {
    init();
    if (real_mmap == NULL) { errno = ENOMEM; return MAP_FAILED; }
    if ((prot & PROT_EXEC) && (prot & PROT_WRITE)) {
        exec_mmap_count++;
        if (fail_after > 0 && exec_mmap_count == fail_after) {
            fail_count++;
            fprintf(stderr, "[fail_mmap] INJECTING FAIL at exec mmap #%ld\n", exec_mmap_count);
            errno = ENOMEM;
            return MAP_FAILED;
        }
        if (fail_rate > 0.0 && (double)rand() / RAND_MAX < fail_rate) {
            fail_count++;
            errno = ENOMEM;
            return MAP_FAILED;
        }
    }
    return real_mmap(addr, length, prot, flags, fd, offset);
}
EOF

cat > $LOWMEM/injectors/fail_malloc.c << 'EOF'
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <time.h>
#include <string.h>
static void *(*real_malloc)(size_t) = NULL;
static void *(*real_realloc)(void*, size_t) = NULL;
static void *(*real_calloc)(size_t, size_t) = NULL;
static double fail_rate = 0.0;
static long fail_after = -1;
static long alloc_count = 0;
static size_t min_size = 0;
static int initialized = 0;
static void init() {
    if (initialized) return;
    initialized = 1;
    srand(time(NULL));
    real_malloc = dlsym(RTLD_NEXT, "malloc");
    real_realloc = dlsym(RTLD_NEXT, "realloc");
    real_calloc = dlsym(RTLD_NEXT, "calloc");
    char *rate = getenv("MALLOC_FAIL_RATE");
    if (rate) fail_rate = atof(rate);
    char *after = getenv("MALLOC_FAIL_AFTER");
    if (after) fail_after = atol(after);
    char *minsize = getenv("MALLOC_FAIL_MIN_SIZE");
    if (minsize) min_size = atol(minsize);
}
static int should_fail(size_t size) {
    if (size < min_size) return 0;
    alloc_count++;
    if (fail_after > 0 && alloc_count == fail_after) {
        fprintf(stderr, "[fail_malloc] FAIL at alloc #%ld (size=%zu)\n", alloc_count, size);
        return 1;
    }
    if (fail_rate > 0.0 && (double)rand() / RAND_MAX < fail_rate) return 1;
    return 0;
}
void *malloc(size_t size) { init(); if (should_fail(size)) { errno=ENOMEM; return NULL; } return real_malloc(size); }
void *realloc(void *p, size_t s) { init(); if (should_fail(s)) { errno=ENOMEM; return NULL; } return real_realloc(p,s); }
void *calloc(size_t n, size_t s) { init(); if (should_fail(n*s)) { errno=ENOMEM; return NULL; }
    void *ptr=real_malloc(n*s); if(ptr) memset(ptr,0,n*s); return ptr; }
EOF

gcc -shared -fPIC -o $LOWMEM/injectors/fail_mmap.so \
    $LOWMEM/injectors/fail_mmap.c -ldl
echo "Built fail_mmap.so"

gcc -shared -fPIC -o $LOWMEM/injectors/fail_malloc.so \
    $LOWMEM/injectors/fail_malloc.c -ldl
echo "Built fail_malloc.so"

# Verify injectors load cleanly
echo ""
echo "=== Verifying injectors ==="
MMAP_FAIL_RATE=0 LD_PRELOAD=$LOWMEM/injectors/fail_mmap.so \
    $FUZZING/cpython/python -c "print('mmap injector ok')" 2>&1 | head -3
MALLOC_FAIL_RATE=0 LD_PRELOAD=$LOWMEM/injectors/fail_malloc.so \
    $FUZZING/cpython/python -c "print('malloc injector ok')" 2>&1 | head -3

# ── 4. Install phase scripts ──────────────────────────────────────────────────
echo ""
echo "=== Installing phase scripts ==="

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cp $SCRIPT_DIR/scripts/harness.py             $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/trace_exhaustion.py    $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/concurrent_stress.py   $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/invalidation_stress.py $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase1_ulimit.sh       $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase2_injection.sh    $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase4_exhaustion.sh   $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase5_concurrent.sh   $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase6_invalidation.sh $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase7_asan.sh         $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase10_libfiu.sh      $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/phase11_benchmark.sh   $LOWMEM/scripts/
cp $SCRIPT_DIR/scripts/generate_summary.py    $LOWMEM/scripts/
cp $SCRIPT_DIR/run_all.sh                     $LOWMEM/

chmod +x $LOWMEM/scripts/*.sh $LOWMEM/run_all.sh

echo ""
echo "=== Phase 3 note ==="
echo "Phase 3 requires a manual patch to ~/fuzzing/cpython/Python/jit.c"
echo "Instructions: $SCRIPT_DIR/PHASE3_PATCH.md"

echo ""
echo "=============================="
echo "Setup complete!"
echo ""
echo "Next steps:"
echo "  1. Run automated phases:  $LOWMEM/run_all.sh"
echo "  2. Phase 3 (manual patch): see PHASE3_PATCH.md"
echo "  3. Phase 8 (labeille):    $SCRIPT_DIR/scripts/phase8_labeille_manual.sh"
echo "  4. Phase 9 (lafleur):     $SCRIPT_DIR/scripts/phase9_lafleur_manual.sh"
echo "=============================="
