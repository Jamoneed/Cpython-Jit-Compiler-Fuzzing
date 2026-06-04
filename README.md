# CPython JIT Compiler Fuzzing

Coverage-guided fuzzing of CPython's experimental Tier 2 JIT compiler using [lafleur](https://github.com/devdanzin/lafleur), plus a low-memory stress-testing framework for probing JIT allocation error paths.

This repository contains all research artifacts from the thesis *Coverage-Guided Fuzzing of CPython's Experimental Tier 2 JIT Compiler: Infrastructure, Validation, and Memory-Pressure Characterization* (Hameed Sahib, UC Irvine, 2026). The full thesis is in `docs/thesis.pdf`.

---

## Repository layout

```
seeds/              18 hand-written seed programs targeting specific JIT behaviors
lowmem/             Low-memory stress-testing framework (phases 1–9)
  injectors/        LD_PRELOAD fault injector C source and build script
  scripts/          Per-phase shell scripts and Python stress programs
reproducers/        Minimized crash reproducers
crashes/            Raw crash artifacts and reproduction details for both bugs found
  gh144681_lafleur/           lafleur campaign crash (gh-144681)
  unlink_executor_lowmem/     low-memory framework crash (unlink_executor)
scripts/            Campaign launch script (launch_campaign.sh)
docs/               Thesis PDF
environment.md      Exact versions and build configs used in the research
requirements.txt    Python dependencies for the lafleur venv
```

---

## Bugs found

Two JIT-specific bugs were found during this research. Full crash artifacts, reproduction commands, and root cause analysis are in `crashes/`.

### Bug 1 — gh-144681 (lafleur campaign)

| Field | Value |
|---|---|
| Assertion | `jump_happened == (target_instr[1].cache & 1)` |
| File | `Python/optimizer.c:790` |
| Signal | SIGABRT, exit code -6 |
| Affected build | CPython commit `6908372fb81` (3.15.0a6+, March 2, 2026) |
| Fixed by | PR #144742, commit `c32e264227b` |
| Found by | lafleur `debug-1` instance, March 20, 2026 |

**Quick reproduction** (requires build at `6908372fb81`):
```bash
PYTHON_JIT=1 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
# Expected: SIGABRT, optimizer.c:790 assertion failure

PYTHON_JIT=0 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
# Expected: clean exit, code 0
```

### Bug 2 — unlink_executor assertion (low-memory framework, Phase 8)

| Field | Value |
|---|---|
| Assertion | `idx >= 0 && (size_t)idx < interp->executor_count` |
| Function | `unlink_executor`, `Python/optimizer.c` |
| Signal | SIGABRT |
| Affected build | CPython commit `c32e264227b` (April 1, 2026) |
| No longer reproduces | After commit `d0e7c6acc93` (April 14, 2026) |
| Reproduction rate | ~15–18% with `PYTHON_JIT=1`, 0% with `PYTHON_JIT=0` |
| Related issue | gh-136996 (same function, different assertion) |

**Quick reproduction** (requires build at `c32e264227b` and libfiu):
```bash
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

---

## Part 1 — Coverage-guided fuzzing with lafleur

### Step 1: System dependencies

Tested on Ubuntu 22.04 (x86-64). Install required packages:

```bash
sudo apt update
sudo apt install -y \
  build-essential git tmux wget clang \
  libssl-dev zlib1g-dev libbz2-dev libreadline-dev \
  libsqlite3-dev libffi-dev liblzma-dev uuid-dev \
  libfiu-dev fiu-utils
