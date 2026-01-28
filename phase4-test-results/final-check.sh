#!/bin/bash
# Final results checker for Phase 4 performance test

TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")
echo "[$TIMESTAMP] Checking for Phase 4 test completion..."

# Check if the test output has the final results
if grep -q "RESULTS:" /private/tmp/claude/-Users-scttfrdmn-src-bwa-mem2-arm/tasks/ba215c8.output 2>/dev/null; then
    echo "✅ Test complete! Extracting results..."
    echo ""
    tail -100 /private/tmp/claude/-Users-scttfrdmn-src-bwa-mem2-arm/tasks/ba215c8.output
    exit 0
else
    # Get current progress
    LATEST=$(tail -10 /private/tmp/claude/-Users-scttfrdmn-src-bwa-mem2-arm/tasks/ba215c8.output 2>/dev/null)
    RUNNING=$(ssh -o StrictHostKeyChecking=no -i ~/.ssh/cws-aws-west-2-key ec2-user@54.203.65.92 'ps aux | grep "bwa-mem2.*mem -t 4" | grep -v grep | wc -l' 2>/dev/null || echo "0")

    echo "⏳ Test still in progress..."
    echo "   BWA-MEM2 processes running: $RUNNING"
    echo ""
    echo "Latest output:"
    echo "$LATEST"
    exit 1
fi
