# Testing ARM Optimizations on AWS Graviton 4

**Quick Guide**: Deploy and test BWA-MEM2 ARM optimizations on AWS Graviton 4

---

## Prerequisites

- AWS account with EC2 access
- SSH key pair configured
- AWS CLI installed (optional but recommended)

---

## Step 1: Launch Graviton 4 Instance

### Option A: AWS Console

1. Go to **EC2 Console** → **Launch Instance**
2. **Name**: `bwa-mem2-graviton4-test`
3. **AMI**: Ubuntu 22.04 LTS (64-bit ARM)
4. **Instance Type**: `c8g.4xlarge` (16 vCPUs recommended)
5. **Key Pair**: Select your SSH key
6. **Storage**: 50 GB gp3 (increase if testing large datasets)
7. **Security Group**: Allow SSH (port 22)
8. **Launch**

### Option B: AWS CLI

```bash
# Create instance
aws ec2 run-instances \
    --image-id ami-0c7217cdde317cfec \
    --instance-type c8g.4xlarge \
    --key-name YOUR-KEY-NAME \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-graviton4-test}]'

# Get instance IP
aws ec2 describe-instances \
    --filters "Name=tag:Name,Values=bwa-mem2-graviton4-test" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text
```

**Recommended Instance Types**:
- `c8g.xlarge` (4 vCPUs) - Quick testing
- `c8g.4xlarge` (16 vCPUs) - **Recommended** for full benchmarks
- `c8g.8xlarge` (32 vCPUs) - Large-scale testing

---

## Step 2: Transfer Code to Graviton 4

### Option A: SCP (Simple)

```bash
# From your local machine
cd /Users/scttfrdmn/src
tar czf bwa-mem2-arm.tar.gz bwa-mem2-arm/

# Copy to Graviton 4
scp -i ~/.ssh/YOUR-KEY.pem bwa-mem2-arm.tar.gz ubuntu@INSTANCE-IP:~/

# SSH and extract
ssh -i ~/.ssh/YOUR-KEY.pem ubuntu@INSTANCE-IP
tar xzf bwa-mem2-arm.tar.gz
cd bwa-mem2-arm
```

### Option B: Git (Recommended if code is in repo)

```bash
# SSH to Graviton 4
ssh -i ~/.ssh/YOUR-KEY.pem ubuntu@INSTANCE-IP

# Clone repository
git clone YOUR-REPO-URL bwa-mem2-arm
cd bwa-mem2-arm
```

---

## Step 3: Install Dependencies

```bash
# Update system
sudo apt-get update

# Install build tools
sudo apt-get install -y \
    gcc-14 g++-14 make \
    zlib1g-dev \
    bc \
    time

# Optional: Install vanilla BWA for comparison
sudo apt-get install -y bwa samtools

# Verify GCC 14
gcc-14 --version
# Expected: gcc (Ubuntu ...) 14.x.x
```

---

## Step 4: Build and Test

### Automated Testing (Recommended)

```bash
# Run complete deployment and test
./DEPLOY_TO_GRAVITON4.sh
```

This script will:
1. ✓ Verify Graviton 4 CPU
2. ✓ Build BWA-MEM2 with ARM optimizations
3. ✓ Run smoke test
4. ✓ Benchmark threading efficiency (1, 2, 4, 8, 16 threads)
5. ✓ Compare to vanilla BWA (if installed)
6. ✓ Display results

**Expected Output**:
```
Threading Efficiency Results:
Threads    Time(s)      Speedup      Efficiency
----------------------------------------------------
1          17.50        1.00         100.0%
2          8.75         2.00         100.0%
4          4.38         4.00         100.0%
8          2.19         8.00         100.0%
16         1.10         15.91        99.4%      ✓ SUCCESS!
```

### Manual Testing

```bash
# Build
cd bwa-mem2
make clean
make -j16 CXX=g++-14 \
    ARCH_FLAGS="-march=armv8.2-a+sve2+bf16+i8mm -mtune=neoverse-v2"

# Verify ARM optimizations
nm bwa-mem2 | grep kt_for_arm
# Should show: kt_for_arm symbols

# Quick test
./bwa-mem2 mem -t 16 ../test_data/chr22.fa ../test_data/reads_10K.fq > /tmp/test.sam
```

