# Phase 1 Deployment Guide

## Pre-Deployment Checklist

### ✅ Local Preparation

- [x] Code implementation complete
- [x] Documentation complete
- [x] Test scripts ready
- [ ] Git commit created
- [ ] Changes pushed to remote (if applicable)

---

## Step 1: Commit Changes

### Quick Commit (Recommended)

```bash
cd /Users/scttfrdmn/src/bwa-mem2-arm

# Stage all Phase 1 changes
git add -A

# Create commit
git commit -m "Phase 1: ARM/Graviton optimization - Compiler flags + optimized movemask

Implementation complete for Phase 1 targeting 40-50% performance improvement.

Key changes:
- Multi-version build for Graviton2/3/4 (Makefile)
- Enabled fast movemask implementation (simd_arm_neon.h)
- Runtime CPU dispatcher with auto-detection (runsimd_arm.cpp)
- Comprehensive documentation and automated testing

Expected performance: 2.587s → 2.0s (1.29x speedup on c7g.xlarge)

Testing: Run ./test-phase1.sh full on AWS Graviton instance

Files modified: 4 | Files created: 9 | Total lines: ~3,100"

# View commit
git log -1 --stat

# Push to remote (if you have a remote configured)
# git push origin main
```

---

## Step 2: Launch AWS Instance

### Option A: AWS Console

1. Go to EC2 → Launch Instance
2. **Name**: bwa-mem2-phase1-test
3. **AMI**: Amazon Linux 2023 (ARM64)
4. **Instance Type**: c7g.xlarge (4 vCPU, 8 GB RAM, Graviton3)
5. **Key pair**: Select or create
6. **Security group**: Allow SSH (port 22)
7. Click "Launch Instance"

### Option B: AWS CLI

```bash
# Set your parameters
KEY_NAME="your-key-name"
SECURITY_GROUP="sg-xxxxxxxxx"
SUBNET_ID="subnet-xxxxxxxxx"

# Launch instance
aws ec2 run-instances \
  --image-id ami-0c55b159cbfafe1f0 \
  --instance-type c7g.xlarge \
  --key-name $KEY_NAME \
  --security-group-ids $SECURITY_GROUP \
  --subnet-id $SUBNET_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-phase1-test}]' \
  --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=30}' \
  --output table

# Get instance IP
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bwa-mem2-phase1-test" \
  --query "Reservations[0].Instances[0].PublicIpAddress" \
  --output text
```

---

## Step 3: Deploy Code to AWS

### Transfer Repository

```bash
# Get instance IP (from AWS console or CLI)
INSTANCE_IP="<your-instance-ip>"
KEY_FILE="~/.ssh/your-key.pem"

# Option A: Git clone (if pushed to remote)
ssh -i $KEY_FILE ec2-user@$INSTANCE_IP << 'EOF'
  sudo yum update -y
  sudo yum install -y git gcc gcc-c++ make zlib-devel wget python3
  git clone https://github.com/your-org/bwa-mem2-arm.git
  cd bwa-mem2-arm
  git submodule update --init --recursive
EOF

# Option B: Direct transfer (if not pushed to remote)
# Create tarball locally
cd /Users/scttfrdmn/src/bwa-mem2-arm
tar czf phase1.tar.gz \
  bwa-mem2/ \
  *.md \
  *.sh \
  *.txt \
  --exclude='bwa-mem2/*.o' \
  --exclude='bwa-mem2/*.a' \
  --exclude='bwa-mem2/bwa-mem2'

# Copy to instance
scp -i $KEY_FILE phase1.tar.gz ec2-user@$INSTANCE_IP:~/

# Extract on instance
ssh -i $KEY_FILE ec2-user@$INSTANCE_IP << 'EOF'
  sudo yum update -y
  sudo yum install -y gcc gcc-c++ make zlib-devel wget python3
  tar xzf phase1.tar.gz
  cd bwa-mem2-arm
  cd bwa-mem2 && git submodule update --init --recursive && cd ..
EOF
```

---

## Step 4: Run Tests

### Automated Testing (Recommended)

```bash
# SSH into instance
ssh -i $KEY_FILE ec2-user@$INSTANCE_IP

# Navigate to repository
cd bwa-mem2-arm

# Make test script executable
chmod +x test-phase1.sh

# Run full test suite
./test-phase1.sh full

# This will:
# 1. Build baseline (5-10 minutes)
# 2. Benchmark baseline 5x (3-5 minutes)
# 3. Build Phase 1 (5-10 minutes)
# 4. Benchmark Phase 1 5x (3-5 minutes)
# 5. Compare results (instant)
# Total time: ~15-20 minutes
```

