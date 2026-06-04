# unlink_executor assertion failure — low-memory campaign (Phase 8)

## Summary

JIT-specific assertion failure in `unlink_executor` in `Python/optimizer.c`,
found during Phase 8 (libfiu mmap injection) of the low-memory stress-testing
campaign. Triggered when `mmap` calls for JIT executable pages are failed at
random using libfiu's `posix/mm/mmap` injection point.

This is a novel finding. It is not the same assertion as gh-136996, which
also involves `unlink_executor` but hits a different condition in the same
function. No upstream commit explicitly named this exact assertion. The most
likely explanation is that it was resolved as a side effect of JIT changes
that landed between April 1 and April 14, 2026.

---

## Crash details

| Field | Value |
|---|---|
| Affected build | CPython main commit `c32e264227b` (April 1, 2026) |
| Fixed build | CPython main commit `d0e7c6acc93` (April 14, 2026) |
| Build flags | `--with-pydebug --enable-experimental-jit` |
| Function | `unlink_executor` in `Python/optimizer.c` |
| Assertion | `idx >= 0 && (size_t)idx < interp->executor_count` |
| Reproduction rate | ~15–18% with `PYTHON_JIT=1` |
| Reproduction rate | 0% with `PYTHON_JIT=0` across 50 runs |
| Campaign phase | Phase 8 — libfiu precise mmap injection |
| Injection command | `fiu-run -x -c "enable_random name=posix/mm/mmap,probability=0.5"` |
| Related upstream issue | gh-136996 (same function, different assertion) |

---

## Expected crash output

When the failure triggers you will see output like this:

```
python: Python/optimizer.c:NNN:
unlink_executor:
Assertion 'idx >= 0 && (size_t)idx < interp->executor_count' failed.
Aborted (core dumped)
```

Process exits with SIGABRT. Because the failure is nondeterministic
(~15–18% hit rate), most runs will exit cleanly and only some will crash.

---

## Files in this directory

| File | Description |
|---|---|
| `reproducer.py` | Python script that triggers the failure under libfiu mmap injection |
| `README.md` | This file |

---

## Prerequisites

```bash
# Install libfiu if not already present
sudo apt install -y libfiu-dev fiu-utils

# Verify fiu-run is available
fiu-run --help
```

---

## Reproducing the crash

### Step 1: Check out the affected CPython build

```bash
cd ~/fuzzing/cpython
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit
make -j$(nproc)
```

### Step 2: Run the reproducer under libfiu mmap injection

The failure is nondeterministic. Run it in a loop — expect a crash within
~10 runs at probability=0.5:

```bash
for i in $(seq 1 50); do
    result=$(PYTHON_JIT=1 fiu-run -x \
        -c "enable_random name=posix/mm/mmap,probability=0.5" \
        ~/fuzzing/cpython/python \
        crashes/unlink_executor_lowmem/reproducer.py 2>&1)
    if echo "$result" | grep -qE "Assertion|Aborted|SIGABRT"; then
        echo "RUN $i: CRASH"
        echo "$result"
        break
    else
        echo "RUN $i: clean"
    fi
done
```

The `-x` flag is required. It tells libfiu to intercept at the libc call
level. Without it the failure does not reproduce.

### Step 3: Confirm JIT-specificity

```bash
# With JIT enabled — crashes ~15-18% of runs:
PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    ~/fuzzing/cpython/python \
    crashes/unlink_executor_lowmem/reproducer.py

# With JIT disabled — clean across all runs (0/50 in original campaign):
PYTHON_JIT=0 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    ~/fuzzing/cpython/python \
    crashes/unlink_executor_lowmem/reproducer.py
echo "Exit code: $?"
```

---

## Confirming the fix

Update to the fixed build and verify the failure no longer reproduces:

```bash
cd ~/fuzzing/cpython
git checkout d0e7c6acc93
make -j$(nproc)

# Run 100 times — should be clean across all runs:
CLEAN=0; CRASH=0
for i in $(seq 1 100); do
    result=$(PYTHON_JIT=1 fiu-run -x \
        -c "enable_random name=posix/mm/mmap,probability=0.5" \
        ~/fuzzing/cpython/python \
        crashes/unlink_executor_lowmem/reproducer.py 2>&1)
    if echo "$result" | grep -qE "Assertion|Aborted"; then
        CRASH=$((CRASH+1))
    else
        CLEAN=$((CLEAN+1))
    fi
done
echo "clean=$CLEAN crash=$CRASH"
```

In the original campaign: 100 clean runs, 0 crashes on `d0e7c6acc93`.

---

## Root cause

The JIT allocates executable memory for compiled traces via `mmap` with
`PROT_EXEC | PROT_WRITE`. When libfiu fails those calls, the JIT's cleanup
path in `unlink_executor` runs to tear down the partially-constructed
executor. Under certain conditions, the executor index used during cleanup
falls outside the range recorded in `interp->executor_count`, triggering the
bounds assertion.

This path is effectively untested under normal conditions because `mmap` for
small JIT trace buffers almost always succeeds. libfiu forces the failure
path to be exercised consistently, exposing the bounds check violation.

---

## Distinction from gh-136996

gh-136996 also involves `unlink_executor` in `Python/optimizer.c`. However:

- gh-136996 hits a different assertion in the same function
- This campaign reached the executor index bounds check:
  `idx >= 0 && (size_t)idx < interp->executor_count`
- The two overlap in location but represent distinct failure modes

---

## Verification results from original campaign

| Method | Runs | Crashes on `c32e264227b` | Crashes on `d0e7c6acc93` |
|---|---|---|---|
| libfiu mmap prob=0.5 | 50 | ~8–9 (~15–18%) | 0 |
| ulimit | 50 | 0 | 0 |
| malloc injector | 50 | 0 | 0 |
| libfiu mmap prob=0.5, JIT=0 | 50 | 0 | 0 |

---

## References

- [gh-136996](https://github.com/python/cpython/issues/136996) — related issue
  in the same function (different assertion)
- [libfiu documentation](https://blitiri.com.ar/p/libfiu/)
