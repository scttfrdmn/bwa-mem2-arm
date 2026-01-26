#!/bin/bash
#
# AWS x86 vs ARM Correctness & Performance Comparison
# Launches matching x86 and ARM instances, runs identical tests, compares results
#

set -e

# Configuration
AWS_PROFILE="${AWS_PROFILE:-aws}"
REGION="${AWS_REGION:-us-east-1}"
KEY_NAME="${AWS_KEY_NAME:-bwa-mem2-test}"
SECURITY_GROUP="${AWS_SECURITY_GROUP}"
SUBNET_ID="${AWS_SUBNET_ID}"

# Instance types (7th gen - matching compute resources, 4 vCPU, 8 GB RAM)
INTEL_INSTANCE="c7i.xlarge"   # Intel Xeon Scalable (Sapphire Rapids)
AMD_INSTANCE="c7a.xlarge"     # AMD EPYC (Genoa)
ARM_INSTANCE="c7g.xlarge"     # AWS Graviton3 (Neoverse V1)

# AMIs will be auto-detected based on architecture

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
    sync  # Flush to disk
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
    sync
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    sync
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
    sync
}

check_prerequisites() {
    log "Checking prerequisites..."

    if ! command -v aws &> /dev/null; then
        error "AWS CLI not found. Install with: brew install awscli"
        exit 1
    fi

    if ! aws configure get aws_access_key_id --profile $AWS_PROFILE &> /dev/null; then
        error "AWS profile '$AWS_PROFILE' not configured"
        exit 1
    fi

    if [ -z "$SECURITY_GROUP" ]; then
        error "Please set AWS_SECURITY_GROUP environment variable"
        exit 1
    fi

    log "Prerequisites OK"
}

get_ami() {
    local arch=$1

    # Get latest Amazon Linux 2023 AMI for the architecture
    local ami=$(aws ec2 describe-images \
        --profile $AWS_PROFILE \
        --region $REGION \
        --owners amazon \
        --filters "Name=name,Values=al2023-ami-2023.*-kernel-*-$arch" \
                  "Name=state,Values=available" \
        --query 'sort_by(Images, &CreationDate)[-1].ImageId' \
        --output text)

    echo "$ami"
}

launch_instance() {
    local instance_type=$1
    local arch=$2
    local arch_name=$3

    log "Launching $arch_name instance ($instance_type)..."

    # Get appropriate AMI
    local ami=$(get_ami $arch)
    info "Using AMI: $ami"

    local instance_id=$(aws ec2 run-instances \
        --profile $AWS_PROFILE \
        --region $REGION \
        --instance-type $instance_type \
        --image-id $ami \
        --key-name $KEY_NAME \
        --security-group-ids $SECURITY_GROUP \
        --subnet-id $SUBNET_ID \
        --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-test-$arch_name},{Key=Project,Value=bwa-mem2-arm}]" \
        --query 'Instances[0].InstanceId' \
        --output text)

    log "Instance ID: $instance_id"

    # Wait for instance to be running
    log "Waiting for instance to start..."
    aws ec2 wait instance-running \
        --profile $AWS_PROFILE \
        --region $REGION \
        --instance-ids $instance_id

    # Get public IP
    local public_ip=$(aws ec2 describe-instances \
        --profile $AWS_PROFILE \
        --region $REGION \
        --instance-ids $instance_id \
        --query 'Reservations[0].Instances[0].PublicIpAddress' \
        --output text)

    log "$arch_name instance ready at: $public_ip"

    # Wait for SSH to be ready
    log "Waiting for SSH..."
    local ssh_key="$HOME/.ssh/${AWS_KEY_NAME}"
    [ ! -f "$ssh_key" ] && ssh_key="${ssh_key}.pem"
    local max_attempts=30
    local attempt=0
    while [ $attempt -lt $max_attempts ]; do
        if ssh -i "$ssh_key" -o StrictHostKeyChecking=no -o ConnectTimeout=5 ec2-user@$public_ip "echo 'SSH ready'" &> /dev/null; then
            log "SSH connection established"
            break
        fi
        attempt=$((attempt + 1))
        sleep 10
    done

    if [ $attempt -eq $max_attempts ]; then
        error "SSH connection timeout"
        exit 1
    fi

    echo "$instance_id|$public_ip"
}