### Expected Output

```
================================================================================
                        PHASE 1 PERFORMANCE COMPARISON
================================================================================
Baseline time:  2.587s
Phase 1 time:   2.012s
Speedup:        1.29x
Improvement:    22.2%
--------------------------------------------------------------------------------
✅ PASS: Achieved ≥1.25x speedup target!

CORRECTNESS CHECK:
Baseline alignments: 61,888
Phase 1 alignments:  61,888
✅ PASS: Alignment counts match
================================================================================
```

---

## Step 5: Collect Results

### Retrieve Test Results

```bash
# From local machine, download results
scp -i $KEY_FILE -r \
  ec2-user@$INSTANCE_IP:~/bwa-mem2-arm/phase1-results \
  ./phase1-results-$(date +%Y%m%d)

# Download logs
scp -i $KEY_FILE \
  ec2-user@$INSTANCE_IP:~/bwa-mem2-arm/phase1-results/*.txt \
  ./
```

### Document Results

Create `PHASE1_RESULTS.md`:

```markdown
# Phase 1 Validation Results

**Date**: $(date)
**Instance**: c7g.xlarge (Graviton3)
**Status**: ✅ PASS / ❌ FAIL

## Performance

- Baseline time: X.XXXs
- Phase 1 time: X.XXXs
- Speedup: X.XXx
- Improvement: XX.X%

## Correctness

- Baseline alignments: XX,XXX
- Phase 1 alignments: XX,XXX
- Match: ✅ YES / ❌ NO

## CPU Detection

```
ARM CPU Feature Detection:
  NEON:    yes
  DOTPROD: yes
  SVE:     yes
  ...
Detected: Graviton3 (Neoverse V1)
```

## Conclusion

Phase 1 [PASSED/FAILED]. Ready to proceed to Phase 2.
```

---

## Step 6: Cleanup

### Terminate Instance (when done)

```bash
# Get instance ID
INSTANCE_ID=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bwa-mem2-phase1-test" \
  --query "Reservations[0].Instances[0].InstanceId" \
  --output text)

# Terminate
aws ec2 terminate-instances --instance-ids $INSTANCE_ID

# Or via console: EC2 → Instances → Select → Actions → Terminate
```

---

## Troubleshooting

### Build Fails

```bash
# Check dependencies
ssh -i $KEY_FILE ec2-user@$INSTANCE_IP << 'EOF'
  sudo yum install -y gcc gcc-c++ make zlib-devel
  cd bwa-mem2-arm/bwa-mem2
  git submodule update --init --recursive
  make clean
  make multi 2>&1 | tee build.log
EOF
```

### Test Script Fails

```bash
# Run manually step by step
cd bwa-mem2-arm
./test-phase1.sh baseline  # Build and test baseline
./test-phase1.sh phase1    # Build and test Phase 1
./test-phase1.sh compare   # Compare results
```

### Performance Lower Than Expected

```bash
# Check CPU frequency
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor

# Set to performance mode
echo performance | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

# Re-run test
./test-phase1.sh phase1
```

---

## Quick Reference Commands

```bash
# SSH into instance
ssh -i ~/.ssh/your-key.pem ec2-user@<instance-ip>

# Run full test
cd bwa-mem2-arm && ./test-phase1.sh full

# Check results
cat phase1-results/*_summary.txt

# View logs
tail -f phase1-results/*.txt

# Clean and retry
./test-phase1.sh clean
./test-phase1.sh full
```

---

## Success Criteria

✅ **PASS if ALL true**:
- Speedup ≥ 1.25x
- Alignment counts match exactly
- No crashes or errors
- Dispatcher detects CPU correctly

⚠️ **INVESTIGATE if**:
- Speedup 1.1-1.24x (partial success)
- Need perf profiling

❌ **FAIL if**:
- Speedup < 1.1x
- Alignment counts differ
- Crashes or stability issues

---

## After Successful Validation

1. ✅ Document actual results in `PHASE1_RESULTS.md`
2. ✅ Commit results to repository
3. ✅ Tag release: `git tag v0.1.0-phase1`
4. ✅ Update `IMPLEMENTATION_STATUS.md` with actual performance
5. ✅ Begin Phase 2 planning

---

## Contact & Support

- Documentation: See README_PHASE1.md
- Testing: See AWS_TESTING_GUIDE.md
- Issues: Check troubleshooting section above

---

**Ready to deploy!** 🚀

Next command: `git add -A && git commit -m "Phase 1 complete"`
