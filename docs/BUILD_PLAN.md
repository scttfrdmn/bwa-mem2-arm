# BWA-MEM2 ARM Build Plan

## Immediate Tasks (Week 1)

### 1. Code Audit
- [ ] Grep for all `emmintrin.h`, `smmintrin.h` includes
- [ ] List all SSE intrinsics used
- [ ] Identify hot paths (profiling on x86)
- [ ] Document current build failures on ARM

### 2. Compatibility Layer
```cpp
// arm_compat.h
#ifdef __aarch64__
#include <arm_neon.h>
// Map SSE types to NEON
typedef int8x16_t __m128i_compat;
#define _mm_load_si128(p) vld1q_s8((int8_t*)(p))
// ... etc
#else
#include <emmintrin.h>
typedef __m128i __m128i_compat;
#endif
```

### 3. Minimal Viable Build
- [ ] Get BWA-MEM2 compiling on ARM (stub functions if needed)
- [ ] Run basic alignment test
- [ ] Establish performance baseline (scalar code)

## Short Term (Weeks 2-4)

### 4. NEON Implementation
- [ ] Port Smith-Waterman to NEON
- [ ] Port FM-Index operations
- [ ] Benchmark vs scalar
- [ ] Target: 2-3x speedup over scalar

### 5. Testing
- [ ] Unit tests for SIMD functions
- [ ] Correctness tests (output identical to x86)
- [ ] Performance regression tests

## Medium Term (Weeks 5-8)

### 6. SVE Support (Graviton3E)
- [ ] Add runtime CPU detection
- [ ] Implement 256-bit SVE paths
- [ ] Benchmark vs NEON
- [ ] Target: 1.5-2x speedup over NEON

### 7. Optimization
- [ ] Profile on Graviton3/4
- [ ] Optimize cache usage
- [ ] Tune for specific workloads

## Long Term (Weeks 9-12)

### 8. Integration
- [ ] Clean up build system
- [ ] Add CI/CD for ARM
- [ ] Documentation
- [ ] Upstream PR

### 9. Benchmarking
- [ ] Compare with x86 on identical workloads
- [ ] Test on all Graviton generations
- [ ] Document performance characteristics