setup_instance() {
    local ip=$1
    local arch=$2
    local compiler=$3

    log "Setting up $arch instance..."

    local ssh_key="$HOME/.ssh/${AWS_KEY_NAME}"
    [ ! -f "$ssh_key" ] && ssh_key="${ssh_key}.pem"

    ssh -i "$ssh_key" ec2-user@$ip bash << 'REMOTE_SETUP'
set -e

# Update system
sudo yum update -y

# Install dependencies
sudo yum install -y gcc-c++ git make zlib-devel time

# Clone repository with ARM support
git clone https://github.com/scttfrdmn/bwa-mem2.git
cd bwa-mem2
git checkout arm-graviton-optimization
git submodule update --init --recursive

# Build
echo "Building BWA-MEM2..."
make arch=native CXX=g++ all

# Verify build
./bwa-mem2 version
file ./bwa-mem2

# Show CPU info
echo ""
echo "=== CPU Information ==="
lscpu | grep -E "Architecture|Model name|CPU\(s\)|Thread|Core|Socket|Flags"
cat /proc/cpuinfo | grep -E "model name|flags" | head -2

# Show memory
echo ""
echo "=== Memory ==="
free -h

echo ""
echo "Setup complete!"
REMOTE_SETUP

    log "$arch instance setup complete"
}

download_test_data() {
    local ip=$1

    log "Downloading test dataset to instance..."

    local ssh_key="$HOME/.ssh/${AWS_KEY_NAME}"
    [ ! -f "$ssh_key" ] && ssh_key="${ssh_key}.pem"

    ssh -i "$ssh_key" ec2-user@$ip bash << 'REMOTE_DATA'
set -e
cd bwa-mem2

# Create test directory
mkdir -p test_data
cd test_data

# Download test reads from BWA repository
echo "Downloading test reads..."
wget -q https://github.com/lh3/bwa/raw/master/test/bwa-mem_test1.fq
wget -q https://github.com/lh3/bwa/raw/master/test/bwa-mem_test2.fq

# Create small test reference (E. coli, ~4.6 MB)
echo "Downloading E. coli reference genome..."
wget -q ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz
gunzip GCF_000005845.2_ASM584v2_genomic.fna.gz
mv GCF_000005845.2_ASM584v2_genomic.fna ecoli.fa

# Show sizes
echo ""
echo "=== Test Data ==="
ls -lh
echo ""
echo "Reference: $(wc -l ecoli.fa) lines"
echo "Reads 1: $(wc -l bwa-mem_test1.fq) lines"
echo "Reads 2: $(wc -l bwa-mem_test2.fq) lines"

cd ..
echo "Test data ready!"
REMOTE_DATA

    log "Test data downloaded"
}

run_test() {
    local ip=$1
    local arch=$2
    local threads=$3

    log "Running BWA-MEM2 test on $arch..."

    local ssh_key="$HOME/.ssh/${AWS_KEY_NAME}"
    [ ! -f "$ssh_key" ] && ssh_key="${ssh_key}.pem"

    ssh -i "$ssh_key" ec2-user@$ip bash << REMOTE_TEST
set -e
cd bwa-mem2

echo "=== BWA-MEM2 $arch Test ==="
echo "Architecture: \$(uname -m)"
echo "Threads: $threads"
echo ""

# Index the reference
echo "Indexing reference genome..."
/usr/bin/time -v ./bwa-mem2 index test_data/ecoli.fa 2>&1 | tee index_$arch.log

# Run alignment (single-end)
echo ""
echo "Running alignment (single-end)..."
/usr/bin/time -v ./bwa-mem2 mem -t $threads test_data/ecoli.fa test_data/bwa-mem_test1.fq > test_data/output_se_$arch.sam 2>&1 | tee align_se_$arch.log

# Run alignment (paired-end)
echo ""
echo "Running alignment (paired-end)..."
/usr/bin/time -v ./bwa-mem2 mem -t $threads test_data/ecoli.fa test_data/bwa-mem_test1.fq test_data/bwa-mem_test2.fq > test_data/output_pe_$arch.sam 2>&1 | tee align_pe_$arch.log

# Validate SAM files
echo ""
echo "Validating SAM output..."
grep -v "^@" test_data/output_se_$arch.sam | wc -l
grep -v "^@" test_data/output_pe_$arch.sam | wc -l

# Extract timing information
echo ""
echo "=== Performance Summary ==="
grep "Elapsed" index_$arch.log align_se_$arch.log align_pe_$arch.log
grep "Maximum resident set size" index_$arch.log align_se_$arch.log align_pe_$arch.log

echo ""
echo "Test complete!"
REMOTE_TEST

    log "$arch test complete"
}

