#!/bin/bash
#
# Quick launcher for AWS comparison test
#

set -e

cd "$(dirname "$0")"

# Load configuration
if [ ! -f .aws-test-config ]; then
    echo "ERROR: .aws-test-config not found"
    echo "Create it with your AWS settings first"
    exit 1
fi

source .aws-test-config

# Verify SSH key exists
if [ ! -f ~/.ssh/${AWS_KEY_NAME}.pem ] && [ ! -f ~/.ssh/${AWS_KEY_NAME} ]; then
    echo "WARNING: SSH key not found at ~/.ssh/${AWS_KEY_NAME}.pem or ~/.ssh/${AWS_KEY_NAME}"
    echo "Make sure your SSH key is accessible"
fi

echo ""
echo "Starting BWA-MEM2 ARM Correctness & Performance Test"
echo "===================================================="
echo ""
echo "This will:"
echo "  1. Launch 3 EC2 instances (Intel c7i, AMD c7a, ARM c7g)"
echo "  2. Build BWA-MEM2 on each architecture"
echo "  3. Run identical tests in parallel"
echo "  4. Compare correctness and performance"
echo "  5. Optionally terminate instances when done"
echo ""
echo "Estimated cost: ~\$0.50-1.00"
echo "Estimated time: 30-45 minutes"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Cancelled"
    exit 0
fi

# Run the test
./scripts/aws-comparison-test.sh