```

### Step 2: Clone CPython and build a debug+JIT binary

lafleur requires a CPython debug build with the experimental JIT enabled. This is not your system Python — you build it from source.

```bash
mkdir -p ~/fuzzing
cd ~/fuzzing
git clone https://github.com/python/cpython.git
cd cpython
```

To reproduce the exact campaign results, check out the campaign commit:

```bash
git checkout c32e264227b
```

To reproduce gh-144681 specifically, check out the crashing build:

```bash
git checkout 6908372fb81
```

Build:

```bash
./configure --with-pydebug --enable-experimental-jit
make -j$(nproc)
```

Confirm the binary works:

```bash
./python -VV
```

### Step 3: Create a virtualenv from the CPython build

lafleur must run inside a venv created from the same CPython build you are fuzzing:

```bash
./python -m venv ~/fuzzing/lafleur_venv
source ~/fuzzing/lafleur_venv/bin/activate
```

### Step 4: Install lafleur

```bash
cd ~/fuzzing
git clone https://github.com/devdanzin/lafleur.git
cd lafleur
pip install -e .
```

Confirm the install:

```bash
lafleur --help
lafleur-report --help
lafleur-campaign --help
```

### Step 5: Tune the JIT threshold and rebuild CPython

lafleur includes a tuning utility that lowers CPython's JIT compilation threshold in the C headers. This makes the JIT compile sooner during fuzzing — without it, short seed programs may never trigger JIT compilation at all.

```bash
lafleur-jit-tweak ~/fuzzing/cpython
```

Then rebuild:

```bash
cd ~/fuzzing/cpython
make -j$(nproc)
```

The campaign used a threshold of 63 (down from the default ~4,096). Verify the JIT fires on a seed:

```bash
PYTHON_JIT=1 PYTHON_LLTRACE=1 ~/fuzzing/cpython/python seeds/seed_math.py 2>&1 | head -30
```

You should see lines like `ADD_TO_TRACE: _BINARY_OP_ADD_INT`. If you see nothing, the threshold was not applied — re-run `lafleur-jit-tweak` and rebuild.

### Step 6: Apply the CPython 3.15 compatibility patches to lafleur

**Required for CPython 3.15 or later.** Without these patches lafleur silently reports zero UOP-edge coverage — the fuzzer appears to run but all coverage data is discarded.

---

#### Patch 1 — UOP regex: register allocation suffixes

CPython 3.15 introduced register allocation for the Tier 2 JIT. UOP names in trace output now include register suffixes, e.g. `_ITER_NEXT_RANGE_r23`. lafleur's original regex stopped matching at the lowercase `r`, silently dropping every UOP name from an optimized trace.

Open `~/fuzzing/lafleur/lafleur/coverage.py`, line 45. Change:

```python
# OLD
UOP_REGEX = re.compile(
    r"(?:ADD_TO_TRACE|OPTIMIZED): (_[A-Z0-9_]+)(?=\s|\n|$)")
```

to:

```python
# NEW
UOP_REGEX = re.compile(
    r"(?:ADD_TO_TRACE|OPTIMIZED): (_[A-Z0-9_]+?)(?:_r\d+)?(?=\s|\(|\n|$)")
```

---

#### Patch 2 — Missing UOP names

Four UOP names introduced in CPython 3.15 were absent from lafleur's recognition table. Any edge chain containing one of these was silently discarded even after Patch 1.

Open `~/fuzzing/lafleur/lafleur/uop_names.py`. Add to the `UOP_NAMES` set:

```python
"_SWAP_FAST",
"_SWAP_FAST_0",
"_SWAP_FAST_1",
"_SPILL_OR_RELOAD",
```

---

#### Patch 3 — Harness marker requirement for hand-written seeds

lafleur's coverage parser only accumulates UOP edges after seeing the string `[f1]` printed to stderr. Without it `current_harness_id` is never set and all coverage is silently discarded.

The seeds in this repo already include the marker. Any new seeds you write must prepend:

```python
import sys
print('[f1] STRATEGY: fuzzing', file=sys.stderr)
```

---

#### Patch 4 — Remove `--session-fuzz` from all instances

Session-fuzz mode runs scripts via `exec()` in a shared interpreter process. CPython's JIT logging flags are evaluated at interpreter startup, so scripts run later produce no trace output and coverage is always zero for session-fuzz instances on CPython 3.15.

`scripts/launch_campaign.sh` in this repo has `--session-fuzz` removed from all instances. Do not add it back unless you switch to a non-log-based coverage mechanism.

---

### Step 7: Validate the coverage pipeline before a long run

Always do this first. A broken pipeline looks identical to a working one.

```bash
source ~/fuzzing/lafleur_venv/bin/activate
mkdir -p /tmp/test_corpus

lafleur \
  --target-python ~/fuzzing/cpython/python \
  --corpus-dir /tmp/test_corpus \
  --seed-dir seeds/ \
  --runs 1 \
  --max-iterations 50

lafleur-report /tmp/test_corpus
```

After 50 iterations `Global UOP Edges` must be nonzero (expect 200–500). If it is still 0 work through Patches 1–4 before proceeding.

---

### Step 8: Set up additional build configurations (optional but recommended)

The campaign used six instances across four build types. Each needs its own CPython binary.

**ASAN build** (detects heap corruption and use-after-free):

```bash
mkdir -p ~/fuzzing/cpython-asan && cd ~/fuzzing/cpython-asan
git clone https://github.com/python/cpython.git .
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit \
  CC=clang \
  CFLAGS="-fsanitize=address -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=address"
