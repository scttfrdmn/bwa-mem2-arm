# AWS Graviton Testing Quick Start Guide

## 🚀 Quick Start (5 minutes)

### Prerequisites
- AWS account with access to c7g instances
- SSH key configured
- Basic familiarity with AWS EC2

### Step 1: Launch Graviton Instance

```bash
# Launch c7g.xlarge (Graviton3, 4 vCPU, 8 GB RAM)
# Via AWS Console or CLI:
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \  # Amazon Linux 2023 ARM
  --instance-type c7g.xlarge \
  --key-name YOUR_KEY_NAME \
  --security-group-ids YOUR_SG_ID \
  --subnet-id YOUR_SUBNET_ID

# Or use AWS Console:
# 1. Go to EC2 → Launch Instance
# 2. Choose: Amazon Linux 2023 ARM64
# 3. Instance type: c7g.xlarge
# 4. Launch
```

### Step 2: Connect and Setup

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>

# Update system
sudo yum update -y

# Install build dependencies
sudo yum install -y git gcc gcc-c++ make zlib-devel wget

# Clone repository
cd ~
git clone <your-repo-url> bwa-mem2-arm
cd bwa-mem2-arm
```

### Step 3: Run Phase 1 Test

```bash
# One command to run everything
./test-phase1.sh full

# This will:
# 1. Build baseline version
# 2. Benchmark baseline (5 iterations)
# 3. Build Phase 1 optimized versions
# 4. Benchmark Phase 1 (5 iterations)
# 5. Compare results
# 6. Report pass/fail

# Expected runtime: ~15-20 minutes
```

### Step 4: Check Results

```bash
# View results summary
cat phase1-results/baseline_summary.txt
cat phase1-results/phase1_summary.txt

# Expected output:
# Baseline:  ~2.6s
# Phase 1:   ~2.0s or better
# Speedup:   ≥1.25x
# Status:    ✅ PASS
```

---

## 📋 Detailed Testing Procedure

### Manual Step-by-Step (if automated script has issues)

#### 1. Build Baseline

```bash
cd ~/bwa-mem2-arm/bwa-mem2

# Clean
make clean

# Build with baseline flags
make arch="-march=armv8-a+simd"

# Verify binary
./bwa-mem2 version
```

#### 2. Setup Test Data

```bash
# Create test directory
mkdir -p ~/test-data
cd ~/test-data

# Download E. coli reference
wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz
gunzip GCF_000005845.2_ASM584v2_genomic.fna.gz
mv GCF_000005845.2_ASM584v2_genomic.fna ecoli.fa

# Index reference
~/bwa-mem2-arm/bwa-mem2/bwa-mem2 index ecoli.fa

# Generate test reads (100K paired-end, 150bp)
# Option A: Use wgsim (if available)
wgsim -N 100000 -1 150 -2 150 ecoli.fa reads_1.fq reads_2.fq

# Option B: Download pre-generated reads
# (Provide your own test reads or use existing dataset)
```

#### 3. Benchmark Baseline

```bash
cd ~/test-data

# Run 5 iterations
for i in {1..5}; do
  echo "Iteration $i"
  time ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
    ecoli.fa reads_1.fq reads_2.fq > baseline_$i.sam 2>&1
done

# Note the times and calculate average
```

#### 4. Build Phase 1

```bash
cd ~/bwa-mem2-arm/bwa-mem2

# Clean previous build
make clean

# Build multi-version (all Graviton generations)
make multi

# Verify binaries were created
ls -lh bwa-mem2*
# Should see:
#   bwa-mem2           (dispatcher)
#   bwa-mem2.graviton2 (Graviton2 optimized)
#   bwa-mem2.graviton3 (Graviton3 optimized)
#   bwa-mem2.graviton4 (Graviton4 optimized)
```

#### 5. Test Dispatcher

```bash
# Run dispatcher to see CPU detection
~/bwa-mem2-arm/bwa-mem2/bwa-mem2 2>&1 | head -20

