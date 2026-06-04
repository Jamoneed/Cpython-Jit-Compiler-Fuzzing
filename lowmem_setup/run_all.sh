#!/bin/bash
# Master runner — phases 1-2, 4-7, 10-11 (automated)
# Phases 3 (manual patch), 8 (labeille), 9 (lafleur) run separately

echo "=============================="
echo "Low-Memory JIT Campaign"
echo "Started: $(date)"
echo "=============================="

SCRIPTS=~/fuzzing/lowmem_tests/scripts

run_phase() {
    local name="$1"
    local script="$2"
    echo ""
    echo "=== $name ==="
    bash "$script"
    local crashes=$(ls ~/fuzzing/lowmem_tests/crashes/ 2>/dev/null | wc -l)
    echo "Crashes so far: $crashes"
}

run_phase "PHASE 1: ulimit mapping"     $SCRIPTS/phase1_ulimit.sh
run_phase "PHASE 2: Random injection"   $SCRIPTS/phase2_injection.sh
run_phase "PHASE 4: Trace exhaustion"   $SCRIPTS/phase4_exhaustion.sh
run_phase "PHASE 5: Concurrent stress"  $SCRIPTS/phase5_concurrent.sh
run_phase "PHASE 6: Invalidation racing" $SCRIPTS/phase6_invalidation.sh
run_phase "PHASE 7: ASAN under pressure" $SCRIPTS/phase7_asan.sh
run_phase "PHASE 10: libfiu injection"  $SCRIPTS/phase10_libfiu.sh
run_phase "PHASE 11: Performance"       $SCRIPTS/phase11_benchmark.sh

echo ""
echo "=============================="
echo "All automated phases complete: $(date)"
echo "Crashes: $(ls ~/fuzzing/lowmem_tests/crashes/ 2>/dev/null | wc -l) files"
ls ~/fuzzing/lowmem_tests/crashes/ 2>/dev/null || echo "No crashes found."
echo ""
echo "Remaining manual phases:"
echo "  Phase 3: Apply jit.c patch, then run scripts/phase3_systematic.sh"
echo "  Phase 8: See scripts/phase8_labeille_manual.sh"
echo "  Phase 9: See scripts/phase9_lafleur_manual.sh"
echo ""
echo "Summary:"
python3 ~/fuzzing/lowmem_tests/scripts/generate_summary.py
echo "=============================="