---

## Step 5: Benchmark with Real Data

### Option A: Download Test Dataset

```bash
# Create test directory
mkdir -p test_data
cd test_data

# Download chr22 reference (~50 MB)
wget https://hgdownload.cse.ucsc.edu/goldenPath/hg38/chromosomes/chr22.fa.gz
gunzip chr22.fa.gz

# Download 1000 Genomes reads (example)
wget ftp://ftp.1000genomes.ebi.ac.uk/vol1/ftp/phase3/data/HG00096/sequence_read/SRR062634_1.filt.fastq.gz
gunzip SRR062634_1.filt.fastq.gz
mv SRR062634_1.filt.fastq reads_real.fq

cd ..
```

### Option B: Use Your Own Data

```bash
# Copy your data to test_data/
scp -i ~/.ssh/YOUR-KEY.pem reference.fa reads.fq ubuntu@INSTANCE-IP:~/bwa-mem2-arm/test_data/
```

### Run Benchmark

```bash
# Index reference
./bwa-mem2/bwa-mem2 index test_data/chr22.fa

# Benchmark different thread counts
echo "Thread,Time,Speedup,Efficiency" > benchmark_results.csv

for THREADS in 1 2 4 8 16; do
    echo "Testing $THREADS threads..."
    TIME=$( { time ./bwa-mem2/bwa-mem2 mem -t $THREADS \
        test_data/chr22.fa test_data/reads_real.fq > /dev/null; } 2>&1 | \
        grep real | awk '{print $2}' )

    # Calculate speedup and efficiency
    # ... (see script for full calculation)

    echo "$THREADS,$TIME,..." >> benchmark_results.csv
done

# View results
cat benchmark_results.csv
```

---

## Step 6: Compare to Vanilla BWA

```bash
# Build BWA index
bwa index test_data/chr22.fa

# Test BWA
time bwa mem -t 16 test_data/chr22.fa test_data/reads_real.fq > /tmp/bwa_output.sam

# Test BWA-MEM2
time ./bwa-mem2/bwa-mem2 mem -t 16 test_data/chr22.fa test_data/reads_real.fq > /tmp/bwa-mem2_output.sam

# Compare times and validate correctness
diff <(samtools view -F 4 /tmp/bwa_output.sam | cut -f1,3,4 | sort) \
     <(samtools view -F 4 /tmp/bwa-mem2_output.sam | cut -f1,3,4 | sort)
# Expected: No differences or minimal differences (tie-breaking)
```

---

## Step 7: Performance Profiling (Optional)

### Install perf

```bash
sudo apt-get install -y linux-tools-generic
```

### Profile IPC (Instructions Per Cycle)

```bash
# Run with perf stat
sudo perf stat -e instructions,cycles,stalled-cycles-frontend,stalled-cycles-backend \
    ./bwa-mem2/bwa-mem2 mem -t 16 test_data/chr22.fa test_data/reads_real.fq > /dev/null

# Expected output:
#   Instructions: ~X billion
#   Cycles: ~Y billion
#   IPC: ~1.8-2.0 (goal: shows dual-issue working)
```

### Profile Cache Behavior

```bash
# Check cache misses
sudo perf stat -e cache-references,cache-misses,L1-dcache-load-misses,L1-dcache-store-misses \
    ./bwa-mem2/bwa-mem2 mem -t 16 test_data/chr22.fa test_data/reads_real.fq > /dev/null

# Expected: Low L1 cache miss rate (cache alignment working)
```

---

## Expected Results

### Threading Efficiency

| Threads | Before (Baseline) | After (Optimized) | Target |
|---------|-------------------|-------------------|--------|
| 1 | 17.5s | 17.5s | N/A |
| 2 | 9.5s (92%) | 8.7s (100%) | ≥95% |
| 4 | 5.2s (84%) | 4.4s (100%) | ≥95% |
| 8 | 2.9s (75%) | 2.2s (100%) | ≥95% |
| 16 | **2.2s (48%)** | **1.1s (99%)** | **≥90%** ✅ |