make -j$(nproc)
```

**UBSAN build** (detects undefined behavior in CPython's C code):

```bash
mkdir -p ~/fuzzing/cpython-ubsan && cd ~/fuzzing/cpython-ubsan
git clone https://github.com/python/cpython.git .
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit \
  CC=clang \
  CFLAGS="-fsanitize=undefined -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=undefined"
make -j$(nproc)
```

**Free-threaded build** (tests behavior without the GIL):

```bash
mkdir -p ~/fuzzing/cpython-ft && cd ~/fuzzing/cpython-ft
git clone https://github.com/python/cpython.git .
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit --disable-gil
make -j$(nproc)
```

Run `lafleur-jit-tweak` on each build after cloning, then rebuild:

```bash
source ~/fuzzing/lafleur_venv/bin/activate
for dir in ~/fuzzing/cpython-asan ~/fuzzing/cpython-ubsan ~/fuzzing/cpython-ft; do
  lafleur-jit-tweak $dir
  cd $dir && make -j$(nproc)
done
```

---

### Step 9: Place seeds into the corpus

```bash
mkdir -p ~/fuzzing/campaign1/corpus/jit_interesting_tests
cp seeds/*.py ~/fuzzing/campaign1/corpus/jit_interesting_tests/
```

| Seed file | JIT behavior targeted |
|---|---|
| `seed_math.py` | Integer and float arithmetic UOPs |
| `seed_type_confusion.py` | `GUARD_TYPE_VERSION`, mid-loop type switching |
| `seed_attrs.py` | Instance, class, method, module attribute access |
| `seed_closures.py` | Closure-cell UOPs, `nonlocal` access |
| `seed_generators.py` | `ITER_NEXT_RANGE`, list/tuple/range iteration |
| `seed_collections.py` | List, tuple, set, dict construction |
| `seed_subscripts.py` | String, tuple, list subscript UOPs |
| `seed_exceptions.py` | `ERROR_POP_N`, exception handling in hot loops |
| `seed_truth_tests.py` | Boolean, int, str, None truth-testing UOPs |
| `seed_class_mutation.py` | Dynamic class modification mid-loop |
| `seed_many_locals.py` | Register pressure (15+ local variables) |
| `seed_module_attrs.py` | Module attribute access and deletion |
| `seed_guard_failures.py` | `GUARD_DORV_NO_DICT`, mid-loop class swapping |
| `seed_deopt_chains.py` | `EXIT_TRACE`, `DEOPT`, repeated deoptimization |
| `seed_trace_stitching.py` | Side-exit traces, seven branch paths |
| `seed_nested_inlining.py` | `PUSH_FRAME`, `POP_FRAME`, deep call chains |
| `seed_gc_pressure.py` | JIT and GC interaction, reference cycles |
| `seed_async_generators.py` | Async/await UOPs, asyncio event loop |

Each seed has a function named `uop_harness_f1` containing a `for i in range(300)` loop with the `[f1]` harness marker printed to stderr at startup.

---

### Step 10: Set up a RAM disk (optional, for the fast instance)

```bash
sudo mkdir -p /mnt/fuzz_ram
sudo mount -t tmpfs -o size=2G tmpfs /mnt/fuzz_ram
mkdir -p /mnt/fuzz_ram/corpus /mnt/fuzz_ram/crashes
```

Back up crash files every two hours:

```bash
crontab -e
# Add:
0 */2 * * * cp -r /mnt/fuzz_ram/crashes ~/fuzzing/crash_backups/$(date +\%Y\%m\%d_\%H\%M\%S)/ 2>/dev/null
```

---

### Step 11: Launch the full campaign

```bash
cd ~/fuzzing/campaign1
chmod +x ~/path/to/CPython-Bug-Hunting/scripts/launch_campaign.sh
~/path/to/CPython-Bug-Hunting/scripts/launch_campaign.sh
```

This opens a tmux session named `fuzz_campaign` with six windows:

| Instance | Build | Purpose |
|---|---|---|
| `debug-1` | debug+JIT | Primary — assertion failures, JIT logic errors |
| `diff-1` | debug+JIT | Differential testing — JIT=1 vs JIT=0 output |
| `freethreaded-1` | free-threaded+JIT | GIL-free race conditions |
| `asan-1` | ASAN+JIT | Heap corruption, use-after-free |
| `ubsan-1` | UBSAN+JIT | Undefined behavior in JIT C code |
| `ram-fast-1` | debug+JIT (tmpfs) | Breadth-first coverage exploration |

Attach: `tmux attach -t fuzz_campaign`  
Switch windows: `Ctrl+b` + window number  
Detach: `Ctrl+b d`

---

### Step 12: Monitor the campaign

```bash
source ~/fuzzing/lafleur_venv/bin/activate

