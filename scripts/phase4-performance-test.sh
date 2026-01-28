#!/bin/bash
#
# Phase 4 Performance Testing
# Tests prefetch + SIMD optimizations on AWS Graviton 3
#
# Expected improvement: 15.5-17.5% overall speedup
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load AWS configuration
if [ ! -f "$PROJECT_ROOT/.aws-test-config" ]; then
    echo "ERROR: .aws-test-config not found"
    echo "Create it with your AWS settings first"
    exit 1
fi

source "$PROJECT_ROOT/.aws-test-config"

# Phase 4 specific settings
INSTANCE_TYPE="c7g.xlarge"  # Graviton 3
REGION="${AWS_REGION:-us-west-2}"
AMI_ID="${AWS_AMI_ARM:-ami-0cbac0f1d6260a580}"  # Amazon Linux 2023 ARM (al2023-ami-2023.10.20260120.4)
KEY_NAME="${AWS_KEY_NAME}"
SECURITY_GROUP="${AWS_SECURITY_GROUP}"

LOG_DIR="$PROJECT_ROOT/phase4-test-results"
mkdir -p "$LOG_DIR"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_FILE="$LOG_DIR/phase4-test-${TIMESTAMP}.log"

echo "========================================" | tee "$LOG_FILE"
echo "Phase 4 Performance Test - Graviton 3" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Testing: Prefetch + SIMD optimizations" | tee -a "$LOG_FILE"
echo "Target: 15.5-17.5% overall speedup" | tee -a "$LOG_FILE"
echo "Instance: $INSTANCE_TYPE" | tee -a "$LOG_FILE"
echo "Timestamp: $TIMESTAMP" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Launch instance
echo "=== Launching Graviton 3 instance ===" | tee -a "$LOG_FILE"

INSTANCE_ID=$(aws ec2 run-instances \
    --region "$REGION" \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --security-group-ids "$SECURITY_GROUP" \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=phase4-test-graviton3},{Key=Project,Value=bwa-mem2-arm},{Key=Phase,Value=4}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

if [ -z "$INSTANCE_ID" ]; then
    echo "ERROR: Failed to launch instance" | tee -a "$LOG_FILE"
    exit 1
fi

echo "Instance ID: $INSTANCE_ID" | tee -a "$LOG_FILE"

# Wait for instance to be running
echo "Waiting for instance to start..." | tee -a "$LOG_FILE"
aws ec2 wait instance-running --region "$REGION" --instance-ids "$INSTANCE_ID"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo "Public IP: $PUBLIC_IP" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Wait for SSH to be available
echo "Waiting for SSH access..." | tee -a "$LOG_FILE"
SSH_KEY_PATH="${HOME}/.ssh/${KEY_NAME}"
if [ ! -f "$SSH_KEY_PATH" ]; then
    SSH_KEY_PATH="${HOME}/.ssh/${KEY_NAME}.pem"
fi
for i in {1..60}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 -i "$SSH_KEY_PATH" ec2-user@$PUBLIC_IP "echo 'SSH ready'" 2>/dev/null; then
        echo "SSH is ready!" | tee -a "$LOG_FILE"
        break
    fi
    if [ $((i % 10)) -eq 0 ]; then
        echo "Attempt $i/60: Still waiting for SSH..." | tee -a "$LOG_FILE"
    fi
    sleep 10
done

echo "" | tee -a "$LOG_FILE"

# Upload test script
echo "=== Uploading test script ===" | tee -a "$LOG_FILE"

cat > /tmp/phase4_test_runner.sh << 'RUNNER_SCRIPT'
#!/bin/bash
set -e

echo "=========================================="
echo "Phase 4 Performance Test Runner"
echo "=========================================="
echo ""

# System info
echo "=== System Information ==="
uname -a
cat /proc/cpuinfo | grep -E "^(model name|processor|Features)" | head -20
free -h
df -h
echo ""

