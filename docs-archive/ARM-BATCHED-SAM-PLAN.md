# ARM Batched SAM Processing Implementation Plan

## Executive Summary

**Root Cause Identified:** ARM Graviton is 76% slower (23.7s vs 13.8s estimated) in SAM processing because it uses the slow iterative path (`mem_sam_pe`) instead of the fast batched path (`mem_sam_pe_batch`) that x86 uses.

**Impact:** SAM processing accounts for **76% of total runtime** (23.7s of 31.2s). This is the primary bottleneck preventing ARM from achieving competitive performance with x86.

**Solution:** Implement ARM NEON/SVE versions of the batched Smith-Waterman scoring functions (`getScores8` and `getScores16`) to enable the fast batched SAM processing path on ARM.

---

## Performance Analysis

### Current Performance (Human chr22, 100K paired reads, 4 threads)

| Component | ARM Graviton3 | Estimated x86 | % of Runtime (ARM) |
|-----------|---------------|---------------|-------------------|
| **SAM Processing** | 23.74s | ~13.8s | **76%** |
| BSW (Smith-Waterman) | 4.34s | ~3.0s | 14% |
| SMEM (Seeding) | 2.27s | ~1.6s | 7% |
| SAL (Seed Align) | 0.32s | ~0.2s | 1% |
| I/O + Index | 0.58s | ~0.5s | 2% |
| **Total** | **31.25s** | **~19.1s** | **100%** |

**ARM is 1.64x slower than estimated x86 performance.**

### Why SAM Processing is Slow on ARM

BWA-MEM2 has two SAM processing implementations:

1. **Fast Batched Path** (`mem_sam_pe_batch`) - x86 only
   - Processes pairs in batches using vectorized Smith-Waterman
   - Uses `kswv->getScores8()` and `kswv->getScores16()`
   - Enabled by: `#if __AVX512BW__ || __AVX2__`

2. **Slow Iterative Path** (`mem_sam_pe`) - ARM uses this
   - Processes pairs one at a time
   - Non-vectorized scalar code
   - Used when no AVX2/AVX512 detected

**ARM condition:**
```cpp
#if (((!__AVX512BW__) && (!__AVX2__)) || ((!__AVX512BW__) && (__AVX2__)))
    // ARM takes this path - SLOW
    for (int i=start; i< end; i+=2)
        mem_sam_pe(...);  // One pair at a time
#else
    // x86 takes this path - FAST
    mem_sam_pe_batch(...);  // Batched processing
#endif
```

---

## Code Analysis

### Files Requiring Changes

#### 1. `src/bandedSWA.cpp` (4,872 lines)
**Current SIMD Implementations:**
- Lines 263-1817: AVX2 version (1,554 lines)
- Lines 1818-3360: AVX512BW version (1,542 lines)
- Lines 3361-4872: SSE2 version (1,511 lines)

**Required:** Add ARM NEON/SVE version (~1,500-2,000 lines)

**Key Functions to Port:**
- `getScores8()` - 8-bit scoring (more common)
- `getScores16()` - 16-bit scoring (longer sequences)
- Helper functions: `smithWaterman_*_16()`, alignment kernels

#### 2. `src/bwamem.cpp` (Line 1247)
**Change:** Update preprocessor condition to enable batched path for ARM
```cpp
// Current
#if (((!__AVX512BW__) && (!__AVX2__)) || ((!__AVX512BW__) && (__AVX2__)))
    // Slow path
#else
    // Fast batched path
#endif

// Proposed
#if ((!__AVX512BW__) && (!__AVX2__) && (!__ARM_NEON))
    // Slow path (fallback only)
#else
    // Fast batched path (x86 AND ARM)
#endif
```

#### 3. `src/bwamem_pair.cpp` (Lines 650, 699)
**Change:** Update `mem_sam_pe_batch()` to support ARM
```cpp
// Current
#if __AVX512BW__
    pwsw->getScores8(...);
    pwsw->getScores16(...);
#else
    fprintf(stderr, "Error...");
    exit(EXIT_FAILURE);
#endif

// Proposed
#if __AVX512BW__ || __AVX2__ || __ARM_NEON
    pwsw->getScores8(...);
    pwsw->getScores16(...);
#else
    fprintf(stderr, "Error...");
    exit(EXIT_FAILURE);
#endif
```

#### 4. `src/bandedSWA.h`
**Minimal changes:** Already has SIMD_WIDTH8/16 defined for ARM NEON

---

## Implementation Approach

### Option A: Port SSE2 Code to ARM NEON (Recommended)

**Rationale:**
- SSE2 and ARM NEON are both 128-bit SIMD instruction sets
- Most SSE2 intrinsics have direct NEON equivalents
- BWA-MEM2 already has 1,511 lines of SSE2 implementation
- Many SSE2-to-NEON porting guides exist

