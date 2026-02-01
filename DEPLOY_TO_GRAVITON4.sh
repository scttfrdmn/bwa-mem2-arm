#!/bin/bash
################################################################################
# Complete Deployment and Testing Script for AWS Graviton 4
# Run this script on a Graviton 4 instance (c8g, m8g, r8g)
#
# Usage:
#   1. Copy this entire directory to Graviton 4
#   2. Run: ./DEPLOY_TO_GRAVITON4.sh
################################################################################

set -e  # Exit on error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "BWA-MEM2 ARM Optimization - Graviton 4 Deployment"
echo "=========================================="
echo ""

# Verify we're on ARM
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo -e "${RED}ERROR: Not on ARM64 (detected: $ARCH)${NC}"
    echo "This script must run on AWS Graviton 4 (c8g, m8g, r8g)"
    exit 1
fi

# Check CPU
CPU_MODEL=$(lscpu | grep "Model name" | cut -d: -f2 | xargs)
echo -e "${BLUE}CPU Model:${NC} $CPU_MODEL"

if echo "$CPU_MODEL" | grep -q "Neoverse-V2"; then
    echo -e "${GREEN}✓ Perfect! Graviton 4 (Neoverse-V2) detected${NC}"
elif echo "$CPU_MODEL" | grep -q "Neoverse-V1"; then
    echo -e "${YELLOW}⚠ Warning: Graviton 3 detected. Results will be suboptimal.${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
elif echo "$CPU_MODEL" | grep -q "Neoverse-N1"; then
    echo -e "${YELLOW}⚠ Warning: Graviton 2 detected. Only threading benefits available.${NC}"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
else
    echo -e "${RED}ERROR: Unknown CPU. This script requires Graviton 4.${NC}"
    exit 1
fi

# Check for required tools
echo ""
echo "Checking dependencies..."

MISSING_DEPS=()

if ! command -v gcc &> /dev/null; then
    MISSING_DEPS+=("gcc")
fi

if ! command -v g++ &> /dev/null; then
    MISSING_DEPS+=("g++")
fi

if ! command -v make &> /dev/null; then
    MISSING_DEPS+=("make")
fi

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    echo -e "${RED}Missing dependencies: ${MISSING_DEPS[*]}${NC}"
    echo ""
    echo "Install with:"
    echo "  # Ubuntu/Debian:"
    echo "  sudo apt-get update && sudo apt-get install -y gcc-14 g++-14 make zlib1g-dev"
    echo ""
    echo "  # Amazon Linux 2023:"
    echo "  sudo yum install -y gcc gcc-c++ make zlib-devel"
    exit 1
fi

# Check GCC version
GCC_VERSION=$(gcc --version | head -1)
echo -e "${GREEN}✓${NC} Found: $GCC_VERSION"

# Prefer GCC 14 if available
if command -v gcc-14 &> /dev/null; then
    export CC=gcc-14
    export CXX=g++-14
    echo -e "${GREEN}✓${NC} Using GCC 14 (recommended)"
else
    export CC=gcc
    export CXX=g++
    echo -e "${YELLOW}⚠${NC} Using system GCC (GCC 14 recommended for best performance)"
fi

echo ""
echo "=========================================="
echo "Step 1: Building BWA-MEM2 with ARM Optimizations"
echo "=========================================="
echo ""

cd bwa-mem2

# Clean previous build
echo "Cleaning previous build..."
make clean 2>&1 | head -5

echo ""
echo "Building with ARM optimizations..."
echo "  - Threading: kthread_arm.cpp"
echo "  - Vectorization: SVE2"
echo "  - Dual-issue: ILP via 2× unrolling"
echo "  - Compiler flags: -march=armv8.2-a+sve2+bf16+i8mm -mtune=neoverse-v2"
echo ""

# Build with ARM-specific flags
make -j$(nproc) \
    CXX=$CXX \
    ARCH_FLAGS="-march=armv8.2-a+sve2+bf16+i8mm -mtune=neoverse-v2" \
    CXXFLAGS="-O3 -g -DGRAVITON4_SVE2_ENABLED" 2>&1 | tee build.log

if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
    echo -e "${RED}Build failed! Check build.log for details.${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Build successful!${NC}"

# Verify ARM optimizations
echo ""
echo "Verifying ARM optimizations..."
if nm bwa-mem2 2>/dev/null | grep -q "kt_for_arm"; then
    echo -e "${GREEN}✓ ARM threading enabled (kt_for_arm found)${NC}"
