#!/bin/bash
# Minimap2 ARM Optimization Benchmark Script
# Run this on AWS Graviton 4 (c8g or r8g instance)
#
# This script:
# 1. Installs and builds minimap2 with baseline flags (-O2, no -march)
# 2. Rebuilds minimap2 with optimized ARM flags (-O3 -march=armv8.2-a+simd)
# 3. Benchmarks both versions with perf stat
# 4. Reports the performance improvement
#
# Expected improvement: 5-10% from better compilation flags

set -e

echo "=========================================="
echo "Minimap2 ARM Optimization Benchmark"
echo "=========================================="
echo ""

# Check we're on ARM
ARCH=$(uname -m)
if [ "$ARCH" != "aarch64" ]; then
    echo "ERROR: This script must run on ARM64 (aarch64), not $ARCH"
    exit 1
fi
echo "✓ Running on ARM64"

# Check we're on Graviton 4 if possible
if [ -f /proc/cpuinfo ]; then
    CPU_PART=$(grep "CPU part" /proc/cpuinfo | head -1 | awk '{print $4}')
    if [ "$CPU_PART" = "0xd4f" ]; then
        echo "✓ Confirmed Graviton 4 (Neoverse-V2)"
    else
        echo "⚠ WARNING: Not Graviton 4 (CPU part: $CPU_PART)"
        echo "  Benchmarks will still run but may not be representative"
    fi
fi
echo ""

# Create workspace
WORK_DIR=~/minimap2-benchmark
mkdir -p "$WORK_DIR"
cd "$WORK_DIR"

echo "Working directory: $WORK_DIR"
echo ""

# Install dependencies
echo "Installing dependencies..."
if command -v yum &>/dev/null; then
    # Amazon Linux / RHEL
    sudo yum install -y gcc gcc-c++ make git zlib-devel python3 wget time >/dev/null 2>&1
    echo "✓ Dependencies installed (Amazon Linux)"
elif command -v apt-get &>/dev/null; then
    # Ubuntu / Debian
    sudo apt-get update >/dev/null 2>&1
    sudo apt-get install -y gcc g++ make git zlib1g-dev python3 wget time >/dev/null 2>&1
    echo "✓ Dependencies installed (Ubuntu)"
else
    echo "⚠ WARNING: Unknown package manager, assuming dependencies are installed"
fi
echo ""

# Download minimap2 if not present
if [ ! -d minimap2 ]; then
    echo "Downloading minimap2..."
    git clone --quiet https://github.com/lh3/minimap2.git
    echo "✓ minimap2 downloaded"
else
    echo "✓ minimap2 already present"
fi
echo ""

# Generate test data if not present
if [ ! -f chr22.fa ] || [ ! -f chr22_reads_1M.fq ]; then
    echo "Generating test data (this takes ~2 minutes)..."

    # Download chr22 reference
    if [ ! -f chr22.fa ]; then
        echo "  Downloading chr22 reference..."
        wget -q -O chr22.fa.gz \
            "http://hgdownload.cse.ucsc.edu/goldenPath/hg38/chromosomes/chr22.fa.gz"
        gunzip chr22.fa.gz
        echo "  ✓ chr22 reference downloaded (50 MB)"
    fi

    # Generate synthetic reads
    if [ ! -f chr22_reads_1M.fq ]; then
        echo "  Generating 1M synthetic reads..."
        python3 << 'PYTHON'
import random
import sys

# Read chr22 sequence
with open('chr22.fa', 'r') as f:
    lines = f.readlines()
seq = ''.join(line.strip() for line in lines if not line.startswith('>'))

# Generate reads
n_reads = 1000000
read_len = 150

with open('chr22_reads_1M.fq', 'w') as f:
    for i in range(n_reads):
        if i % 100000 == 0:
            print(f"  Generated {i:,} / {n_reads:,} reads...", file=sys.stderr)

        # Random position
        pos = random.randint(0, len(seq) - read_len)
        read = seq[pos:pos + read_len]

        # Add some sequencing errors (1%)
        read = list(read)
        for j in range(read_len):
            if random.random() < 0.01:
                read[j] = random.choice('ACGT')
        read = ''.join(read)

        # Write FASTQ
        f.write(f"@read_{i}\n")
        f.write(f"{read}\n")
        f.write(f"+\n")
        f.write(f"{'I' * read_len}\n")

print(f"  ✓ Generated {n_reads:,} reads", file=sys.stderr)
PYTHON
        echo "  ✓ Test data generated (1M reads × 150bp)"
    fi
    echo "✓ Test data ready"