download_results() {
    local ip=$1
    local arch=$2
    local output_dir=$3

    log "Downloading results from $arch instance..."

    local ssh_key="$HOME/.ssh/${AWS_KEY_NAME}"
    [ ! -f "$ssh_key" ] && ssh_key="${ssh_key}.pem"

    mkdir -p $output_dir

    # Download SAM files
    scp -i "$ssh_key" ec2-user@$ip:bwa-mem2/test_data/output_se_$arch.sam $output_dir/
    scp -i "$ssh_key" ec2-user@$ip:bwa-mem2/test_data/output_pe_$arch.sam $output_dir/

    # Download logs
    scp -i "$ssh_key" ec2-user@$ip:bwa-mem2/index_$arch.log $output_dir/
    scp -i "$ssh_key" ec2-user@$ip:bwa-mem2/align_se_$arch.log $output_dir/
    scp -i "$ssh_key" ec2-user@$ip:bwa-mem2/align_pe_$arch.log $output_dir/

    log "Results downloaded to $output_dir/"
}

compare_results_three() {
    local output_dir=$1

    log "Comparing Intel vs AMD vs ARM results..."

    echo ""
    info "=== CORRECTNESS COMPARISON (7th Gen) ==="
    echo ""

    # Compare single-end results
    echo "Single-end alignment correctness:"

    # Intel vs AMD
    if diff -q $output_dir/output_se_intel.sam $output_dir/output_se_amd.sam > /dev/null; then
        echo -e "  ${GREEN}✓ Intel ↔ AMD: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ Intel ↔ AMD: DIFFER${NC} (alignment counts: Intel=$(grep -v "^@" $output_dir/output_se_intel.sam | wc -l), AMD=$(grep -v "^@" $output_dir/output_se_amd.sam | wc -l))"
    fi

    # Intel vs ARM
    if diff -q $output_dir/output_se_intel.sam $output_dir/output_se_arm.sam > /dev/null; then
        echo -e "  ${GREEN}✓ Intel ↔ ARM: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ Intel ↔ ARM: DIFFER${NC} (alignment counts: Intel=$(grep -v "^@" $output_dir/output_se_intel.sam | wc -l), ARM=$(grep -v "^@" $output_dir/output_se_arm.sam | wc -l))"
    fi

    # AMD vs ARM
    if diff -q $output_dir/output_se_amd.sam $output_dir/output_se_arm.sam > /dev/null; then
        echo -e "  ${GREEN}✓ AMD ↔ ARM: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ AMD ↔ ARM: DIFFER${NC} (alignment counts: AMD=$(grep -v "^@" $output_dir/output_se_amd.sam | wc -l), ARM=$(grep -v "^@" $output_dir/output_se_arm.sam | wc -l))"
    fi

    echo ""
    echo "Paired-end alignment correctness:"

    # Intel vs AMD
    if diff -q $output_dir/output_pe_intel.sam $output_dir/output_pe_amd.sam > /dev/null; then
        echo -e "  ${GREEN}✓ Intel ↔ AMD: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ Intel ↔ AMD: DIFFER${NC}"
    fi

    # Intel vs ARM
    if diff -q $output_dir/output_pe_intel.sam $output_dir/output_pe_arm.sam > /dev/null; then
        echo -e "  ${GREEN}✓ Intel ↔ ARM: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ Intel ↔ ARM: DIFFER${NC}"
    fi

    # AMD vs ARM
    if diff -q $output_dir/output_pe_amd.sam $output_dir/output_pe_arm.sam > /dev/null; then
        echo -e "  ${GREEN}✓ AMD ↔ ARM: IDENTICAL${NC}"
    else
        echo -e "  ${YELLOW}✗ AMD ↔ ARM: DIFFER${NC}"
    fi

    echo ""
    info "=== PERFORMANCE COMPARISON (7th Gen) ==="
    echo ""

    # Extract and compare performance metrics
    echo "Indexing time:"
    printf "  Intel (c7i): %s\n" "$(grep "Elapsed" $output_dir/index_intel.log | awk '{print $8}')"
    printf "  AMD   (c7a): %s\n" "$(grep "Elapsed" $output_dir/index_amd.log | awk '{print $8}')"
    printf "  ARM   (c7g): %s\n" "$(grep "Elapsed" $output_dir/index_arm.log | awk '{print $8}')"

    echo ""
    echo "Single-end alignment time:"
    printf "  Intel (c7i): %s\n" "$(grep "Elapsed" $output_dir/align_se_intel.log | awk '{print $8}')"
    printf "  AMD   (c7a): %s\n" "$(grep "Elapsed" $output_dir/align_se_amd.log | awk '{print $8}')"
    printf "  ARM   (c7g): %s\n" "$(grep "Elapsed" $output_dir/align_se_arm.log | awk '{print $8}')"

    echo ""
    echo "Paired-end alignment time:"
    printf "  Intel (c7i): %s\n" "$(grep "Elapsed" $output_dir/align_pe_intel.log | awk '{print $8}')"
    printf "  AMD   (c7a): %s\n" "$(grep "Elapsed" $output_dir/align_pe_amd.log | awk '{print $8}')"
    printf "  ARM   (c7g): %s\n" "$(grep "Elapsed" $output_dir/align_pe_arm.log | awk '{print $8}')"

    echo ""
    echo "Memory usage (single-end):"
    printf "  Intel (c7i): %.0f MB\n" "$(grep "Maximum resident" $output_dir/align_se_intel.log | awk '{print $6/1024}')"
    printf "  AMD   (c7a): %.0f MB\n" "$(grep "Maximum resident" $output_dir/align_se_amd.log | awk '{print $6/1024}')"
    printf "  ARM   (c7g): %.0f MB\n" "$(grep "Maximum resident" $output_dir/align_se_arm.log | awk '{print $6/1024}')"

    # Calculate relative performance
    echo ""
    info "=== PERFORMANCE ANALYSIS ==="
    echo ""

    local intel_time=$(grep "Elapsed" $output_dir/align_pe_intel.log | awk '{print $8}' | sed 's/://' | awk -F: '{print ($1 * 60) + $2}')
    local amd_time=$(grep "Elapsed" $output_dir/align_pe_amd.log | awk '{print $8}' | sed 's/://' | awk -F: '{print ($1 * 60) + $2}')
    local arm_time=$(grep "Elapsed" $output_dir/align_pe_arm.log | awk '{print $8}' | sed 's/://' | awk -F: '{print ($1 * 60) + $2}')

    echo "ARM (Graviton3) vs Intel (Sapphire Rapids):"
    if [ -n "$intel_time" ] && [ -n "$arm_time" ]; then
        local arm_vs_intel=$(awk "BEGIN {printf \"%.1f\", ($intel_time / $arm_time) * 100}")
        echo "  ARM is ${arm_vs_intel}% of Intel speed"
    fi

    echo ""
    echo "ARM (Graviton3) vs AMD (Genoa):"
    if [ -n "$amd_time" ] && [ -n "$arm_time" ]; then
        local arm_vs_amd=$(awk "BEGIN {printf \"%.1f\", ($amd_time / $arm_time) * 100}")
        echo "  ARM is ${arm_vs_amd}% of AMD speed"
    fi
}

