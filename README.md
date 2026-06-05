# CPython JIT Compiler Fuzzing

Coverage-guided fuzzing of CPython's experimental Tier 2 JIT compiler using [lafleur](https://github.com/devdanzin/lafleur), plus a low-memory stress-testing framework for probing JIT allocation error paths.

This repository contains all research artifacts from the thesis *Coverage-Guided Fuzzing of CPython's Experimental Tier 2 JIT Compiler: Infrastructure, Validation, and Memory-Pressure Characterization* (Hameed Sahib, UC Irvine, 2026).

---

## Set your paths

Set these once before running any commands in this README:

```bash
export CPYTHON_DIR=~/fuzzing/cpython      # where you cloned and built CPython
export CPYTHON=$CPYTHON_DIR/python        # the debug+JIT binary
export VENV=~/fuzzing/lafleur_venv        # lafleur virtualenv
export CAMPAIGN_DIR=~/fuzzing/campaign1   # campaign working directory
export REPO=$(pwd)                        # root of this repo (after cloning)
```

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
| Found on | CPython commit `6908372fb81` (3.15.0a6+, March 2, 2026) |
| Found by | lafleur `debug-1` instance, March 20, 2026 |
| Fixed by | PR #144742, confirmed clean on commit `c32e264227b` |

**Quick reproduction** (requires build at `6908372fb81`):
```bash
PYTHON_JIT=1 $CPYTHON reproducers/gh144681_crash.py
# Expected: SIGABRT, optimizer.c:790 assertion failure

PYTHON_JIT=0 $CPYTHON reproducers/gh144681_crash.py
# Expected: clean exit, code 0
```

### Bug 2 — unlink_executor assertion (low-memory framework, Phase 8)

| Field | Value |
|---|---|
| Assertion | `idx >= 0 && (size_t)idx < interp->executor_count` |
| Function | `unlink_executor`, `Python/optimizer.c` |
| Signal | SIGABRT |
| Found on | CPython commit `c32e264227b` (April 1, 2026) |
| Reproduction rate | ~15–18% with `PYTHON_JIT=1`, 0% with `PYTHON_JIT=0` |
| No longer reproduces | After commit `d0e7c6acc93` (April 14, 2026) |
| Related issue | gh-136996 (same function, different assertion) |

**Quick reproduction** (requires build at `c32e264227b` and libfiu):
```bash
for i in $(seq 1 50); do
  result=$(PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    $CPYTHON \
    crashes/unlink_executor_lowmem/reproducer.py 2>&1)
  if echo "$result" | grep -qE "Assertion|Aborted"; then
    echo "RUN $i: CRASH"; echo "$result"; break
  else
    echo "RUN $i: clean"
  fi
done
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
  libfiu-dev fiu-utils python3.11 libzstd-dev
```

CPython 3.15's JIT build tool requires **Python 3.11+** and **clang-21**. Install clang-21:

```bash
wget https://apt.llvm.org/llvm.sh
chmod +x llvm.sh
sudo ./llvm.sh 21
```

Verify:

```bash
python3.11 --version
clang-21 --version
```

### Step 2: Clone CPython and build a debug+JIT binary

**Important:** deactivate any active virtualenv before building. The venv Python will interfere with the JIT build tool.

```bash
deactivate   # if a venv is active
```

Clone CPython:

```bash
mkdir -p $CPYTHON_DIR
cd $CPYTHON_DIR
git clone https://github.com/python/cpython.git .
```

Check out the campaign build:

```bash
git checkout 6908372fb81
```

Build:

```bash
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
```

Confirm the binary works:

```bash
$CPYTHON -VV
$CPYTHON -c "import _zstd; print('zstd ok')"
```

### Step 3: Create a virtualenv from the CPython build

lafleur must run inside a venv created from the same CPython build you are fuzzing:

```bash
$CPYTHON -m venv $VENV
source $VENV/bin/activate
```

### Step 4: Install lafleur

```bash
git clone https://github.com/devdanzin/lafleur.git ~/fuzzing/lafleur
cd ~/fuzzing/lafleur
git checkout e5c1d6c   # pinned to campaign version (February 20, 2026)
pip install -e .
```

Confirm:

```bash
lafleur --help
lafleur-report --help
```

### Step 5: Tune the JIT threshold and rebuild CPython

lafleur includes a tuning utility that lowers CPython's JIT compilation threshold. Without it, short seed programs may never trigger JIT compilation.

```bash
deactivate
lafleur-jit-tweak $CPYTHON_DIR
cd $CPYTHON_DIR
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate
```

