# What's Next: BWA-MEM2 ARM Development Roadmap

**Status**: Phase 1 Complete (Week 1) ✅
**Next**: Phase 2 - Validation & Benchmarking (Weeks 2-4)

---

## 🎯 Immediate Priorities (Next 1-2 Weeks)

### 1. **Correctness Validation** 🔴 CRITICAL
Test that ARM binary produces identical results to x86.

**Tasks:**
```bash
# Download test dataset
wget ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/technical/reference/phase2_reference_assembly_sequence/hs37d5.fa.gz
gunzip hs37d5.fa.gz

# Download sample reads (small test)
wget https://github.com/lh3/bwa/raw/master/test/bwa-mem_test1.fq
wget https://github.com/lh3/bwa/raw/master/test/bwa-mem_test2.fq

# Test on M4 Pro
./bwa-mem2 index hs37d5.fa
./bwa-mem2 mem hs37d5.fa bwa-mem_test1.fq bwa-mem_test2.fq > output_arm.sam

# Compare with x86 reference (if available)
diff output_x86.sam output_arm.sam
# Or validate with samtools
samtools quickcheck output_arm.sam
samtools flagstat output_arm.sam
```

**Success Criteria:**
- ✅ SAM output passes samtools validation
- ✅ Alignment scores match expected values
- ✅ No segfaults or crashes on real data
- ✅ Memory usage reasonable

---

### 2. **Performance Profiling on M4** 📊
Identify bottlenecks and optimization opportunities.

**Tasks:**
```bash
# Profile with Instruments
instruments -t "Time Profiler" ./bwa-mem2 mem hs37d5.fa reads1.fq reads2.fq > /dev/null

# Or use built-in profiling
./bwa-mem2 mem -t 4 hs37d5.fa reads1.fq reads2.fq > output.sam 2>&1 | grep -E "Time|ticks"

# Check CPU features being used
# Add SIMD_DEBUG flag and recompile:
make arch=native CXX=clang++ CPPFLAGS="-DSIMD_DEBUG" clean all
./bwa-mem2 mem ... # Will print "BWA-MEM2 SIMD Implementation: ARM NEON"
```

**Analyze:**
- Where is the code spending most time?
- Is `_mm_movemask_epi8` a bottleneck? (Expected)
- Are prefetch hints effective on M4?
- Cache miss rates?

**Optimization Ideas:**
- Implement faster `_mm_movemask_epi8` using M4's DotProd feature
- Tune prefetch distances for M4's cache hierarchy
- Consider using `vld1q_dup` for broadcast operations

---

### 3. **AWS Graviton2 Testing** ☁️
Validate on real Graviton hardware.

**Launch Instance:**
```bash
# Graviton2 (baseline, cheapest)
aws ec2 run-instances \
  --profile aws \
  --instance-type c6g.xlarge \
  --image-id ami-0c55b159cbfafe1f0 \  # Amazon Linux 2023 ARM
  --key-name YOUR_KEY \
  --security-group-ids sg-xxx \
  --subnet-id subnet-xxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-arm-test}]'

# Get instance IP
aws ec2 describe-instances \
  --profile aws \
  --filters "Name=tag:Name,Values=bwa-mem2-arm-test" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

**Deploy & Test:**
```bash
ssh ec2-user@<instance-ip>

# Install dependencies
sudo yum update -y
sudo yum install -y gcc-c++ git make zlib-devel

# Clone and build
git clone https://github.com/scttfrdmn/bwa-mem2-arm.git
cd bwa-mem2-arm/bwa-mem2
git checkout arm-graviton-optimization
make arch=native CXX=g++ clean all

# Verify CPU features
cat /proc/cpuinfo | grep Features
# Expected on Graviton2: fp asimd evtstrm aes pmull sha1 sha2 crc32 atomics

# Run test
./bwa-mem2 version
./bwa-mem2 mem -t 4 reference.fa reads1.fq reads2.fq > output.sam
```

**Benchmark:**
```bash
# Time the alignment
time ./bwa-mem2 mem -t 4 hs37d5.fa reads1.fq reads2.fq > output.sam

# Compare with original x86 timing
# Record: reads/second, CPU time, memory usage
```

---

### 4. **Create Benchmark Suite** 📈

**Script: `benchmark.sh`**
```bash
#!/bin/bash
# benchmark.sh - BWA-MEM2 performance testing

