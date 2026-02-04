# Minimap2 ARM Optimization Status

**Date**: 2026-02-03
**Platform**: AWS Graviton 4 (target)
**Goal**: Optimize minimap2 for ARM with better compilation flags

---

## Executive Summary

### ✅ **What We Know**

1. **minimap2 is significantly faster than BWA-MEM2**
   - minimap2: 4.84s (baseline with -O2)
   - BWA-MEM2: 8.80s (ARM-optimized)
   - **Speedup**: 1.82× faster (45% faster)

2. **minimap2 has better threading efficiency**
   - minimap2: 89.3% (14.3 / 16 CPUs)
   - BWA-MEM2: 77.7% (12.4 / 16 CPUs)

3. **minimap2 baseline build is suboptimal**
   - Built with: `-O2` (no architecture-specific flags)
   - Using: sse2neon for SSE→NEON translation
   - Missing: `-O3`, `-march=armv8.2-a+simd`, `-mtune` flags

4. **Expected improvement from better compilation**
   - Conservative: 5-10% (4.4-4.6s)
   - From: Better optimization level (-O3)
   - From: ARM-specific code generation (-march)
   - Potential: Additional 2-5% from native NEON vs sse2neon

---

## Current Status

### ⏳ **Ready to Benchmark**

A comprehensive benchmark script has been prepared to:
1. Download and build minimap2 with baseline flags (-O2)
2. Rebuild minimap2 with optimized ARM flags (-O3 -march=armv8.2-a+simd)
3. Generate test data (chr22 reference + 1M synthetic reads)
4. Benchmark both versions with perf stat
5. Report detailed performance metrics

**Status**: Scripts ready, needs Graviton 4 instance to execute

---

## Files Created

### 1. **`benchmark_minimap2_graviton4.sh`**

Comprehensive benchmark script that runs on Graviton 4. Does everything automatically:
- Installs dependencies
- Downloads minimap2 source
- Generates test data (chr22 + 1M reads)
- Builds baseline version (original flags)
- Builds optimized version (ARM flags)
- Benchmarks both with perf stat
- Reports detailed metrics

**Usage**:
```bash
# On Graviton 4 instance:
./benchmark_minimap2_graviton4.sh
```

**Output**:
- Baseline binary: `~/minimap2-benchmark/minimap2/minimap2.baseline`
- Optimized binary: `~/minimap2-benchmark/minimap2/minimap2.optimized`
- Detailed perf stat output for both versions

**Expected runtime**: 10-15 minutes total

### 2. **`run_minimap2_benchmark.sh`**

Launcher script that connects to a Graviton 4 instance and runs the benchmark remotely.

**Usage**:
```bash
# Option 1: Provide instance ID
./run_minimap2_benchmark.sh i-0123456789abcdef0

# Option 2: Interactive (finds running instances)
./run_minimap2_benchmark.sh
```

**What it does**:
1. Finds or uses specified Graviton 4 instance
2. Tests SSH connection
3. Uploads benchmark script
4. Runs benchmark remotely
5. Downloads results to `minimap2_benchmark_results.txt`

---

## How to Run

### Option A: Launch New Graviton 4 Instance

```bash
# 1. Launch Graviton 4 instance (if you have a launch script)
./launch_graviton4_test.sh

# 2. Run benchmark on the instance
./run_minimap2_benchmark.sh i-<instance-id>

# 3. Results will be in minimap2_benchmark_results.txt
```

### Option B: Use Existing Graviton 4 Instance

```bash
# 1. Find running instances
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
            "Name=architecture,Values=arm64" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,PublicIpAddress]' \
  --output table

# 2. Run benchmark
./run_minimap2_benchmark.sh <instance-id>
```

### Option C: Manual Execution on Graviton 4

```bash
# 1. SSH to Graviton 4 instance
ssh ec2-user@<instance-ip>

# 2. Copy benchmark script
# (upload benchmark_minimap2_graviton4.sh)

# 3. Run it
chmod +x benchmark_minimap2_graviton4.sh
./benchmark_minimap2_graviton4.sh
```

