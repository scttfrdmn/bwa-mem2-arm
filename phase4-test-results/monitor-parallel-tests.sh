#!/bin/bash
#
# Phase 4 Parallel Test Monitor
# Monitors Graviton 3E and Graviton 4 tests running in parallel
#

G3E_IP="34.217.58.196"
G4_IP="52.27.75.98"
SSH_KEY="~/.ssh/cws-aws-west-2-key"

echo "=== Phase 4 Parallel Test Monitor ===" | tee -a monitor.log
echo "Started: $(date)" | tee -a monitor.log
echo "" | tee -a monitor.log

while true; do
    TIMESTAMP=$(date "+%Y-%m-%d %H:%M:%S")

    # Check Graviton 3E
    G3E_RUNNING=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G3E_IP 'ps aux | grep "bwa-mem2.*mem -t 4" | grep -v grep | wc -l' 2>/dev/null || echo "0")
    G3E_LATEST=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G3E_IP 'tail -5 test-output.log 2>/dev/null' || echo "No output yet")

    # Check Graviton 4
    G4_RUNNING=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G4_IP 'ps aux | grep "bwa-mem2.*mem -t 4" | grep -v grep | wc -l' 2>/dev/null || echo "0")
    G4_LATEST=$(ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G4_IP 'tail -5 test-output.log 2>/dev/null' || echo "No output yet")

    echo "[$TIMESTAMP] Status Check" | tee -a monitor.log
    echo "  Graviton 3E: $G3E_RUNNING BWA-MEM2 process(es)" | tee -a monitor.log
    echo "  Graviton 4:  $G4_RUNNING BWA-MEM2 process(es)" | tee -a monitor.log

    # Check if both tests are done
    if [ "$G3E_RUNNING" = "0" ] && [ "$G4_RUNNING" = "0" ]; then
        echo "" | tee -a monitor.log
        echo "[$TIMESTAMP] Both tests completed!" | tee -a monitor.log

        # Fetch final results
        echo "" | tee -a monitor.log
        echo "=== GRAVITON 3E RESULTS ===" | tee -a monitor.log
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G3E_IP 'tail -100 test-output.log' | tee -a graviton3e-results.log

        echo "" | tee -a monitor.log
        echo "=== GRAVITON 4 RESULTS ===" | tee -a monitor.log
        ssh -o StrictHostKeyChecking=no -i $SSH_KEY ec2-user@$G4_IP 'tail -100 test-output.log' | tee -a graviton4-results.log

        break
    fi

    # Wait 20 minutes before next check
    sleep 1200
done

echo "" | tee -a monitor.log
echo "Monitoring complete: $(date)" | tee -a monitor.log
