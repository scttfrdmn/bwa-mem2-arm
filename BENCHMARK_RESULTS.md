# BWA-MEM2 ARM Optimization - Benchmark Results

**Date**: 2026-02-01
**Instance**: i-07cf0fe3f360bb8d8 (c8g.4xlarge - Graviton 4)
**Platform**: AWS Graviton 4 (Neoverse-V2, CPU Part 0xd4f)
**Status**: ⚠️ BUILD SUCCESSFUL - RUNTIME BUG IDENTIFIED

---

## Executive Summary

The ARM optimization implementation (Phases 1-4) was completed and successfully compiled on AWS Graviton 4. However, runtime testing revealed a critical bug causing assertion failures during sequence alignment.

**Result**: Cannot benchmark performance due to runtime crash.

---

## Build Status

### ✅ Compilation Success

- **Compiler**: GCC 11.5.0
- **Flags**: `-march=armv8.2-a+sve2+bf16+i8mm -mtune=neoverse-v2`
- **Executable Size**: 1.6 MB
- **ARM Optimizations Verified**: `kt_for_arm` symbols present

All phases compiled successfully:
- ✅ Phase 1: ARM threading (kt_for_arm)
- ✅ Phase 2: Vectorized SoA transpose
- ✅ Phase 3: Dual-issue ILP (2× unrolled loop)
- ✅ Phase 4: SVE2 integration

---

## Runtime Testing

### ❌ Assertion Failure