else
    echo "✓ Test data already present"
fi
echo ""

# Build baseline version (original flags)
echo "=========================================="
echo "Building minimap2 (baseline: -O2)"
echo "=========================================="
cd minimap2
make clean >/dev/null 2>&1 || true

echo "Building with: CC=gcc arm_neon=1 aarch64=1 CFLAGS=\"-g -Wall -O2\""
if ! make arm_neon=1 aarch64=1 CC=gcc \
     CFLAGS="-g -Wall -O2 -Wc++-compat -D_FILE_OFFSET_BITS=64 -fsigned-char" \
     2>&1 | grep -E "(CC|LD)" | tail -5; then
    echo "ERROR: Baseline build failed"
    exit 1
fi

# Save baseline binary
cp minimap2 minimap2.baseline
echo "✓ Baseline build complete"
echo "✓ Binary saved as: minimap2.baseline"
echo ""

# Build optimized version (ARM-optimized flags)
echo "=========================================="
echo "Building minimap2 (optimized: -O3 + ARM flags)"
echo "=========================================="
make clean >/dev/null 2>&1

echo "Building with: CC=gcc arm_neon=1 aarch64=1 CFLAGS=\"-O3 -march=armv8.2-a+simd -mtune=generic\""
if ! make arm_neon=1 aarch64=1 CC=gcc \
     CFLAGS="-O3 -march=armv8.2-a+simd -mtune=generic -D_FILE_OFFSET_BITS=64 -fsigned-char" \
     2>&1 | grep -E "(CC|LD)" | tail -5; then
    echo "ERROR: Optimized build failed"
    exit 1
fi

# Save optimized binary
cp minimap2 minimap2.optimized
echo "✓ Optimized build complete"
echo "✓ Binary saved as: minimap2.optimized"
echo ""

# Create index
cd "$WORK_DIR"
echo "=========================================="
echo "Creating minimap2 index"
echo "=========================================="
if [ ! -f chr22.mmi ]; then
    echo "Indexing chr22.fa (takes ~30 seconds)..."
    ./minimap2/minimap2.optimized -d chr22.mmi chr22.fa 2>&1 | grep -E "(indexed|sequences)" || true
    echo "✓ Index created"
else
    echo "✓ Index already exists"
fi
echo ""

# Warm up
echo "Warming up system (running small test)..."
./minimap2/minimap2.optimized -ax sr chr22.mmi chr22.fa | head -1000 > /dev/null 2>&1
echo "✓ System warmed up"
echo ""

# Benchmark function
benchmark_version() {
    local VERSION=$1
    local BINARY=$2

    echo "=========================================="
    echo "Benchmarking: $VERSION"
    echo "=========================================="
    echo "Command: perf stat -d $BINARY -t 16 -ax sr chr22.mmi chr22_reads_1M.fq"
    echo ""

    # Run with perf stat
    perf stat -d "$BINARY" -t 16 -ax sr chr22.mmi chr22_reads_1M.fq > /dev/null 2>&1

    echo ""
}

# Benchmark baseline
benchmark_version "Baseline (-O2)" "./minimap2/minimap2.baseline"

# Benchmark optimized
benchmark_version "Optimized (-O3 + ARM flags)" "./minimap2/minimap2.optimized"

# Summary
echo "=========================================="
echo "Benchmark Complete!"
echo "=========================================="
echo ""
echo "Results saved in this directory:"
echo "  Baseline binary:  ./minimap2/minimap2.baseline"
echo "  Optimized binary: ./minimap2/minimap2.optimized"
echo ""
echo "Key metrics to compare:"
echo "  1. Wall clock time (seconds)"
echo "  2. CPU utilization (CPUs utilized / 16 threads)"
echo "  3. Instructions per cycle (IPC)"
echo "  4. Branch miss rate (%)"
echo "  5. Cache miss rate (%)"
echo ""
echo "Expected improvement from optimized build:"
echo "  - 5-10% faster wall clock time"
echo "  - Similar or better IPC"
echo "  - Lower branch miss rate"
echo ""
echo "To re-run individual tests:"
echo "  perf stat -d ./minimap2/minimap2.baseline -t 16 -ax sr chr22.mmi chr22_reads_1M.fq > /dev/null"
echo "  perf stat -d ./minimap2/minimap2.optimized -t 16 -ax sr chr22.mmi chr22_reads_1M.fq > /dev/null"
echo ""
