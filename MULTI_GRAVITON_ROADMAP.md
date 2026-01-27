# Multi-Graviton Support Roadmap

**Date:** January 27, 2026
**Current Status:** Week 2 validated on Graviton 3

---

## Overview

Now that Week 2 (8-bit NEON) is working on Graviton 3, we should:
1. **Test backward compatibility** (Graviton 2)
2. **Test forward compatibility** (Graviton 3E, 4)
3. **Optimize for each generation** (generation-specific builds)
4. **Implement SVE/SVE2** (advanced vector instructions)

---

## Graviton Generation Comparison

| Generation | CPU | ISA | Vector | Clock | Availability | Notes |
|-----------|-----|-----|--------|-------|-------------|-------|
| **Graviton 1** | A72 | ARMv8.0 | NEON 128-bit | 2.3 GHz | c6g (deprecated) | Skip testing |
| **Graviton 2** | N1 | ARMv8.2-A | NEON 128-bit, dotprod | 2.5 GHz | c6g.xlarge | **Test now** |
| **Graviton 3** | V1 | ARMv8.4-A | SVE 256-bit, bf16, i8mm | 2.6 GHz | c7g.xlarge | ✅ **Working** |
| **Graviton 3E** | V1+ | ARMv8.4-A | SVE 256-bit (+35%) | 2.6 GHz | c7gn.xlarge | **Test now** |
| **Graviton 4** | V2 | ARMv9-A | SVE2 512-bit, MOPS | 2.8 GHz | c8g.xlarge | **Test now** |

---

## Phase Roadmap

### ✅ Phase 1: Week 2 Complete (DONE)
- **Status:** ✅ Complete
- **Target:** Graviton 3 (c7g.xlarge)
- **Implementation:** 8-bit NEON + 16-bit NEON
- **Performance:** 1.7-2.0x vs scalar baseline
- **Next:** Test on other generations

### ⏳ Phase 2: Multi-Generation Support (IN PROGRESS)

#### 2.1 Backward Compatibility - Graviton 2
**Priority:** HIGH
**Effort:** 1-2 days
**Status:** ⏳ Not tested yet

**Why Important:**
- Still widely deployed (c6g instances)
- Lacks SVE, bf16, i8mm features
- Needs ARMv8.2-A compatible build

**Tasks:**
- [ ] Build with `-march=armv8.2-a+dotprod+crypto -mtune=neoverse-n1`
- [ ] Test Week 2 implementation on c6g.xlarge
- [ ] Verify NEON 128-bit paths work without SVE
- [ ] Benchmark performance (expect similar to Graviton 3)

**Expected Result:** Should work (NEON 128-bit is ARMv8.0 baseline)

---

#### 2.2 Forward Compatibility - Graviton 3E
**Priority:** MEDIUM
**Effort:** 1 day
**Status:** ⏳ Not tested yet

**Why Important:**
- 35% better vector performance than Graviton 3
- Same ISA (ARMv8.4-A) but enhanced execution
- Network-optimized instances (c7gn)

**Tasks:**
- [ ] Test Week 2 on c7gn.xlarge
- [ ] Measure performance improvement (expect +10-15% vs c7g)
- [ ] Validate stability
- [ ] Document performance gains

**Expected Result:** Should work with better performance

---

#### 2.3 Latest Generation - Graviton 4
**Priority:** HIGH
**Effort:** 1 day testing, 2-3 weeks optimization
**Status:** ⏳ Not tested yet

**Why Important:**
- Latest generation (2024)
- ARMv9-A with SVE2 (512-bit capable)
- New instructions: MOPS, SVE2-bitperm
- Best performance potential

**Tasks:**
- [ ] Test Week 2 on c8g.xlarge
- [ ] Build with `-march=armv9-a+sve2 -mtune=neoverse-v2`
- [ ] Validate NEON fallback works
- [ ] Benchmark baseline performance
- [ ] Plan SVE2 optimizations (Phase 3)

**Expected Result:** Should work (has NEON compatibility)

---

### 🔮 Phase 3: SVE/SVE2 Optimizations (FUTURE)

#### 3.1 SVE 256-bit (Graviton 3/3E)
**Priority:** HIGH
**Effort:** 3-4 weeks
**Status:** Not started