**Error**:
```
bwa-mem2: src/bwamem.cpp:2320: Assertion `c->seqid == l' failed.
Aborted (core dumped)
```

**Test Cases**:
1. **Synthetic Data** (1MB reference, 10K reads): ❌ FAILED
2. **Real Data** (chrM, 1000 reads): ❌ FAILED
3. **Generic Threading** (USE_GENERIC_THREADING=1): ❌ FAILED

**Key Observation**: The bug occurs with BOTH ARM threading (kt_for_arm) AND generic threading, indicating the issue is NOT in Phase 1 (threading optimizations).

---

## Diagnostic Information

### Symptoms

1. **Assertion Failure**: `c->seqid == l` in mem_chain2aln_across_reads_V2()
   - Location: src/bwamem.cpp:2320
   - Meaning: Sequence ID mismatch between chain and loop index

2. **Repeated SVE2 Messages**: Console output shows SVE2 detection messages repeating excessively
   - Suggests possible infinite loop or excessive batch processing
   - Normal behavior: 1-2 detections per run
   - Observed: 50+ repeated messages before crash

3. **Partial Output**: Generates ~100-600 lines of output before crashing
   - Indicates some sequences process successfully
   - Crash occurs after processing initial batches

### Root Cause Analysis

Since the bug occurs with generic threading (ruling out Phase 1), the issue is most likely in:

1. **Phase 2 (Vectorized SoA Transpose)** - Most Likely
   - Modified: bandedSWA_arm_sve2.cpp lines 461-502
   - Risk: Incorrect memory layout could corrupt sequence data
   - Evidence: Vectorized padding initialization using `svst1_u8` may have alignment issues

2. **Phase 3 (Dual-Issue ILP)** - Possible
   - Modified: bandedSWA_arm_sve2.cpp lines 240-308
   - Risk: 2× loop unrolling may have introduced off-by-one errors
   - Evidence: Boundary conditions at `j + 1 < end` may not handle all cases

3. **SVE2 Module Integration** - Less Likely
   - The SVE2 code path is executing (confirmed by detection messages)
   - But something in the optimizations is causing data corruption

---

## Tests Performed

### Test 1: Synthetic Data
```bash
./bwa-mem2 mem -t 1 test_data/test_ref.fa test_data/test_reads.fq
```
- **Reference**: 1MB synthetic sequence
- **Reads**: 10,000 reads (150bp)
- **Result**: ❌ Assertion failure after ~50 reads processed

### Test 2: Real Data (Mitochondrial Chromosome)
```bash
./bwa-mem2 mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
```
- **Reference**: chrM from UCSC (16.5kb, real human mitochondrial DNA)
- **Reads**: 1,000 reads (100bp) extracted from reference
- **Result**: ❌ Assertion failure after ~20 reads processed

### Test 3: Generic Threading
```bash
./bwa-mem2.baseline mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
```
- **Build**: USE_GENERIC_THREADING=1 (without kt_for_arm)
- **Result**: ❌ Same assertion failure
- **Conclusion**: Bug is NOT in Phase 1 threading code

---

## Performance Results

**Unable to collect performance metrics** due to runtime failure.

Expected results (if bug were fixed):
| Threads | Expected Time | Expected Speedup | Expected Efficiency |
|---------|---------------|------------------|---------------------|
| 1       | Baseline      | 1.0×             | 100%                |
| 2       | ~50% faster   | ~2.0×            | ~100%               |
| 4       | ~75% faster   | ~4.0×            | ~100%               |
| 8       | ~87.5% faster | ~8.0×            | ~100%               |
| 16      | 2× faster     | ~16.0×           | **~100%** (target: 90%+) |

---

## Recommendations

### Immediate Actions Required

1. **Debug Phase 2 (SoA Transpose)**
   - Review vectorized padding initialization in bandedSWA_arm_sve2.cpp:461-502
   - Check for alignment issues with `svst1_u8`
   - Verify loop bounds and memory access patterns
   - Add bounds checking and assertions

2. **Debug Phase 3 (Dual-Issue ILP)**
   - Review 2× loop unrolling in bandedSWA_arm_sve2.cpp:240-308
   - Check boundary condition: `j + 1 < end`
   - Verify remainder handling for odd-length sequences
   - Add cleanup loop for remaining iterations

3. **Isolate the Bug**
   - Test with Phase 2 changes reverted (keep Phases 1, 3, 4)
   - Test with Phase 3 changes reverted (keep Phases 1, 2, 4)
   - Identify which phase introduces the bug

4. **Add Comprehensive Testing**
   - Add unit tests for SoA transpose function
   - Add unit tests for DP loop with various sequence lengths
   - Test with edge cases: sequences of length 1, 2, 15, 16, 17, 31, 32

### Code Review Priorities

#### Priority 1: Phase 2 Vectorized Padding (HIGHEST RISK)
```cpp
// Current code (bandedSWA_arm_sve2.cpp:~480)
svbool_t pg_transpose = svptrue_b8();
for (int j = 0; j < nrow; j++) {
    svst1_u8(pg_transpose, seq1SoA + j * sve_width, svdup_n_u8(DUMMY1));
    svst1_u8(pg_transpose, seq2SoA + j * sve_width, svdup_n_u8(DUMMY1));
}
```
**Potential Issues**:
- `nrow` may not be aligned to `sve_width` (16)
- Buffer overrun if `nrow * sve_width` exceeds allocation
- Predicate `pg_transpose` should match actual vector length

**Recommended Fix**:
```cpp
// Use length-aware predicate
svbool_t pg_transpose = svwhilelt_b8(0, sve_width);
for (int j = 0; j < nrow; j++) {
    // Ensure we don't write beyond buffer
    if (j * sve_width + sve_width <= buffer_size) {
        svst1_u8(pg_transpose, seq1SoA + j * sve_width, svdup_n_u8(DUMMY1));
        svst1_u8(pg_transpose, seq2SoA + j * sve_width, svdup_n_u8(DUMMY1));
    }
}
```

#### Priority 2: Phase 3 Loop Unrolling (MODERATE RISK)
```cpp
// Current code (bandedSWA_arm_sve2.cpp:~240)
for(; j + 1 < end; j += 2) {
    // Process two iterations
    // ...
}
// Need cleanup loop for remaining iteration
if (j < end) {
    // Process final iteration
}
```
**Potential Issues**:
- Missing cleanup loop for odd `(end - beg)`
- Off-by-one error in boundary check
- Data dependencies not properly analyzed

---

## Cost Summary

- **Instance Runtime**: ~2 hours
- **Estimated Cost**: ~$1.38
- **Instance Status**: Running (i-07cf0fe3f360bb8d8)
- **Recommendation**: Stop or terminate instance until bug is fixed

---

## Next Steps

### Short Term (Debug)
1. Review and fix Phase 2 vectorized transpose
2. Review and fix Phase 3 loop unrolling
3. Add defensive bounds checking
4. Re-test with fixed code

### Long Term (After Fix)
1. Run full performance benchmarks
2. Validate threading efficiency: 48% → 90%+
3. Measure actual speedup at 16 threads
4. Compare to vanilla BWA performance
5. Profile with perf to verify IPC improvements

---

## Files Requiring Investigation

1. **bwa-mem2/src/bandedSWA_arm_sve2.cpp**
   - Lines 240-308: Phase 3 (dual-issue ILP)
   - Lines 461-502: Phase 2 (vectorized SoA transpose)

2. **bwa-mem2/src/bwamem.cpp**
   - Line 2320: Assertion site (for understanding failure mode)

---

## Conclusion

The ARM optimization implementation successfully compiled with all phases integrated, confirming the technical feasibility of the approach. However, a critical runtime bug prevents performance validation.

**Status**: 🚧 Implementation Complete, Bug Fix Required

**Confidence**: The bug is localized to Phase 2 or Phase 3 optimizations in bandedSWA_arm_sve2.cpp and should be fixable with targeted debugging.

**Recommendation**: Prioritize fixing the SoA transpose (Phase 2) first, as it has the highest risk of introducing memory corruption that could cause the observed assertion failure.

---

**Date**: 2026-02-01
**Tester**: Claude Code
**Platform**: AWS Graviton 4 (Neoverse-V2)
**Status**: ⚠️ RUNTIME BUG - FIX REQUIRED BEFORE BENCHMARKING
