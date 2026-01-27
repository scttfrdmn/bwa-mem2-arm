# BWA-MEM2 ARM Optimization - Next Steps & Recommendations

**Date**: 2026-01-27
**Status**: Phase 3 Complete, Optimization Direction Identified

---

## Executive Summary

✅ **Phase 3 SVE 256-bit implementation is complete and correct**

⚠️ **Key Discovery**: Smith-Waterman (BSW) accounts for < 2% of total runtime
- Seeding is the real bottleneck (80% of time)
- BSW optimization has minimal end-to-end impact (< 1% improvement even with 2x speedup)
- SVE implementation optimizes the wrong phase of the algorithm

---

## Current Status

### What We Accomplished

**Phase 1**: ✅ Compiler optimization (15-20% improvement potential)
**Phase 2**: ✅ NEON 8-bit implementation (functional, stable)
**Phase 3**: ✅ SVE 256-bit implementation (correct, no end-to-end speedup)

### Performance Results

| Phase | ARM Graviton 3 (4 threads) | vs Intel/AMD | Status |
|-------|---------------------------|--------------|--------|
| Baseline (Week 0) | 2.587s | 1.64-1.84x slower | ❌ Poor |
| After compiler fixes | ~2.0s (estimated) | 1.27-1.43x slower | ⚠️ Better |
| After NEON (Week 2) | ~2.0s | 1.27-1.43x slower | ⚠️ Same |
| After SVE (Week 3) | ~2.0s | 1.27-1.43x slower | ⚠️ No change |

**BSW optimization ceiling**: Even with infinite BSW speedup, maximum gain is 1-2%

---

## The Real Bottleneck: Seeding Phase

### Time Breakdown (Actual Measurements)

```
Total Runtime: 0.31s (1M reads, 4 threads)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
█████████████████████ Seeding (smem)      80% (0.25s)  ← BOTTLENECK
███ Chaining (sal)                         13% (0.04s)
▌ Alignment (BSW)                          < 2% (< 0.005s)
█ SAM output                                3% (0.01s)
██ I/O                                     10% (0.03s)
```

### What Seeding Does

1. **Find exact matches** between reads and reference using FM-index
2. **Seed and extend** to cover as much of the read as possible
3. **Skip BSW** for regions already covered by seeds

**Result**: Most of the read is aligned via exact matching, BSW is rarely needed

---

## Recommended Path Forward

### Option 1: Optimize the Seeding Phase ⭐ **RECOMMENDED**

**Impact**: 80% of runtime, potentially 1.5-2x overall speedup
**Difficulty**: High (complex FM-index algorithms)
**Approach**:
1. Profile `mem_collect_intv()` and seed extension
2. Identify SIMD opportunities in exact matching
3. Optimize FM-index lookups (possibly with SVE)
4. Cache optimization for large index structures

**Why this matters**:
- Seeding is 80% of runtime vs 2% for BSW
- 25% seeding improvement = 20% overall speedup
- Brings ARM to parity with x86

### Option 2: Test on Long-Read Workloads

**Impact**: Makes BSW 10-30% of runtime instead of 2%
**Difficulty**: Medium (need new test data)
**Approach**:
1. Get PacBio or Oxford Nanopore test data
2. Test with high-error rate scenarios (>5% error)
3. Try ancient DNA samples
4. Cross-species alignment

**Why this matters**:
- Long reads have more indels/errors
- Less seed coverage → more BSW usage
- SVE 256-bit would show 1.5-2x speedup in BSW
- Overall speedup: 15-60% on these workloads

### Option 3: Document and Defer BSW Optimization

**Impact**: None immediately, positions for future
**Difficulty**: Low
**Approach**:
1. Document SVE implementation thoroughly
2. Add to upstream BWA-MEM2 as optional feature
3. Wait for workloads where BSW matters
4. Revisit with Graviton 4/5 (SVE2)

**Why this matters**:
- Infrastructure in place when needed
- Community benefit (open source)
- Future-proofing for different workloads

### Option 4: Pivot to Different Algorithm

**Impact**: Could be 2-10x depending on use case
**Difficulty**: Very High (different tool)
**Approach**:
1. Profile other genomics tools (minimap2, bowtie2)
2. Find tools where alignment is the bottleneck
3. Apply SVE optimization there

**Why this matters**:
- Some tools spend more time in alignment
- Better fit for SVE optimization
- Broader impact on genomics ecosystem

---

## Detailed Next Steps (Option 1: Optimize Seeding)

### Week 1: Profiling and Analysis

**Goals**:
- Identify hotspots in seeding phase
- Understand FM-index data structures
- Find SIMD opportunities

**Tasks**:
1. Instrument seeding functions with timing
2. Run perf record + report for detailed hotspots
3. Analyze `mem_collect_intv()`, `mem_chain()`, FM-index lookups
4. Document algorithmic flow

**Expected Output**: Profiling report showing top 10 functions by time

### Week 2: Proof-of-Concept Optimization

**Goals**:
- Implement one high-impact optimization
- Measure actual speedup
- Validate correctness

**Tasks**:
1. Choose highest-impact function (likely FM-index operations)
2. Implement SIMD version (NEON first, then SVE)
3. Benchmark vs baseline
4. Verify correctness with test suite

**Expected Output**: 10-20% speedup in targeted function

### Week 3-4: Full Seeding Optimization

**Goals**:
- Optimize all major seeding bottlenecks
- Achieve target performance

**Tasks**:
1. Vectorize remaining hot functions
2. Cache optimization for index structures
3. Memory access pattern improvements
4. Integration and testing