The campaign used a threshold of 63 (down from the default ~4,096). Verify the JIT fires:

```bash
PYTHON_JIT=1 PYTHON_LLTRACE=1 $CPYTHON $REPO/seeds/seed_math.py 2>&1 | head -30
```

You should see lines like `ADD_TO_TRACE: _BINARY_OP_ADD_INT`. If you see nothing, re-run `lafleur-jit-tweak` and rebuild.

### Step 6: Apply the CPython 3.15 compatibility patches to lafleur

**Required for CPython 3.15 or later.** Without these patches lafleur silently reports zero UOP-edge coverage.

---

#### Patch 1 — UOP regex: register allocation suffixes

CPython 3.15 introduced register allocation suffixes on UOP names in trace output, e.g. `_ITER_NEXT_RANGE_r23`. lafleur's original regex stopped matching at the lowercase `r`, silently dropping every UOP name from an optimized trace.

Use a script to apply — avoids paste issues in the terminal:

```bash
cat > /tmp/patch1.py << 'SCRIPT'
import os
path = os.path.expanduser('~/fuzzing/lafleur/lafleur/coverage.py')
with open(path, 'r') as f:
    content = f.read()
content = content.replace(
    'UOP_REGEX = re.compile(r"(?:ADD_TO_TRACE|OPTIMIZED): (_[A-Z0-9_]+)(?=\\s|\\n|$)")',
    'UOP_REGEX = re.compile(r"(?:ADD_TO_TRACE|OPTIMIZED): (_[A-Z0-9_]+?)(?:_r\\d+)?(?=\\s|\\(|\\n|$)")'
)
with open(path, 'w') as f:
    f.write(content)
print("Done")
SCRIPT
python3 /tmp/patch1.py
```

Verify:
```bash
grep -n "UOP_REGEX" ~/fuzzing/lafleur/lafleur/coverage.py | head -1
# Should contain: (?:_r\d+)?
```

---

#### Patch 2 — Missing UOP names

Four UOP names introduced in CPython 3.15 were absent from lafleur's recognition table. Any edge chain containing one of these was silently discarded even after Patch 1.

```bash
cat > /tmp/patch2.py << 'SCRIPT'
import os
path = os.path.expanduser('~/fuzzing/lafleur/lafleur/uop_names.py')
with open(path, 'r') as f:
    content = f.read()
content = content.replace(
    '    "_YIELD_VALUE",\n}',
    '    "_YIELD_VALUE",\n    "_SWAP_FAST",\n    "_SWAP_FAST_0",\n    "_SWAP_FAST_1",\n    "_SPILL_OR_RELOAD",\n}'
)
with open(path, 'w') as f:
    f.write(content)
print("Done")
SCRIPT
python3 /tmp/patch2.py
```

Verify:
```bash
grep -n "SWAP_FAST\|SPILL_OR_RELOAD" ~/fuzzing/lafleur/lafleur/uop_names.py
# Should show 4 lines inside the set, before the closing }
python3 -c "from lafleur.uop_names import UOP_NAMES; print('ok', len(UOP_NAMES))"
# Expected: ok 350
```

---

#### Patch 3 — Harness marker requirement for hand-written seeds

lafleur's coverage parser only accumulates UOP edges after seeing `[f1]` printed to stderr. The seeds in this repo already include the marker. Any new seeds you write must prepend:

```python
import sys
print('[f1] STRATEGY: fuzzing', file=sys.stderr)
```

---

#### Patch 4 — Remove `--session-fuzz`

Session-fuzz mode produces zero coverage on CPython 3.15 because JIT logging flags are evaluated at interpreter startup, not at `exec()` call time. `scripts/launch_campaign.sh` in this repo has `--session-fuzz` removed. Do not add it back.

---

### Step 7: Validate the coverage pipeline before a long run

Seeds go into `$CAMPAIGN_DIR/corpus/jit_interesting_tests/`. lafleur picks them up automatically when run from `$CAMPAIGN_DIR`.

```bash
mkdir -p $CAMPAIGN_DIR/corpus/jit_interesting_tests
cp $REPO/seeds/*.py $CAMPAIGN_DIR/corpus/jit_interesting_tests/

cd $CAMPAIGN_DIR
lafleur \
  --target-python $CPYTHON \
  --min-corpus-files 20 \
  --dynamic-runs \
  --runs 3 \
  --instance-name test-1
```

Let it run 1–2 minutes, then `Ctrl+C` and check:

```bash
lafleur-report $CAMPAIGN_DIR
```