REF=$1
READS1=$2
READS2=$3
THREADS=${4:-4}

echo "=== BWA-MEM2 ARM Benchmark ==="
echo "Platform: $(uname -m)"
echo "CPU: $(sysctl -n machdep.cpu.brand_string 2>/dev/null || cat /proc/cpuinfo | grep 'model name' | head -1)"
echo "Threads: $THREADS"
echo

# Index benchmark
echo "Indexing..."
/usr/bin/time -v ./bwa-mem2 index $REF 2>&1 | grep -E "Elapsed|Maximum resident"

# Alignment benchmark
echo "Aligning..."
/usr/bin/time -v ./bwa-mem2 mem -t $THREADS $REF $READS1 $READS2 > /dev/null 2>&1 | grep -E "Elapsed|Maximum resident|CPU"

# Parse internal profiling
./bwa-mem2 mem -t $THREADS $REF $READS1 $READS2 > /dev/null 2>&1 | grep "Total time"
```

**Track Metrics:**
- Total runtime (seconds)
- CPU utilization (%)
- Memory usage (GB)
- Reads/second throughput
- Index build time

---

## 📅 Phase 2: Weeks 2-4

### Week 2: Optimization Round 1
- [ ] Optimize `_mm_movemask_epi8` for ARM
- [ ] Implement DotProd-accelerated operations (M4, Graviton3+)
- [ ] Profile cache behavior and tune prefetching
- [ ] Test on Graviton3 (c7g instances)

### Week 3: Graviton3 & Graviton4 Testing
- [ ] Deploy to Graviton3 (c7g.xlarge)
- [ ] Deploy to Graviton4 (c8g.xlarge)
- [ ] Run comprehensive benchmarks
- [ ] Document performance vs x86

### Week 4: Correctness & Edge Cases
- [ ] Test with various read lengths (50bp, 100bp, 150bp, 250bp)
- [ ] Test paired-end and single-end reads
- [ ] Stress test with large genomes (human, plant)
- [ ] Memory leak testing (valgrind on Linux)

---

## 📅 Phase 3: Weeks 5-8 (SVE Support)

### Graviton3E SVE Implementation
**Goal**: Match x86 AVX2 performance with 256-bit vectors

**Prerequisites:**
- Access to hpc7g instances (AWS HPC Graviton3E)
- SVE compiler support (GCC 10+ or Clang 12+)

**Tasks:**
1. Implement `simd_arm_sve.h` with 256-bit operations:
   - `svld1_u8()` - Gather loads
   - `svmax_u8_x()` - Max operations
   - `svsel()` - Blend/select
   - Predicated operations

2. Benchmark on hpc7g:
   ```bash
   # Launch Graviton3E HPC instance
   aws ec2 run-instances \
     --instance-type hpc7g.4xlarge \
     --placement GroupName=my-placement-group
   ```

3. Compare performance:
   - Graviton3 NEON vs Graviton3E SVE
   - Graviton3E SVE vs x86 AVX2

**Expected Results:**
- 1.5-2x speedup over NEON on same data
- Within 10% of x86 AVX2 performance

---

## 📅 Phase 4: Weeks 9-12 (Upstream Contribution)

### Prepare for Upstream PR

**Code Quality:**
- [ ] Clean up all debug code
- [ ] Add comprehensive comments
- [ ] Ensure code style matches BWA-MEM2
- [ ] Fix all compiler warnings
- [ ] Add ARM-specific documentation

**Testing:**
- [ ] Create automated test suite
- [ ] CI/CD for ARM builds (GitHub Actions with ARM runners)
- [ ] Performance regression tests
- [ ] Multi-platform validation (Linux, macOS)

**Documentation:**
- [ ] Technical writeup of implementation
- [ ] Performance comparison report
- [ ] Build instructions for all platforms
- [ ] Troubleshooting guide

**Submission:**
```bash
# Create clean branch for upstream
cd bwa-mem2
git checkout -b upstream-arm-support
git rebase -i master  # Clean up commits
git push scttfrdmn upstream-arm-support

# Create PR to upstream
gh pr create \
  --repo bwa-mem2/bwa-mem2 \
  --base master \
  --head scttfrdmn:upstream-arm-support \
  --title "Add ARM/Graviton SIMD support with NEON and SVE implementations" \
  --body-file PR_DESCRIPTION.md
