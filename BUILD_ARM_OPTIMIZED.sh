#!/bin/bash
################################################################################
# Build Script for ARM-Optimized BWA-MEM2
# Target: AWS Graviton 4 (Neoverse V2, ARMv9-A with SVE2)
#
# This script builds BWA-MEM2 with ARM-specific optimizations:
# - Phase 1: ARM-optimized threading (kthread_arm.cpp)
# - Phase 2: Vectorized SoA transpose (SVE2)
# - Phase 3: Dual-issue ILP (unrolled DP loop)
# - Phase 4: Integration with fastmap
#
# Expected Performance:
# - Threading efficiency: 48% → 90%+ (16 threads)
# - 16-thread time: 2.20s → 1.10s (2× improvement)
################################################################################

set -e  # Exit on error
set -x  # Print commands

echo "=================================="
echo "Building ARM-Optimized BWA-MEM2"
echo "=================================="

# Check if running on ARM
ARCH=$(uname -m)
if [[ "$ARCH" != "aarch64" && "$ARCH" != "arm64" ]]; then
    echo "WARNING: Not running on ARM architecture (detected: $ARCH)"
    echo "This build is optimized for AWS Graviton 4"
    echo "Continuing anyway for cross-compilation testing..."
fi

# Check for GCC 14 (recommended for ARM optimizations)
if command -v gcc-14 &> /dev/null; then
    GCC=gcc-14
    GXX=g++-14
    echo "Using GCC 14: $GCC"
elif command -v gcc &> /dev/null; then
    GCC=gcc
    GXX=g++
    GCC_VERSION=$(gcc --version | head -1)
    echo "Using system GCC: $GCC_VERSION"
else
    echo "ERROR: GCC not found"
    exit 1
fi

# Clean previous build
cd bwa-mem2
make clean

# Build with ARM optimizations
echo ""
echo "Building with ARM optimizations..."
echo "  - ARM threading: kthread_arm.cpp"
echo "  - Vectorized transpose: bandedSWA_arm_sve2.cpp"
echo "  - Dual-issue ILP: unrolled DP loop"
echo ""

# Build command with ARM-specific flags
make -j$(nproc 2>/dev/null || echo 4) \
    CXX=$GXX \
    ARCH_FLAGS="-march=armv8.2-a+sve2+bf16+i8mm -mtune=neoverse-v2" \
    CXXFLAGS="-O3 -g -DGRAVITON4_SVE2_ENABLED"

echo ""
echo "=================================="
echo "Build completed successfully!"
echo "=================================="
echo ""
echo "Executable: bwa-mem2/bwa-mem2"
echo ""
echo "To test threading efficiency:"
echo "  ./bwa-mem2/bwa-mem2 mem -t 1,2,4,8,16 ref.fa reads.fq"
echo ""
echo "Expected improvements:"
echo "  - 16-thread speedup: ~14-15× (vs 7.9× baseline)"
echo "  - Threading efficiency: 90%+ (vs 48% baseline)"
echo ""
