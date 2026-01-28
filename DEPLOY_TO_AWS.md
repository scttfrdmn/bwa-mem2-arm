# Deploy and Test BWA-MEM2 on AWS Graviton

**Quick Start Guide for Integration Testing**

---

## Prerequisites

1. AWS account with EC2 access
2. SSH key pair configured
3. Security group allowing SSH (port 22)

---

## Step 1: Launch Graviton Instance

### Option A: Graviton 3 (Recommended for Initial Testing)

```bash
# Launch c7g.4xlarge (16 vCPU, 32 GB RAM)
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \  # Ubuntu 22.04 ARM
  --instance-type c7g.4xlarge \
  --key-name YOUR_KEY_NAME \
  --security-group-ids YOUR_SECURITY_GROUP \
  --subnet-id YOUR_SUBNET \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=100}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-phase4-test}]'
```

### Option B: Graviton 4 (For Final Performance Testing)

```bash
# Launch c8g.8xlarge (32 vCPU, 64 GB RAM) - Best performance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \  # Ubuntu 22.04 ARM
  --instance-type c8g.8xlarge \
  --key-name YOUR_KEY_NAME \
  --security-group-ids YOUR_SECURITY_GROUP \
  --subnet-id YOUR_SUBNET \
  --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=200}' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-phase4-graviton4}]'
```

Get instance IP:
```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bwa-mem2-phase4-test" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' \
  --output text
```

---

## Step 2: Deploy Code

```bash
# Set instance IP
INSTANCE_IP=<your-instance-ip>

# Copy project to instance
scp -r /Users/scttfrdmn/src/bwa-mem2-arm ubuntu@$INSTANCE_IP:~/

# Or use rsync for faster transfer
rsync -avz -e ssh /Users/scttfrdmn/src/bwa-mem2-arm/ ubuntu@$INSTANCE_IP:~/bwa-mem2-arm/
```

---

## Step 3: Install Dependencies

```bash
# SSH to instance
ssh ubuntu@$INSTANCE_IP

# Update system
sudo apt-get update
sudo apt-get install -y build-essential zlib1g-dev

# Verify compiler
gcc --version  # Should be GCC 11+
g++ --version

# Check CPU
lscpu | grep "Model name"
cat /proc/cpuinfo | grep "CPU part"
```

Expected CPU part:
- `0xd0c` = Graviton 2 (Neoverse N1)
- `0xd40` = Graviton 3/3E (Neoverse V1)
- `0xd4f` = Graviton 4 (Neoverse V2)

---

## Step 4: Run Integration Test

```bash
cd ~/bwa-mem2-arm

# Run integration test script
./scripts/phase4-integration-test.sh
```

Expected output:
```
======================================================================
Phase 4 Integration Test - BWA-MEM2 ARM Optimizations
======================================================================

CPU: AWS Graviton 3 (Neoverse V1)
Expected optimization path: SVE or NEON

==> Building BWA-MEM2 with all phases...
  ✓ Build successful

==> Checking binary...
  ✓ Binary size: 5.2 MiB

==> Testing Phase 4 features in code...
  ✓ Branch prediction hints present (Week 4)
  ✓ Batch processing present (Week 3)
  ✓ Seed filtering present (Week 3)
  ✓ Function inlining present (Week 4)
  ✓ Loop unrolling present (Week 4)

==> Running basic functionality test...
  ✓ Alignment complete: 1234 lines, 450ms
  ✓ Output format valid (SAM header + alignments present)

======================================================================
Integration Test Summary
======================================================================

Build: ✓ Successful
Phase 4 Week 3: ✓ Batch processing + seed filtering
Phase 4 Week 4: ✓ Branch hints + inlining + unrolling

Integration test complete!
======================================================================
```

---

## Step 5: Download Test Data (Optional)

If you need larger test datasets:

```bash
# Download human chromosome 22 (small, good for testing)
cd ~/bwa-mem2-arm/test
wget ftp://ftp.ncbi.nlm.nih.gov/genomes/H_sapiens/CHR_22/hs_ref_chr22.fa.gz
gunzip hs_ref_chr22.fa.gz

# Build index
cd ~/bwa-mem2-arm/bwa-mem2
./bwa-mem2 index ../test/hs_ref_chr22.fa

# Generate simulated reads (if you have wgsim)
wgsim -N 100000 -1 150 -2 150 ../test/hs_ref_chr22.fa ../test/reads_R1.fq ../test/reads_R2.fq
```

---

## Step 6: Run Performance Benchmark

```bash
cd ~/bwa-mem2-arm

# Run performance test
./scripts/phase4-performance-test.sh

# Or run parallel test (multiple thread counts)
./scripts/phase4-parallel-test.sh
```

Expected improvements:
- **Baseline** (no Phase 4): 1.00x
- **Phase 4 Week 1+2**: 1.23x faster
- **Phase 4 Week 1+2+3**: 1.41x faster
- **Phase 4 Complete**: **1.40-1.42x faster** (38-42% improvement)

---

## Step 7: Validate Correctness

```bash
cd ~/bwa-mem2-arm/bwa-mem2

# Build baseline version (without Phase 4)
git checkout HEAD~4  # Go back 4 commits (before Phase 4)
make clean
make -j$(nproc)
mv bwa-mem2 bwa-mem2.baseline

# Build optimized version
git checkout main
make clean
make -j$(nproc)

# Run both versions
./bwa-mem2.baseline mem -t 16 ref.fa reads.fq > baseline.sam 2>&1
./bwa-mem2 mem -t 16 ref.fa reads.fq > optimized.sam 2>&1

# Compare outputs (should be identical)
diff baseline.sam optimized.sam

# Check alignment counts
grep -v "^@" baseline.sam | wc -l
grep -v "^@" optimized.sam | wc -l
```

