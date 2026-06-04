# Phase 3 — Manual jit.c Patch

Phase 3 requires injecting a fault at a specific allocation number inside CPython's
JIT allocator. This needs a one-time manual patch to `jit.c` and a rebuild.

## Step 1: Backup and open jit.c

```bash
cp ~/fuzzing/cpython/Python/jit.c ~/fuzzing/cpython/Python/jit.c.bak
nano ~/fuzzing/cpython/Python/jit.c   # or vim
```

## Step 2: Find jit_alloc

Search for the function `jit_alloc`. It looks something like:

```c
static void *
jit_alloc(size_t size)
{
    // ... existing code ...
```

## Step 3: Insert the fault injection block

Add this block immediately after the opening `{` of `jit_alloc`, **before** any
existing code in the function:

```c
    // ── FAULT INJECTION ──────────────────────────────────────────────────────
    {
        static long _count = 0;
        static long _fail_after = -1;
        static int _init = 0;
        if (!_init) {
            _init = 1;
            const char *env = getenv("JIT_ALLOC_FAIL_AFTER");
            if (env) _fail_after = atol(env);
        }
        if (_fail_after > 0 && ++_count >= _fail_after) {
            fprintf(stderr, "[jit_alloc] INJECTING FAIL at alloc #%ld\n", _count);
            return NULL;
        }
    }
    // ─────────────────────────────────────────────────────────────────────────
```

You'll also need `#include <stdlib.h>` at the top of the file if it isn't already
there (for `atol` and `getenv`).

## Step 4: Rebuild CPython

```bash
cd ~/fuzzing/cpython
make -j$(nproc) PYTHON_FOR_BUILD=/home/hameed/venvs/lafleur_venv/bin/python3.15
```

## Step 5: Verify the patch works

```bash
JIT_ALLOC_FAIL_AFTER=1 PYTHON_JIT=1 ~/fuzzing/cpython/python -c "
def hot():
    for i in range(300): pass
hot()
" 2>&1 | head -5
```

You should see a line like:
```
[jit_alloc] INJECTING FAIL at alloc #1
```

If you do, the patch is working. Run Phase 3:

```bash
bash ~/fuzzing/lowmem_tests/scripts/phase3_systematic.sh
```

## Reverting after Phase 3

```bash
cp ~/fuzzing/cpython/Python/jit.c.bak ~/fuzzing/cpython/Python/jit.c
cd ~/fuzzing/cpython
make -j$(nproc) PYTHON_FOR_BUILD=/home/hameed/venvs/lafleur_venv/bin/python3.15
```
