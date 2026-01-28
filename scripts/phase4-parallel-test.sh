#!/bin/bash
#
# Phase 4 Parallel Testing - Graviton 3, 3E, and 4
# Tests prefetch + SIMD optimizations across all Graviton generations
#

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$PROJECT_ROOT/.aws-test-config"

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="$PROJECT_ROOT/phase4-test-results"
mkdir -p "$LOG_DIR"

echo "=========================================="
echo "Phase 4 Parallel Testing"
echo "=========================================="
echo "Testing on: Graviton 3E + Graviton 4"
echo "Timestamp: $TIMESTAMP"
echo ""

# Launch Graviton 3E (c7gn instance)
echo "=== Launching Graviton 3E (c7gn.xlarge) ==="
G3E_INSTANCE=$(AWS_PROFILE=aws aws ec2 run-instances \
    --region us-west-2 \
    --image-id ami-0cbac0f1d6260a580 \
    --instance-type c7gn.xlarge \
    --key-name cws-aws-west-2-key \
    --security-group-ids sg-0e849a974f163c1d9 \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=phase4-graviton3e},{Key=Project,Value=bwa-mem2-phase4}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "Graviton 3E Instance: $G3E_INSTANCE"

# Launch Graviton 4 (c8g instance)
echo "=== Launching Graviton 4 (c8g.xlarge) ==="
G4_INSTANCE=$(AWS_PROFILE=aws aws ec2 run-instances \
    --region us-west-2 \
    --image-id ami-0cbac0f1d6260a580 \
    --instance-type c8g.xlarge \
    --key-name cws-aws-west-2-key \
    --security-group-ids sg-0e849a974f163c1d9 \
    --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=phase4-graviton4},{Key=Project,Value=bwa-mem2-phase4}]" \
    --query 'Instances[0].InstanceId' \
    --output text)
echo "Graviton 4 Instance: $G4_INSTANCE"

echo ""
echo "Waiting for instances to start..."
AWS_PROFILE=aws aws ec2 wait instance-running --region us-west-2 --instance-ids $G3E_INSTANCE $G4_INSTANCE

# Get IPs
G3E_IP=$(AWS_PROFILE=aws aws ec2 describe-instances --region us-west-2 --instance-ids $G3E_INSTANCE --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
G4_IP=$(AWS_PROFILE=aws aws ec2 describe-instances --region us-west-2 --instance-ids $G4_INSTANCE --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "Graviton 3E IP: $G3E_IP"
echo "Graviton 4 IP: $G4_IP"
echo ""

# Save instance info
cat > "$LOG_DIR/parallel-instances-${TIMESTAMP}.txt" << EOF
Graviton 3E: $G3E_INSTANCE ($G3E_IP)
Graviton 4:  $G4_INSTANCE ($G4_IP)
EOF

echo "=========================================="
echo "Instances launched successfully!"
echo "Instance IDs saved to: $LOG_DIR/parallel-instances-${TIMESTAMP}.txt"
echo ""
echo "Next: SSH to each instance and run the test script"
echo ""
echo "Commands to run tests:"
echo "  # Graviton 3E:"
echo "  ssh -i ~/.ssh/cws-aws-west-2-key ec2-user@$G3E_IP"
echo ""
echo "  # Graviton 4:"
echo "  ssh -i ~/.ssh/cws-aws-west-2-key ec2-user@$G4_IP"
echo ""
echo "=========================================="
