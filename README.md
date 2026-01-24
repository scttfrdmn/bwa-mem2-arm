# BWA-MEM2 ARM/Graviton Optimization Project

## Mission

Extend BWA-MEM2 with native ARM optimizations targeting AWS Graviton processors (Graviton2, Graviton3, Graviton3E, Graviton4).

## Problem

BWA-MEM2 is heavily optimized for x86 (SSE2, AVX-512) but lacks ARM-specific optimizations. Current ARM builds either:
1. Fail to compile (SSE intrinsics not available)
2. Fall back to generic scalar code (slow)
3. Don't leverage ARM-specific features (NEON, SVE, SVE2)

## Solution

Implement ARM-specific SIMD paths using:
- **NEON** (128-bit): Graviton2, Graviton3, Graviton4 (baseline)
- **SVE** (256-bit): Graviton3E HPC instances (hpc7g)
- **SVE2** (variable): Future Graviton generations

## Target Performance

- **Graviton3 (NEON)**: Match or exceed x86 SSE4.1 performance
- **Graviton3E (SVE)**: Match x86 AVX2 performance
- **Graviton4 (NEON+)**: Approach x86 AVX-512 performance

## Architecture

### Key Files to Modify

1. **src/bandedSWA.cpp**: Banded Smith-Waterman alignment (SSE intrinsics)
2. **src/FMI_search.cpp**: FM-Index search operations
3. **src/kswv.cpp**: KSW alignment kernel
4. **ext/safestringlib/**: Safe string operations

### Strategy

1. Create ARM-specific headers (`arm_neon.h` wrappers)
2. Implement SIMD functions with compile-time arch detection
3. Add SVE paths for Graviton3E
4. Benchmark against x86 and generic ARM builds

## Graviton Processor Generations

### Graviton2 (2020)
- ARM Neoverse N1
- 64 vCPUs per instance
- NEON 128-bit SIMD
- Example: c6g, m6g, r6g instances

### Graviton3 (2022)
- ARM Neoverse V1
- 64 vCPUs per instance
- NEON 128-bit SIMD (enhanced)
- DDR5 memory
- Example: c7g, m7g, r7g instances

### Graviton3E (2022)
- ARM Neoverse V1 + SVE
- 64 vCPUs per instance
- SVE 256-bit SIMD
- HPC-optimized
- Example: hpc7g instances

### Graviton4 (2024)
- ARM Neoverse V2
- 96 vCPUs per instance
- NEON 128-bit (improved)
- 30% faster than Graviton3
- Example: c8g, m8g, r8g instances

## Implementation Plan

### Phase 1: NEON Baseline (Graviton2/3/4)
- [ ] Create ARM SIMD abstraction layer
- [ ] Port SSE2/SSE4.1 operations to NEON
- [ ] Implement banded Smith-Waterman (NEON)
- [ ] Implement FM-Index search (NEON)
- [ ] Benchmark vs scalar code

### Phase 2: Graviton3E SVE Support
- [ ] Add SVE detection at runtime
- [ ] Implement 256-bit SVE paths
- [ ] Benchmark vs NEON and x86 AVX2

### Phase 3: Graviton4 Optimizations
- [ ] Leverage Neoverse V2 improvements
- [ ] Profile and optimize hot paths
- [ ] Compare with x86 AVX-512

### Phase 4: Integration & Testing
- [ ] Clean build system for all ARM variants
- [ ] CI/CD for ARM builds
- [ ] Performance regression tests
- [ ] Submit upstream PR to BWA-MEM2

## Development Environment

### Local (macOS Apple Silicon)
- Test NEON code paths
- Quick iteration on ARM assembly
- Validate cross-compilation

### AWS Graviton Instances
- **c7g.8xlarge**: Graviton3 testing ($1.16/hr)
- **hpc7g.8xlarge**: Graviton3E SVE testing ($1.10/hr)
- **c8g.8xlarge**: Graviton4 testing ($1.24/hr)

## References

- [ARM NEON Intrinsics Reference](https://developer.arm.com/architectures/instruction-sets/intrinsics/)
- [ARM SVE Programming Guide](https://developer.arm.com/documentation/100987/latest/)
- [BWA-MEM2 Architecture](https://github.com/bwa-mem2/bwa-mem2)
- [AWS Graviton Technical Guide](https://github.com/aws/aws-graviton-getting-started)

## Success Metrics

- BWA-MEM2 compiles cleanly on ARM
- NEON performance within 10% of x86 SSE4.1
- SVE performance within 10% of x86 AVX2
- Graviton4 approaches x86 AVX-512 (within 20%)
- Accepted upstream by BWA-MEM2 maintainers

---

**Status**: Project initialized
**Next**: Analyze BWA-MEM2 SSE usage patterns