# Expected output on c7g (Graviton3):
# ARM CPU Feature Detection:
#   NEON:    yes
#   DOTPROD: yes
#   SVE:     yes
#   SVE2:    no
#   I8MM:    yes
#   BF16:    yes
# Detected: Graviton3/3E (Neoverse V1)
#
# Looking to launch Graviton3 executable "bwa-mem2.graviton3"
# Launching Graviton3-optimized executable...
```

#### 6. Benchmark Phase 1

```bash
cd ~/test-data

# Run 5 iterations
for i in {1..5}; do
  echo "Iteration $i"
  time ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
    ecoli.fa reads_1.fq reads_2.fq > phase1_$i.sam 2>&1
done

# Note the times and calculate average
```

#### 7. Validate Correctness

```bash
cd ~/test-data

# Compare alignment counts
echo "Baseline alignments:"
grep -c "^[^@]" baseline_1.sam

echo "Phase 1 alignments:"
grep -c "^[^@]" phase1_1.sam

# Should be identical (e.g., 61,888 for 100K reads)

# Optional: Full diff (may show timestamp differences only)
diff <(grep "^[^@]" baseline_1.sam | sort) \
     <(grep "^[^@]" phase1_1.sam | sort)
```

#### 8. Calculate Speedup

```bash
# Use Python or calculator
python3 << EOF
baseline_times = [2.6, 2.58, 2.61, 2.59, 2.57]  # Replace with your times
phase1_times = [2.0, 1.98, 2.02, 1.99, 2.01]    # Replace with your times

baseline_avg = sum(baseline_times) / len(baseline_times)
phase1_avg = sum(phase1_times) / len(phase1_times)
speedup = baseline_avg / phase1_avg

print(f"Baseline average: {baseline_avg:.3f}s")
print(f"Phase 1 average:  {phase1_avg:.3f}s")
print(f"Speedup:          {speedup:.2f}x")
print(f"Status:           {'✅ PASS' if speedup >= 1.25 else '❌ FAIL'}")
EOF
```

---

## 🔍 Advanced Testing

### Profiling with perf

```bash
# Install perf
sudo yum install -y perf

# Profile baseline
sudo perf stat -d ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
  ecoli.fa reads_1.fq reads_2.fq > /dev/null

# Profile Phase 1
# (rebuild with multi first)
sudo perf stat -d ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
  ecoli.fa reads_1.fq reads_2.fq > /dev/null

# Compare metrics:
# - Instructions per cycle (IPC): Should increase
# - Cache miss rate: Should decrease or stay same
# - Branch mispredictions: Should decrease or stay same
```

### Hotspot Analysis

```bash
# Record with call graphs
sudo perf record -g ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
  ecoli.fa reads_1.fq reads_2.fq > /dev/null

# View report
sudo perf report

# Look for:
# - Time spent in smithWaterman functions
# - Time spent in _mm_movemask_epi8
# - Cache misses in hot loops
```

### Multi-Thread Scaling

```bash
# Test with different thread counts
for threads in 1 2 4; do
  echo "Testing with $threads threads"
  time ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t $threads \
    ecoli.fa reads_1.fq reads_2.fq > /dev/null 2>&1
done

# Expected scaling:
# 1 thread: ~7.1s
# 2 threads: ~3.9s
# 4 threads: ~2.0s
```

---

## 📊 Interpreting Results

### Success Criteria

✅ **PASS if ALL of the following are true**:
- Phase 1 time < 2.0s (on 4 threads, c7g.xlarge)
- Speedup ≥ 1.25x vs baseline
- Alignment counts match exactly
- No crashes or segfaults

⚠️ **PARTIAL if**:
- Speedup 1.1x - 1.24x (modest improvement)
- Alignment counts match
- Need to investigate further

❌ **FAIL if**:
- Speedup < 1.1x
- Alignment counts differ
- Crashes or stability issues

### Expected Performance by Instance Type

| Instance | CPU | Expected Baseline | Expected Phase 1 | Speedup |
|----------|-----|-------------------|------------------|---------|
| c7g.xlarge | Graviton3 | ~2.6s | ~2.0s | 1.3x |
| c7g.2xlarge | Graviton3 | ~2.6s | ~2.0s | 1.3x |
| c7gn.xlarge | Graviton3E | ~2.4s | ~1.8s | 1.35x |
| c6g.xlarge | Graviton2 | ~3.2s | ~2.5s | 1.28x |
| r8g.xlarge | Graviton4 | ~2.5s | ~1.9s | 1.32x |

### Understanding the Output

#### Good Sign ✅
```
ARM CPU Feature Detection:
  NEON:    yes
  DOTPROD: yes   ← Important for fast movemask
  SVE:     yes   ← Not used yet, but detected