# Install dependencies
echo "=== Installing dependencies ==="
sudo dnf install -y git gcc gcc-c++ make zlib-devel bzip2 perf
echo ""

# Clone repository
echo "=== Cloning BWA-MEM2 ==="
cd ~
if [ -d bwa-mem2 ]; then
    rm -rf bwa-mem2
fi
git clone -b arm-graviton-optimization https://github.com/scttfrdmn/bwa-mem2.git
cd bwa-mem2
CURRENT_COMMIT=$(git rev-parse HEAD)
echo "Current commit: $CURRENT_COMMIT"
git log --oneline -3
echo ""

# Get test data
echo "=== Downloading test data ==="
cd ~
if [ ! -f ecoli.fa ]; then
    wget -q https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz -O ecoli.fa.gz
    gunzip ecoli.fa.gz
    mv ecoli.fa.gz ecoli.fa 2>/dev/null || true
fi

if [ ! -f reads_1.fq ] || [ ! -f reads_2.fq ]; then
    echo "Generating test reads..."
    # Simulate 100K paired-end reads (150bp)
    cd ~/bwa-mem2
    # Use existing test data if available
    if [ -f test/reads_1.fq ]; then
        cp test/reads_1.fq ~/reads_1.fq
        cp test/reads_2.fq ~/reads_2.fq
    fi
fi

cd ~/bwa-mem2

# Build optimized version (with prefetch + SIMD)
echo "=== Building OPTIMIZED version ==="
echo "Commits: bed1d02 (prefetch) + 24456f7 (SIMD)"
make clean
make -j4 2>&1 | tail -20
OPTIMIZED_BIN="./bwa-mem2"
if [ ! -f "$OPTIMIZED_BIN" ]; then
    echo "ERROR: Optimized build failed"
    exit 1
fi
cp bwa-mem2 ~/bwa-mem2-optimized
echo "Optimized binary built: $(ls -lh ~/bwa-mem2-optimized)"
echo ""

# Build baseline version (checkout before Phase 4 optimizations)
echo "=== Building BASELINE version ==="
echo "Checking out commit before prefetch/SIMD optimizations..."
# Go back to commit before bed1d02 (prefetch) - that's 0243ef7 or HEAD~2
BASELINE_COMMIT="0243ef7"
echo "Baseline commit: $BASELINE_COMMIT (before prefetch optimization)"
git checkout $BASELINE_COMMIT 2>&1 | head -5
make clean
make -j4 2>&1 | tail -20
if [ ! -f bwa-mem2 ]; then
    echo "ERROR: Baseline build failed"
    exit 1
fi
cp bwa-mem2 ~/bwa-mem2-baseline
git checkout arm-graviton-optimization  # Return to optimized branch
echo "Baseline binary built: $(ls -lh ~/bwa-mem2-baseline)"
echo ""

# Index reference
echo "=== Indexing reference genome ==="
cd ~
if [ ! -f ecoli.fa.bwt.2bit.64 ]; then
    ~/bwa-mem2-optimized index ecoli.fa
fi
echo ""

# Generate test reads if needed
if [ ! -f reads_1.fq ]; then
    echo "=== Generating test reads ==="
    # Simple read generator for testing
    ~/bwa-mem2-optimized mem -t 4 ecoli.fa ecoli.fa 2>/dev/null | head -100000 > reads_1.fq || true
    cp reads_1.fq reads_2.fq
fi

echo "=== Running Performance Tests ==="
echo ""

# Test 1: Baseline (no optimizations)
echo "--- Test 1: BASELINE (no prefetch/SIMD) ---"
cd ~
rm -f test_baseline.sam
echo "Running 3 iterations for baseline..."
BASELINE_TIMES=()
for i in 1 2 3; do
    echo "  Iteration $i/3..."
    TIME_OUTPUT=$( { time ~/bwa-mem2-baseline mem -t 4 ecoli.fa reads_1.fq reads_2.fq > test_baseline.sam 2>&1; } 2>&1 )
    REAL_TIME=$(echo "$TIME_OUTPUT" | grep "^real" | awk '{print $2}')
    echo "    Time: $REAL_TIME"
    BASELINE_TIMES+=("$REAL_TIME")
