# Phase 4: Seeding Phase Analysis & Optimization Plan

**Date**: 2026-01-27
**Status**: Week 1 - Analysis Phase
**Target**: Seeding phase (80% of runtime)

---

## Executive Summary

Based on profiling data showing **seeding accounts for 80% of runtime**, Phase 4 focuses on optimizing the seed-and-extend algorithm. This document provides:
1. Analysis of seeding phase components
2. Identified optimization opportunities
3. Concrete implementation plan
4. Expected performance improvements

---

## Seeding Phase Architecture

### BWA-MEM2 Seeding Algorithm

```
For each read (150bp):
├─ 1. Split into k-mers (seeds)
├─ 2. Find exact matches using FM-index (backward search)
├─ 3. Extend seeds bidirectionally (SMEM)
├─ 4. Chain seeds into larger alignments
└─ 5. Fill gaps with Smith-Waterman (BSW) ← Only 2% of time
```

### Time Breakdown (From Profiling)

```
Total Seeding: 0.25s (80% of 0.31s total)
├─ FM-Index Lookups: ~0.15s (60%)  ← PRIMARY BOTTLENECK
├─ Seed Extension (SMEM): ~0.06s (24%)
├─ Seed Chaining: ~0.04s (16%)
└─ Other: < 0.01s
```

---

## Critical Functions (Expected Hotspots)

### 1. FM-Index Operations (~60% of seeding time)

**Primary Hotspot**: `bwt_extend()` and `bwt_smem1()`
- **What they do**: Backward search in FM-index to find exact matches
- **Why they're slow**: Many random memory accesses to large index structure
- **File**: `src/FMI_search.cpp`

**Characteristics**:
- Cache-unfriendly (large index ~1-4GB for E. coli/human)
- Many branches (character comparisons)
- Serial dependencies (each step depends on previous)

**Optimization Opportunities**:
```cpp
// Current (pseudocode):
for each character in seed:
    k = forward_search(c, k, l)  // Random memory access
    if (k > l) break  // Branch

// Opportunity: SIMD-ize multiple lookups, prefetch
```

### 2. Seed Extension (SMEM) (~24% of seeding time)

**Function**: `mem_collect_intv()` and `bwt_smem1()`
- **What they do**: Extend seeds bidirectionally to find maximal exact matches
- **Why they're slow**: Iterative FM-index queries
- **File**: `src/bwamem.cpp`

**Characteristics**:
- Recursive/iterative (hard to vectorize)
- Many short exact matches
- Cache pressure from index lookups

**Optimization Opportunities**:
```cpp
// Current: Serial extension
while (can_extend) {
    extend_forward();
    extend_backward();
}

// Opportunity: Batch multiple extensions, cache optimization
```

### 3. Seed Chaining (~16% of seeding time)

**Function**: `mem_chain_seeds()`
- **What they do**: Connect compatible seeds into chains using dynamic programming
- **Why they're slow**: O(n²) comparison of seed positions
- **File**: `src/bwamem.cpp:808`

**Characteristics**:
- Dynamic programming (sequential dependencies)
- Many comparisons
- Sorting operations

**Optimization Opportunities**:
```cpp
// Current: Compare all seed pairs
for (i = 0; i < n; i++)
    for (j = i+1; j < n; j++)
        if (compatible(seeds[i], seeds[j]))
            score = dp[i] + gap_penalty

// Opportunity: SIMD comparisons, better algorithms
```

---

## Optimization Strategy

### Tier 1: FM-Index Optimizations (Highest Impact)

#### 1.1 Prefetch Optimization
**Impact**: 20-30% improvement in FM-index lookups
**Difficulty**: Medium
**Timeline**: 1 week

**Approach**:
```cpp
// Add software prefetching
__builtin_prefetch(&index[next_pos], 0, 3);  // Temporal locality

// Batch lookups to improve prefetch efficiency
for (int i = 0; i < batch_size; i++) {
    __builtin_prefetch(&index[positions[i+4]], 0, 3);
    results[i] = lookup(positions[i]);
}
```

**Files to modify**:
- `src/FMI_search.cpp` - Add prefetch hints
- `src/bwt.h` - Update lookup functions

#### 1.2 Cache-Aware Index Layout
**Impact**: 15-25% improvement
**Difficulty**: High
**Timeline**: 2 weeks

**Approach**:
- Reorganize FM-index data structure for better cache locality
- Use blocked/tiled layout instead of row-major
- Group frequently co-accessed data

**Trade-off**: Requires index format changes (one-time rebuild)

#### 1.3 SIMD Character Comparisons
**Impact**: 10-15% improvement
**Difficulty**: Medium
**Timeline**: 1 week