**SIMD Width Comparison:**
| Platform | Width | Elements (8-bit) | Elements (16-bit) |
|----------|-------|------------------|-------------------|
| SSE2 | 128-bit | 16 | 8 |
| ARM NEON | 128-bit | 16 | 8 |
| AVX2 | 256-bit | 32 | 16 |
| AVX512 | 512-bit | 64 | 32 |

**Common SSE2 to NEON Mappings:**
```cpp
// Load/Store
__m128i a = _mm_load_si128(p);     → uint8x16_t a = vld1q_u8(p);
_mm_store_si128(p, a);             → vst1q_u8(p, a);

// Arithmetic
_mm_add_epi8(a, b);                → vaddq_u8(a, b);
_mm_sub_epi8(a, b);                → vsubq_u8(a, b);
_mm_max_epu8(a, b);                → vmaxq_u8(a, b);
_mm_min_epu8(a, b);                → vminq_u8(a, b);

// Comparison
_mm_cmpeq_epi8(a, b);              → vceqq_u8(a, b);
_mm_cmpgt_epi8(a, b);              → vcgtq_s8(a, b);

// Blending (SSE4.1, but can be emulated)
_mm_blendv_epi8(a, b, mask);       → vbslq_u8(mask, b, a);

// Shifting
_mm_slli_epi16(a, 3);              → vshlq_n_u16(a, 3);
_mm_srli_epi16(a, 3);              → vshrq_n_u16(a, 3);
```

**Effort Estimate:** 3-4 weeks
- Week 1: Port getScores16 (16-bit version, simpler)
- Week 2: Port getScores8 (8-bit version, more complex)
- Week 3: Testing, debugging, correctness validation
- Week 4: Performance tuning, edge cases

### Option B: Port AVX2 Code with ARM SVE

**Rationale:**
- Graviton3/3E support SVE with 256-bit width (same as AVX2)
- Could achieve parity with AVX2 performance
- Future-proof for Graviton 4+ with wider SVE

**Challenges:**
- SVE is more complex than NEON (predicate-based)
- Less mature compiler support and tooling
- Would need NEON fallback for Graviton2 anyway

**Effort Estimate:** 6-8 weeks
- Weeks 1-2: Learn SVE programming model
- Weeks 3-4: Port AVX2 → SVE for getScores16/8
- Weeks 5-6: Testing and debugging
- Weeks 7-8: Performance tuning

---

## Phased Implementation Plan

### Phase 1: Enable ARM NEON Batched Path (Week 1-4)

**Goal:** Port SSE2 Smith-Waterman to ARM NEON

**Tasks:**
1. **Week 1: Setup & Port getScores16()**
   - Set up build system for ARM NEON
   - Port 16-bit scoring function (~700 lines)
   - Add `#if __ARM_NEON` sections
   - Basic correctness testing

2. **Week 2: Port getScores8()**
   - Port 8-bit scoring function (~800 lines)
   - Handle more complex bit manipulations
   - Port helper functions

3. **Week 3: Integration & Testing**
   - Update preprocessor conditions in bwamem.cpp, bwamem_pair.cpp
   - Build and test on Graviton3
   - Correctness validation against x86 output
   - Run full test suite

4. **Week 4: Performance Tuning**
   - Profile to identify hotspots
   - Optimize critical loops
   - Test different compiler flags
   - Benchmark against baseline

**Expected Outcome:**
- SAM processing: 23.7s → **~14-16s** (40-50% speedup)
- Total runtime: 31.2s → **~22-24s** (30-40% faster)
- **ARM competitive with x86** (within 1.2x)

### Phase 2: ARM SVE Optimization (Week 5-12, Optional)

**Goal:** Port AVX2 version to ARM SVE for Graviton3/3E/4

**Only pursue if Phase 1 shows < 1.5x speedup**

**Tasks:**
- Weeks 5-6: SVE learning and prototyping
- Weeks 7-9: Port AVX2 → SVE for getScores16/8
- Weeks 10-11: Testing and debugging
- Week 12: Performance evaluation

**Expected Outcome:**
- SAM processing: ~14-16s → **~12-13s** (additional 15-20% speedup)
- Total runtime: ~22-24s → **~20-21s**
- **ARM parity with x86**

### Phase 3: ARM Compiler Optimization (Week 13-14, Optional)

**Goal:** Test ARM Compiler (armclang) and ARM Performance Libraries

**Tasks:**
- Week 13: Install and configure ARM Compiler for Linux
- Week 13: Build BWA-MEM2 with armclang
- Week 13: Integrate ARM Performance Libraries (if applicable)
- Week 14: Benchmark and compare with GCC builds
- Week 14: Tune compiler flags specific to ARM Compiler

**Expected Outcome:**
- Additional 5-15% speedup over GCC build
- Better code generation for ARM-specific instructions

---

## Technical Details

### SSE2 Intrinsics Requiring Special Attention