```

---

## 🎯 Success Metrics

### Performance Targets
- [x] ✅ Compiles on ARM (DONE!)
- [ ] NEON performance: ≥90% of x86 SSE4.1
- [ ] SVE performance: ≥90% of x86 AVX2
- [ ] Graviton4: Approach x86 AVX-512 (≥80%)
- [ ] No memory leaks or crashes
- [ ] Bit-identical output to x86

### Community Goals
- [ ] Accepted by upstream BWA-MEM2 maintainers
- [ ] Documented in official BWA-MEM2 README
- [ ] Available in BioConda for ARM
- [ ] Adopted by genomics community

---

## 🛠️ Development Tools

### Profiling
```bash
# macOS
instruments -t "Time Profiler" ./bwa-mem2 mem ...
instruments -t "Allocations" ./bwa-mem2 mem ...

# Linux (Graviton)
perf record -g ./bwa-mem2 mem ...
perf report

# Valgrind (memory leaks)
valgrind --leak-check=full --show-leak-kinds=all ./bwa-mem2 mem ...
```

### Debugging
```bash
# Enable debug symbols
make arch=native CXX=g++ CXXFLAGS="-g -O0" clean all

# Run with gdb
gdb --args ./bwa-mem2 mem reference.fa reads.fq
```

### ARM Feature Detection
```bash
# macOS
sysctl hw.optional.arm.FEAT_DotProd
sysctl hw.optional.arm.FEAT_FP16

# Linux
cat /proc/cpuinfo | grep Features
getconf LEVEL1_DCACHE_SIZE  # L1 cache
```

---

## 📚 Resources

### ARM Documentation
- [ARM NEON Intrinsics](https://developer.arm.com/architectures/instruction-sets/intrinsics/)
- [ARM SVE Programming Guide](https://developer.arm.com/documentation/100987/latest/)
- [Neoverse N1 Optimization Guide](https://developer.arm.com/documentation/pjdoc466751330-9707/latest/)

### AWS Graviton
- [Graviton Performance Runbook](https://github.com/aws/aws-graviton-getting-started)
- [Graviton3 Features](https://aws.amazon.com/ec2/graviton/)
- [HPC on Graviton](https://aws.amazon.com/hpc/)

### BWA-MEM2
- [Original Paper (IPDPS 2019)](https://doi.org/10.1109/IPDPS.2019.00041)
- [GitHub Issues](https://github.com/bwa-mem2/bwa-mem2/issues)

---

## 🐛 Known Issues to Address

1. **`_mm_movemask_epi8` Performance**
   - Current: ~6 NEON instructions
   - Impact: ~15-20% overhead in hot paths
   - Solution: Optimize with lookup tables or DotProd

2. **Prefetch Tuning**
   - Current: Using x86 distances
   - Impact: May not be optimal for ARM cache
   - Solution: Profile and adjust HINT levels

3. **Submodule Changes**
   - safestringlib has local modifications
   - Need to either upstream or maintain fork
   - Currently: Local patches in ext/safestringlib

---

## 💡 Quick Wins

### Easy Optimizations (1-2 days each)
1. **Add `-flto` (Link-Time Optimization)**
   ```bash
   make arch=native CXX=clang++ CXXFLAGS="-O3 -flto" clean all
   # Expected: 5-10% speedup
   ```

2. **Enable ARM-specific flags**
   ```makefile
   # For Graviton3+
   ARCH_FLAGS += -mcpu=neoverse-v1 -mtune=neoverse-v1
   ```

3. **Use `__builtin_expect` for branch prediction**
   ```cpp
   if (__builtin_expect(rare_condition, 0)) { ... }
   ```

---

## 📞 Next Steps Summary

**This Week:**
1. ✅ Validate correctness with real genomic data
2. ✅ Profile on M4 Pro
3. ✅ Test on Graviton2 (AWS)

**Next Week:**
4. Optimize `_mm_movemask_epi8`
5. Test on Graviton3/4
6. Create benchmark suite

**Weeks 5-8:**
7. Implement SVE for Graviton3E
8. Comprehensive testing

**Weeks 9-12:**
9. Prepare upstream PR
10. Community engagement

---

**Last Updated**: January 24, 2026
**Current Status**: Phase 1 Complete ✅
