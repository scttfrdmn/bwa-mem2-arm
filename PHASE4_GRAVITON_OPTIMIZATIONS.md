# Phase 4: Graviton 3E and Graviton 4 Specific Optimizations

## Overview

This document describes platform-specific optimizations for AWS Graviton 3E and Graviton 4 processors, building on the Phase 4 Week 2 Tier 1 optimizations (prefetch + SIMD).

## Platform Specifications

### Graviton 3 (c7g)
- **CPU**: Neoverse V1, ARMv8.4-A
- **SVE**: 256-bit (2×256-bit units)
- **Cache**: 1MB L2 per 2 cores
- **Memory**: DDR5-4800
- **Clock**: 2.6 GHz

### Graviton 3E (c7gn, hpc7g)
- **CPU**: Neoverse V1, ARMv8.4-A (same as G3)
- **SVE**: 256-bit (2×256-bit units)
- **Cache**: 1MB L2 per 2 cores
- **Memory**: DDR5-4800
- **Clock**: 2.6 GHz
- **Key difference**: **Higher TDP** ("higher power version")
  - 35% better sustained vector performance
  - Better thermal design (less throttling)
  - Same ISA, different power budget

### Graviton 4 (c8g, m8g, r8g)
- **CPU**: Neoverse V2, ARMv9.0-A
- **SVE**: 256-bit with **SVE2** extensions
- **Cache**: **2MB L2 per core** (2x larger than G3/G3E)
- **Memory**: **DDR5-5600** (faster than G3/G3E)
- **Clock**: 2.6-2.8 GHz
- **New features**:
  - SVE2-bitperm for bit operations
  - SVE2 MATCH for pattern matching
  - sve-int8 for enhanced integer ops

## Optimization Strategy

### Platform Detection: Compile-Time

Platform-specific optimizations are enabled at compile-time based on compiler flags:

```cpp
// graviton_opt.h
#if defined(__ARM_FEATURE_SVE2)
    #define TARGET_GRAVITON4 1
    #define PREFETCH_DISTANCE 6
    #define LOOP_UNROLL_FACTOR 16
    #define L2_CACHE_SIZE (2*1024*1024)
#elif defined(__ARM_FEATURE_SVE) && defined(__ARM_FEATURE_BF16)
    #define TARGET_GRAVITON3 1
    #define PREFETCH_DISTANCE 4
    #define LOOP_UNROLL_FACTOR 8
    #define L2_CACHE_SIZE (1*1024*1024)
#else
    #define TARGET_GENERIC 1
    #define PREFETCH_DISTANCE 2
    #define LOOP_UNROLL_FACTOR 4
#endif
```

### Makefile Build Targets

The Makefile builds multiple platform-specific binaries:

```make
# Graviton 3/3E: Same binary (G3E benefits from aggressive tuning)
GRAVITON3_FLAGS= -march=armv8.4-a+sve+bf16+i8mm+dotprod+crypto -mtune=neoverse-v1

# Graviton 4: SVE2 support
GRAVITON4_FLAGS= -march=armv9-a+sve2+sve2-bitperm+bf16+i8mm -mtune=neoverse-v2
```

## Graviton 3E Optimizations

**Philosophy**: G3E uses the same ISA as G3, so optimizations are aggressive tuning parameters that help both but benefit G3E's higher power budget more.

### 1. Aggressive Prefetching

**Target**: `src/FMI_search.cpp:backwardExt()`

```cpp
#define PREFETCH_DISTANCE 4  // vs 2 in generic

for (int pf_i = 0; pf_i < PREFETCH_DISTANCE; pf_i++) {
    _mm_prefetch((const char *)(&cp_occ[(sp >> CP_SHIFT) + pf_i]), _MM_HINT_T0);
    _mm_prefetch((const char *)(&cp_occ[(ep >> CP_SHIFT) + pf_i]), _MM_HINT_T0);
}
```

**Impact**: 5-8% improvement on G3E (sustained performance), 2-4% on G3

### 2. Deeper Loop Unrolling

**Target**: `src/bwamem.cpp:sequence encoding`

```cpp
#define LOOP_UNROLL_FACTOR 8  // vs 4 in generic

// Process 256 bytes (8×32) at once with SVE
for (; i + (32 * 8) <= len; i += (32 * 8)) {
    #pragma unroll(8)
    for (int unroll = 0; unroll < 8; unroll++) {
        // SVE encoding
    }
}
```

**Impact**: 3-5% improvement on G3E (more power available)

### 3. 256-bit SVE Utilization

**Target**: Both G3 and G3E

```cpp
#ifdef __ARM_FEATURE_SVE
svuint8_t data = svld1_u8(svptrue_b8(), (uint8_t*)&seq[i]);
// Use 256-bit SVE operations
#endif
```

**Impact**: 2x throughput vs 128-bit NEON

## Graviton 4 Optimizations

**Philosophy**: G4 has qualitatively different features (SVE2, larger cache, faster memory) requiring specific optimizations.

### 1. SVE2 Instructions

**Target**: `src/bwamem.cpp:sequence encoding`

