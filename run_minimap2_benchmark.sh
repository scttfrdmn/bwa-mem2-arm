#!/bin/bash
# Launch Graviton 4 instance and run minimap2 benchmark
#
# Usage:
#   ./run_minimap2_benchmark.sh [instance-id]
#
# If instance-id is provided, uses that instance
# Otherwise, helps you find or launch an instance

set -e

# Load AWS config
if [ -f .aws-test-config ]; then
    source .aws-test-config
fi

echo "=========================================="
echo "Minimap2 Graviton 4 Benchmark Launcher"
echo "=========================================="
echo ""

# Check if instance-id provided
if [ -n "$1" ]; then
    INSTANCE_ID="$1"
    echo "Using provided instance: $INSTANCE_ID"
else
    echo "Checking for running Graviton 4 instances..."

    # List running ARM instances
    RUNNING_INSTANCES=$(aws ec2 describe-instances \
        --filters "Name=instance-state-name,Values=running" \
                  "Name=architecture,Values=arm64" \
        --query 'Reservations[].Instances[].[InstanceId,InstanceType,PublicIpAddress,State.Name]' \
        --output text 2>/dev/null || true)

    if [ -z "$RUNNING_INSTANCES" ]; then
        echo ""
        echo "No running ARM instances found."
        echo ""
        echo "To launch a Graviton 4 instance, use:"
        echo "  ./launch_graviton4_test.sh"
        echo ""
        echo "Or manually launch and provide instance ID:"
        echo "  $0 <instance-id>"
        echo ""
        exit 1
    fi

    echo ""
    echo "Found running ARM instances:"
    echo "$RUNNING_INSTANCES"
    echo ""
    echo "Enter instance ID to use:"
    read -r INSTANCE_ID

    if [ -z "$INSTANCE_ID" ]; then
        echo "No instance ID provided. Exiting."
        exit 1
    fi
fi

# Get instance info
echo ""
echo "Getting instance details..."
INSTANCE_INFO=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].[PublicIpAddress,InstanceType,State.Name]' \
    --output text 2>/dev/null)

if [ -z "$INSTANCE_INFO" ]; then
    echo "ERROR: Instance $INSTANCE_ID not found"
    exit 1
fi

PUBLIC_IP=$(echo "$INSTANCE_INFO" | awk '{print $1}')
INSTANCE_TYPE=$(echo "$INSTANCE_INFO" | awk '{print $2}')
STATE=$(echo "$INSTANCE_INFO" | awk '{print $3}')

echo "Instance: $INSTANCE_ID"
echo "Type: $INSTANCE_TYPE"
echo "State: $STATE"
echo "IP: $PUBLIC_IP"

if [ "$STATE" != "running" ]; then
    echo "ERROR: Instance is not running (state: $STATE)"
    exit 1
fi

# Determine SSH key
if [ -f ~/.ssh/bwa-mem2-test-key.pem ]; then
    SSH_KEY=~/.ssh/bwa-mem2-test-key.pem
elif [ -f ~/.ssh/cws-aws-west-2-key.pem ]; then
    SSH_KEY=~/.ssh/cws-aws-west-2-key.pem
else
    echo ""
    echo "Enter path to SSH private key:"
    read -r SSH_KEY
    if [ ! -f "$SSH_KEY" ]; then
        echo "ERROR: SSH key not found: $SSH_KEY"
        exit 1
    fi
fi

SSH_OPTS="-i $SSH_KEY -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"

# Test SSH connection
echo ""
echo "Testing SSH connection..."
if ! ssh $SSH_OPTS ec2-user@"$PUBLIC_IP" "echo 'Connected'" &>/dev/null; then
    echo "ERROR: Cannot connect to $PUBLIC_IP"
    echo "Trying ubuntu@ instead of ec2-user@..."
    if ! ssh $SSH_OPTS ubuntu@"$PUBLIC_IP" "echo 'Connected'" &>/dev/null; then
        echo "ERROR: Cannot connect with either ec2-user or ubuntu"
        exit 1
    fi
    SSH_USER="ubuntu"
else
    SSH_USER="ec2-user"
fi

echo "✓ SSH connection successful (user: $SSH_USER)"
echo ""

# Upload benchmark script
echo "Uploading benchmark script..."
scp $SSH_OPTS benchmark_minimap2_graviton4.sh "$SSH_USER@$PUBLIC_IP":~/
echo "✓ Upload complete"
echo ""

# Run benchmark
echo "=========================================="
echo "Running minimap2 benchmark on Graviton 4"
echo "=========================================="
echo ""
echo "This will take approximately 10-15 minutes:"
echo "  - Installing dependencies: ~2 min"
echo "  - Downloading test data: ~1 min"
echo "  - Generating synthetic reads: ~2 min"
echo "  - Building minimap2 (2 versions): ~2 min"
echo "  - Benchmarking (2 runs): ~5-10 min"
echo ""
echo "Starting benchmark..."
echo ""

ssh $SSH_OPTS "$SSH_USER@$PUBLIC_IP" 'bash -s' << 'ENDSSH'
chmod +x benchmark_minimap2_graviton4.sh
./benchmark_minimap2_graviton4.sh 2>&1 | tee minimap2_benchmark_output.log
ENDSSH

# Download results
echo ""
echo "=========================================="
echo "Downloading results"
echo "=========================================="
scp $SSH_OPTS "$SSH_USER@$PUBLIC_IP":~/minimap2_benchmark_output.log ./minimap2_benchmark_results.txt
echo "✓ Results saved to: minimap2_benchmark_results.txt"
echo ""

echo "=========================================="
echo "Benchmark Complete!"
echo "=========================================="
echo ""
echo "Results: ./minimap2_benchmark_results.txt"
echo ""
echo "Instance $INSTANCE_ID is still running."
echo "To terminate:"
echo "  aws ec2 terminate-instances --instance-ids $INSTANCE_ID"
echo ""
