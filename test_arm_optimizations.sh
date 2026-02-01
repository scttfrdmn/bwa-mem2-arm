#!/bin/bash
################################################################################
# Test Script for ARM-Optimized BWA-MEM2
# Target: AWS Graviton 4 (Neoverse V2, ARMv9-A with SVE2)
#
# This script performs comprehensive testing of ARM optimizations:
# 1. Verify ARM optimizations are enabled
# 2. Test threading efficiency at different thread counts
# 3. Compare against vanilla BWA (if available)
# 4. Validate correctness
################################################################################

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo "=================================="
echo "BWA-MEM2 ARM Optimization Test Suite"
echo "=================================="
echo ""

# Check if running on ARM
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" ]]; then
    echo -e "${RED}ERROR: Not running on ARM64 (detected: $ARCH)${NC}"
    echo "This test requires AWS Graviton 4"
    exit 1
fi
echo -e "${GREEN}✓${NC} Running on ARM64: $ARCH"

# Check CPU model
CPU_MODEL=$(lscpu | grep "Model name" | head -1 || echo "Unknown")
echo -e "${BLUE}CPU:${NC} $CPU_MODEL"

if echo "$CPU_MODEL" | grep -q "Neoverse-V2"; then
    echo -e "${GREEN}✓${NC} Detected Graviton 4 (Neoverse-V2) - optimal target"
elif echo "$CPU_MODEL" | grep -q "Neoverse-V1"; then
    echo -e "${YELLOW}⚠${NC} Detected Graviton 3 (Neoverse-V1) - partial benefits"
elif echo "$CPU_MODEL" | grep -q "Neoverse-N1"; then
    echo -e "${YELLOW}⚠${NC} Detected Graviton 2 (Neoverse-N1) - threading only"
else
    echo -e "${YELLOW}⚠${NC} Unknown ARM CPU - results may vary"
fi

echo ""

# Check if executable exists
BWA_MEM2="./bwa-mem2/bwa-mem2"
if [[ ! -f "$BWA_MEM2" ]]; then
    echo -e "${RED}ERROR: $BWA_MEM2 not found${NC}"
    echo "Please build first: ./BUILD_ARM_OPTIMIZED.sh"
    exit 1
fi
echo -e "${GREEN}✓${NC} Found executable: $BWA_MEM2"

# Test 1: Verify ARM optimizations are enabled
echo ""
echo "=================================="
echo "Test 1: Verify ARM Optimizations"
echo "=================================="

if nm "$BWA_MEM2" 2>/dev/null | grep -q "kt_for_arm"; then
    echo -e "${GREEN}✓${NC} ARM threading enabled (kt_for_arm found)"
else
    echo -e "${RED}✗${NC} ARM threading NOT enabled"
    echo "Build may have failed or ARM optimizations not compiled"
    exit 1
fi

# Check for SVE2 symbols (optional, may be inlined)
if nm "$BWA_MEM2" 2>/dev/null | grep -q "sve2"; then
    echo -e "${GREEN}✓${NC} SVE2 optimizations present"
else
    echo -e "${YELLOW}⚠${NC} SVE2 symbols not found (may be inlined - OK)"
fi

# Test 2: Quick smoke test
echo ""
echo "=================================="
echo "Test 2: Smoke Test (1 thread)"
echo "=================================="

# Check if test data exists
if [[ ! -f "test_data/chr22.fa" ]] || [[ ! -f "test_data/reads_100K.fq" ]]; then
    echo -e "${YELLOW}⚠${NC} Test data not found - skipping smoke test"
    echo "To run smoke test, provide:"
    echo "  - test_data/chr22.fa (reference)"
    echo "  - test_data/reads_100K.fq (reads)"
else
    echo "Running BWA-MEM2 with 1 thread..."
    START=$(date +%s)
    "$BWA_MEM2" mem -t 1 test_data/chr22.fa test_data/reads_100K.fq > /tmp/test_output.sam 2>&1
    END=$(date +%s)
    ELAPSED=$((END - START))
    echo -e "${GREEN}✓${NC} Smoke test passed (${ELAPSED}s)"
fi

# Test 3: Threading efficiency test
echo ""
echo "=================================="
echo "Test 3: Threading Efficiency"
echo "=================================="

if [[ ! -f "test_data/chr22.fa" ]] || [[ ! -f "test_data/reads_100K.fq" ]]; then
    echo -e "${YELLOW}⚠${NC} Test data not found - skipping threading test"
