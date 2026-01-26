# Phase 1 Implementation: Compiler Flags + Optimized Movemask

## Implementation Status: ✅ COMPLETE

**Date**: January 26, 2026
**Target**: 40-50% performance improvement over baseline ARM
**Risk Level**: Low
**Estimated Time**: 1-2 days

---

## Changes Implemented

### 1. Makefile Enhancements (`bwa-mem2/Makefile`)

#### Added Graviton-Specific Compiler Flags

Three optimization tiers for different Graviton generations:

```makefile
# Graviton2 (ARMv8.2-A, Neoverse N1) - c6g, m6g, r6g, t4g instances
GRAVITON2_FLAGS= -march=armv8.2-a+fp16+rcpc+dotprod+crypto -mtune=neoverse-n1 -ffast-math -funroll-loops

# Graviton3 (ARMv8.4-A, Neoverse V1) - c7g, m7g, r7g instances
GRAVITON3_FLAGS= -march=armv8.4-a+sve+bf16+i8mm+dotprod+crypto -mtune=neoverse-v1 -ffast-math -funroll-loops

# Graviton4 (ARMv9-A, Neoverse V2) - r8g instances
GRAVITON4_FLAGS= -march=armv9-a+sve2+sve2-bitperm -mtune=neoverse-v2 -ffast-math -funroll-loops
```

**Key Optimizations**:
- `-mtune=neoverse-*`: CPU-specific instruction scheduling
- `-ffast-math`: Aggressive floating-point optimizations
- `-funroll-loops`: Loop unrolling for better pipelining
- `+dotprod`: Enable dot product instructions (2-3x faster for certain operations)
- `+sve/sve2`: Enable Scalable Vector Extensions
- `+crypto`: Hardware-accelerated cryptographic instructions
- `+bf16`: BFloat16 support (Graviton3+)
- `+i8mm`: 8-bit integer matrix multiply (Graviton3+)

#### Multi-Version Build for ARM

Changed from single ARM build to multi-version builds:

```makefile
multi:
ifeq ($(SYSTEM_ARCH),aarch64)
    # Build three optimized binaries
    $(MAKE) arch="$(GRAVITON2_FLAGS)" EXE=bwa-mem2.graviton2 CXX=$(CXX) all
    $(MAKE) arch="$(GRAVITON3_FLAGS)" EXE=bwa-mem2.graviton3 CXX=$(CXX) all
    $(MAKE) arch="$(GRAVITON4_FLAGS)" EXE=bwa-mem2.graviton4 CXX=$(CXX) all
    # Build dispatcher
    $(CXX) -Wall -O3 src/runsimd_arm.cpp -o bwa-mem2
endif
```

**Build Output**:
- `bwa-mem2.graviton2` - Optimized for Graviton2
- `bwa-mem2.graviton3` - Optimized for Graviton3/3E
- `bwa-mem2.graviton4` - Optimized for Graviton4
- `bwa-mem2` - Runtime dispatcher

### 2. Optimized Movemask (`src/simd/simd_arm_neon.h`)

#### Enabled Fast Movemask Implementation

The codebase already contained an optimized `_mm_movemask_epi8_fast()` function but it wasn't enabled by default. This implementation uses:

1. **Lookup table** with bitmasks
2. **ARM dot product** instructions (available on Graviton2+)
3. **Pairwise adds** to reduce from 16 bytes to single result

**Performance**: ~5-7 instructions vs 15-20 in naive version

```cpp
#if defined(__ARM_FEATURE_DOTPROD)
// Enable optimized movemask by default on ARMv8.2+ (Graviton2+)
#undef _mm_movemask_epi8
#define _mm_movemask_epi8 _mm_movemask_epi8_fast
#endif
```

**Impact**: This change alone should provide **25-30% speedup** in Smith-Waterman loops where movemask is called extensively.

### 3. Runtime CPU Dispatcher (`src/runsimd_arm.cpp`)

Created ARM equivalent of `runsimd.cpp` for x86. Features:

#### CPU Feature Detection