```

#### Concerning ❌
```
Looking to launch Graviton3 executable "bwa-mem2.graviton3"
WARNING: Graviton3 executable not found
```
→ Indicates build failed, check compilation errors

#### Dispatcher Working Correctly ✅
```
Launching Graviton3-optimized executable "bwa-mem2.graviton3"
[bwa_index] bwa-mem2 version 2.2.1
```

---

## 🐛 Troubleshooting

### Issue: Build Fails

```bash
# Check for missing dependencies
make 2>&1 | grep -i "error"

# Common fixes:
sudo yum install -y gcc-c++ make zlib-devel

# If submodule issues:
git submodule update --init --recursive
```

### Issue: Dispatcher Can't Find Binary

```bash
# Verify binaries exist
ls -l ~/bwa-mem2-arm/bwa-mem2/bwa-mem2*

# Check if dispatcher is in same directory as binaries
cd ~/bwa-mem2-arm/bwa-mem2
./bwa-mem2  # Run from same directory
```

### Issue: Performance Lower Than Expected

```bash
# Check CPU frequency scaling
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
# Should be "performance" not "powersave"

# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check CPU frequency
lscpu | grep MHz
```

### Issue: Segmentation Fault

```bash
# Run with debug info
gdb --args ~/bwa-mem2-arm/bwa-mem2/bwa-mem2 mem -t 4 \
  ecoli.fa reads_1.fq reads_2.fq
> run
> bt  # Get backtrace

# Check memory
free -h
# Need at least 4GB free for E. coli test
```

---

## 📁 Results Location

After running `./test-phase1.sh full`, results are in:

```
~/bwa-mem2-arm/phase1-results/
├── baseline_times.txt         # Raw times from baseline runs
├── baseline_summary.txt       # Average baseline time
├── baseline_output.sam        # Baseline alignment output
├── baseline_count.txt         # Baseline alignment count
├── phase1_times.txt          # Raw times from Phase 1 runs
├── phase1_summary.txt        # Average Phase 1 time
├── phase1_output.sam         # Phase 1 alignment output
└── phase1_count.txt          # Phase 1 alignment count
```

---

## 📤 Reporting Results

After testing, report back with:

1. **Instance Type**: (e.g., c7g.xlarge)
2. **Baseline Time**: (average of 5 runs)
3. **Phase 1 Time**: (average of 5 runs)
4. **Speedup**: (baseline / phase1)
5. **Correctness**: (alignment counts match?)
6. **Dispatcher Output**: (copy/paste CPU detection output)
7. **Status**: ✅ Pass / ⚠️ Partial / ❌ Fail

**Example Report**:
```
Instance: c7g.xlarge (Graviton3, 4 vCPU)
Baseline: 2.587s (avg of 5 runs)
Phase 1:  2.012s (avg of 5 runs)
Speedup:  1.29x (29% improvement)
Alignments: 61,888 (both baseline and Phase 1)
Correctness: ✅ Match
Dispatcher: ✅ Detected Graviton3, launched graviton3 binary
Status: ✅ PASS

Ready to proceed to Phase 2.
```

---

## 🚀 Next Steps After Validation

### If Phase 1 Passes (≥1.25x speedup)
1. Save results for reference
2. Begin Phase 2 planning (NEON refinements)
3. Collect perf profiles to identify next bottlenecks

### If Needs Investigation (1.1-1.24x)
1. Run detailed perf profiling
2. Check if movemask optimization is active
3. Verify compiler flags were applied
4. May still proceed to Phase 2 with caution

### If Fails (<1.1x or correctness issues)
1. Debug Phase 1 implementation
2. Verify dispatcher is launching correct binary
3. Check for compilation warnings
4. Do NOT proceed to Phase 2 until Phase 1 works

---

**Ready to Test!** 🎯

Use the automated script for easiest testing:
```bash
./test-phase1.sh full
```

Or follow the manual procedure if you need more control.