**Approach**:
```cpp
// Current: Scalar comparison
if (query[i] == 'A') pos = count_A[pos];
else if (query[i] == 'C') pos = count_C[pos];
...

// Optimized: NEON/SVE lookup table
uint8x16_t chars = vld1q_u8(query);
uint8x16_t lut = {/* A,C,G,T mappings */};
uint8x16_t indices = vqtbl1q_u8(lut, chars);  // Parallel lookup
```

**Files to modify**:
- `src/FMI_search.cpp` - Vectorize character tests
- `src/simd/simd_arm_neon.h` - Add lookup primitives

### Tier 2: Algorithm Improvements (Medium Impact)

#### 2.1 Batch Seed Processing
**Impact**: 15-20% improvement
**Difficulty**: Medium
**Timeline**: 1-2 weeks

**Approach**:
- Process multiple seeds from same read in parallel
- Reduces index access overhead
- Better cache reuse

```cpp
// Current: Process seeds one at a time
for each seed:
    result = fm_index_search(seed)

// Optimized: Batch multiple seeds
seeds_batch[32] = collect_seeds(read)
results[32] = fm_index_search_batch(seeds_batch)  // SIMD/parallel
```

#### 2.2 Smarter Seed Selection
**Impact**: 10-15% improvement (fewer FM lookups)
**Difficulty**: Medium
**Timeline**: 1 week

**Approach**:
- Filter out repetitive seeds before FM-index lookup
- Use minimizers or other sampling strategies
- Reduce total number of index queries

### Tier 3: Low-Level Optimizations (Incremental)

#### 3.1 Branch Prediction Hints
**Impact**: 5-10% improvement
**Difficulty**: Low
**Timeline**: 2-3 days

```cpp
// Add __builtin_expect hints for hot branches
if (__builtin_expect(k > l, 0)) {  // Rare case
    break;
}
```

#### 3.2 Loop Unrolling
**Impact**: 3-5% improvement
**Difficulty**: Low
**Timeline**: 2-3 days

```cpp
// Unroll small fixed-length loops
#pragma GCC unroll 4
for (int i = 0; i < seed_len; i++) {
    ...
}
```

#### 3.3 Function Inlining
**Impact**: 3-7% improvement
**Difficulty**: Low
**Timeline**: 1-2 days

```cpp
// Force inline hot small functions
__attribute__((always_inline))
inline uint64_t get_sa(uint64_t pos) {
    return index->sa[pos];
}
```

---

## Implementation Roadmap

### Week 1: Analysis & Preparation ✅ (Current)
- [x] Profile seeding phase
- [x] Identify hotspot functions
- [x] Analyze optimization opportunities
- [ ] Instrument code with detailed timing
- [ ] Create baseline performance metrics

### Week 2: Tier 1 Optimizations (Prefetch + SIMD)
**Day 1-2**: Prefetch optimization
- Add software prefetch to FM-index lookups
- Test impact on lookup latency
- Target: 20-25% improvement in FM operations

**Day 3-4**: SIMD character comparisons
- Implement NEON lookup tables
- Vectorize character tests in FM-index
- Target: 10-15% additional improvement

**Day 5**: Integration and testing
- Combine optimizations
- Run correctness tests
- Measure cumulative speedup

**Expected Result**: 30-40% improvement in seeding phase = 24-32% overall speedup

### Week 3: Tier 2 Optimizations (Algorithms)
**Day 1-3**: Batch seed processing
- Refactor to process multiple seeds together
- Implement parallel FM-index lookups
- Target: 15-20% additional improvement

**Day 4-5**: Smarter seed selection
- Implement minimizer-based filtering
- Reduce redundant FM lookups
- Target: 10-15% additional improvement

**Expected Result**: 50-60% cumulative improvement in seeding = 40-48% overall speedup

### Week 4: Polish & Integration
**Day 1-2**: Tier 3 optimizations
- Branch hints, inlining, unrolling
- Target: 5-10% additional improvement

**Day 3-4**: Full integration testing
- Correctness validation (vs x86 baseline)
- Performance benchmarking
- Thread scaling tests

**Day 5**: Documentation and upstream preparation
- Code cleanup
- Performance report
- Prepare upstream PR

**Final Target**: 60-80% improvement in seeding = 48-64% overall speedup

---

## Expected Performance Impact

### Conservative Estimate

| Optimization | Seeding Improvement | Overall Improvement |
|--------------|-------------------|---------------------|
| **Baseline** | 0% | 0% (2.0s ARM vs 1.4s AMD) |
| Tier 1 (Prefetch + SIMD) | +35% | +28% (2.0s → 1.56s) |
| Tier 2 (Algorithms) | +25% more | +20% more (1.56s → 1.25s) |
| Tier 3 (Polish) | +8% more | +6% more (1.25s → 1.18s) |
| **Total** | **+68%** | **+54%** (2.0s → 1.18s) |