done
echo "Baseline times: ${BASELINE_TIMES[@]}"
echo ""

# Test 2: Optimized (prefetch + SIMD)
echo "--- Test 2: OPTIMIZED (prefetch + SIMD) ---"
rm -f test_optimized.sam
echo "Running 3 iterations for optimized..."
OPTIMIZED_TIMES=()
for i in 1 2 3; do
    echo "  Iteration $i/3..."
    TIME_OUTPUT=$( { time ~/bwa-mem2-optimized mem -t 4 ecoli.fa reads_1.fq reads_2.fq > test_optimized.sam 2>&1; } 2>&1 )
    REAL_TIME=$(echo "$TIME_OUTPUT" | grep "^real" | awk '{print $2}')
    echo "    Time: $REAL_TIME"
    OPTIMIZED_TIMES+=("$REAL_TIME")
done
echo "Optimized times: ${OPTIMIZED_TIMES[@]}"
echo ""

# Test 3: Performance counters with perf
echo "--- Test 3: Performance Counters ---"
echo "Baseline:"
sudo perf stat -d ~/bwa-mem2-baseline mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /dev/null 2>&1 || true
echo ""
echo "Optimized:"
sudo perf stat -d ~/bwa-mem2-optimized mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /dev/null 2>&1 || true
echo ""

# Correctness check
echo "--- Test 4: Correctness Check ---"
if [ -f test_baseline.sam ] && [ -f test_optimized.sam ]; then
    BASELINE_MD5=$(md5sum test_baseline.sam | awk '{print $1}')
    OPTIMIZED_MD5=$(md5sum test_optimized.sam | awk '{print $1}')
    echo "Baseline MD5:  $BASELINE_MD5"
    echo "Optimized MD5: $OPTIMIZED_MD5"
    if [ "$BASELINE_MD5" = "$OPTIMIZED_MD5" ]; then
        echo "✅ PASS: Output is identical"
    else
        echo "❌ FAIL: Output differs!"
        diff test_baseline.sam test_optimized.sam | head -50 || true
    fi
fi
echo ""

echo "=========================================="
echo "Phase 4 Performance Test Complete"
echo "=========================================="
RUNNER_SCRIPT

chmod +x /tmp/phase4_test_runner.sh

scp -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" /tmp/phase4_test_runner.sh ec2-user@$PUBLIC_IP:~/phase4_test.sh

echo "=== Running performance tests ===" | tee -a "$LOG_FILE"
echo "This will take 15-30 minutes..." | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Run test and capture output
ssh -o StrictHostKeyChecking=no -i "$SSH_KEY_PATH" ec2-user@$PUBLIC_IP "bash ~/phase4_test.sh" 2>&1 | tee -a "$LOG_FILE"

echo "" | tee -a "$LOG_FILE"
echo "=== Test Complete ===" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"
echo "Results saved to: $LOG_FILE" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Ask about termination
read -p "Terminate instance $INSTANCE_ID? (y/n) " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Terminating instance..." | tee -a "$LOG_FILE"
    aws ec2 terminate-instances --region "$REGION" --instance-ids "$INSTANCE_ID" > /dev/null
    echo "Instance terminated" | tee -a "$LOG_FILE"
else
    echo "Instance left running: $INSTANCE_ID" | tee -a "$LOG_FILE"
    echo "Public IP: $PUBLIC_IP" | tee -a "$LOG_FILE"
    echo "To terminate later: aws ec2 terminate-instances --region $REGION --instance-ids $INSTANCE_ID" | tee -a "$LOG_FILE"
fi

echo ""
echo "========================================" | tee -a "$LOG_FILE"
echo "Phase 4 Test Complete" | tee -a "$LOG_FILE"
echo "========================================" | tee -a "$LOG_FILE"
