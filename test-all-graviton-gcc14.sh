#!/bin/bash
#
# Test all Graviton generations with GCC 14 from AL2023 repos
#

set -e

AWS_PROFILE="aws"
AWS_REGION="us-west-2"
SSH_KEY=~/.ssh/graviton-test-key

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Multi-Graviton Test with GCC 14 (AL2023 repos)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Get latest AL2023 AMI
echo "Getting latest AL2023 ARM64 AMI..."
AMI=$(aws ec2 describe-images \
    --profile $AWS_PROFILE \
    --region $AWS_REGION \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-2023.*-kernel-*-arm64" \
              "Name=state,Values=available" \
    --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
    --output text)

echo "AMI: $AMI"

# Verify it's the latest
AMI_NAME=$(aws ec2 describe-images \
    --profile $AWS_PROFILE \
    --region $AWS_REGION \
    --image-ids $AMI \
    --query 'Images[0].Name' \
    --output text)
echo "AMI Name: $AMI_NAME"

# Create deployment package
echo "Creating deployment package..."
cd bwa-mem2
tar czf /tmp/bwa-mem2-week2.tar.gz \
    --exclude='.git' \
    --exclude='*.o' \
    --exclude='bwa-mem2' \
    --exclude='bwa-mem2.*' \
    .
cd ..

# Test function
test_generation() {
    local name=$1
    local instance_type=$2

    echo ""
    echo "═══════════════════════════════════════════════════════════════"
    echo "  Testing $name ($instance_type) with GCC 14"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""

    # Launch instance
    echo "Launching $name..."
    local instance_id=$(aws ec2 run-instances \
        --profile $AWS_PROFILE \
        --region $AWS_REGION \
        --image-id $AMI \
        --instance-type $instance_type \
        --key-name graviton-test-key \
        --security-group-ids sg-0e849a974f163c1d9 \
        --subnet-id subnet-0a73ca94ed00cdaf9 \
        --block-device-mappings 'DeviceName=/dev/xvda,Ebs={VolumeSize=20,VolumeType=gp3}' \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-$name-gcc14}]" \
        --query 'Instances[0].InstanceId' \
        --output text 2>&1)

    if [ -z "$instance_id" ] || echo "$instance_id" | grep -q "error"; then
        echo "⚠️  $name: Instance type unavailable"
        echo "$name SKIP" >> /tmp/graviton_gcc14_results.txt
        return 1
    fi

    echo "$name: Instance $instance_id"

    # Wait for instance
    aws ec2 wait instance-running \
        --profile $AWS_PROFILE \
        --region $AWS_REGION \
        --instance-ids $instance_id 2>/dev/null

    sleep 30

    # Get IP
    local ip=$(aws ec2 describe-instances \
        --profile $AWS_PROFILE \
        --region $AWS_REGION \
        --instance-ids $instance_id \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    echo "$name: IP $ip"

    # Upload code
    echo "Uploading code..."
    scp -i $SSH_KEY \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        /tmp/bwa-mem2-week2.tar.gz \
        ec2-user@$ip:~/ 2>&1 | grep -v "Warning:" || true

    # Build and test
    echo "Installing GCC 14 and building..."
    ssh -i $SSH_KEY \
        -o StrictHostKeyChecking=no \
        -o UserKnownHostsFile=/dev/null \
        -o ConnectTimeout=30 \
        ec2-user@$ip bash << 'EOF'
set -e

# Install dependencies including GCC 14
echo "Installing dependencies and GCC 14..."
sudo yum install -y gcc14 gcc14-c++ make zlib-devel git python3 wget &>/dev/null
echo "✅ Dependencies and GCC 14 installed"

# Set up GCC 14 environment
export CC=gcc14-gcc
export CXX=gcc14-g++

echo ""
echo "GCC version:"
$CC --version | head -1
$CXX --version | head -1

# Verify ARMv9 support
if ! $CXX -march=armv9-a -E - < /dev/null &>/dev/null; then
    echo "❌ GCC 14 does not support ARMv9-a"
    exit 1
fi
echo "✅ ARMv9-a support confirmed"
echo ""

# Extract BWA-MEM2
mkdir -p test && cd test
tar xzf ../bwa-mem2-week2.tar.gz 2>&1 | grep -v "LIBARCHIVE\|tar:" | head -3 || true

# Clone safestringlib
if [ ! -d ext/safestringlib ]; then
    mkdir -p ext
    git clone --quiet https://github.com/intel/safestringlib.git ext/safestringlib
fi

# Fix safestringlib for GCC 14 strictness (add missing ctype.h include)
sed -i '/#include "safe_str_lib.h"/a #include <ctype.h>' ext/safestringlib/safeclib/strcasecmp_s.c
sed -i '/#include "safe_str_lib.h"/a #include <ctype.h>' ext/safestringlib/safeclib/strcasestr_s.c

# Detect CPU generation
CPU_PART=$(grep "CPU part" /proc/cpuinfo | head -1 | awk '{print $4}')
case "$CPU_PART" in
    0xd0c)
        CPU_NAME="Graviton2 (Neoverse N1)"
        ARCH_FLAGS="-march=armv8.2-a+fp16+rcpc+dotprod+crypto -mtune=neoverse-n1"
        ;;
    0xd40)
        CPU_NAME="Graviton3/3E (Neoverse V1)"
        ARCH_FLAGS="-march=armv8.4-a+sve+bf16+i8mm+crypto -mtune=neoverse-v1"
        ;;
    0xd4f)
        CPU_NAME="Graviton4 (Neoverse V2)"
        ARCH_FLAGS="-march=armv9-a+sve2+sve2-bitperm+bf16+i8mm -mtune=neoverse-v2"
        ;;
    *)
        CPU_NAME="Unknown (part: $CPU_PART)"
        ARCH_FLAGS="-march=armv8-a"
        ;;
