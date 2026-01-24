#!/bin/bash
set -e

echo "=== Setting up BWA-MEM2 ARM Development Environment ==="

# Install build dependencies
sudo yum install -y gcc-c++ git make zlib-devel

# Check architecture
ARCH=$(uname -m)
echo "Architecture: $ARCH"

if [ "$ARCH" != "aarch64" ]; then
    echo "WARNING: Not running on ARM64. Cross-compilation not yet supported."
    exit 1
fi

# Clone BWA-MEM2 if not already present
if [ ! -d "bwa-mem2" ]; then
    git clone https://github.com/bwa-mem2/bwa-mem2.git
fi

cd bwa-mem2

# Initialize submodules
git submodule update --init --recursive

echo ""
echo "Environment ready!"
echo ""
echo "Next steps:"
echo "  1. Analyze SSE usage: grep -r 'emmintrin\|smmintrin' src/"
echo "  2. Create ARM compatibility layer"
echo "  3. Attempt build: make arch=native"
