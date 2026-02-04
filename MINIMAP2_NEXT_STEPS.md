# Minimap2 Optimization - Next Steps

## Quick Summary

We've prepared everything needed to benchmark minimap2 ARM optimization. The work from the previous session on Graviton 4 showed that minimap2 is **1.82× faster than BWA-MEM2** (4.84s vs 8.80s), but it was built with suboptimal flags (-O2, no -march).

**Expected improvement**: 5-10% (240-480ms) from using `-O3 -march=armv8.2-a+simd -mtune=generic`

---

## What's Ready

✅ **Comprehensive benchmark script**: `benchmark_minimap2_graviton4.sh`
- Downloads minimap2, generates test data, builds both versions, benchmarks with perf stat
- Fully automated, takes ~15 minutes

✅ **Remote launcher**: `run_minimap2_benchmark.sh`
- Connects to Graviton 4 instance, runs benchmark, downloads results
- Handles SSH, uploads, execution

✅ **Documentation**: `MINIMAP2_OPTIMIZATION_STATUS.md`
- Complete technical details, expected results, cost estimate

---

## To Continue

### Option 1: Quick Execution (Recommended)

```bash
# If you have a running Graviton 4 instance
./run_minimap2_benchmark.sh <instance-id>

# If you need to find instances
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
            "Name=architecture,Values=arm64" \
  --query 'Reservations[].Instances[].[InstanceId,PublicIpAddress]' \
  --output table
```

Results will be in `minimap2_benchmark_results.txt`

### Option 2: Launch New Instance

```bash
# Launch c8g.4xlarge (if you have a launch script)
./launch_graviton4_test.sh

# Then run benchmark
./run_minimap2_benchmark.sh i-<new-instance-id>
```

Cost: ~$0.17 for 15-minute benchmark

### Option 3: Manual Execution

```bash
# 1. SSH to any Graviton 4 instance
ssh ec2-user@<graviton4-ip>

# 2. Upload benchmark script
# (copy benchmark_minimap2_graviton4.sh to instance)

# 3. Run it
./benchmark_minimap2_graviton4.sh
```

---

## Key Insight from Previous Session

You correctly identified:
> "comparing the simple, short read focused bwa against bwa-mem2 or minimap2 is silly. What we are really asking is if there are enhancements to, say minimap2, on Graviton that are worth making to improve its speed."

**Why minimap2 is the right target**:
- Already 1.82× faster than BWA-MEM2
- Modern algorithm (minimizer-based)
- Better threading (89% vs 78%)
- More optimization potential
- Actively maintained

---

## Expected Outcome

### Baseline (current)
```
Time: 4.84s
CPU: 89.3% efficiency
Branch misses: 2.78%
```

### Optimized (expected)
```
Time: 4.4-4.6s (5-10% faster)
CPU: ~89% efficiency
Branch misses: <2.5%
```

**Value**: If we get 5-10% improvement, it's worth sharing with the minimap2 community. Simple Makefile change benefits all ARM users.

---

## Scripts Created

1. **`benchmark_minimap2_graviton4.sh`** - Main benchmark (runs on Graviton 4)
2. **`run_minimap2_benchmark.sh`** - Remote launcher (runs locally)
3. **`MINIMAP2_OPTIMIZATION_STATUS.md`** - Complete documentation
4. **`MINIMAP2_NEXT_STEPS.md`** - This file

All scripts are executable and ready to run.

---

## Context from Previous Sessions

**BWA-MEM2 work** (completed):
- ✅ Fixed horizontal vectorization bugs
- ✅ Profiled and identified bottlenecks (threading overhead 19%, BSW 62%)
- ✅ Attempted threading optimization (failed - 12% slower)
- ✅ Investigated FM-Index optimization (already well-optimized)
- ✅ Documented everything comprehensively

**Key learning**: BWA-MEM2 is constrained by Intel-optimized complexity. Better to focus on modern tools like minimap2.

**minimap2 work** (in progress):
- ✅ Profiled baseline (4.84s, 89% efficiency, but built with -O2)
- ✅ Identified optimization opportunity (better compilation flags)
- ✅ Created comprehensive benchmark infrastructure
- ⏳ **Ready to benchmark optimized build** ← We are here

---

## The Question

**Do ARM-specific compilation flags provide meaningful speedup for minimap2?**

We hypothesize: **Yes, 5-10% improvement** from `-O3 -march=armv8.2-a+simd`

Cost to find out: **15 minutes + $0.17**

**Ready when you are.**