Expected result: **No differences** (identical output)

---

## Step 8: Performance Profiling (Optional)

```bash
# Install perf if not available
sudo apt-get install -y linux-tools-generic linux-tools-$(uname -r)

# Profile with perf
sudo perf stat -e cycles,instructions,cache-references,cache-misses,branches,branch-misses \
  ./bwa-mem2 mem -t 16 ref.fa reads.fq > /dev/null

# Expected metrics:
# - IPC (instructions per cycle): >1.5 (higher is better)
# - Cache hit rate: >95% (higher is better)
# - Branch misprediction: <2% (lower is better)
```

Example output:
```
 Performance counter stats:

   12,345,678,901      cycles
   18,456,789,012      instructions              #    1.49  insn per cycle
      234,567,890      cache-references
        4,567,890      cache-misses              #    1.95 % of all cache refs
    3,456,789,012      branches
       34,567,890      branch-misses             #    1.00% of all branches

       3.456 seconds time elapsed
```

---

## Step 9: Multi-Thread Scaling Test

```bash
# Test scaling across different thread counts
for THREADS in 1 2 4 8 16 32; do
  echo "Testing with $THREADS threads..."
  /usr/bin/time -v ./bwa-mem2 mem -t $THREADS ref.fa reads.fq > /dev/null 2>&1 | grep "Elapsed"
done
```

Expected: Near-linear scaling up to physical core count

---

## Step 10: Cleanup

```bash
# On your local machine
aws ec2 terminate-instances --instance-ids <instance-id>

# Or keep instance running for more tests
aws ec2 stop-instances --instance-ids <instance-id>  # Stop to save costs
aws ec2 start-instances --instance-ids <instance-id> # Restart when needed
```

---

## Troubleshooting

### Build fails with "command not found"
```bash
# Install missing dependencies
sudo apt-get install -y build-essential zlib1g-dev
```

### Binary crashes or segfaults
```bash
# Check if binary is correct architecture
file bwa-mem2  # Should say "ARM aarch64"

# Run with debug symbols
make clean
make DEBUG=1
gdb --args ./bwa-mem2 mem -t 1 ref.fa reads.fq
```

### Performance lower than expected
```bash
# Check CPU frequency scaling
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
# Should say "performance", not "powersave"

# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Check for CPU throttling
sudo apt-get install -y sysstat
mpstat -P ALL 1 10  # Monitor CPU usage
```

### Out of memory
```bash
# Check memory usage
free -h

# Reduce thread count
./bwa-mem2 mem -t 8 ref.fa reads.fq  # Instead of -t 32

# Or use a larger instance type
# c7g.4xlarge: 32 GB RAM (16 cores)
# c7g.8xlarge: 64 GB RAM (32 cores)
# c8g.12xlarge: 96 GB RAM (48 cores)
```

---

## Quick Reference: Instance Types

| Instance Type | CPU | Cores | RAM | Cost/hr* | Best For |
|---------------|-----|-------|-----|----------|----------|
| c7g.2xlarge | Graviton 3 | 8 | 16 GB | $0.29 | Quick tests |
| c7g.4xlarge | Graviton 3 | 16 | 32 GB | $0.58 | Development |
| c7g.8xlarge | Graviton 3 | 32 | 64 GB | $1.15 | Testing |
| c8g.8xlarge | **Graviton 4** | 32 | 64 GB | $1.23 | **Production** |
| c8g.12xlarge | **Graviton 4** | 48 | 96 GB | $1.85 | Large datasets |

*Approximate US East pricing (2026)

---

## Expected Results Summary

### Build Success Criteria
- ✅ Compiles without errors on Ubuntu 22.04 ARM
- ✅ Binary size ~5-8 MB
- ✅ All Phase 4 features present in code
- ✅ No crashes on basic alignment test

### Performance Success Criteria
- ✅ Phase 4 Week 1+2: +20-25% improvement
- ✅ Phase 4 Week 1+2+3: +30-35% improvement
- ✅ Phase 4 Complete: **+38-42% improvement**
- ✅ Cache hit rate >95%
- ✅ Branch misprediction <2%

### Correctness Success Criteria
- ✅ Output identical to baseline (diff test)
- ✅ Same number of alignments
- ✅ No crashes or segfaults
- ✅ Scales linearly with thread count

---

## Next Steps After Successful Testing

1. **Update Documentation**
   - Add benchmark results to PHASE4_FINAL_SUMMARY.md
   - Update BWA-MEM3.md with Phase 4 achievements
   - Create PHASE4_RESULTS.md with detailed profiling data

2. **Tag Release**
   ```bash
   git tag -a v2.3.0-phase4 -m "Phase 4: Seeding optimizations complete"
   git push origin v2.3.0-phase4
   ```

3. **Announce**
   - GitHub release notes
   - Update README.md
   - Post performance results

4. **Production Deployment**
   - Create AMI with optimized binary
   - Document best practices for production use
   - Set up CI/CD for future changes

---

**Questions?** See PHASE4_INTEGRATION.md for detailed integration guide.

**Status**: Ready for AWS testing ✅
