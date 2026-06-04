# CPython JIT Compiler Fuzzing
Coverage-guided fuzzing campaign and low-memory stress testing framework targeting CPython's experimental Tier 2 JIT compiler.

## Overview
This repository archives the research artifacts from two complementary research tracks against CPython's experimental JIT compiler (`--enable-experimental-jit`), conducted as part of a Masters thesis at UC Irvine.

## Track 1 — Coverage-guided fuzzing with lafleur
Uses lafleur, a UOP edge coverage-guided evolutionary fuzzer, to target CPython 3.15's Tier 2 JIT compiler across six parallel build configurations: debug, differential, free-threaded, AddressSanitizer, UndefinedBehaviorSanitizer, and a RAM-disk instance. The campaign independently rediscovered gh-144681, a confirmed JIT assertion failure in `Python/optimizer.c` triggered by runtime code object mutation (`func.__code__ = other.__code__`), validating that the setup correctly targets real JIT vulnerabilities.

## Track 2 — Low-memory stress testing
A 9-phase framework testing JIT behavior under memory pressure using ulimit virtual memory caps, LD_PRELOAD fault injection targeting JIT executable page allocations, deterministic per-allocation failure walking via a direct patch to `jit_alloc` in `Python/jit.c`, trace cache exhaustion, concurrent thread stress testing, trace invalidation racing, ASAN under pressure, libfiu precise fault injection, and performance characterization.

The framework found a JIT-specific assertion failure in `unlink_executor` in `Python/optimizer.c` on CPython main commit `c32e264227b`, triggered via libfiu mmap failure injection (Phase 8). The failure reproduced at a 15–18% rate with `PYTHON_JIT=1` and did not reproduce with `PYTHON_JIT=0` across 50 runs. It no longer reproduced after updating to commit `d0e7c6acc93` on April 14, 2026.

## Contents
- `seed_*.py` — 18 hand-rolled seed files targeting specific JIT UOP families. Each seed has a `uop_harness_f1` function containing a `for i in range(300)` hot loop and a `[f1]` harness marker printed to stderr for lafleur's coverage parser.
- `coverage.py` — lafleur compatibility patch: updated UOP regex to handle CPython 3.15 register suffixes (e.g. `_ITER_NEXT_RANGE_r23`)
- `uop_names.py` — lafleur compatibility patch: four missing UOP names added for CPython 3.15 (`_SWAP_FAST`, `_SWAP_FAST_0`, `_SWAP_FAST_1`, `_SPILL_OR_RELOAD`)
- `launch_campaign.sh` — campaign launch configuration for six parallel lafleur instances via tmux
- `gh144681_crash.py` — minimized reproducer for gh-144681, confirmed to crash on CPython 3.15.0a6+ (commit `6908372fb81`) and pass cleanly on 3.15.0a7+ (commit `c32e264227b`)
- `lowmem/lowmem_setup.tar.gz` — complete low-memory stress testing framework including `fail_mmap.c`, `fail_malloc.c`, `harness.py`, and all 9 phase runner scripts

## Low-Memory Framework Phases
| Phase | Method | Target |
|-------|--------|--------|
| 1 | ulimit virtual memory caps (4GB down to 16MB) | Whole-process memory threshold |
| 2 | LD_PRELOAD mmap/malloc failure injection | JIT executable page allocation failures |
| 3 | Direct `jit_alloc` patch, fail at allocation N | Every individual JIT allocator error path |
| 4 | Compile 500 distinct hot functions | Trace cache eviction bugs |
| 5 | Multiple threads triggering JIT under pressure | Race conditions in JIT memory management |
| 6 | JIT execution + class-mutation invalidation thread | Use-after-free in trace invalidation |
| 7 | ASAN build + mmap injection | Silent heap corruption during allocation failure |
| 8 | libfiu named failure-point injection | Precise mmap failure at libc call level |
| 9 | JIT vs. non-JIT timing under mmap injection | Performance overhead under memory pressure |

Phase 3 requires a manual patch to `Python/jit.c` and a CPython rebuild. All other phases run automatically via `run_all.sh`.

## Compatibility Changes
Four compatibility challenges in lafleur prevented it from working successfully on CPython 3.15. All were diagnosed and resolved during this campaign:

1. **UOP regex** — CPython 3.15 appends register suffixes to optimized UOP names. Fixed in `coverage.py` line 45.
2. **Missing UOP names** — Four new UOP names in CPython 3.15 were absent from lafleur's known set. Fixed in `uop_names.py`.
3. **Harness marker** — Hand-rolled seeds must print `[f1] STRATEGY: fuzzing` to stderr or lafleur discards all coverage data.
4. **Session fuzz mode** — `--session-fuzz` suppresses JIT logs because the driver runs scripts via `exec()` after JIT logging flags have already been evaluated. Removed from all instances.

## Bug Found
The campaign independently rediscovered **gh-144681**: a JIT assertion failure at `Python/optimizer.c:790` triggered by runtime code object swapping (`func.__code__ = other.__code__`). The bug was confirmed JIT-specific — crashing with `PYTHON_JIT=1` and passing cleanly with `PYTHON_JIT=0`. The fix was merged in PR #144742.

## Environment
- **Target**: CPython 3.15.0a7+ (`--with-pydebug --enable-experimental-jit`)
- **Platform**: WSL2 Ubuntu 22.04
- **Instances**: 6 parallel (debug, differential, free-threaded, ASAN, UBSAN, RAM-disk)

## Related
- [lafleur](https://github.com/devdanzin/lafleur) — the fuzzer used in this campaign
- [gh-144681](https://github.com/python/cpython/issues/144681) — the bug independently rediscovered
- [PR #144742](https://github.com/python/cpython/pull/144742) — the fix