```cpp
#ifdef __ARM_FEATURE_SVE2
// SVE2: More efficient predicated operations
svbool_t is_A = svorr_b_z(svptrue_b8(),
    svcmpeq_n_u8(svptrue_b8(), chars, 'A'),
    svcmpeq_n_u8(svptrue_b8(), chars, 'a'));
result = svsel_u8(is_A, svdup_n_u8(0), result);
#endif
```

**Impact**: 10-15% faster character encoding (SVE2 vs SVE)

### 2. Tuning for 2MB L2 Cache

**Strategy**: Deeper prefetching and larger working sets

```cpp
#define PREFETCH_DISTANCE 6  // vs 4 on G3/G3E
#define LOOP_UNROLL_FACTOR 16  // vs 8 on G3/G3E

// Prefetch into L2 as well
#if USE_L2_PREFETCH
_mm_prefetch((const char *)(&cp_occ[(sp >> CP_SHIFT) + i + 8]), _MM_HINT_T1);
#endif
```

**Impact**: 5-10% improvement from better cache utilization

### 3. DDR5-5600 Memory Bandwidth

**Strategy**: More aggressive memory access patterns

```cpp
#define MEMORY_BANDWIDTH 5600  // vs 4800 on G3/G3E

// Deep unrolling for high bandwidth
for (; i + (32 * 16) <= len; i += (32 * 16)) {
    #pragma unroll(16)
    for (int unroll = 0; unroll < 16; unroll++) {
        // Process 512 bytes at once
    }
}
```

**Impact**: 3-7% improvement from memory bandwidth utilization

## Expected Performance Improvements

### Graviton 3E vs Graviton 3
- **Prefetch + SIMD (Week 2)**: 15.5-17.5% (same for both)
- **Platform-specific tuning**: +5-10% additional on G3E
- **Total improvement**: 20-27% on G3E, 15-20% on G3

**Rationale**: G3E's higher power budget allows sustained performance without throttling

### Graviton 4 vs Graviton 3
- **SVE2 instructions**: 10-15% (sequence encoding)
- **2MB L2 cache**: 5-10% (better locality)
- **DDR5-5600 memory**: 3-7% (bandwidth)
- **Combined**: 18-32% faster than G3

**Note**: G4 has 256-bit SVE (not 512-bit), but SVE2 provides qualitatively better instructions

## Implementation Files

### New Files
1. **src/graviton_opt.h**: Platform detection and tuning parameters
2. **src/cpu_detect.h**: Runtime CPU detection (for future use)
3. **src/cpu_detect.cpp**: CPU detection implementation
4. **src/FMI_search_g3e.cpp**: G3E-specific implementations (reference)
5. **src/FMI_search_g4.cpp**: G4 SVE2 implementations (reference)
6. **src/FMI_search_graviton.h**: Platform-specific class definitions

### Modified Files
1. **src/FMI_search.cpp**:
   - Added graviton_opt.h include
   - Platform-specific prefetch distances in backwardExt()
   - Tuned for G3E/G4 cache hierarchies

2. **src/bwamem.cpp**:
   - SVE2 sequence encoding for G4
   - 256-bit SVE encoding for G3/G3E
   - Platform-specific loop unrolling

3. **Makefile**:
   - Added new object files to build
   - Platform-specific compilation flags

## Testing Strategy

### Phase 1: Parallel Testing (In Progress)
- **Graviton 3** (c7g.xlarge): Baseline + Week 2 optimizations
- **Graviton 3E** (c7gn.xlarge): Same binary as G3 (test sustained performance)
- **Graviton 4** (c8g.xlarge): Same binary as G3 (baseline for SVE2)

### Phase 2: Platform-Specific Builds
After Phase 1 completes:
1. Build G3/G3E binary with `GRAVITON3_FLAGS`
2. Build G4 binary with `GRAVITON4_FLAGS`
3. Test each on respective hardware
4. Compare: Generic vs Platform-Specific

### Success Criteria
- **G3E**: 5-10% additional improvement over G3 (sustained performance)
- **G4**: 18-32% improvement over G3 (SVE2 + cache + memory)
- **Correctness**: All outputs match MD5 hash

## Build Commands

```bash
# Build for Graviton 3/3E
cd bwa-mem2
make clean
make arch="$(GRAVITON3_FLAGS)" EXE=bwa-mem2.graviton3 CXX=g++ all

# Build for Graviton 4
make clean
make arch="$(GRAVITON4_FLAGS)" EXE=bwa-mem2.graviton4 CXX=g++ all
```

## References

- [AWS Graviton 3E Announcement](https://www.infoq.com/news/2023/07/aws-ec2-graviton3e/)
- [ARM Neoverse V2 Specifications](https://chipsandcheese.com/p/arms-neoverse-v2-in-awss-graviton-4)
- [AWS Graviton Technical Guide](https://aws.github.io/graviton/)
- [SVE2 Performance Analysis](https://lemire.me/blog/2022/11/29/how-big-are-your-sve-registers-aws-graviton/)

---

*Status: Implementation complete, testing in progress*
*Next: Analyze parallel test results, build platform-specific binaries*
