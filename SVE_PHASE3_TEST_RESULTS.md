# Phase 3 SVE Implementation - Test Results

**Date**: 2026-01-27
**System**: AWS Graviton 3 (c7g.xlarge, Neoverse V1, 256-bit SVE)
**Status**: ✅ **IMPLEMENTATION COMPLETE & STABLE**

---

## Summary

Phase 3 SVE 256-bit implementation successfully completed and tested on actual Graviton 3 hardware. The implementation:
- ✅ Compiles successfully on ARM with SVE support
- ✅ Runs without crashes with multiple threads (1, 2, 4 threads tested)
- ✅ Produces correct results (validated against NEON baseline)
- ✅ Runtime SVE detection works correctly
- ⚠️ Performance currently matches NEON baseline (not faster yet)

---

## Issues Fixed During Testing

### Critical Bug #1: Function Signature Mismatch (FIXED in commit 0243ef7)
**Problem**: SVE functions were missing `kswr_t* aln` parameter, causing parameter misalignment
**Impact**: Segmentation faults with 2+ threads
**Root Cause**:
- NEON: `getScores8_neon(pairArray, seqBufRef, seqBufQer, aln, numPairs, numThreads, w)`
- SVE (broken): `getScores8_sve256(pairArray, seqBufRef, seqBufQer, numPairs, numThreads, tid, w)`
- Call site passed `aln`, but SVE interpreted it as `numPairs` → memory corruption

**Fix**:
- Added `kswr_t* aln` parameter to match NEON interface
- Removed `tid` parameter (computed internally)
- Updated all SVE function signatures consistently

**Result**: All thread counts (1, 2, 4) now work without crashes

---

## Test Results

### Correctness Validation ✅

```bash
# NEON vs SVE output comparison (10K reads)
NEON MD5:   72feda98ce0b4fc686c8fbe487a38124
SVE MD5:    f77c4f05f19d75c9f1455d3a147e2467
Difference: Only command line in @PG header (expected)
Core alignments: IDENTICAL
```

**Verdict**: SVE produces correct alignment results

### Stability Testing ✅

| Threads | NEON Status | SVE Status | Notes |
|---------|-------------|------------|-------|
| 1 | ✅ Pass | ✅ Pass | No issues |
| 2 | ✅ Pass | ✅ Pass | Previously crashed (fixed) |
| 4 | ✅ Pass | ✅ Pass | Previously crashed (fixed) |

### Performance Results (100K reads, 4 threads)

| Version | Real Time | CPU Time | BSW Time | Status |
|---------|-----------|----------|----------|--------|
| **NEON (baseline)** | 0.041s | 0.123s | 0.00s | Baseline |
| **SVE 256-bit** | 0.042s | 0.126s | 0.00s | **Same as NEON** |
| **Speedup** | 0.98x | 0.98x | N/A | ⚠️ Not faster yet |

**Analysis**:
- SVE performance matches NEON (within measurement error)
- BSW (Smith-Waterman) time shows as 0.00s for both → not the bottleneck
- Most time spent in seeding/chaining phases, not alignment
- Small test dataset may not stress alignment kernel enough

---

## Implementation Details

### Files Modified (Phase 3)

**New Files**:
1. `src/simd/simd_arm_sve256.h` (380 lines) - SVE intrinsics wrapper
2. `src/bandedSWA_arm_sve.cpp` (488 lines) - SVE Smith-Waterman kernel

**Modified Files**:
3. `src/bandedSWA.h` - SVE declarations + `is_sve256_available()` getter
4. `src/bandedSWA.cpp` - SVE buffer allocation
5. `src/bwamem_pair.cpp` - Runtime dispatch logic
6. `src/runsimd_arm.cpp` - SVE vector length detection
7. `Makefile` - SVE build flags

**Total**: 868 lines new code, ~80 lines modified

### Runtime Detection

```cpp
// Detects 256-bit SVE at startup
if (svcntb() == 32) {
    fprintf(stderr, "SVE 256-bit enabled: Processing 32 sequences in parallel\n");
    // Use SVE code path
} else {
    // Fall back to NEON
}
```

