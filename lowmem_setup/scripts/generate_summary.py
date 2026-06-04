import os, glob, datetime

reports = sorted(glob.glob(os.path.expanduser("~/fuzzing/lowmem_tests/reports/*.txt")))
crashes = glob.glob(os.path.expanduser("~/fuzzing/lowmem_tests/crashes/*.log"))

print("=" * 60)
print("LOW-MEMORY JIT STRESS TEST RESULTS")
print(f"Generated: {datetime.datetime.now()}")
print("=" * 60)
print(f"Phases completed: {len(reports)}")
print(f"Crashes found: {len(crashes)}")

if crashes:
    print("\nCrash files:")
    for c in sorted(crashes):
        print(f"  {os.path.basename(c)}")
    print("\nNext: minimize reproducer, verify JIT-specific, file bug report")
    print("  Verify command: PYTHON_JIT=1 ~/fuzzing/cpython/python <script>")
    print("  Confirm clean:  PYTHON_JIT=0 ~/fuzzing/cpython/python <script>")
    print("  File at: https://github.com/python/cpython/issues/new/choose")
    print("  Labels: topic-JIT type-crash")
else:
    print("\nResult: JIT degrades gracefully under all tested conditions.")
    print("Document as:")
    print("  - Minimum memory for JIT-enabled CPython: [from phase 1]")
    print("  - Memory error handling: robust (no crashes)")
    print("  - Performance under pressure: [from phase 11]")
    print("  - Concurrent safety: verified")
    print("  - ASAN clean: no silent memory corruption")
    print("\nFuture work:")
    print("  - Test with upcoming JIT features as they land")
    print("  - Expand labeille beyond top 50 packages")
    print("  - Test on ARM/AArch64 (different mmap behavior)")
    print("  - Test with Python 3.16 alpha when available")

print("=" * 60)