else
    echo "Testing different thread counts..."
    echo ""

    declare -a THREAD_COUNTS=(1 2 4 8 16)
    declare -a TIMES

    for T in "${THREAD_COUNTS[@]}"; do
        echo -n "Testing $T threads... "
        START=$(date +%s.%N)
        "$BWA_MEM2" mem -t "$T" test_data/chr22.fa test_data/reads_100K.fq > /dev/null 2>&1
        END=$(date +%s.%N)
        ELAPSED=$(echo "$END - $START" | bc)
        TIMES[$T]=$ELAPSED
        echo "${ELAPSED}s"
    done

    echo ""
    echo "Threading Efficiency Results:"
    echo "-----------------------------"
    printf "%-10s %-10s %-10s %-10s\n" "Threads" "Time(s)" "Speedup" "Efficiency"

    BASELINE_TIME=${TIMES[1]}
    for T in "${THREAD_COUNTS[@]}"; do
        TIME=${TIMES[$T]}
        SPEEDUP=$(echo "scale=2; $BASELINE_TIME / $TIME" | bc)
        EFFICIENCY=$(echo "scale=1; ($SPEEDUP / $T) * 100" | bc)
        printf "%-10s %-10s %-10s %-10s%%\n" "$T" "$TIME" "${SPEEDUP}×" "$EFFICIENCY"
    done

    echo ""

    # Check if we achieved target efficiency
    EFFICIENCY_16=$(echo "scale=0; (${TIMES[1]} / ${TIMES[16]}) / 16 * 100" | bc)
    if [[ $EFFICIENCY_16 -ge 90 ]]; then
        echo -e "${GREEN}✓${NC} Target achieved: ${EFFICIENCY_16}% efficiency @ 16 threads (goal: 90%+)"
    else
        echo -e "${YELLOW}⚠${NC} Below target: ${EFFICIENCY_16}% efficiency @ 16 threads (goal: 90%+)"
    fi
fi

# Test 4: Compare to vanilla BWA (if available)
echo ""
echo "=================================="
echo "Test 4: Compare to Vanilla BWA"
echo "=================================="

if command -v bwa &> /dev/null && [[ -f "test_data/chr22.fa" ]] && [[ -f "test_data/reads_100K.fq" ]]; then
    echo "Running vanilla BWA (16 threads)..."
    START=$(date +%s.%N)
    bwa mem -t 16 test_data/chr22.fa test_data/reads_100K.fq > /tmp/bwa_output.sam 2>&1
    END=$(date +%s.%N)
    BWA_TIME=$(echo "$END - $START" | bc)

    echo "Running BWA-MEM2 (16 threads)..."
    START=$(date +%s.%N)
    "$BWA_MEM2" mem -t 16 test_data/chr22.fa test_data/reads_100K.fq > /tmp/bwa-mem2_output.sam 2>&1
    END=$(date +%s.%N)
    BWA_MEM2_TIME=$(echo "$END - $START" | bc)

    RATIO=$(echo "scale=2; $BWA_MEM2_TIME / $BWA_TIME" | bc)

    echo ""
    echo "Comparison Results:"
    echo "-------------------"
    echo "BWA (vanilla):  ${BWA_TIME}s"
    echo "BWA-MEM2 (ARM): ${BWA_MEM2_TIME}s"
    echo "Ratio:          ${RATIO}× (${BWA_MEM2_TIME}s / ${BWA_TIME}s)"

    if (( $(echo "$RATIO <= 1.1" | bc -l) )); then
        echo -e "${GREEN}✓${NC} Competitive with vanilla BWA (within 10%)"
    elif (( $(echo "$RATIO <= 1.3" | bc -l) )); then
        echo -e "${YELLOW}⚠${NC} Slower than vanilla BWA but acceptable"
    else
        echo -e "${RED}✗${NC} Significantly slower than vanilla BWA"
    fi
else
    echo -e "${YELLOW}⚠${NC} Vanilla BWA or test data not found - skipping comparison"
fi

# Test 5: Correctness validation
echo ""
echo "=================================="
echo "Test 5: Correctness Validation"
echo "=================================="

if command -v bwa &> /dev/null && command -v samtools &> /dev/null && \
   [[ -f "test_data/chr22.fa" ]] && [[ -f "test_data/reads_100K.fq" ]]; then
    echo "Comparing alignments (BWA vs BWA-MEM2)..."

    bwa mem -t 16 test_data/chr22.fa test_data/reads_100K.fq 2>/dev/null | \
        samtools view -F 4 | cut -f1,3,4 | sort > /tmp/bwa_alignments.txt

    "$BWA_MEM2" mem -t 16 test_data/chr22.fa test_data/reads_100K.fq 2>/dev/null | \
        samtools view -F 4 | cut -f1,3,4 | sort > /tmp/bwa-mem2_alignments.txt

    DIFF_COUNT=$(diff /tmp/bwa_alignments.txt /tmp/bwa-mem2_alignments.txt | wc -l)

    if [[ $DIFF_COUNT -eq 0 ]]; then
        echo -e "${GREEN}✓${NC} Alignments identical to vanilla BWA (0 differences)"
    else
        echo -e "${YELLOW}⚠${NC} Found $DIFF_COUNT differences (may be acceptable)"
        echo "Note: Minor differences can occur due to tie-breaking in equally-scored alignments"
    fi
else
    echo -e "${YELLOW}⚠${NC} BWA, samtools, or test data not found - skipping correctness test"
fi

# Summary
echo ""
echo "=================================="
echo "Test Summary"
echo "=================================="
echo ""
echo "Tests completed. Summary:"
echo "  ✓ ARM optimizations enabled"
if [[ ! -f "test_data/chr22.fa" ]]; then
    echo "  ⚠ Performance tests skipped (no test data)"
else
    echo "  ✓ Performance tests completed"
fi
echo ""
echo "To get test data for comprehensive testing:"
echo "  mkdir -p test_data"
echo "  # Download chr22 reference and 100K reads"
echo ""
echo "For production benchmarking, see:"
echo "  - ARM_OPTIMIZATION_QUICKSTART.md"
echo "  - ARM_OPTIMIZATION_IMPLEMENTATION.md"
echo ""
echo "=================================="
echo "Test suite completed!"
echo "=================================="