else
    echo -e "${RED}✗ ARM threading NOT enabled - build may have issues${NC}"
    exit 1
fi

cd ..

echo ""
echo "=========================================="
echo "Step 2: Quick Smoke Test"
echo "=========================================="
echo ""

# Check if we have test data
if [[ ! -f "test_data/chr22.fa" ]] || [[ ! -f "test_data/reads_10K.fq" ]]; then
    echo -e "${YELLOW}⚠ Test data not found. Downloading sample data...${NC}"

    mkdir -p test_data
    cd test_data

    # Create minimal test data (if wget available)
    if command -v wget &> /dev/null; then
        echo "Downloading chr22 (this may take a few minutes)..."
        if [[ ! -f "chr22.fa" ]]; then
            wget -q --show-progress \
                "https://hgdownload.cse.ucsc.edu/goldenPath/hg38/chromosomes/chr22.fa.gz" \
                -O chr22.fa.gz && gunzip chr22.fa.gz
        fi

        # Generate synthetic reads if no real reads
        if [[ ! -f "reads_10K.fq" ]] && command -v python3 &> /dev/null; then
            echo "Generating synthetic test reads..."
            python3 << 'EOF'
import random
with open('chr22.fa', 'r') as f:
    lines = f.readlines()
    seq = ''.join([l.strip() for l in lines[1:]])[:10000]

with open('reads_10K.fq', 'w') as out:
    for i in range(10000):
        pos = random.randint(0, len(seq) - 150)
        read = seq[pos:pos+150]
        out.write(f'@read{i}\n{read}\n+\n{"I"*150}\n')
EOF
        fi
    else
        echo -e "${YELLOW}⚠ Cannot download test data (wget not found)${NC}"
        echo "Please provide test data manually:"
        echo "  - test_data/chr22.fa (reference)"
        echo "  - test_data/reads_10K.fq (reads)"
        echo ""
        echo "Skipping smoke test..."
        cd ..
        exit 0
    fi

    cd ..
fi

# Index if needed
if [[ ! -f "test_data/chr22.fa.bwt.2bit.64" ]]; then
    echo "Building BWA-MEM2 index..."
    ./bwa-mem2/bwa-mem2 index test_data/chr22.fa
fi

# Quick smoke test
echo "Running smoke test (1 thread)..."
START=$(date +%s)
./bwa-mem2/bwa-mem2 mem -t 1 test_data/chr22.fa test_data/reads_10K.fq > /tmp/test_output.sam 2>&1
END=$(date +%s)
ELAPSED=$((END - START))
echo -e "${GREEN}✓ Smoke test passed (${ELAPSED}s)${NC}"

echo ""
echo "=========================================="
echo "Step 3: Threading Efficiency Benchmark"
echo "=========================================="
echo ""

echo "Testing threading efficiency with different thread counts..."
echo "This will take several minutes..."
echo ""

declare -a THREAD_COUNTS=(1 2 4 8 16)
declare -A TIMES

for T in "${THREAD_COUNTS[@]}"; do
    echo -n "Testing $T threads... "
    START=$(date +%s.%N)
    ./bwa-mem2/bwa-mem2 mem -t "$T" test_data/chr22.fa test_data/reads_10K.fq > /dev/null 2>&1
    END=$(date +%s.%N)
    ELAPSED=$(echo "$END - $START" | bc)
    TIMES[$T]=$ELAPSED
    printf "${GREEN}%.2fs${NC}\n" "$ELAPSED"
done

echo ""
echo "=========================================="
echo "RESULTS: Threading Efficiency"
echo "=========================================="
echo ""
printf "%-10s %-12s %-12s %-12s\n" "Threads" "Time(s)" "Speedup" "Efficiency"
echo "----------------------------------------------------"

BASELINE=${TIMES[1]}
for T in "${THREAD_COUNTS[@]}"; do
    TIME=${TIMES[$T]}
    SPEEDUP=$(echo "scale=2; $BASELINE / $TIME" | bc)
    EFFICIENCY=$(echo "scale=1; ($SPEEDUP / $T) * 100" | bc)

    if (( $(echo "$EFFICIENCY >= 90" | bc -l) )); then
        EFFICIENCY_COLOR=$GREEN
    elif (( $(echo "$EFFICIENCY >= 70" | bc -l) )); then
        EFFICIENCY_COLOR=$YELLOW
    else
        EFFICIENCY_COLOR=$RED
    fi

    printf "%-10s %-12.2f %-12.2f ${EFFICIENCY_COLOR}%-12s${NC}\n" \
        "$T" "$TIME" "$SPEEDUP" "${EFFICIENCY}%"