# Single instance
lafleur-report ~/fuzzing/campaign1/

# HTML dashboard across all instances
lafleur-campaign ~/fuzzing/campaign1/ --html ~/fuzzing/campaign_report.html
```

Watch: `Global UOP Edges` (grows over time), `Corpus Files` (grows from 18 seed baseline), `Crashes Found`.

---

### Crash triage

**Step 1** — Discard any crash with `SyntaxError` or `IndentationError` — invalid Python from a bad mutation, not a JIT bug.

**Step 2** — Confirm JIT-specificity:

```bash
PYTHON_JIT=1 ~/fuzzing/cpython/python path/to/crash_script.py   # should crash
PYTHON_JIT=0 ~/fuzzing/cpython/python path/to/crash_script.py   # should be clean
```

**Step 3** — Record the exact commit:

```bash
~/fuzzing/cpython/python -VV
```

**Step 4** — Search the [CPython issue tracker](https://github.com/python/cpython/issues) for the assertion text. If no issue exists, file one with the minimized reproducer, assertion text, commit hash, and JIT-on vs JIT-off output.

---

## Part 2 — Low-memory stress testing

The low-memory framework tests how the JIT behaves when memory allocation fails. Normal execution never reaches these paths — the framework forces them deliberately.

### Step 1: Install libfiu

```bash
sudo apt install -y libfiu-dev fiu-utils
fiu-run --help   # verify
```

### Step 2: Build the fault injector libraries

```bash
cd lowmem/injectors
chmod +x build.sh
./build.sh
```

Or manually:

```bash
gcc -shared -fPIC -o lowmem/injectors/fail_mmap.so lowmem/injectors/fail_mmap.c -ldl
gcc -shared -fPIC -o lowmem/injectors/fail_malloc.so lowmem/injectors/fail_malloc.c -ldl
```

`fail_mmap.so` intercepts `mmap()` calls for executable pages (JIT trace buffer allocations). Failure probability set via `MMAP_FAIL_RATE`.  
`fail_malloc.so` intercepts `malloc()`, `realloc()`, `calloc()`. Failure probability set via `MALLOC_FAIL_RATE`.

### Step 3: Run the automated phases

```bash
cd lowmem
chmod +x run_all.sh
./run_all.sh
```

| Phase | Method | What it targets |
|---|---|---|
| 1 | `ulimit -v` sweep | Virtual memory caps 64 MB – 2048 MB |
| 2 | `LD_PRELOAD` mmap injection | JIT executable page allocation failures |
| 3 | Direct `jit_alloc` patch *(manual)* | Every individual JIT allocator error path |
| 4 | 500 distinct hot functions | Trace cache exhaustion and eviction |
| 5 | Concurrent threads under pressure | Race conditions in JIT memory management |
| 6 | JIT execution + class mutation thread | Use-after-free in trace invalidation |
| 7 | ASAN build + mmap injection | Silent heap corruption under allocation failure |
| 8 | `libfiu` named-function injection | Precise `mmap` interception at libc level |
| 9 | JIT vs non-JIT timing under mmap injection | Performance characterization |

**Phase 3 is manual** — requires patching `Python/jit.c` and rebuilding. See `lowmem/PHASE3_PATCH.md`.

### Step 4: Run Phase 8 manually (the phase that found the bug)

First check out the affected build:

```bash
cd ~/fuzzing/cpython
git checkout c32e264227b
make -j$(nproc)
```

Then run the reproducer under libfiu mmap injection. Because the failure is nondeterministic (~15–18% hit rate), run in a loop:

```bash
for i in $(seq 1 50); do
  result=$(PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    ~/fuzzing/cpython/python \
    crashes/unlink_executor_lowmem/reproducer.py 2>&1)
  if echo "$result" | grep -qE "Assertion|Aborted"; then
    echo "RUN $i: CRASH"
    echo "$result"
    break
  else
    echo "RUN $i: clean"
  fi
done
```

The `-x` flag is required. Without it the failure does not reproduce.

Expected crash output when it fires:

```
python: Python/optimizer.c:NNN:
unlink_executor:
Assertion 'idx >= 0 && (size_t)idx < interp->executor_count' failed.
Aborted (core dumped)
```

### Step 5: Confirm JIT-specificity

```bash
# Crashes ~15-18% of runs:
PYTHON_JIT=1 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  ~/fuzzing/cpython/python crashes/unlink_executor_lowmem/reproducer.py