cleanup_instances() {
    local instance_ids=$1

    warn "Terminating instances: $instance_ids"
    read -p "Terminate instances? (y/n) " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        aws ec2 terminate-instances \
            --profile $AWS_PROFILE \
            --region $REGION \
            --instance-ids $instance_ids
        log "Instances terminated"
    else
        info "Instances left running. Clean up manually:"
        echo "  aws ec2 terminate-instances --instance-ids $instance_ids"
    fi
}

# Main execution
main() {
    log "Starting BWA-MEM2 x86 vs ARM comparison test"
    echo ""

    check_prerequisites

    # Launch instances (7th gen for fair comparison)
    info "Launching 7th generation instances for comparison:"
    echo "  - Intel: $INTEL_INSTANCE (Sapphire Rapids)"
    echo "  - AMD:   $AMD_INSTANCE (Genoa)"
    echo "  - ARM:   $ARM_INSTANCE (Graviton3)"
    echo ""

    INTEL_INFO=$(launch_instance $INTEL_INSTANCE "x86_64" "intel")
    INTEL_ID=$(echo $INTEL_INFO | cut -d'|' -f1)
    INTEL_IP=$(echo $INTEL_INFO | cut -d'|' -f2)

    AMD_INFO=$(launch_instance $AMD_INSTANCE "x86_64" "amd")
    AMD_ID=$(echo $AMD_INFO | cut -d'|' -f1)
    AMD_IP=$(echo $AMD_INFO | cut -d'|' -f2)

    ARM_INFO=$(launch_instance $ARM_INSTANCE "arm64" "arm")
    ARM_ID=$(echo $ARM_INFO | cut -d'|' -f1)
    ARM_IP=$(echo $ARM_INFO | cut -d'|' -f2)

    echo ""
    info "Instances launched:"
    echo "  Intel ($INTEL_INSTANCE): $INTEL_IP (ID: $INTEL_ID)"
    echo "  AMD   ($AMD_INSTANCE):   $AMD_IP   (ID: $AMD_ID)"
    echo "  ARM   ($ARM_INSTANCE):   $ARM_IP   (ID: $ARM_ID)"
    echo ""

    # Setup all instances sequentially (parallel SSH doesn't work well with nohup)
    log "Setting up Intel instance..."
    setup_instance $INTEL_IP "intel" "g++"
    log "Intel setup complete"

    log "Setting up AMD instance..."
    setup_instance $AMD_IP "amd" "g++"
    log "AMD setup complete"

    log "Setting up ARM instance..."
    setup_instance $ARM_IP "arm" "g++"
    log "ARM setup complete"

    # Download test data to all instances sequentially
    log "Downloading test data to Intel instance..."
    download_test_data $INTEL_IP

    log "Downloading test data to AMD instance..."
    download_test_data $AMD_IP

    log "Downloading test data to ARM instance..."
    download_test_data $ARM_IP

    log "Test data downloaded to all instances"

    # Run tests sequentially
    log "Running tests on Intel..."
    run_test $INTEL_IP "intel" 4

    log "Running tests on AMD..."
    run_test $AMD_IP "amd" 4

    log "Running tests on ARM..."
    run_test $ARM_IP "arm" 4

    log "All tests complete"

    # Download and compare results
    OUTPUT_DIR="./test_results_$(date +%Y%m%d_%H%M%S)"
    mkdir -p $OUTPUT_DIR

    download_results $INTEL_IP "intel" $OUTPUT_DIR
    download_results $AMD_IP "amd" $OUTPUT_DIR
    download_results $ARM_IP "arm" $OUTPUT_DIR

    # Compare all three
    log "Comparing results across all architectures..."
    compare_results_three "$OUTPUT_DIR"

    echo ""
    log "All tests complete! Results saved to: $OUTPUT_DIR"
    echo ""

    # Cleanup
    cleanup_instances "$INTEL_ID $AMD_ID $ARM_ID"
}

# Run if executed directly
if [ "${BASH_SOURCE[0]}" == "${0}" ]; then
    main "$@"
fi