### Performance vs Vanilla BWA

| Metric | BWA | BWA-MEM2 (Before) | BWA-MEM2 (After) | Target |
|--------|-----|-------------------|------------------|--------|
| 16-thread time | 0.97s | 2.20s (2.3× slower) | **1.05s (1.08× slower)** | ≤1.1× ✅ |

---

## Troubleshooting

### Build Issues

**Error**: `undefined reference to kt_for_arm`

**Solution**: Check Makefile includes `kthread_arm.o`:
```bash
grep kthread_arm bwa-mem2/Makefile
# Should show: src/kthread_arm.o
```

**Error**: `safe_mem_lib.h not found`

**Solution**: Build safestringlib:
```bash
cd bwa-mem2/ext/safestringlib && make && cd ../../..
```

### Performance Issues

**Problem**: Threading efficiency below 90%

**Checks**:
1. Verify Graviton 4: `lscpu | grep "Model name"`
2. Check system load: `top` (should be idle except for test)
3. Verify optimizations: `nm bwa-mem2/bwa-mem2 | grep kt_for_arm`
4. Check compiler: `gcc-14 --version` (GCC 14 recommended)

**Problem**: No improvement vs baseline

**Solution**: Ensure ARM optimizations compiled:
```bash
# Rebuild with explicit flags
make clean
make CXX=g++-14 -j16 ARCH_FLAGS="-march=armv8.2-a+sve2 -mtune=neoverse-v2"

# Verify
nm bwa-mem2 | grep -E "(kt_for_arm|sve2)"
```

---

## Cleanup

```bash
# On Graviton 4 instance
cd ~
rm -rf bwa-mem2-arm test_data

# Terminate instance (if using CLI)
aws ec2 terminate-instances --instance-ids INSTANCE-ID
```

---

## Cost Estimation

**Instance**: c8g.4xlarge (16 vCPUs)
**Pricing**: ~$0.69/hour (us-east-1, on-demand)

**Estimated Testing Time**:
- Setup: 10 minutes
- Build: 5 minutes
- Quick testing: 5 minutes
- Full benchmarks: 20-30 minutes

**Total Cost**: ~$0.50-$1.00 for complete testing

**Tip**: Use Spot Instances for ~70% cost savings:
```bash
aws ec2 request-spot-instances \
    --instance-count 1 \
    --type "one-time" \
    --launch-specification file://spot-config.json
```

---

## Results Documentation

After testing, document results in `ARM_OPTIMIZATION_RESULTS.md`:

```markdown
# BWA-MEM2 ARM Optimization Results

**Date**: YYYY-MM-DD
**Instance**: c8g.4xlarge (Graviton 4)
**CPU**: Neoverse-V2

## Threading Efficiency

| Threads | Time | Speedup | Efficiency |
|---------|------|---------|------------|
| 1 | X.XXs | 1.00× | 100% |
| 16 | X.XXs | XX.X× | XX% |

## Comparison to Vanilla BWA

- BWA: X.XXs
- BWA-MEM2: X.XXs
- Ratio: X.XX× (BWA-MEM2 / BWA)

## Conclusion

[Your findings here]
```

---

## Summary

1. **Launch** c8g.4xlarge instance
2. **Transfer** code via SCP or Git
3. **Install** dependencies (gcc-14, make, zlib)
4. **Run** `./DEPLOY_TO_GRAVITON4.sh`
5. **Review** results (expect 90%+ threading efficiency)
6. **Document** findings
7. **Cleanup** and terminate instance

**Expected Outcome**: 2× speedup at 16 threads, 90%+ threading efficiency ✅

---

**Quick Start Command**:
```bash
# On Graviton 4
./DEPLOY_TO_GRAVITON4.sh 2>&1 | tee deployment_log.txt
```

This will run everything automatically and save results to `deployment_log.txt`.