esac

echo "CPU: $CPU_NAME"
echo "Flags: $ARCH_FLAGS"
echo ""

# Build
echo "Building BWA-MEM2 with GCC 14..."
make clean &>/dev/null || true
make arch="$ARCH_FLAGS" CXX=$CXX CC=$CC 2>&1 | tail -20

if [ ! -f bwa-mem2 ]; then
    echo "❌ Build failed"
    exit 1
fi

echo "✅ Build successful: $(ls -lh bwa-mem2 | awk '{print $5}')"

# Download E. coli
if [ ! -f ~/ecoli.fa ]; then
    wget -q -O ~/ecoli.fa.gz \
        "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz"
    gunzip ~/ecoli.fa.gz
fi

# Index
./bwa-mem2 index ~/ecoli.fa 2>&1 | grep "Total time" || echo "Indexed"

# Generate test reads
python3 << 'PYSCRIPT' > ~/test_1k.fq 2>/dev/null
import random
genome = ""
with open("/home/ec2-user/ecoli.fa") as f:
    for line in f:
        if not line.startswith(">"): genome += line.strip()
for i in range(1000):
    pos = random.randint(0, len(genome) - 150)
    print(f"@read{i}\n{genome[pos:pos+150]}\n+\n{'I'*150}")
PYSCRIPT

# Run test
echo ""
echo "Running alignment (1K reads, 4 threads)..."
time ./bwa-mem2 mem -t 4 ~/ecoli.fa ~/test_1k.fq > /tmp/test.sam 2>&1

ALIGNMENTS=$(grep -v '^@' /tmp/test.sam | wc -l)
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "Results: $ALIGNMENTS alignments"
echo "═══════════════════════════════════════════════════════════════"

if [ $ALIGNMENTS -gt 900 ]; then
    echo "✅ $CPU_NAME: PASS"
    exit 0
else
    echo "⚠️  $CPU_NAME: Low alignment count"
    exit 1
fi
EOF

    local result=$?

    # Terminate instance
    echo "Terminating $name instance..."
    aws ec2 terminate-instances \
        --profile $AWS_PROFILE \
        --region $AWS_REGION \
        --instance-ids $instance_id &>/dev/null

    if [ $result -eq 0 ]; then
        echo "✅ $name: PASS"
        echo "$name PASS" >> /tmp/graviton_gcc14_results.txt
        return 0
    else
        echo "⚠️  $name: FAIL"
        echo "$name FAIL" >> /tmp/graviton_gcc14_results.txt
        return 1
    fi
}

# Clear results
rm -f /tmp/graviton_gcc14_results.txt

# Test each generation
test_generation "graviton2" "c6g.xlarge" || true
test_generation "graviton3" "c7g.xlarge" || true
test_generation "graviton3e" "c7gn.xlarge" || true
test_generation "graviton4" "c8g.xlarge" || true

# Summary
echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Results Summary (GCC 14.2.1 from AL2023 repos)"
echo "═══════════════════════════════════════════════════════════════"
echo ""

if [ -f /tmp/graviton_gcc14_results.txt ]; then
    cat /tmp/graviton_gcc14_results.txt | while read line; do
        echo "  $line"
    done
else
    echo "  No results"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo ""