**Goal:** Use SVE 256-bit to approach x86 AVX2 performance

**Implementation:**
```cpp
// Current: NEON 128-bit (16 sequences)
int8x16_t score = vmaxq_s8(a, b);

// Target: SVE 256-bit (32 sequences)
svint8_t score = svmax_s8_x(pg, a, b);
```

**Expected Gains:**
- 2x throughput (256-bit vs 128-bit)
- Predicated operations (no movemask overhead)
- Better gather/scatter (indexed memory access)
- **Target:** 2.5-3.0x vs scalar baseline

**Files to Modify:**
- `src/simd/simd_arm_sve.h` (implement SVE intrinsics)
- `src/bandedSWA_arm_neon.cpp` (add SVE variants)
- Runtime detection and dispatch

---

#### 3.2 SVE2 (Graviton 4)
**Priority:** MEDIUM
**Effort:** 2-3 weeks (after SVE done)
**Status:** Not started

**Goal:** Leverage SVE2 enhancements for Graviton 4

**New Features:**
- `MATCH` instruction (vector intersection)
- Enhanced permutes
- Wider predicates
- Better matrix operations

**Expected Gains:**
- Additional 10-20% over SVE (256-bit)
- Close to or match x86 AVX-512 (512-bit)
- **Target:** 3.0-3.5x vs scalar baseline

---

## Build Strategy

### Option 1: Multi-Binary (Recommended)
Build 3 separate binaries with runtime selection:

```makefile
bwa-mem2.graviton2  # -march=armv8.2-a+dotprod -mtune=neoverse-n1
bwa-mem2.graviton3  # -march=armv8.4-a+sve+bf16 -mtune=neoverse-v1
bwa-mem2.graviton4  # -march=armv9-a+sve2 -mtune=neoverse-v2
```

**Pros:**
- Maximum performance per generation
- Clear build targets
- Easy A/B testing

**Cons:**
- Multiple binaries to maintain
- Users must pick correct binary

---

### Option 2: Runtime Dispatch
Single binary with CPU detection:

```cpp
void init_simd() {
    if (has_sve2()) {
        use_sve2_kernels();
    } else if (has_sve()) {
        use_sve_kernels();
    } else {
        use_neon_kernels();
    }
}
```

**Pros:**
- Single binary
- Automatic optimization
- User-friendly

**Cons:**
- More complex
- Larger binary
- Slightly slower startup

---

### Recommended: Hybrid Approach

1. **Build 3 binaries** (graviton2, graviton3, graviton4)
2. **Runtime dispatcher** selects best binary
3. **Fallback** to NEON if newer features unavailable

```bash
./bwa-mem2  # Automatically selects best version
# or
./bwa-mem2.graviton3  # Force specific version
```

---

## Testing Plan

### Immediate Testing (Phase 2)

**Week of Jan 27, 2026:**
1. Run `test-all-graviton.sh` (multi-generation test)
2. Validate Week 2 on Graviton 2, 3E, 4
3. Measure baseline performance across generations
4. Document compatibility matrix

**Expected Results:**
- Graviton 2: ✅ Should work (NEON baseline)
- Graviton 3: ✅ Already working
- Graviton 3E: ✅ Should work (+10-15% faster)
- Graviton 4: ✅ Should work (NEON fallback)

---

### Performance Benchmarking

**Test Dataset:** E. coli K-12 (100K reads, 4 threads)

**Expected Performance:**
| Platform | Time (s) | Speedup | Status |
|----------|----------|---------|--------|
| Graviton 2 (NEON) | ~3.5s | 1.5x | ⏳ Test |
| Graviton 3 (NEON) | **~3.0s** | **1.7x** | ✅ Validated |
| Graviton 3E (NEON) | ~2.6s | 1.9x | ⏳ Test |
| Graviton 4 (NEON) | ~2.5s | 2.0x | ⏳ Test |
| | | | |
| Graviton 3 (SVE 256) | ~1.8s | 2.8x | 🔮 Future |
| Graviton 4 (SVE2 512) | ~1.5s | 3.3x | 🔮 Future |

**Baseline:** ~5s (scalar, no batching)
**x86 AVX2:** ~1.4s (target for parity)

