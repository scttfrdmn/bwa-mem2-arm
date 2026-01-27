#!/bin/bash
################################################################################
# AWS Graviton Testing Commands
# Copy and paste these commands into your AWS instance terminal
################################################################################

echo "═══════════════════════════════════════════════════════════════"
echo "  BWA-MEM2 Phase 1 - AWS Graviton Testing"
echo "═══════════════════════════════════════════════════════════════"
echo ""

# Step 1: Install dependencies
echo "Step 1: Installing dependencies..."
sudo yum update -y
sudo yum install -y gcc gcc-c++ make zlib-devel python3 wget git

# Step 2: Extract deployment package (if you uploaded the tar.gz)
echo ""
echo "Step 2: Extracting deployment package..."
if [ -f phase1-deploy.tar.gz ]; then
    tar xzf phase1-deploy.tar.gz
    cd bwa-mem2-arm
    echo "✅ Extracted from phase1-deploy.tar.gz"
elif [ -d bwa-mem2-arm ]; then
    cd bwa-mem2-arm
    echo "✅ Already in bwa-mem2-arm directory"
else
    echo "❌ ERROR: Cannot find deployment package or directory"
    echo "Please upload phase1-deploy.tar.gz first"
    exit 1
fi

# Step 3: Initialize submodules
echo ""
echo "Step 3: Initializing git submodules..."
cd bwa-mem2
git submodule update --init --recursive
cd ..

# Step 4: Run tests
echo ""
echo "Step 4: Running Phase 1 tests..."
echo "This will take approximately 15-20 minutes..."
echo ""
chmod +x test-phase1.sh
./test-phase1.sh full

echo ""
echo "═══════════════════════════════════════════════════════════════"
echo "  Testing Complete!"
echo "═══════════════════════════════════════════════════════════════"
