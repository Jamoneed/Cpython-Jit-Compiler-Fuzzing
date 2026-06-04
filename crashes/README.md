# Crashes

Two JIT-specific bugs found during this research — one from each testing track.
Each subdirectory contains the triggering script, full crash details, exact
reproduction commands, expected output, and verification steps.

---

## gh144681_lafleur — coverage-guided fuzzing campaign

Found by lafleur's `debug-1` instance on **March 20, 2026 at 01:19:51**.
Independent reproduction of gh-144681: a JIT assertion failure in
`Python/optimizer.c:790` triggered by runtime code-object mutation
(`func.__code__ = other.__code__`).

| Field | Value |
|---|---|
| Bug | [gh-144681](https://github.com/python/cpython/issues/144681) |
| Assertion | `jump_happened == (target_instr[1].cache & 1)` |
| Signal | SIGABRT, exit code -6 |
| Affected build | `6908372fb81` (CPython 3.15.0a6+, March 2, 2026) |
| Fixed by | [PR #144742](https://github.com/python/cpython/pull/144742), commit `c32e264227b` |
| Mutator | Cache-invalidation family (`CodeSwapMutator`), depth 40 |

**Quick reproduction** (requires build at `6908372fb81`):
```bash
PYTHON_JIT=1 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
# Expected: SIGABRT, Python/optimizer.c:790 assertion failure

PYTHON_JIT=0 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
# Expected: clean exit, code 0
```

Full details, the raw lafleur-generated script, and step-by-step build
instructions are in `gh144681_lafleur/README.md`.

---

## unlink_executor_lowmem — low-memory stress-testing campaign

Found during **Phase 8 (libfiu mmap injection)** of the low-memory framework,
on CPython main commit `c32e264227b` (April 1, 2026). A JIT-specific assertion
failure in `unlink_executor` in `Python/optimizer.c`, distinct from gh-136996
despite occurring in the same function.

| Field | Value |
|---|---|
| Assertion | `idx >= 0 && (size_t)idx < interp->executor_count` |
| Signal | SIGABRT |
| Affected build | `c32e264227b` (April 1, 2026) |
| No longer reproduces | After `d0e7c6acc93` (April 14, 2026) |
| Reproduction rate | ~15–18% with `PYTHON_JIT=1`, 0% with `PYTHON_JIT=0` |
| Related issue | [gh-136996](https://github.com/python/cpython/issues/136996) (same function, different assertion) |

**Quick reproduction** (requires build at `c32e264227b` and libfiu installed):
```bash
# Run in a loop — expect a crash within ~10 attempts
for i in $(seq 1 50); do
    result=$(PYTHON_JIT=1 fiu-run -x \
        -c "enable_random name=posix/mm/mmap,probability=0.5" \
        ~/fuzzing/cpython/python \
        crashes/unlink_executor_lowmem/reproducer.py 2>&1)
    if echo "$result" | grep -qE "Assertion|Aborted"; then
        echo "RUN $i: CRASH"; echo "$result"; break
    else
        echo "RUN $i: clean"
    fi
done

# JIT-specificity check — should be clean 100% of the time:
PYTHON_JIT=0 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    ~/fuzzing/cpython/python \
    crashes/unlink_executor_lowmem/reproducer.py
```

Full details, root cause analysis, verification table, and fix confirmation
commands are in `unlink_executor_lowmem/README.md`.

---

## Installing libfiu (required for the low-memory crash only)

```bash
sudo apt install -y libfiu-dev fiu-utils
fiu-run --help   # verify install
```