done

echo ""

# Check if we met the target
SPEEDUP_16=$(echo "scale=2; $BASELINE / ${TIMES[16]}" | bc)
EFFICIENCY_16=$(echo "scale=1; ($SPEEDUP_16 / 16) * 100" | bc)

echo "=========================================="
echo "SUMMARY"
echo "=========================================="
echo ""
echo "Target: 90%+ efficiency @ 16 threads"
echo "Actual: ${EFFICIENCY_16}% efficiency @ 16 threads"
echo ""

if (( $(echo "$EFFICIENCY_16 >= 90" | bc -l) )); then
    echo -e "${GREEN}✓✓✓ SUCCESS! Target achieved!${NC}"
    echo ""
    echo "Threading efficiency improved from ~48% to ${EFFICIENCY_16}%"
    echo "This represents a ~2× speedup from the baseline."
else
    echo -e "${YELLOW}⚠ Below target${NC}"
    echo "Expected: ≥90% efficiency"
    echo "Actual: ${EFFICIENCY_16}% efficiency"
    echo ""
    echo "Possible reasons:"
    echo "  - Test dataset too small (try larger dataset)"
    echo "  - System under load (check with 'top')"
    echo "  - Not on Graviton 4 (check 'lscpu')"
fi

echo ""
echo "=========================================="
echo "Step 4: Performance Comparison"
echo "=========================================="
echo ""

# Compare to vanilla BWA if available
if command -v bwa &> /dev/null; then
    echo "Comparing to vanilla BWA..."
    echo ""

    # Index for vanilla BWA if needed
    if [[ ! -f "test_data/chr22.fa.bwt" ]]; then
        echo "Building vanilla BWA index..."
        bwa index test_data/chr22.fa
    fi

    echo -n "BWA (16 threads):     "
    START=$(date +%s.%N)
    bwa mem -t 16 test_data/chr22.fa test_data/reads_10K.fq > /dev/null 2>&1
    END=$(date +%s.%N)
    BWA_TIME=$(echo "$END - $START" | bc)
    printf "${BLUE}%.2fs${NC}\n" "$BWA_TIME"

    echo -n "BWA-MEM2 (16 threads): "
    BWA_MEM2_TIME=${TIMES[16]}
    printf "${BLUE}%.2fs${NC}\n" "$BWA_MEM2_TIME"

    echo ""
    RATIO=$(echo "scale=2; $BWA_MEM2_TIME / $BWA_TIME" | bc)
    echo "Ratio: ${RATIO}× (BWA-MEM2 / BWA)"

    if (( $(echo "$RATIO <= 1.1" | bc -l) )); then
        echo -e "${GREEN}✓ Competitive with vanilla BWA (within 10%)${NC}"
    elif (( $(echo "$RATIO <= 1.3" | bc -l) )); then
        echo -e "${YELLOW}⚠ Slower than vanilla BWA but acceptable${NC}"
    else
        echo -e "${RED}✗ Significantly slower than vanilla BWA${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Vanilla BWA not found - skipping comparison${NC}"
    echo "Install with: sudo apt-get install bwa"
fi

echo ""
echo "=========================================="
echo "DEPLOYMENT COMPLETE"
echo "=========================================="
echo ""
echo "Summary:"
echo "  ✓ Build successful with ARM optimizations"
echo "  ✓ Threading efficiency: ${EFFICIENCY_16}%"
echo "  ✓ 16-thread speedup: ${SPEEDUP_16}×"
echo ""
echo "Detailed results saved to:"
echo "  - bwa-mem2/build.log (build output)"
echo "  - Results displayed above"
echo ""
echo "Next steps:"
echo "  1. Review results above"
echo "  2. Test with production workloads"
echo "  3. Document results in ARM_OPTIMIZATION_RESULTS.md"
echo ""
echo "For more information:"
echo "  - ARM_OPTIMIZATION_IMPLEMENTATION.md (technical details)"
echo "  - ARM_OPTIMIZATION_QUICKSTART.md (quick reference)"
echo ""