**Result**: ARM within 15% of AMD (1.18s vs 1.00s) - **Competitive!**

### Optimistic Estimate

| Optimization | Seeding Improvement | Overall Improvement |
|--------------|-------------------|---------------------|
| **Baseline** | 0% | 0% |
| Tier 1 + Cache Layout | +50% | +40% (2.0s → 1.20s) |
| Tier 2 | +30% more | +24% more (1.20s → 0.91s) |
| Tier 3 | +10% more | +8% more (0.91s → 0.84s) |
| **Total** | **+90%** | **+72%** (2.0s → 0.84s) |

**Result**: ARM **faster** than AMD (0.84s vs 1.00s) - **Best-in-class!**

---

## Risk Assessment

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Correctness bugs | Medium | Critical | Extensive testing vs x86 golden output |
| Limited SIMD benefit | Low | High | Profile each optimization independently |
| Index format incompatibility | Low | Medium | Maintain backward compatibility option |
| Cache thrashing | Medium | Medium | Careful buffer sizing, profiling |

### Schedule Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Complex algorithms | High | High | Start simple (prefetch), add complexity gradually |
| Integration issues | Medium | Medium | Incremental integration, frequent testing |
| Hardware access | Low | High | Use c7g.xlarge spot instances (<$0.10/hr) |

---

## Validation Plan

### Correctness Testing

**Test Suite**:
1. **Unit tests**: Each optimization against reference implementation
2. **Integration tests**: E. coli (4.6MB), Human chr22 (51MB)
3. **Golden reference**: Compare vs x86 Intel AVX-512 output
4. **Edge cases**: Short reads, long reads, high error rates

**Pass Criteria**: Bitwise identical SAM output

### Performance Testing

**Benchmarks**:
1. **Micro**: Individual function timing (FM-index, SMEM, chaining)
2. **Component**: Seeding phase timing
3. **End-to-end**: Full alignment pipeline
4. **Scaling**: 1, 2, 4, 8, 16 threads

**Metrics**:
- Wall clock time
- IPC (instructions per cycle)
- Cache miss rate
- Branch miss rate
- Memory bandwidth utilization

---

## Success Criteria

### Minimum Success
- ✅ 30% improvement in seeding phase
- ✅ 25% end-to-end speedup
- ✅ Zero correctness regressions
- ✅ ARM within 30% of x86

### Target Success
- ✅ 60% improvement in seeding phase
- ✅ 48% end-to-end speedup
- ✅ ARM within 15% of x86
- ✅ Code accepted upstream

### Stretch Goals
- ✅ 80% improvement in seeding phase
- ✅ 64% end-to-end speedup
- ✅ ARM faster than x86
- ✅ Published performance paper

---

## Next Actions

### Immediate (This Week)
1. [ ] Add detailed timing instrumentation to seeding functions
2. [ ] Create baseline performance numbers (current state)
3. [ ] Set up automated testing pipeline
4. [ ] Begin Tier 1.1 (prefetch) implementation

### Week 2
1. [ ] Complete and test prefetch optimization
2. [ ] Implement SIMD character comparisons
3. [ ] Measure cumulative improvement
4. [ ] Prepare for Tier 2 work

---

## Resources Needed

### Development Environment
- AWS c7g.xlarge (Graviton 3): ~$0.145/hr × 160hr = **$23**
- AWS c7i.xlarge (Intel comparison): ~$0.172/hr × 20hr = **$3**
- AWS c7a.xlarge (AMD comparison): ~$0.173/hr × 20hr = **$3**
- **Total AWS**: ~$30 for 4 weeks

### Tools
- perf (Linux profiling) - ✅ Available
- gdb (debugging) - ✅ Available
- FlameGraphs (visualization) - ✅ Available
- Compiler: GCC 14 with SVE - ✅ Available

### Knowledge
- FM-index algorithms - Documentation available
- ARM NEON/SVE programming - ✅ Have expertise from Phase 3
- BWA-MEM2 codebase - ✅ Familiar

---

## Conclusion

Phase 4 focuses on the **real bottleneck** (seeding, 80% of runtime) with a clear path to:
- 48-64% end-to-end speedup (target range)
- ARM competitive with or faster than x86
- Validated correctness
- Upstreamable code

**Status**: Ready to proceed with implementation
**Next**: Begin Week 2 - Tier 1 optimizations (prefetch + SIMD)

---

**Document Date**: 2026-01-27
**Author**: Scott Friedman
**Phase**: 4 - Seeding Optimization
**Task #1 Status**: Analysis Complete → Moving to Implementation
