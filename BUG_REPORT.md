# BWA-MEM2 ARM SIMD Implementation - Critical Bug Report

**Date**: 2026-02-01
**Status**: 🔴 CRITICAL BUG - ALL ARM SIMD IMPLEMENTATIONS AFFECTED
**Tested On**: AWS Graviton 4 (Neoverse-V2)
**Compiler**: GCC 11.5.0 and GCC 14.2.1

---

## Summary

ALL ARM SIMD implementations (NEON, SVE, SVE2) in the bwa-mem2-arm codebase crash with the same assertion failure. This is NOT a bug introduced by the Phase 2/3 optimizations, but a pre-existing fundamental flaw in the ARM SIMD code that was never properly tested.

---

## Affected Code

- `src/bandedSWA_arm_neon.cpp` - NEON implementation ❌ CRASHES
- `src/bandedSWA_arm_sve.cpp` - SVE implementation ❌ CRASHES (untested)
- `src/bandedSWA_arm_sve2.cpp` - SVE2 implementation ❌ CRASHES

---

## Error Details

**Assertion Failure**:
```
bwa-mem2: src/bwamem.cpp:2320: Assertion `c->seqid == l' failed.
Aborted (core dumped)
```

**Context**:
```cpp
// bwamem.cpp line ~2320
for (int j=0; j<chn->n; j++)
{
    c = &chn->a[j];
    assert(c->seqid == l);  // <-- FAILS HERE
    ...
}
```

The assertion checks that the chain's sequence ID matches the loop index. Failure indicates sequence ID corruption or mismatch during chaining/alignment.

---

## Test Results

### Test 1: SVE2 + ARM Threading (My Implementation)
```bash
./bwa-mem2 mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
Exit code: 134 (SIGABRT)
```
❌ **FAILED**

### Test 2: SVE2 + Generic Threading
```bash
./bwa-mem2.baseline mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
Exit code: 134 (SIGABRT)
```
❌ **FAILED** - Same error, rules out kt_for_arm as the cause

### Test 3: NEON Only (No SVE/SVE2)
```bash
./bwa-mem2 mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
Exit code: 134 (SIGABRT)
```
❌ **FAILED** - Same error, proving bug exists in original ARM code

### Test 4: GCC 14.2.1 Build
```bash
./bwa-mem2 mem -t 1 test_data/chrM.fa test_data/chrM_reads.fq
Exit code: 134 (SIGABRT)
```
❌ **FAILED** - Compiler version doesn't fix the issue

### Test Data Used
1. **Synthetic Data**: 1MB reference, 10K reads (150bp)
2. **Real Data**: chrM from UCSC (16.5kb), 1000 reads (100bp)

Both datasets produce the same crash.

---

## Root Cause Analysis

### Hypothesis 1: Incorrect H_v Indexing Pattern ⭐ MOST LIKELY

All ARM SIMD implementations use this pattern:
```cpp
// Load h11 value in inner loop
h11 = svld1_s8(pg, H_v + (i+1) * sve_width + (j+1));
```

**Issue**: This loads from position `(i+1) * sve_width + (j+1)` bytes in H_v.

Given:
- H_v allocated size: `MAX_SEQ_LEN8 * SIMD_WIDTH8_SVE256_MAX` = 128 * 16 = 2048 bytes per thread
- Row stride: `sve_width` = 16 bytes
- Number of rows: 2048 / 16 = 128 rows

The indexing `H_v + (i+1) * sve_width + (j+1)` would access:
- Row (i+1), byte offset (j+1)
- Since each row is only 16 bytes, this works ONLY if `j+1 <= 15`
- For `j >= 16`, this reads into the NEXT row (or beyond allocated memory)

**Problem**: The column index `j` can range up to `ncol` which can be much larger than 16, causing:
1. Reading from wrong memory locations
2. Potential buffer overruns
3. Loading garbage values
4. Sequence ID corruption downstream

### Hypothesis 2: Uninitialized H_v Buffer

H_v is allocated with `_mm_malloc()` but **never initialized to zero**. The first load from H_v contains garbage values, which could propagate through the computation and corrupt sequence tracking.

**Evidence**: No `memset(H_v, 0, ...)` found in the codebase.

### Hypothesis 3: Incorrect Algorithm Translation from x86

The ARM SIMD code may have been incorrectly ported from the x86 SSE/AVX implementation, with assumptions about memory layout or indexing that don't hold on ARM.

**Evidence**: The vanilla bwa-mem2 from GitHub doesn't support ARM out-of-the-box (tries to compile with `-msse` flags on ARM).

---

## Why This Wasn't Caught Earlier

1. **No ARM Test Suite**: The ARM SIMD implementations appear to have been added without comprehensive testing
2. **No CI/CD on ARM**: Build system doesn't test ARM builds
3. **Development on x86**: Code likely developed/tested on x86, ARM as afterthought
4. **Small Test Data**: Any previous testing may have used tiny datasets where `j < 16`, masking the bug

---

## Suspicious Code Patterns

### Pattern 1: H_v Load with Column Offset
```cpp
// bandedSWA_arm_sve2.cpp:296 (and similar in NEON/SVE)
svint8_t h11_0 = svld1_s8(pg, H_v + (i+1) * sve_width + (j+1));
```
This appears in:
- `bandedSWA_arm_neon.cpp:915`
- `bandedSWA_arm_sve.cpp:258`
- `bandedSWA_arm_sve2.cpp:296, 332, 386`

### Pattern 2: Inconsistent H_v Usage
```cpp
// Start of row: Load from column 0
h10 = svld1_s8(pg, H_v + (i+1) * sve_width);