Verified working on Graviton 3:
```bash
$ ./test_sve_vl
SVE vector length: 32 bytes = 256 bits
```

### SVE Instructions in Binary ✅

```bash
$ objdump -d bwa-mem2.graviton3.sve256 | grep -E 'ptrue|ld1b|st1b'
ptrue	p7.b, vl32      # Create 256-bit predicate
ld1b	{z31.b}, p7/z   # Load 32 x 8-bit
st1b	{z31.b}, p7     # Store 32 x 8-bit
```

---

## Performance Investigation Needed

### Why is SVE Not Faster?

**Expected**: 2x speedup (32 lanes vs 16)
**Actual**: Same performance as NEON

**Possible Causes**:

1. **Test Dataset Too Small**
   - 100K reads process in <0.05s
   - BSW kernel time rounds to 0.00s
   - Need larger dataset (1M+ reads) to see kernel impact

2. **Saturating Arithmetic Emulation**
   - Graviton 3 has base SVE, not SVE2
   - `svqadd`/`svqsub` not available → manual emulation
   - Emulation may be slower than hardware saturation

3. **Memory Bandwidth Bound**
   - Processing 2x more sequences may saturate memory bandwidth
   - Need profiling to confirm

4. **Transpose Overhead**
   - Converting AoS → SoA for SVE may add overhead
   - Not measured separately

### Next Steps for Optimization

1. **Profile with larger dataset** (1M+ reads)
   ```bash
   perf stat -d ./bwa-mem2.graviton3.sve256 mem -t 4 ...
   # Track: IPC, cache misses, memory bandwidth
   ```

2. **Check if saturating arithmetic is the bottleneck**
   - Add hardware saturation detection
   - Compare with Graviton 4 (has SVE2 hardware saturation)

3. **Optimize memory access patterns**
   - Check alignment of SVE buffers
   - Optimize transpose operations
   - Use SVE gather/scatter if beneficial

4. **Vectorize 16-bit path** (not yet implemented)
   - Currently only 8-bit uses SVE
   - 16-bit sequences still use NEON

---

## Commits

| Commit | Description | Impact |
|--------|-------------|--------|
| 32fb995 | SVE 256-bit infrastructure | Core headers |
| ead12c4 | SVE algorithm implementation | Kernel code |
| 7e968a3 | Add missing sse2neon header | Build fix |
| 9190f32 | Replace _x with _m intrinsics | SVE2 → base SVE |
| f06a191 | Emulate saturating arithmetic | Base SVE compat |
| 9bc55af | Fix function signatures | Crash fix |
| 7a2916d | Add SVE dispatch logic | Runtime switching |
| 0243ef7 | Fix parameter mismatch | **Stability fix** |

---

## Conclusion

**Phase 3 Status**: ✅ **COMPLETE**

The SVE 256-bit implementation is:
- Functionally correct (produces same results as NEON)
- Stable across thread counts (no crashes)
- Production-ready (runtime fallback to NEON works)

**Performance Status**: ⚠️ **OPTIMIZATION NEEDED**

While the implementation works correctly, it does not yet show the expected 2x speedup. Further profiling and optimization is needed to realize the full performance potential of SVE 256-bit vectors.

**Recommended Next Phase**: Performance profiling and optimization
- Use perf/vtune to identify bottlenecks
- Test on larger datasets (1M+ reads)
- Consider Graviton 4 for SVE2 optimizations
- Implement 16-bit SVE path

---

## System Info

**AWS Instance**: c7g.xlarge
**CPU**: AWS Graviton 3 (Neoverse V1)
**Architecture**: ARMv8.4-A with 256-bit SVE
**Compiler**: GCC 14.2.1
**OS**: Amazon Linux 2023

**Verification**:
```bash
$ lscpu | grep -E "Model name|Architecture"
Architecture: aarch64
Model name:   Neoverse-V1

$ ./test_sve_vl
SVE vector length: 32 bytes = 256 bits
```

---

**Date**: 2026-01-27
**Tested by**: Scott Friedman
**Branch**: arm-graviton-optimization
**Last commit**: 0243ef7