# Clean 100% of the time:
PYTHON_JIT=0 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  ~/fuzzing/cpython/python crashes/unlink_executor_lowmem/reproducer.py
```

### Step 6: Confirm the fix

```bash
cd ~/fuzzing/cpython
git checkout d0e7c6acc93
make -j$(nproc)

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
# Expected: clean=100 crash=0
```

---

## Reproducing gh-144681

### With the minimized reproducer (~15 lines)

```bash
cd ~/fuzzing/cpython
git checkout 6908372fb81
make -j$(nproc)

# Should SIGABRT, exit code -6:
PYTHON_JIT=1 ~/fuzzing/cpython/python reproducers/gh144681_crash.py

# Should exit cleanly:
PYTHON_JIT=0 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
```

Expected crash output:

```
python: Python/optimizer.c:790:
_PyJit_translate_single_bytecode_to_trace:
Assertion 'jump_happened == (target_instr[1].cache & 1)' failed.
Aborted (core dumped)
```

### With the raw lafleur crash script

The exact script lafleur produced is in `crashes/gh144681_lafleur/crash_script.py`. Same build requirement:

```bash
PYTHON_JIT=1 ~/fuzzing/cpython/python crashes/gh144681_lafleur/crash_script.py
PYTHON_JIT=0 ~/fuzzing/cpython/python crashes/gh144681_lafleur/crash_script.py
```

### Confirming the fix

```bash
cd ~/fuzzing/cpython
git checkout c32e264227b
make -j$(nproc)

# Should exit cleanly:
PYTHON_JIT=1 ~/fuzzing/cpython/python reproducers/gh144681_crash.py
echo "Exit code: $?"   # expected: 0
```

---

## Campaign results (reference)

Results from the corrected campaign on CPython 3.15.0a7+ commit `c32e264227b`:

| Metric | Value |
|---|---|
| Run ID (debug-1) | `43e6593d-d074-4e38-be94-fee52773b4d1` |
| Global UOP edges | 1,482 |
| Global distinct UOPs | 230 |
| Corpus size | 118 files (grew from 18 seeds in first hour) |
| Max mutation tree depth | 40 |
| Total executions (first hour) | ~4,025 |
| Crashes found | 1 unique fingerprint (gh-144681) |
| Top mutator | ArithmeticSpamMutator (754 selections) |
| Second mutator | ComprehensiveFunctionMutator (143) |
| Third mutator | HelperFunctionInjector (141) |

The pre-fix 48-hour run executed 748,039 programs and found zero UOP edges — all coverage was discarded due to the four compatibility issues in Patches 1–4.

---

## Environment summary

See `environment.md` for full details. Key versions:

| Component | Version / config |
|---|---|
| OS | Ubuntu 22.04 (WSL2 on Windows 11), x86-64 |
| CPython (campaign) | 3.15.0a7+, commit `c32e264227b` |
| CPython (gh-144681 crash) | 3.15.0a6+, commit `6908372fb81` |
| CPython (lowmem bug found) | commit `c32e264227b` (April 1, 2026) |
| CPython (lowmem bug resolved) | commit `d0e7c6acc93` (April 14, 2026) |
| CPython build flags | `--with-pydebug --enable-experimental-jit` |
| JIT threshold | 63 (via `lafleur-jit-tweak`, default ~4,096) |
| lafleur | `devdanzin/lafleur` main, 4 compatibility patches applied |
| libfiu | system package via `apt` (`libfiu-dev`, `fiu-utils`) |
| Campaign instances | 6 parallel (debug, diff, freethreaded, ASAN, UBSAN, RAM-disk) |
| Hardware | 6 physical / 12 logical cores, 7.61 GB RAM, local SSD |

---

## References

- [lafleur](https://github.com/devdanzin/lafleur) — devdanzin
- [PEP 744 — JIT Compilation](https://peps.python.org/pep-0744/) — Brandt Bucher
- [gh-144681](https://github.com/python/cpython/issues/144681) — independently reproduced by this campaign
- [PR #144742](https://github.com/python/cpython/pull/144742) — upstream fix for gh-144681
- [gh-136996](https://github.com/python/cpython/issues/136996) — related issue in same function as Bug 2
- [CPython JIT internals](https://github.com/python/cpython/blob/main/InternalDocs/jit.md)
- Thesis PDF: `docs/thesis.pdf`
