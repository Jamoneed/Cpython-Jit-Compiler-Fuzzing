# CPython JIT Compiler Fuzzing

Coverage-guided fuzzing of CPython's experimental Tier 2 JIT compiler using [lafleur](https://github.com/devdanzin/lafleur), plus a low-memory stress-testing framework for probing JIT allocation error paths.

This repository contains all research artifacts from the thesis *Coverage-Guided Fuzzing of CPython's Experimental Tier 2 JIT Compiler: Infrastructure, Validation, and Memory-Pressure Characterization*.

---

## Repository layout

```
seeds/              18 hand-written seed programs targeting specific JIT behaviors
lowmem/             Low-memory stress-testing framework (phases 1–9)
reproducers/        Minimized crash reproducers
scripts/            Campaign launch script (launch_campaign.sh)
```

---

## Part 1 — Coverage-guided fuzzing with lafleur

### Step 1: System dependencies

Tested on Ubuntu 22.04 (x86-64). Install required packages:

```bash
sudo apt update
sudo apt install -y \
  build-essential git tmux wget \
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

Build (first pass — before JIT tuning):

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

The campaign in this thesis used a threshold of 63 (down from the default ~4,096). Verify the JIT fires on a seed:

```bash
PYTHON_JIT=1 PYTHON_LLTRACE=1 ~/fuzzing/cpython/python ~/fuzzing/CPython-JIT-Compiler-Fuzzing/seeds/seed_math.py 2>&1 | head -30
```

You should see lines like `ADD_TO_TRACE: _BINARY_OP_ADD_INT` in the output. If you see nothing, the threshold was not applied — re-run `lafleur-jit-tweak` and rebuild.

### Step 6: Apply the CPython 3.15 compatibility patches to lafleur

**This step is required if you are targeting CPython 3.15 or later.** Without it, lafleur will silently report zero UOP-edge coverage — the fuzzer appears to run but all coverage data is discarded. There are four issues.

---

#### Patch 1 — UOP regex: register allocation suffixes

CPython 3.15 introduced register allocation for the Tier 2 JIT. UOP names in trace output now include register suffixes, e.g. `_ITER_NEXT_RANGE_r23`. lafleur's original regex stopped matching at the lowercase `r`, so every UOP name from an optimized trace was silently dropped.

Open `~/fuzzing/lafleur/lafleur/coverage.py` and find line 45. Change:

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

The change adds an optional non-capturing group `(?:_r\d+)?` that absorbs the register suffix before the lookahead, and extends the lookahead to also accept `(` which appears in some 3.15 trace formats.

---

#### Patch 2 — Missing UOP names

Four UOP names introduced in CPython 3.15 were absent from lafleur's recognition table. Any edge chain containing one of these was silently discarded even after Patch 1.

Open `~/fuzzing/lafleur/lafleur/uop_names.py`. Add these four entries to the `UOP_NAMES` set:

```python
"_SWAP_FAST",
"_SWAP_FAST_0",
"_SWAP_FAST_1",
"_SPILL_OR_RELOAD",
```

---

#### Patch 3 — Harness marker requirement for hand-written seeds

lafleur's coverage parser only starts accumulating UOP edges after it sees the string `[f1]` printed to stderr. This marker tells the parser which harness function the trace belongs to. Without it, `current_harness_id` is never set and all coverage is silently discarded for that seed.

The seeds in this repository already include the marker. If you write new seeds, prepend these two lines:

```python
import sys
print('[f1] STRATEGY: fuzzing', file=sys.stderr)
```

---

#### Patch 4 — Remove `--session-fuzz` from all instances

Session-fuzz mode runs scripts through lafleur's driver via `exec()` in a shared interpreter process. CPython's JIT logging flags (`PYTHON_LLTRACE`, `PYTHON_OPT_DEBUG`) are evaluated once at interpreter startup. Scripts run later via `exec()` do not produce JIT trace output — so coverage is always zero for session-fuzz instances on CPython 3.15.

The `scripts/launch_campaign.sh` in this repo has `--session-fuzz` removed from all instances. Do not add it back unless you switch to a coverage mechanism that does not depend on trace logs.

---

### Step 7: Validate the coverage pipeline before a long run

Always do this before starting a multi-hour campaign. A broken pipeline looks identical to a working one — lafleur keeps executing programs and cycling mutators either way, just collecting nothing.

```bash
source ~/fuzzing/lafleur_venv/bin/activate
mkdir -p /tmp/test_corpus

lafleur \
  --target-python ~/fuzzing/cpython/python \
  --corpus-dir /tmp/test_corpus \
  --seed-dir ~/fuzzing/CPython-JIT-Compiler-Fuzzing/seeds \
  --runs 1 \
  --max-iterations 50

lafleur-report /tmp/test_corpus
```

After 50 iterations, `Global UOP Edges` should be a nonzero number (expect 200–500 in the first few minutes). If it is still 0, the pipeline is broken — work through Patches 1–4 above before proceeding.

---

### Step 8: Set up additional build configurations (optional but recommended)

The campaign used six instances targeting different build types. Each needs its own CPython binary in a separate directory.

**ASAN build** (detects heap corruption and use-after-free):

```bash
mkdir -p ~/fuzzing/cpython-asan
cd ~/fuzzing/cpython-asan
git clone https://github.com/python/cpython.git .
./configure --with-pydebug --enable-experimental-jit \
  CC=clang \
  CFLAGS="-fsanitize=address -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=address"
make -j$(nproc)
```

**UBSAN build** (detects undefined behavior in CPython's C code):

```bash
mkdir -p ~/fuzzing/cpython-ubsan
cd ~/fuzzing/cpython-ubsan
git clone https://github.com/python/cpython.git .
./configure --with-pydebug --enable-experimental-jit \
  CC=clang \
  CFLAGS="-fsanitize=undefined -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=undefined"
make -j$(nproc)
```

**Free-threaded build** (tests behavior without the GIL):

```bash
mkdir -p ~/fuzzing/cpython-ft
cd ~/fuzzing/cpython-ft
git clone https://github.com/python/cpython.git .
./configure --with-pydebug --enable-experimental-jit --disable-gil
make -j$(nproc)
```

Run `lafleur-jit-tweak` on each build directory after cloning:

```bash
source ~/fuzzing/lafleur_venv/bin/activate
lafleur-jit-tweak ~/fuzzing/cpython-asan
lafleur-jit-tweak ~/fuzzing/cpython-ubsan
lafleur-jit-tweak ~/fuzzing/cpython-ft
# then: cd into each dir and make -j$(nproc)
```

---

### Step 9: Place seeds into the corpus

lafleur expects seeds in `corpus/jit_interesting_tests/` relative to where you run it. Copy the seeds from this repo:

```bash
mkdir -p ~/fuzzing/campaign1/corpus/jit_interesting_tests
cp ~/fuzzing/CPython-JIT-Compiler-Fuzzing/seeds/*.py \
   ~/fuzzing/campaign1/corpus/jit_interesting_tests/
```

Each seed file targets a specific JIT behavior. The naming reflects its focus:

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

Each seed follows the same structure: a function named `uop_harness_f1` containing a `for i in range(300)` loop, with the `[f1]` harness marker printed to stderr at startup.

---

### Step 10: Set up a RAM disk (optional, for the fast instance)

```bash
sudo mkdir -p /mnt/fuzz_ram
sudo mount -t tmpfs -o size=2G tmpfs /mnt/fuzz_ram
mkdir -p /mnt/fuzz_ram/corpus /mnt/fuzz_ram/crashes
```

Back up crash files every two hours so nothing is lost on reboot:

```bash
crontab -e
# Add this line:
0 */2 * * * cp -r /mnt/fuzz_ram/crashes ~/fuzzing/crash_backups/$(date +\%Y\%m\%d_\%H\%M\%S)/ 2>/dev/null
```

---

### Step 11: Launch the full campaign

```bash
cd ~/fuzzing/campaign1
chmod +x ~/fuzzing/CPython-JIT-Compiler-Fuzzing/scripts/launch_campaign.sh
~/fuzzing/CPython-JIT-Compiler-Fuzzing/scripts/launch_campaign.sh
```

This opens a tmux session named `fuzz_campaign` with six windows, one per instance:

| Instance | Build | Purpose |
|---|---|---|
| `debug-1` | debug+JIT | Primary — assertion failures, JIT logic errors |
| `diff-1` | debug+JIT | Differential testing — compares JIT=1 vs JIT=0 output |
| `freethreaded-1` | free-threaded+JIT | GIL-free race conditions |
| `asan-1` | ASAN+JIT | Heap corruption, use-after-free |
| `ubsan-1` | UBSAN+JIT | Undefined behavior in JIT C code |
| `ram-fast-1` | debug+JIT (tmpfs) | Breadth-first coverage exploration |

Attach to the session:

```bash
tmux attach -t fuzz_campaign
```

Switch windows with `Ctrl+b` then the window number (0–5). Detach with `Ctrl+b d`.

---

### Step 12: Monitor the campaign

```bash
source ~/fuzzing/lafleur_venv/bin/activate

# Single instance report
lafleur-report ~/fuzzing/campaign1/

# HTML dashboard across all instances
lafleur-campaign ~/fuzzing/campaign1/ --html ~/fuzzing/campaign_report.html
```

Key metrics to watch: `Global UOP Edges` (should grow over time), `Corpus Files` (should grow from the 18 seed baseline), and `Crashes Found`.

---

### Crash triage

Not every crash is a JIT bug. Use this protocol on anything in the `crashes/` directory.

**Step 1** — Filter parser failures. Discard any crash log containing `SyntaxError` or `IndentationError` — these are mutations that produced invalid Python, not JIT bugs.

**Step 2** — Confirm JIT-specificity. Run the crashing script with and without the JIT on the same build:

```bash
PYTHON_JIT=1 ~/fuzzing/cpython/python path/to/crash_script.py   # should crash
PYTHON_JIT=0 ~/fuzzing/cpython/python path/to/crash_script.py   # should be clean
```

A crash that only appears with `PYTHON_JIT=1` is a genuine JIT-specific bug. If it crashes in both configurations, it is a non-JIT interpreter bug and should be triaged separately.

**Step 3** — Record the exact CPython commit:

```bash
~/fuzzing/cpython/python -VV
```

**Step 4** — Search the [CPython issue tracker](https://github.com/python/cpython/issues) for the assertion text. If no issue exists, file one with the minimized reproducer, the full assertion text, the commit hash, and the JIT-on vs JIT-off comparison.

---

## Part 2 — Low-memory stress testing

The low-memory framework tests how the JIT behaves when memory allocation fails. Normal execution never triggers these paths. The framework forces them deliberately.

### Step 1: Install libfiu

```bash
sudo apt install -y libfiu-dev fiu-utils
```

Verify:

```bash
fiu-run --help
```

### Step 2: Build the fault injector libraries

```bash
cd ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem
gcc -shared -fPIC -o fail_mmap.so fail_mmap.c -ldl
gcc -shared -fPIC -o fail_malloc.so fail_malloc.c -ldl
```

`fail_mmap.so` intercepts `mmap()` calls for executable pages (the allocations the JIT uses for compiled trace buffers). Failure probability is set via the `MMAP_FAIL_RATE` environment variable.

`fail_malloc.so` intercepts `malloc()`, `realloc()`, and `calloc()` calls. Failure probability is set via `MALLOC_FAIL_RATE`.

### Step 3: Run the automated phases

```bash
cd ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem
chmod +x run_all.sh
./run_all.sh
```

This runs phases 1, 2, 4, 5, 6, 7, 8, and 9 in sequence. Each phase applies memory pressure at a different level:

| Phase | Method | What it targets |
|---|---|---|
| 1 | `ulimit -v` threshold sweep | Coarse virtual memory caps from 64 MB to 2048 MB |
| 2 | `LD_PRELOAD` mmap injection | JIT executable page allocation failures |
| 3 | Direct `jit_alloc` patch *(manual — see below)* | Every individual JIT allocator error path |
| 4 | 500 distinct hot functions | Trace cache exhaustion and eviction |
| 5 | Concurrent threads under pressure | Race conditions in JIT memory management |
| 6 | JIT execution + class mutation thread | Use-after-free in trace invalidation |
| 7 | ASAN build + mmap injection | Silent heap corruption under allocation failure |
| 8 | `libfiu` named-function injection | Precise `mmap` interception at libc level |
| 9 | JIT vs non-JIT timing under mmap injection | Performance characterization |

**Phase 3 is manual.** It requires patching `Python/jit.c` directly. See `lowmem/README_phase3.md` for the patch and rebuild instructions.

### Step 4: Run Phase 8 manually (the phase that found the bug)

Phase 8 uses libfiu to intercept `mmap` at the libc call level. This is the phase that found the `unlink_executor` assertion failure. Run it directly with:

```bash
PYTHON_JIT=1 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  ~/fuzzing/cpython/python \
  ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem/harness.py
```

The `-x` flag is required — without it the failure does not reproduce.

Because the failure is nondeterministic (15–18% reproduction rate), run it in a loop:

```bash
for i in $(seq 1 50); do
  result=$(PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    ~/fuzzing/cpython/python \
    ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem/harness.py 2>&1)
  if echo "$result" | grep -q "Assertion\|SIGABRT"; then
    echo "RUN $i: CRASH"
    echo "$result"
    break
  else
    echo "RUN $i: clean"
  fi
done
```

### Step 5: Confirm JIT-specificity of any low-memory crash

Same protocol as for lafleur crashes:

```bash
# Should crash some % of the time with PYTHON_JIT=1:
PYTHON_JIT=1 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  ~/fuzzing/cpython/python ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem/harness.py

# Should be clean 100% of the time with PYTHON_JIT=0:
PYTHON_JIT=0 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  ~/fuzzing/cpython/python ~/fuzzing/CPython-JIT-Compiler-Fuzzing/lowmem/harness.py
```

---

## Reproducing gh-144681

The minimized reproducer is in `reproducers/gh144681_crash.py`.

```bash
# Should crash with SIGABRT and exit code -6:
PYTHON_JIT=1 ~/fuzzing/cpython/python \
  ~/fuzzing/CPython-JIT-Compiler-Fuzzing/reproducers/gh144681_crash.py

# Should exit cleanly:
PYTHON_JIT=0 ~/fuzzing/cpython/python \
  ~/fuzzing/CPython-JIT-Compiler-Fuzzing/reproducers/gh144681_crash.py
```

The failure is an assertion at `Python/optimizer.c:790`:

```
jump_happened == (target_instr[1].cache & 1)
```

Confirmed to crash on CPython 3.15.0a6+ (commit `6908372fb81`, March 2, 2026) and run cleanly after PR #144742 merged into commit `c32e264227b`.

Root cause: the reproducer warms up a function so the JIT builds a trace and caches bytecode metadata, then swaps `func.__code__` at runtime. The JIT then tries to trace the replacement bytecode using stale inline cache entries from the original. The two disagree on whether a jump occurred at a given instruction offset, triggering the assertion.

---

## Campaign results (reference)

Results from the corrected campaign on CPython 3.15.0a7+ commit `c32e264227b`:

| Metric | Value |
|---|---|
| Global UOP edges | 1,482 |
| Global distinct UOPs | 230 |
| Corpus size | 118 files (grew from 18 seeds in first hour) |
| Max mutation tree depth | 40 |
| Total executions (first hour) | ~4,025 |
| Crashes found | 1 unique fingerprint (gh-144681) |
| Top mutator by selections | ArithmeticSpamMutator (754) |
| Second mutator | ComprehensiveFunctionMutator (143) |
| Third mutator | HelperFunctionInjector (141) |

The pre-fix 48-hour run executed 748,039 programs and found zero UOP edges — all coverage was discarded due to the four compatibility issues described in Patches 1–4.

---

## Full environment

| Component | Version / config |
|---|---|
| OS | Ubuntu 22.04 (WSL2 on Windows 11) |
| Architecture | x86-64 |
| CPython | 3.15.0a7+, commit `c32e264227b` |
| CPython build flags | `--with-pydebug --enable-experimental-jit` |
| JIT threshold | 63 (lowered from default ~4,096 via `lafleur-jit-tweak`) |
| lafleur | `devdanzin/lafleur`, installed from source with 4 compatibility patches |
| libfiu | System package via `apt` |
| Campaign instances | 6 parallel (debug, diff, freethreaded, ASAN, UBSAN, RAM-disk) |
| Host hardware | 6 physical / 12 logical cores, 7.61 GB RAM, local SSD |

---

## References

- [lafleur](https://github.com/devdanzin/lafleur) — devdanzin
- [PEP 744 — JIT Compilation](https://peps.python.org/pep-0744/) — Brandt Bucher
- [gh-144681](https://github.com/python/cpython/issues/144681) — the bug independently reproduced by this campaign
- [PR #144742](https://github.com/python/cpython/pull/144742) — upstream fix
- [CPython JIT internals](https://github.com/python/cpython/blob/main/InternalDocs/jit.md)