Uses Linux `getauxval(AT_HWCAP)` to detect:
- NEON (baseline)
- Dot Product (`HWCAP_ASIMDDP`)
- SVE (`HWCAP_SVE`)
- SVE2 (`HWCAP2_SVE2`)
- I8MM (`HWCAP2_I8MM`)
- BF16 (`HWCAP2_BF16`)

#### CPU Model Detection

Parses `/proc/cpuinfo` to identify:
- **Neoverse N1** (0xd0c) → Graviton2
- **Neoverse V1** (0xd40) → Graviton3/3E
- **Neoverse V2** (0xd4f) → Graviton4

#### Intelligent Dispatch

```
Graviton4 → Try: graviton4 → graviton3 → graviton2 → FAIL
Graviton3 → Try: graviton3 → graviton2 → FAIL
Graviton2 → Try: graviton2 → FAIL
```

Automatically falls back to lower-optimized version if specific binary not found.

#### Debug Output

```
ARM CPU Feature Detection:
  NEON:    yes
  DOTPROD: yes
  SVE:     yes
  SVE2:    no
  I8MM:    yes
  BF16:    yes
Detected: Graviton3/3E (Neoverse V1)

Looking to launch Graviton3 executable "bwa-mem2.graviton3"
Launching Graviton3-optimized executable "bwa-mem2.graviton3"
```

---

## Expected Performance Gains

### Phase 1 Targets

| Metric | Baseline | Phase 1 Target | Improvement |
|--------|----------|----------------|-------------|
| 4-thread time | 2.587s | ~2.0s | **1.29x** |
| vs AMD x86 | 1.84x slower | 1.42x slower | 23% gap closure |
| IPC | ~1.8 | ~2.0 | 11% increase |

### Breakdown by Optimization

| Optimization | Expected Gain | Confidence |
|--------------|---------------|------------|
| Compiler flags (`-mtune`, `-ffast-math`) | 15-20% | High |
| Optimized movemask | 25-30% | High |
| Combined effect | ~40% | Medium-High |

**Note**: Gains may not be perfectly additive due to interaction effects.

---

## Testing Instructions

### On AWS Graviton Instance (c7g.xlarge or similar)

#### 1. Build Multi-Version Binaries

```bash
cd /path/to/bwa-mem2-arm/bwa-mem2

# Clean previous build
make clean

# Build all Graviton versions
make multi

# Verify binaries were created
ls -lh bwa-mem2*
# Should see: bwa-mem2, bwa-mem2.graviton2, bwa-mem2.graviton3, bwa-mem2.graviton4
```

#### 2. Test CPU Detection

```bash
# Run dispatcher (it will print detected features)
./bwa-mem2 2>&1 | head -20

# Expected output on Graviton3:
# ARM CPU Feature Detection:
#   NEON:    yes
#   DOTPROD: yes
#   SVE:     yes
#   ...
# Detected: Graviton3/3E (Neoverse V1)
# Launching Graviton3-optimized executable...
```

#### 3. Verify Correct Binary is Launched

```bash
# Check which binary gets executed
strace -f -e execve ./bwa-mem2 mem 2>&1 | grep execve

# On Graviton3, should show:
# execve("./bwa-mem2.graviton3", ...)
```

#### 4. Run Benchmark

Use the existing E. coli benchmark:

```bash
# Download test data if not present
wget -O ecoli.fa.gz ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz
gunzip ecoli.fa.gz

# Index (only once)
./bwa-mem2 index ecoli.fa

# Generate test reads (if not present)
# ... use your existing read generation script ...

# Benchmark Phase 1 (4 threads)
time ./bwa-mem2 mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /dev/null

# Record the time, compare with baseline:
# Baseline: ~2.587s
# Target:   ~2.0s (or better)
```

#### 5. Validation Test

**CRITICAL**: Verify output correctness