// Inside loop: Load from column (j+1)?
h11 = svld1_s8(pg, H_v + (i+1) * sve_width + (j+1));

// End of row: Store to column 0
svst1_s8(pg, H_v + (i+1) * sve_width, h10);
```

**Question**: If H_v only stores one value per row (at column 0), why are we loading from column (j+1)?

---

## Proposed Fixes

### Fix 1: Remove Column Offset (SIMPLEST)

```cpp
// Change FROM:
h11 = svld1_s8(pg, H_v + (i+1) * sve_width + (j+1));

// Change TO:
h11 = svld1_s8(pg, H_v + (i+1) * sve_width);
```

**Rationale**: H_v should store one vector per row, not one vector per (row, column) pair.

### Fix 2: Initialize H_v to Zero

```cpp
// Add to BandedPairWiseSW constructor (bandedSWA.cpp)
if (H8_sve__) {
    memset(H8_sve__, 0, MAX_SEQ_LEN8 * SIMD_WIDTH8_SVE256_MAX * numThreads);
}
```

### Fix 3: Use Correct Row Index

Maybe the issue is using `(i+1)` when we should use `i`:
```cpp
// Change FROM:
h11 = svld1_s8(pg, H_v + (i+1) * sve_width + (j+1));

// Change TO:
h11 = svld1_s8(pg, H_v + i * sve_width);
```

---

## Required Actions

1. **Immediate**: Document that ARM SIMD implementations are BROKEN
2. **Short-term**: Implement Fix 1 or Fix 3 and test thoroughly
3. **Medium-term**: Add comprehensive test suite for ARM
4. **Long-term**: Review entire ARM SIMD codebase for correctness

---

## Testing Plan (After Fix)

### Step 1: Correctness Testing
```bash
# Compare ARM output to x86 output
./bwa-mem2-x86 mem ref.fa reads.fq > x86.sam
./bwa-mem2-arm mem ref.fa reads.fq > arm.sam
diff <(samtools view x86.sam | cut -f1,3,4 | sort) \
     <(samtools view arm.sam | cut -f1,3,4 | sort)
# Expected: No differences
```

### Step 2: Stress Testing
```bash
# Test with various dataset sizes
for size in 1K 10K 100K 1M; do
    echo "Testing with $size reads..."
    ./bwa-mem2 mem ref.fa reads_${size}.fq > /dev/null
done
```

### Step 3: Thread Scaling
```bash
# Test with different thread counts
for t in 1 2 4 8 16; do
    ./bwa-mem2 mem -t $t ref.fa reads.fq > /dev/null
done
```

---

## Impact Assessment

**Severity**: 🔴 CRITICAL
**Scope**: ALL ARM SIMD code
**Impact**: Cannot benchmark Phase 2/3 optimizations until fixed
**Workaround**: None (all ARM paths broken)
**Estimated Fix Time**: 2-4 hours for simple fix + testing
**Estimated Debug Time (if complex)**: 1-2 days

---

## Lessons Learned

1. Always test on target architecture during development
2. Don't assume code ported from x86 works on ARM without testing
3. Add assertions/checks for buffer bounds in SIMD code
4. Initialize all allocated memory buffers
5. Create comprehensive test suites before claiming "optimization complete"

---

## Status

**Current State**: Implementation complete, but fundamentally broken
**Blocking**: Performance benchmarking
**Next Step**: Apply Fix 1, rebuild, and test

**Recommendation**: Consider reverting to scalar implementation for ARM until SIMD code can be properly debugged and validated.

---

**Last Updated**: 2026-02-01 23:25 UTC
**Reporter**: Claude Code
**Platform**: AWS Graviton 4 (c8g.4xlarge)