`Global Edges` must be nonzero (expect 500–1500 in the first few minutes). If still 0, work through Patches 1–4.

---

### Step 8: Set up additional build configurations (optional)

The campaign used six instances across four build types. Each needs its own CPython binary. Always `deactivate` before building.

**ASAN build:**

```bash
deactivate
mkdir -p $CPYTHON_DIR-asan && cd $CPYTHON_DIR-asan
git clone https://github.com/python/cpython.git .
git checkout 6908372fb81
./configure --with-pydebug --enable-experimental-jit \
  CC=clang-21 \
  CFLAGS="-fsanitize=address -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=address" \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate
```

**UBSAN build:**

```bash
deactivate
mkdir -p $CPYTHON_DIR-ubsan && cd $CPYTHON_DIR-ubsan
git clone https://github.com/python/cpython.git .
git checkout 6908372fb81
./configure --with-pydebug --enable-experimental-jit \
  CC=clang-21 \
  CFLAGS="-fsanitize=undefined -fno-omit-frame-pointer" \
  LDFLAGS="-fsanitize=undefined" \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate
```

**Free-threaded build:**

```bash
deactivate
mkdir -p $CPYTHON_DIR-ft && cd $CPYTHON_DIR-ft
git clone https://github.com/python/cpython.git .
git checkout 6908372fb81
./configure --with-pydebug --enable-experimental-jit --disable-gil \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate
```

Run `lafleur-jit-tweak` on each build after cloning:

```bash
deactivate
for dir in $CPYTHON_DIR-asan $CPYTHON_DIR-ubsan $CPYTHON_DIR-ft; do
  lafleur-jit-tweak $dir
  cd $dir && ./configure --with-pydebug --enable-experimental-jit \
    PYTHON_FOR_BUILD=/usr/bin/python3.11 && make -j$(nproc)
done
source $VENV/bin/activate
```

---

### Step 9: Place seeds into the corpus

```bash
mkdir -p $CAMPAIGN_DIR/corpus/jit_interesting_tests
cp $REPO/seeds/*.py $CAMPAIGN_DIR/corpus/jit_interesting_tests/
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

Each seed has a function named `uop_harness_f1` with a `for i in range(300)` loop and the `[f1]` harness marker printed to stderr at startup.

---

### Step 10: Set up a RAM disk (optional)

```bash
sudo mkdir -p /mnt/fuzz_ram
sudo mount -t tmpfs -o size=2G tmpfs /mnt/fuzz_ram
mkdir -p /mnt/fuzz_ram/corpus/jit_interesting_tests
cp $REPO/seeds/*.py /mnt/fuzz_ram/corpus/jit_interesting_tests/
```

Back up crashes every two hours:

```bash
crontab -e
# Add:
0 */2 * * * cp -r $CAMPAIGN_DIR/crashes ~/fuzzing/crash_backups/$(date +\%Y\%m\%d_\%H\%M\%S)/ 2>/dev/null
```

---

### Step 11: Launch the full campaign

```bash
mkdir -p $CAMPAIGN_DIR
chmod +x $REPO/scripts/launch_campaign.sh
$REPO/scripts/launch_campaign.sh
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
source $VENV/bin/activate

# Single instance
lafleur-report $CAMPAIGN_DIR/

# HTML dashboard across all instances
lafleur-campaign $CAMPAIGN_DIR/ --html $CAMPAIGN_DIR/report.html
```

Watch: `Global Edges` (grows over time), `Corpus Files` (grows from 18 seed baseline), `Crashes Found`.

---

### Crash triage

**Step 1** — Discard any crash with `SyntaxError` or `IndentationError` — invalid Python from a bad mutation, not a JIT bug.

**Step 2** — Confirm JIT-specificity:

```bash
PYTHON_JIT=1 $CPYTHON path/to/crash_script.py   # should crash
PYTHON_JIT=0 $CPYTHON path/to/crash_script.py   # should be clean
```

**Step 3** — Record the exact commit:

```bash
$CPYTHON -VV
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
cd $REPO/lowmem/injectors
chmod +x build.sh
./build.sh
```

Or manually:

```bash
gcc -shared -fPIC -o $REPO/lowmem/injectors/fail_mmap.so \
    $REPO/lowmem/injectors/fail_mmap.c -ldl
gcc -shared -fPIC -o $REPO/lowmem/injectors/fail_malloc.so \
    $REPO/lowmem/injectors/fail_malloc.c -ldl
```

### Step 3: Run the automated phases

```bash
cd $REPO/lowmem
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

Requires build at `c32e264227b`:

