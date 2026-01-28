#!/bin/bash
#
# Phase 4 Performance Test Monitor
# Checks test progress every 20 minutes
#

INSTANCE_IP="54.203.65.92"
SSH_KEY="~/.ssh/cws-aws-west-2-key"
LOG_FILE="/Users/scttfrdmn/src/bwa-mem2-arm/phase4-test-results/test-progress.log"

echo "=== Phase 4 Test Monitor ===" | tee -a "$LOG_FILE"
echo "Started: $(date)" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Check if BWA-MEM2 is still running
    RUNNING=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$INSTANCE_IP 'ps aux | grep bwa-mem2 | grep -v grep | wc -l' 2>/dev/null)

    if [ "$RUNNING" -gt 0 ]; then
        # Get current process info
        PROCESS=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$INSTANCE_IP 'ps aux | grep bwa-mem2 | grep -v grep | head -1' 2>/dev/null)
        echo "[$TIMESTAMP] Test still running..." | tee -a "$LOG_FILE"
        echo "  Process: $PROCESS" | tee -a "$LOG_FILE"
    else
        echo "[$TIMESTAMP] Test appears to have completed!" | tee -a "$LOG_FILE"

        # Try to get results
        RESULTS=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$INSTANCE_IP 'tail -100 /tmp/phase4_test_output.log 2>/dev/null || echo "Results file not found"')
        echo "$RESULTS" | tee -a "$LOG_FILE"
        break
    fi

    # Wait 20 minutes before next check
    sleep 1200
done

echo "" | tee -a "$LOG_FILE"
echo "Monitoring complete: $(date)" | tee -a "$LOG_FILE"