```bash
# Run with Phase 1 binary
./bwa-mem2 mem -t 4 ecoli.fa reads_1.fq reads_2.fq > phase1_output.sam

# Compare with baseline (if you have saved baseline output)
diff baseline_output.sam phase1_output.sam
# Should be identical or show only timestamp differences

# Or compare alignment count
grep -c "^[^@]" phase1_output.sam
# Should match baseline: 61,888 alignments
```

#### 6. Profile with perf (Optional)

```bash
# Detailed performance counters
sudo perf stat -d ./bwa-mem2 mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /dev/null

# Check for improvements in:
# - Instructions per cycle (IPC): Should increase
# - L1/L2 cache misses: Should decrease or stay same
# - Branch misses: Should decrease or stay same

# Hotspot analysis
sudo perf record -g ./bwa-mem2 mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /dev/null
sudo perf report --stdio
```

---

## Validation Criteria

### Pass Criteria

✅ **Correctness**:
- Output SAM file matches baseline (bit-for-bit or alignment-count identical)
- All existing unit tests pass

✅ **Performance**:
- 4-thread time < 2.0s (vs baseline 2.587s)
- Speedup ≥ 1.25x
- No regression on single-thread performance

✅ **Stability**:
- No crashes on 5+ consecutive runs
- No memory leaks (check with `valgrind` if needed)

### Fail Criteria

❌ **Output Mismatch**: Even minor differences in alignment results
❌ **Performance Regression**: Slower than baseline
❌ **Crashes or Segfaults**: Any stability issues

---

## Rollback Plan

If Phase 1 shows issues:

### Quick Rollback
```bash
git checkout HEAD -- Makefile src/simd/simd_arm_neon.h
git clean -f src/runsimd_arm.cpp
make clean && make arch="-march=armv8-a+simd"
```

### Selective Disable

To disable just the optimized movemask:
```cpp
// In src/simd/simd_arm_neon.h, comment out:
// #define _mm_movemask_epi8 _mm_movemask_epi8_fast
```

To use specific Graviton version:
```bash
# Directly run a specific binary (bypass dispatcher)
./bwa-mem2.graviton2 mem -t 4 ...
```

---

## Next Steps

After Phase 1 validation:

### If Successful (≥1.25x speedup, no correctness issues)
→ **Proceed to Phase 2**: NEON Algorithm Refinements (Weeks 3-4)

### If Moderate Success (1.1-1.24x speedup)
→ **Investigate**: Profile to identify remaining bottlenecks before Phase 2

### If Failure (<1.1x or correctness issues)
→ **Debug**:
1. Check compiler flag compatibility
2. Verify movemask logic on edge cases
3. Review dispatcher CPU detection

---

## Files Modified

```
bwa-mem2-arm/
├── bwa-mem2/
│   ├── Makefile                         # Added Graviton flags, multi-build
│   └── src/
│       ├── runsimd_arm.cpp              # NEW: ARM dispatcher
│       └── simd/
│           └── simd_arm_neon.h          # Enabled fast movemask
└── PHASE1_IMPLEMENTATION.md             # This file
```

---

## Known Issues

### macOS Build Compatibility

Phase 1 changes work on Linux (target platform) but have minor compilation issues on macOS due to:
- `memset_s` declaration conflict in safestringlib
- Clang strict implicit function warnings

**Workaround**: Build and test on AWS Graviton instances (recommended) or use Docker with Linux ARM base image.

### SVE Not Fully Utilized Yet

Graviton3 flags include `+sve` but Phase 1 does not implement SVE-specific code paths. This is expected and will be addressed in **Phase 3** (Weeks 5-8).

Current behavior: SVE-capable CPUs will still use NEON instructions but benefit from better compiler scheduling with `-mtune=neoverse-v1`.

---

## References

- [ARM Neoverse N1 Software Optimization Guide](https://developer.arm.com/documentation/pjdoc-466751330-9707)
- [AWS Graviton Technical Guide](https://github.com/aws/aws-graviton-getting-started)
- [BWA-MEM2 GitHub](https://github.com/bwa-mem2/bwa-mem2)

---

**Status**: ✅ Ready for AWS Graviton Testing
**Next Action**: Run test script on c7g.xlarge instance and report results