```bash
deactivate
cd $CPYTHON_DIR
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate
```

Run in a loop — failure is nondeterministic (~15–18% hit rate):

```bash
for i in $(seq 1 50); do
  result=$(PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    $CPYTHON \
    $REPO/crashes/unlink_executor_lowmem/reproducer.py 2>&1)
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

Expected crash output:

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
  $CPYTHON $REPO/crashes/unlink_executor_lowmem/reproducer.py

# Clean 100% of the time:
PYTHON_JIT=0 fiu-run -x \
  -c "enable_random name=posix/mm/mmap,probability=0.5" \
  $CPYTHON $REPO/crashes/unlink_executor_lowmem/reproducer.py
```

### Step 6: Confirm the fix

```bash
deactivate
cd $CPYTHON_DIR
git checkout d0e7c6acc93
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate

CLEAN=0; CRASH=0
for i in $(seq 1 100); do
  result=$(PYTHON_JIT=1 fiu-run -x \
    -c "enable_random name=posix/mm/mmap,probability=0.5" \
    $CPYTHON \
    $REPO/crashes/unlink_executor_lowmem/reproducer.py 2>&1)
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
deactivate
cd $CPYTHON_DIR
git checkout 6908372fb81
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate

# Should SIGABRT, exit code -6:
PYTHON_JIT=1 $CPYTHON $REPO/reproducers/gh144681_crash.py

# Should exit cleanly:
PYTHON_JIT=0 $CPYTHON $REPO/reproducers/gh144681_crash.py
```

Expected crash output:

```
python: Python/optimizer.c:790:
_PyJit_translate_single_bytecode_to_trace:
Assertion 'jump_happened == (target_instr[1].cache & 1)' failed.
Aborted (core dumped)
```

### With the raw lafleur crash script

```bash
PYTHON_JIT=1 $CPYTHON $REPO/crashes/gh144681_lafleur/crash_script.py
PYTHON_JIT=0 $CPYTHON $REPO/crashes/gh144681_lafleur/crash_script.py
```

### Confirming the fix

```bash
deactivate
cd $CPYTHON_DIR
git checkout c32e264227b
./configure --with-pydebug --enable-experimental-jit \
  PYTHON_FOR_BUILD=/usr/bin/python3.11
make -j$(nproc)
source $VENV/bin/activate

# Should exit cleanly:
PYTHON_JIT=1 $CPYTHON $REPO/reproducers/gh144681_crash.py
echo "Exit code: $?"   # expected: 0
```

---

## Campaign results (reference)

Results from the campaign on CPython commit `6908372fb81` (3.15.0a6+):

| Metric | Value |
|---|---|
| Run ID (debug-1) | `43e6593d-d074-4e38-be94-fee52773b4d1` |
| Global UOP edges | 1,482 |
| Global distinct UOPs | 230 |
| Corpus size | 118 files (grew from 18 seeds in first hour) |
| Max mutation tree depth | 40 |
| Total executions (first hour) | ~4,025 |
| Crashes found | 1 unique fingerprint (gh-144681, found March 20, 2026) |
| Top mutator | ArithmeticSpamMutator (754 selections) |
| Second mutator | ComprehensiveFunctionMutator (143) |
| Third mutator | HelperFunctionInjector (141) |

The pre-fix 48-hour run executed 748,039 programs and found zero UOP edges — all coverage was discarded due to the four compatibility issues in Patches 1–4.

---

## Environment summary

See `environment.md` for full details. Key versions:

| Component | Version / config |
|---|---|
| OS | Ubuntu 22.04 (x86-64) |
| CPython (bug-finding campaign) | 3.15.0a6+, commit `6908372fb81` (March 2, 2026) |
| CPython (gh-144681 fixed) | 3.15.0a7+, commit `c32e264227b` |
| CPython (lowmem bug found) | commit `c32e264227b` (April 1, 2026) |
| CPython (lowmem bug resolved) | commit `d0e7c6acc93` (April 14, 2026) |
| CPython build flags | `--with-pydebug --enable-experimental-jit` |
| JIT threshold | 63 (via `lafleur-jit-tweak`, default ~4,096) |
| lafleur | commit `e5c1d6c` (February 20, 2026), 4 compatibility patches applied |
| clang | clang-21 (required for JIT stencil generation) |
| Python (build tool) | python3.11 (required by CPython 3.15 JIT build tool) |
| libfiu | system package via `apt` (`libfiu-dev`, `fiu-utils`) |
| libzstd | system package via `apt` (`libzstd-dev`) |
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