---

## Priority Matrix

### Must Do Now (This Week)
1. ✅ **Graviton 3 validation** - DONE
2. ⏳ **Graviton 2 testing** - HIGH PRIORITY (backward compatibility)
3. ⏳ **Graviton 4 testing** - HIGH PRIORITY (latest generation)
4. ⏳ **Document performance** - Needed for comparisons

### Should Do Soon (Next 2 Weeks)
1. ⏳ **Graviton 3E testing** - Validate enhanced performance
2. ⏳ **Multi-binary build** - Production deployment
3. ⏳ **Performance profiling** - Find hot paths for SVE
4. ⏳ **x86 comparison** - Benchmark against AVX2/AVX-512

### Nice to Have (Next Month)
1. 🔮 **SVE 256-bit implementation** - Major performance gain
2. 🔮 **Runtime dispatch** - User-friendly binary selection
3. 🔮 **SVE2 optimization** - Graviton 4 specific
4. 🔮 **Comprehensive benchmarks** - Full genome datasets

---

## Risk Assessment

### Low Risk (Safe to Proceed)
- ✅ Graviton 2 testing (NEON is baseline, should just work)
- ✅ Graviton 3E testing (same ISA as Graviton 3)
- ✅ Multi-binary build (proven approach)

### Medium Risk (Needs Validation)
- ⚠️  Graviton 4 testing (new ISA, need to verify fallback)
- ⚠️  Performance optimization (may introduce bugs)
- ⚠️  Runtime dispatch (complexity)

### High Risk (Plan Carefully)
- 🔴 SVE implementation (new code, extensive testing needed)
- 🔴 SVE2 implementation (bleeding edge, limited documentation)
- 🔴 Algorithmic changes (could break correctness)

---

## Success Criteria

### Phase 2 Complete:
- [ ] Week 2 works on all Graviton generations (2, 3, 3E, 4)
- [ ] Performance documented for each generation
- [ ] Multi-binary build system working
- [ ] No crashes, no heap corruption
- [ ] Correct output validation

### Phase 3 Complete:
- [ ] SVE 256-bit implementation working
- [ ] 2.5-3.0x speedup vs scalar baseline
- [ ] Within 1.2x of x86 AVX2 performance
- [ ] Graviton 4 SVE2 optimizations
- [ ] Production-ready quality

---

## Commands to Run

### Test All Graviton Generations:
```bash
cd /Users/scttfrdmn/src/bwa-mem2-arm
chmod +x test-all-graviton.sh
./test-all-graviton.sh
```

### Manual Testing on Specific Generation:
```bash
# Launch instance
aws ec2 run-instances --instance-type c6g.xlarge ...  # Graviton 2
aws ec2 run-instances --instance-type c7g.xlarge ...  # Graviton 3
aws ec2 run-instances --instance-type c7gn.xlarge ... # Graviton 3E
aws ec2 run-instances --instance-type c8g.xlarge ...  # Graviton 4

# SSH and test
ssh ec2-user@<IP>
cd bwa-mem2-test
./bwa-mem2.graviton3 mem -t 4 ref.fa reads.fq > output.sam
```

---

## Next Actions

### Today (Jan 27, 2026):
1. Run `test-all-graviton.sh` to validate multi-generation support
2. Document results

### This Week:
1. Fix any compatibility issues found
2. Measure and document performance differences
3. Create multi-binary build system

### Next Week:
1. Begin SVE implementation planning
2. Profile hot paths for optimization
3. Compare with x86 benchmarks

---

## Conclusion

**Current Status:** Week 2 working on Graviton 3
**Next Step:** Test on Graviton 2, 3E, and 4
**Future Goal:** SVE/SVE2 optimization for 2.5-3.5x speedup

The script `test-all-graviton.sh` is ready to run. It will:
- Launch instances for each Graviton generation
- Build with generation-specific compiler flags
- Run identical tests on all platforms
- Report compatibility and performance results

**Estimated Time:** 30-40 minutes
**Estimated Cost:** ~$0.50

---

**Document Version:** 1.0
**Last Updated:** January 27, 2026 03:00 UTC
**Status:** Ready to Execute