---

## Expected Results

### Performance Comparison

**Baseline** (current suboptimal build):
```
Time: 4.84s
Threading efficiency: 89.3%
Branch miss rate: 2.78%
Cache miss rate: 0.89%
```

**Optimized** (expected with -O3 + ARM flags):
```
Time: 4.4-4.6s (5-10% faster)
Threading efficiency: 89-90% (similar)
Branch miss rate: <2.5% (better branch prediction)
Cache miss rate: <0.8% (better cache utilization)
IPC: improved from better code generation
```

**Improvement**: 240-440 milliseconds (5-10%)

### Key Metrics to Compare

From the perf stat output, compare:

1. **Wall clock time** - Overall runtime
2. **CPU utilization** - Should be similar (~89-90%)
3. **Instructions per cycle (IPC)** - Expect improvement
4. **Branch miss rate** - Expect lower with -O3
5. **Cache miss rate** - Expect lower with better locality

---

## Why This Matters

### minimap2 vs BWA-MEM2

**minimap2** is already 1.82× faster than BWA-MEM2 because:
1. **Modern algorithm** - Minimizer-based seeding (simpler, faster)
2. **Simpler code** - Less complexity, easier to optimize
3. **Better threading** - Higher efficiency (89% vs 78%)
4. **Designed for modern hardware** - Not ported from 2009 codebase

**BWA-MEM2** is slower because:
1. **Complex algorithm** - FM-Index (62% of runtime)
2. **Intel-optimized** - Batching, transpose overhead
3. **Worse threading** - Lower efficiency, atomic overhead
4. **Legacy constraints** - Compatibility with BWA

### The Right Question

The user correctly identified:
> "comparing the simple, short read focused bwa against bwa-mem2 or minimap2 is silly. What we are really asking is if there are enhancements to, say minimap2, on Graviton that are worth making to improve its speed."

**minimap2 is the right target** because:
- Already faster (better algorithm)
- More potential for ARM optimization
- Actively maintained and modern
- Versatile (not just short reads)

---

## Technical Details

### Build Flags Comparison

**Baseline** (current):
```makefile
CFLAGS = -g -Wall -O2 -Wc++-compat
```

**Optimized** (proposed):
```makefile
CFLAGS = -O3 -march=armv8.2-a+simd -mtune=generic \
         -D_FILE_OFFSET_BITS=64 -fsigned-char
```

**Changes**:
- `-O2` → `-O3`: More aggressive optimization
- Added `-march=armv8.2-a+simd`: Generate ARMv8.2 + SIMD code
- Added `-mtune=generic`: Tune for generic ARM (safe default)
- Keep `-D_FILE_OFFSET_BITS=64 -fsigned-char`: Required for minimap2

### Why Not `-mtune=neoverse-v2`?

- GCC 11.5.0 doesn't support it (would need GCC 13+)
- `-mtune=generic` is safe and still benefits from `-march=armv8.2-a+simd`
- Could be future enhancement with newer compiler

### sse2neon Translation

minimap2 uses SSE intrinsics (designed for x86) with sse2neon header to translate to NEON on ARM:
- `ksw2_extz2_sse.c` - Extension alignment with SSE
- `ksw2_extd2_sse.c` - Dual extension alignment
- `ksw2_exts2_sse.c` - Single extension alignment

**Current**: sse2neon with -O2 (suboptimal code generation)
**Optimized**: sse2neon with -O3 + -march (better vectorization)
**Future**: Could write native NEON versions (additional 2-5% gain)

---

## Profiling Results (Baseline)

**From previous session**:

```
Performance counter stats for './minimap2 -t 16 -ax sr chr22.mmi chr22_reads_1M.fq':

          4.837 seconds time elapsed
         68.961 seconds user
          0.412 seconds sys

 14.29 CPUs utilized            (89.3% efficiency)
  3.47 instructions per cycle
  2.78% branch miss rate         (higher than BWA-MEM2's 0.99%)
  0.89% L1 cache miss rate       (higher than BWA-MEM2's 0.31%)
```

**Analysis**:
- Good threading efficiency (89.3%)
- Room for improvement in branch prediction
- Room for improvement in cache utilization
- Better compilation flags should help both

---

## Next Steps

### Immediate (Ready to Execute)

1. **Launch or connect to Graviton 4 instance**
   - c8g.4xlarge or r8g.xlarge recommended
   - Needs ~8 GB RAM for test data

2. **Run benchmark script**
   ```bash
   ./run_minimap2_benchmark.sh <instance-id>
   ```

3. **Analyze results**
   - Compare wall clock time
   - Check IPC improvement
   - Verify branch/cache miss reduction

### If Results Are Positive (5-10% gain)

1. **Document findings**
   - Quantify exact improvement
   - Show compilation flags matter
   - Demonstrate ARM optimization value

2. **Consider additional optimizations**
   - Branch hints in hot paths (2-3% potential)
   - Native NEON vs sse2neon (2-5% potential)
   - Compiler upgrade to GCC 13+ (1-2% potential)
   - Profile-guided optimization (1-3% potential)

3. **Share with minimap2 project**
   - ARM-specific Makefile flags
   - Benchmarks showing improvement
   - Help other ARM users

### If Results Are Minimal (<3% gain)

1. **Document that compilation flags already good enough**
2. **Focus on algorithmic improvements instead**
3. **Accept that minimap2 is already well-optimized**

---

## Cost Estimate

**Graviton 4 Instance** (c8g.4xlarge):
- On-demand: ~$0.69/hour
- Benchmark runtime: ~15 minutes
- **Cost per benchmark run**: ~$0.17

**One-time cost** for comprehensive testing:
- Initial benchmark: $0.17
- Validation runs (3×): $0.51
- **Total**: ~$0.70

**Very affordable** to get definitive answer on optimization value.

---

## Success Criteria

### Minimum Success (5% improvement)

```
Baseline:  4.84s
Optimized: 4.60s or faster
Gain:      ≥240ms (5% improvement)
```

**Value**: Demonstrates that proper compilation flags matter for ARM

### Target Success (7-8% improvement)

```
Baseline:  4.84s
Optimized: 4.45-4.50s
Gain:      340-390ms (7-8% improvement)
```

**Value**: Significant enough to recommend to minimap2 users

### Stretch Success (10% improvement)

```
Baseline:  4.84s
Optimized: 4.36s or faster
Gain:      ≥480ms (10% improvement)
```

**Value**: Worth contributing back to minimap2 project

---

## Conclusion

**We have**:
- ✅ Comprehensive benchmark scripts ready
- ✅ Clear hypothesis (5-10% improvement from better flags)
- ✅ Evidence-based approach (profiling shows room for improvement)
- ✅ Low cost to validate (~$0.70)

**We need**:
- ⏳ Access to Graviton 4 instance (or launch one)
- ⏳ 15 minutes to run benchmark
- ⏳ Analyze results and document findings

**Recommendation**:
Run the benchmark to get definitive answer. The investment is minimal (~15 minutes, ~$0.70) and the potential value is high (5-10% speedup for all minimap2 ARM users).

**Key insight**: Unlike BWA-MEM2 (complex, Intel-optimized, legacy constraints), minimap2 is modern, simple, and a better optimization target. The user was right to reframe the question.

---

## Files

- `benchmark_minimap2_graviton4.sh` - Main benchmark script (runs on Graviton 4)
- `run_minimap2_benchmark.sh` - Launcher script (runs locally, executes remotely)
- `MINIMAP2_OPTIMIZATION_STATUS.md` - This document

**Ready to execute**. Just need Graviton 4 instance access.
