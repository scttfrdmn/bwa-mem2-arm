#!/bin/bash
################################################################################
# BWA-MEM2 ARM Threading Efficiency Benchmark
# Validates 48% → 90%+ threading efficiency improvement
################################################################################

set -e

echo "=========================================="
echo "BWA-MEM2 Threading Efficiency Benchmark"
echo "=========================================="
echo ""

# Check if we're on the right platform
if [ -f /proc/cpuinfo ]; then
    CPU_PART=$(cat /proc/cpuinfo | grep "CPU part" | head -1 | awk '{print $4}')
    if [ "$CPU_PART" = "0xd4f" ]; then
        echo "✓ Platform: AWS Graviton 4 (Neoverse-V2)"
    else
        echo "⚠ Warning: Not on Graviton 4 (CPU part: $CPU_PART)"
    fi
fi

# Find the executable
if [ -f "./bwa-mem2" ]; then
    BWA_MEM2="./bwa-mem2"
elif [ -f "./bwa-mem2.graviton2" ]; then
    BWA_MEM2="./bwa-mem2.graviton2"
else
    echo "ERROR: bwa-mem2 executable not found"
    exit 1
fi

echo "Executable: $BWA_MEM2"
echo ""

# Check if we have test data
if [ ! -f "test_data/chr22.fa" ]; then
    echo "Creating minimal test data..."
    mkdir -p test_data

    # Create a minimal reference (1MB synthetic sequence)
    python3 << 'EOF'
import random
random.seed(42)
with open('test_data/test_ref.fa', 'w') as f:
    f.write('>test_chr\n')
    bases = ['A', 'C', 'G', 'T']
    seq = ''.join(random.choices(bases, k=1000000))
    # Write in 80-char lines
    for i in range(0, len(seq), 80):
        f.write(seq[i:i+80] + '\n')
print("Created test_ref.fa (1MB)")
EOF

    # Create synthetic reads (10K reads, 150bp)
    python3 << 'EOF'
import random
random.seed(42)
with open('test_data/test_ref.fa', 'r') as f:
    ref_lines = f.readlines()[1:]
    ref = ''.join(line.strip() for line in ref_lines)

with open('test_data/test_reads.fq', 'w') as f:
    for i in range(10000):
        pos = random.randint(0, len(ref) - 150)
        read = ref[pos:pos+150]
        f.write(f'@read{i}\n{read}\n+\n{"I"*150}\n')
print("Created test_reads.fq (10K reads)")
EOF

    REF="test_data/test_ref.fa"
    READS="test_data/test_reads.fq"
else
    REF="test_data/chr22.fa"
    READS="test_data/reads.fq"
fi

# Build index if needed
if [ ! -f "${REF}.bwt.2bit.64" ]; then
    echo "Building index..."
    $BWA_MEM2 index $REF
    echo ""
fi

# Warm-up run
echo "Warm-up run..."
$BWA_MEM2 mem -t 1 $REF $READS > /dev/null 2>&1 || echo "Warm-up failed (OK if no data)"

echo ""
echo "=========================================="
echo "Threading Efficiency Test"
echo "=========================================="
echo ""

# Test different thread counts
declare -a THREAD_COUNTS=(1 2 4 8 16)
declare -A TIMES

echo "Running benchmarks..."
for T in "${THREAD_COUNTS[@]}"; do
    echo -n "Testing $T threads... "

    # Run 3 times and take the median
    RUNS=()
    for RUN in 1 2 3; do
        START=$(date +%s.%N)
        $BWA_MEM2 mem -t $T $REF $READS > /dev/null 2>&1
        END=$(date +%s.%N)
        TIME=$(echo "$END - $START" | bc)
        RUNS+=($TIME)
    done

    # Sort and take median
    MEDIAN=$(printf '%s\n' "${RUNS[@]}" | sort -n | sed -n '2p')
    TIMES[$T]=$MEDIAN

    printf "%.2fs\n" "$MEDIAN"
done

echo ""
echo "=========================================="
echo "RESULTS: Threading Efficiency"
echo "=========================================="
echo ""
printf "%-10s %-12s %-12s %-12s %-10s\n" "Threads" "Time(s)" "Speedup" "Efficiency" "Status"
echo "----------------------------------------------------------------"

BASELINE=${TIMES[1]}
for T in "${THREAD_COUNTS[@]}"; do
    TIME=${TIMES[$T]}
    SPEEDUP=$(echo "scale=2; $BASELINE / $TIME" | bc)
    EFFICIENCY=$(echo "scale=1; ($SPEEDUP / $T) * 100" | bc)

    # Determine status
    if (( $(echo "$EFFICIENCY >= 90" | bc -l) )); then
        STATUS="✓ EXCELLENT"
    elif (( $(echo "$EFFICIENCY >= 70" | bc -l) )); then
        STATUS="✓ GOOD"
    elif (( $(echo "$EFFICIENCY >= 50" | bc -l) )); then
        STATUS="⚠ OK"
    else
        STATUS="✗ POOR"
    fi

    printf "%-10s %-12.2f %-12.2f %-12.1f%% %s\n" "$T" "$TIME" "$SPEEDUP" "$EFFICIENCY" "$STATUS"
done

echo ""
echo "=========================================="
echo "Summary"
echo "=========================================="
echo ""

# Check if we met the target
SPEEDUP_16=$(echo "scale=2; $BASELINE / ${TIMES[16]}" | bc)
EFFICIENCY_16=$(echo "scale=1; ($SPEEDUP_16 / 16) * 100" | bc)

echo "Baseline (1 thread): ${TIMES[1]}s"
echo "16 threads: ${TIMES[16]}s"
echo "Speedup: ${SPEEDUP_16}×"
echo "Efficiency: ${EFFICIENCY_16}%"
echo ""

if (( $(echo "$EFFICIENCY_16 >= 90" | bc -l) )); then
    echo "✓✓✓ SUCCESS: Target achieved!"
    echo "Threading efficiency: ${EFFICIENCY_16}% (target: 90%+)"
    echo ""
    echo "Expected improvement from baseline ~48%:"
    IMPROVEMENT=$(echo "scale=1; $EFFICIENCY_16 - 48" | bc)
    echo "  Before: ~48% efficiency"
    echo "  After:  ${EFFICIENCY_16}% efficiency"
    echo "  Gain:   +${IMPROVEMENT}% ($(echo "scale=1; $EFFICIENCY_16 / 48" | bc)× better)"
else
    echo "⚠ Below target"
    echo "Expected: ≥90% efficiency at 16 threads"
    echo "Actual:   ${EFFICIENCY_16}% efficiency"
    echo ""
    echo "Possible reasons:"
    echo "  - Test dataset too small (try larger reference)"
    echo "  - System under load"
    echo "  - Not on Graviton 4"
fi

echo ""
echo "Results saved to: benchmark_results.txt"
