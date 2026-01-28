#!/bin/bash
#
# Phase 4 test script to run on each Graviton instance
# Usage: bash run-on-instance.sh
#

set -e

echo "=========================================="
echo "Phase 4 Performance Test"
echo "=========================================="
echo ""

# Detect platform
PLATFORM=$(grep "^model name" /proc/cpuinfo | head -1 | awk -F: '{print $2}' | xargs)
echo "Platform: $PLATFORM"
uname -a
echo ""

# Install dependencies
echo "Installing dependencies..."
sudo dnf install -y git gcc gcc-c++ make zlib-devel python3 bc 2>&1 | tail -5
echo ""

# Clone repository
echo "Cloning BWA-MEM2..."
cd ~
rm -rf bwa-mem2
git clone -b arm-graviton-optimization https://github.com/scttfrdmn/bwa-mem2.git
cd bwa-mem2
git submodule update --init --recursive
git log --oneline -3
echo ""

# Build optimized version
echo "Building OPTIMIZED version (prefetch + SIMD)..."
make arch="-march=armv8-a+simd" CXX=g++ EXE=bwa-mem2 all 2>&1 | tail -10
cp bwa-mem2 ~/bwa-mem2-optimized
echo "Optimized: $(ls -lh ~/bwa-mem2-optimized)"

# Build baseline version
echo "Building BASELINE version..."
git checkout 0243ef7 2>&1 | head -3
make clean 2>/dev/null || true
make arch="-march=armv8-a+simd" CXX=g++ EXE=bwa-mem2 all 2>&1 | tail -10
cp bwa-mem2 ~/bwa-mem2-baseline
git checkout arm-graviton-optimization 2>&1 | head -3
echo "Baseline: $(ls -lh ~/bwa-mem2-baseline)"
echo ""

# Download test data
echo "Downloading E. coli reference..."
cd ~
wget -q -O ecoli.fa.gz "https://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz"
gunzip ecoli.fa.gz
echo "Reference: $(wc -l ecoli.fa)"

# Generate test reads
echo "Generating test reads..."
python3 << 'PYTHON'
import random

# Read reference genome
with open('ecoli.fa', 'r') as f:
    lines = f.readlines()
    ref = ''.join([line.strip() for line in lines if not line.startswith('>')])

# Generate 10K random reads (reduced for faster testing)
num_reads = 10000
read_len = 150

with open('reads_1.fq', 'w') as f1, open('reads_2.fq', 'w') as f2:
    for i in range(num_reads):
        pos = random.randint(0, len(ref) - read_len - 1000)
        read1 = ref[pos:pos+read_len]
        read2 = ref[pos+300:pos+300+read_len]
        read1 = ''.join([c if random.random() > 0.01 else random.choice('ACGT') for c in read1])
        read2 = ''.join([c if random.random() > 0.01 else random.choice('ACGT') for c in read2])
        qual = 'I' * read_len
        f1.write(f'@read{i}/1\n{read1}\n+\n{qual}\n')
        f2.write(f'@read{i}/2\n{read2}\n+\n{qual}\n')
print(f'Generated {num_reads} reads')
PYTHON

echo "Reads: $(wc -l reads_*.fq)"
echo ""

# Index reference
echo "Indexing reference..."
~/bwa-mem2-optimized index ecoli.fa 2>&1 | tail -5
echo ""

# Run performance test
echo "=========================================="
echo "PERFORMANCE TEST"
echo "=========================================="
echo ""

# Baseline
echo "--- BASELINE (no optimizations) ---"
BASELINE_TIMES=()
for i in 1 2 3; do
    echo "  Run $i/3..."
    TIME_MS=$( { time ~/bwa-mem2-baseline mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /tmp/baseline.sam 2>&1; } 2>&1 | grep real | awk '{print $2}' | sed 's/[^0-9.]//g' | awk '{printf "%.0f\n", $1 * 1000}' )
    echo "    Time: ${TIME_MS}ms"
    BASELINE_TIMES+=("$TIME_MS")
done
BASELINE_AVG=$(( (${BASELINE_TIMES[0]} + ${BASELINE_TIMES[1]} + ${BASELINE_TIMES[2]}) / 3 ))
echo "Baseline average: ${BASELINE_AVG}ms"
echo ""

# Optimized
echo "--- OPTIMIZED (prefetch + SIMD) ---"
OPTIMIZED_TIMES=()
for i in 1 2 3; do
    echo "  Run $i/3..."
    TIME_MS=$( { time ~/bwa-mem2-optimized mem -t 4 ecoli.fa reads_1.fq reads_2.fq > /tmp/optimized.sam 2>&1; } 2>&1 | grep real | awk '{print $2}' | sed 's/[^0-9.]//g' | awk '{printf "%.0f\n", $1 * 1000}' )
    echo "    Time: ${TIME_MS}ms"
    OPTIMIZED_TIMES+=("$TIME_MS")
done
OPTIMIZED_AVG=$(( (${OPTIMIZED_TIMES[0]} + ${OPTIMIZED_TIMES[1]} + ${OPTIMIZED_TIMES[2]}) / 3 ))
echo "Optimized average: ${OPTIMIZED_AVG}ms"
echo ""

# Calculate improvement
DIFF=$((BASELINE_AVG - OPTIMIZED_AVG))
IMPROVEMENT=$(echo "scale=2; ($DIFF * 100.0) / $BASELINE_AVG" | bc)

# Correctness
BASELINE_MD5=$(md5sum /tmp/baseline.sam | awk '{print $1}')
OPTIMIZED_MD5=$(md5sum /tmp/optimized.sam | awk '{print $1}')

echo "=========================================="
echo "RESULTS ($PLATFORM)"
echo "=========================================="
echo ""
echo "Performance:"
echo "  Baseline:   ${BASELINE_AVG}ms"
echo "  Optimized:  ${OPTIMIZED_AVG}ms"
echo "  Improvement: ${IMPROVEMENT}%"
echo "  Target: 15.5-17.5%"
echo ""
echo "Correctness:"
if [ "$BASELINE_MD5" = "$OPTIMIZED_MD5" ]; then
    echo "  ✅ PASS: Outputs match"
else
    echo "  ❌ FAIL: Outputs differ!"
fi
echo ""
echo "=========================================="
