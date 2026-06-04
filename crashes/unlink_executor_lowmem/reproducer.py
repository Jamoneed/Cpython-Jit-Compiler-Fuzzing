"""
Reproducer for unlink_executor assertion failure found during Phase 8
(libfiu mmap injection) of the low-memory stress-testing campaign.

Affected build:  CPython main commit c32e264227b (April 1, 2026)
Fixed build:     CPython main commit d0e7c6acc93 (April 14, 2026)
Reproduction rate: ~15-18% with PYTHON_JIT=1, 0% with PYTHON_JIT=0 across 50 runs

Assertion:
    Python/optimizer.c: idx >= 0 && (size_t)idx < interp->executor_count

Run command (single attempt):
    PYTHON_JIT=1 fiu-run -x \
        -c "enable_random name=posix/mm/mmap,probability=0.5" \
        ~/fuzzing/cpython/python reproducer.py

Loop command (recommended — nondeterministic, run 50 times):
    for i in $(seq 1 50); do
        PYTHON_JIT=1 fiu-run -x \
            -c "enable_random name=posix/mm/mmap,probability=0.5" \
            ~/fuzzing/cpython/python reproducer.py 2>&1 | \
            grep -E "Assertion|Aborted|PASS"
    done

JIT-specificity check (should be clean 100% of the time):
    PYTHON_JIT=0 fiu-run -x \
        -c "enable_random name=posix/mm/mmap,probability=0.5" \
        ~/fuzzing/cpython/python reproducer.py
"""

import sys
import gc


class Obj:
    def __init__(self):
        self.val = 42


def test_attribute_access():
    obj = Obj()
    result = 0
    for i in range(300):
        result += obj.val
    return result


def test_basic_arithmetic():
    x = 0
    for i in range(300):
        x += i
        x *= 1
    return x


def test_inlined_calls():
    def leaf(x):
        return x + 1
    def mid(x):
        return leaf(x) * 2
    result = 0
    for i in range(300):
        result += mid(i)
    return result


def test_gc_interaction():
    class Node:
        def __init__(self, v):
            self.v = v
            self.ref = None
    result = 0
    for i in range(300):
        a = Node(i)
        b = Node(i + 1)
        a.ref = b
        b.ref = a
        result += a.v
        if i % 50 == 0:
            gc.collect()
    return result


tests = [
    test_attribute_access,
    test_basic_arithmetic,
    test_inlined_calls,
    test_gc_interaction,
]

passed = failed = memfail = 0
for test in tests:
    try:
        test()
        print(f"PASS: {test.__name__}", file=sys.stderr)
        passed += 1
    except MemoryError:
        print(f"MEMFAIL: {test.__name__}", file=sys.stderr)
        memfail += 1
    except Exception as e:
        print(f"FAIL: {test.__name__}: {type(e).__name__}: {e}", file=sys.stderr)
        failed += 1

print(f"passed={passed} failed={failed} memfail={memfail}", file=sys.stderr)
sys.exit(1 if failed > 0 else 0)