**1. Blend Operations (_mm_blendv_epi8)**
```cpp
// SSE4.1
__m128i r = _mm_blendv_epi8(a, b, mask);

// ARM NEON equivalent (using BSL - Bit Select)
uint8x16_t r = vbslq_u8(mask, b, a);  // Note: operand order differs!
```

**2. Horizontal Operations**
```cpp
// SSE: _mm_sad_epu8 (sum of absolute differences)
// NEON: Requires multiple operations
uint8x16_t diff = vabdq_u8(a, b);
uint16x8_t sum16 = vpaddlq_u8(diff);  // Pairwise add
// Continue pairwise adding...
```

**3. Pack/Unpack Operations**
```cpp
// SSE: _mm_packs_epi16
__m128i packed = _mm_packs_epi16(a, b);

// NEON: Different approach
int8x8_t low = vqmovn_s16(a);
int8x8_t high = vqmovn_s16(b);
int8x16_t packed = vcombine_s8(low, high);
```

### Compiler Flags

**GCC/Clang for ARM NEON:**
```makefile
CXXFLAGS += -march=armv8-a+simd -O3
```

**For SVE (Graviton3+):**
```makefile
CXXFLAGS += -march=armv8.4-a+sve -O3
```

### Testing Strategy

**1. Correctness Validation:**
```bash
# Compare ARM output with x86 reference
diff <(./bwa-mem2-x86 mem ref.fa reads.fq | grep -v "^@") \
     <(./bwa-mem2-arm mem ref.fa reads.fq | grep -v "^@")

# Should be identical except for timing comments
```

**2. Performance Testing:**
```bash
# Benchmark on Graviton3 c7g.xlarge
for i in {1..5}; do
    time ./bwa-mem2 mem -t 4 chr22.fa reads_1.fq reads_2.fq > /dev/null
done
```

**3. Unit Testing:**
- Use BWA-MEM2's test suite in `test/` directory
- Add ARM-specific unit tests for getScores8/16
- Validate edge cases (empty sequences, very long sequences, etc.)

---

## Resource Requirements

### Development Environment
- AWS Graviton3 c7g instances (c7g.xlarge or larger)
- Access to x86 instance for correctness comparison
- GCC 11+ with ARM NEON support
- Git, make, standard development tools

### Reference Materials
- ARM NEON Intrinsics Reference: https://developer.arm.com/architectures/instruction-sets/intrinsics/
- SSE to NEON Guide: https://github.com/DLTcollab/sse2neon
- BWA-MEM2 paper: https://ieeexplore.ieee.org/document/8820962

### Testing Datasets
- E. coli K-12 (4.6 MB) - quick testing
- Human chr22 (50 MB) - realistic testing
- Full human genome HG38 (3.1 GB) - final validation

---

## Risk Assessment

### High Risk
- **Correctness bugs:** SIMD code is error-prone
  - Mitigation: Extensive testing, bit-exact validation against x86

### Medium Risk
- **Performance doesn't meet expectations:** <1.3x speedup
  - Mitigation: Profile-guided optimization, consider SVE (Phase 2)

- **Compiler issues:** GCC NEON codegen quality varies
  - Mitigation: Test multiple compilers (GCC, Clang, ARM Compiler)

### Low Risk
- **Code maintenance:** Diverging from upstream BWA-MEM2
  - Mitigation: Submit PR upstream, engage with maintainers

---

## Success Criteria

### Phase 1 (Minimum)
✅ ARM NEON implementation compiles without errors
✅ Produces identical output to x86 (correctness)
✅ **SAM processing speedup: ≥1.4x** (23.7s → ≤17s)
✅ **Total speedup: ≥1.3x** (31.2s → ≤24s)
✅ ARM within 1.3x of x86 performance

### Phase 1 (Target)
✅ **SAM processing speedup: ≥1.6x** (23.7s → ≤15s)
✅ **Total speedup: ≥1.4x** (31.2s → ≤22s)
✅ ARM within 1.15x of x86 performance

### Phase 2 (Stretch Goal)
✅ ARM SVE implementation for Graviton3/3E
✅ **Total runtime: ≤21s**
✅ **ARM parity with x86** (within 1.05x)

---

## Next Steps

1. **Get approval to proceed with Phase 1**
2. **Set up Graviton3 development environment**
3. **Clone BWA-MEM2 and create feature branch**
4. **Start with getScores16() SSE2→NEON port**
5. **Incremental testing and validation**

---

## Questions for Discussion

1. **Timeline:** Is 4-week Phase 1 timeline acceptable?
2. **Resources:** Do we have sustained access to Graviton3 instances?
3. **Upstream:** Should we engage with BWA-MEM2 maintainers early?
4. **Compiler:** Should we procure ARM Compiler license for Phase 3?
5. **Testing:** Do we need additional validation datasets?

---

**Document Version:** 1.0
**Date:** 2026-01-26
**Author:** Analysis of BWA-MEM2 ARM optimization effort