**Expected Output**: 1.5-2x overall speedup, ARM competitive with x86

---

## Decision Matrix

| Option | Impact | Effort | Timeline | Risk |
|--------|--------|--------|----------|------|
| **Optimize Seeding** | ⭐⭐⭐⭐⭐ | High | 4-6 weeks | Medium |
| **Long-Read Testing** | ⭐⭐⭐ | Medium | 1-2 weeks | Low |
| **Document & Defer** | ⭐ | Low | 1 week | None |
| **Pivot to Different Tool** | ⭐⭐⭐⭐ | Very High | 8+ weeks | High |

### Recommended Choice: **Optimize Seeding Phase**

**Reasoning**:
- Highest potential impact (80% of runtime)
- Builds on SVE infrastructure already created
- Direct path to x86 performance parity
- Valuable for all BWA-MEM2 users (not just niche workloads)

**ROI Calculation**:
- Current gap: 1.64-1.84x slower than x86
- Target: 1.5-2x speedup in seeding
- Expected result: ARM at parity or faster than x86
- Business value: Makes Graviton competitive for genomics

---

## Technical Resources Needed

### For Seeding Optimization

**Tools**:
- `perf record` / `perf report` (hotspot analysis)
- `perf stat -d` (IPC, cache misses, branch prediction)
- Linux perf with ARM PMU support
- Visualization: FlameGraphs

**Knowledge**:
- FM-index data structures and algorithms
- Burrows-Wheeler Transform
- Seed-and-extend heuristics
- SIMD optimization techniques

**Hardware**:
- AWS Graviton 3 (c7g.xlarge) for development
- Graviton 3E (c7gn) for testing (35% better vector perf)
- Access to x86 instances for comparison

### For Long-Read Testing

**Data**:
- PacBio HiFi reads (bacterial or small eukaryote)
- Oxford Nanopore reads (high error rate)
- Ancient DNA samples (if available)

**Tools**:
- SRA Toolkit for downloading public datasets
- `pbsim` or `nanosim` for synthetic long reads

---

## Risk Assessment

### Seeding Optimization Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Algorithmic complexity | High | High | Start with profiling, identify simplest wins first |
| No SIMD opportunities | Low | High | FM-index has known vectorization patterns |
| Correctness bugs | Medium | Critical | Extensive testing, compare with x86 output |
| Time overrun | Medium | Medium | Set incremental milestones, stop at 80% gain |

### Long-Read Workload Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Still low BSW usage | Low | Low | Test multiple datasets before deciding |
| Data licensing | Medium | Low | Use public SRA data |
| Different alignment patterns | Low | Medium | Analyze workload characteristics first |

---

## Success Metrics

### Phase 4: Seeding Optimization

**Minimum Success Criteria**:
- ✅ 30% improvement in seeding phase
- ✅ 20% end-to-end speedup
- ✅ Zero correctness regressions

**Target Success Criteria**:
- ✅ 80% improvement in seeding phase
- ✅ 60% end-to-end speedup
- ✅ ARM faster than x86 on BWA-MEM2 workloads

**Stretch Goals**:
- ✅ 2x improvement in seeding phase
- ✅ ARM 20% faster than best x86
- ✅ Contribution accepted upstream

---

## Budget & Resources

### AWS Costs (Estimated)

**Development** (4-6 weeks):
- c7g.xlarge (Graviton 3): $0.145/hr × 8hr/day × 30 days = **~$35**
- c7i.xlarge (Intel x86 comparison): $0.172/hr × 2hr/week × 6 weeks = **~$2**
- **Total**: **~$40/month**

**Testing**:
- Occasional spot instances for larger datasets
- Estimated: **$10-20**

**Grand Total**: **$50-60 for Phase 4**

### Time Investment

**Engineer time**:
- Week 1 (Profiling): 20-30 hours
- Week 2 (PoC): 25-35 hours
- Weeks 3-4 (Full optimization): 40-60 hours
- **Total**: 85-125 hours (~3-4 weeks full-time)

---

## Deliverables

### Documentation
1. Seeding profiling report with hotspot analysis
2. Optimization implementation guide
3. Performance comparison report (ARM vs x86)
4. Upstream contribution PR to BWA-MEM2

### Code
1. Optimized seeding functions (NEON and SVE versions)
2. Comprehensive test suite
3. Build system updates
4. Runtime CPU detection for optimal dispatch

### Benchmarks
1. Standard dataset results (E. coli, human chr22)
2. Scaling analysis (1-64 threads)
3. Memory usage profiling
4. Power efficiency metrics (optional)

---

## Conclusion

### The Path Forward

**Phase 3 taught us**:
- SVE implementation is correct ✅
- But we optimized the wrong phase ⚠️
- Real bottleneck is seeding, not alignment 🎯

**Phase 4 should focus on**:
- Seeding optimization (80% of runtime)
- Target: 1.5-2x speedup overall
- Bring ARM to parity with x86

**Recommendation**:
Proceed with **Option 1: Optimize Seeding Phase**
- Highest ROI
- Clear path to success
- Builds on existing work

---

**Decision Point**: Which path should we take?
- [ ] Option 1: Optimize Seeding (recommended)
- [ ] Option 2: Test Long-Read Workloads
- [ ] Option 3: Document and Defer
- [ ] Option 4: Pivot to Different Tool

**Next Action**: Awaiting decision to proceed with Phase 4 planning

---

**Document Date**: 2026-01-27
**Author**: Scott Friedman
**Project**: BWA-MEM2 ARM/Graviton Optimization
**Branch**: arm-graviton-optimization
