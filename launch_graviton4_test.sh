#!/bin/bash
################################################################################
# Launch AWS Graviton 4 Instance and Deploy ARM Optimizations
# Usage: AWS_PROFILE=aws ./launch_graviton4_test.sh
################################################################################

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "=========================================="
echo "AWS Graviton 4 Launch & Test"
echo "=========================================="
echo ""

# Check AWS CLI
if ! command -v aws &> /dev/null; then
    echo -e "${RED}ERROR: AWS CLI not found${NC}"
    echo "Install with: brew install awscli"
    exit 1
fi

# Check AWS profile
if [[ -z "$AWS_PROFILE" ]]; then
    echo -e "${YELLOW}WARNING: AWS_PROFILE not set, using default${NC}"
    echo "To use specific profile: AWS_PROFILE=aws ./launch_graviton4_test.sh"
else
    echo -e "${GREEN}✓${NC} Using AWS Profile: $AWS_PROFILE"
fi

# Check SSH key
if [[ ! -f ~/.ssh/id_rsa.pub ]]; then
    echo -e "${RED}ERROR: SSH key not found at ~/.ssh/id_rsa.pub${NC}"
    echo "Generate with: ssh-keygen -t rsa -b 4096"
    exit 1
fi

# Configuration
INSTANCE_TYPE="c8g.4xlarge"
INSTANCE_NAME="bwa-mem2-graviton4-test"
AMI_ID="ami-0bb7267a511c0a8e8"  # Amazon Linux 2023 ARM64 (us-east-1)
REGION="us-east-1"
KEY_NAME="bwa-mem2-test-key"

echo ""
echo "Configuration:"
echo "  Instance Type: $INSTANCE_TYPE (16 vCPUs)"
echo "  AMI: Amazon Linux 2023 ARM64"
echo "  Region: $REGION"
echo "  Est. Cost: ~\$0.69/hour (~\$0.35 for 30min test)"
echo ""

read -p "Continue? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
fi

# Check if key pair exists in AWS
echo ""
echo "Checking for SSH key pair in AWS..."
if aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" &>/dev/null; then
    echo -e "${GREEN}✓${NC} Key pair exists: $KEY_NAME"
else
    echo -e "${YELLOW}Creating new key pair: $KEY_NAME${NC}"
    aws ec2 import-key-pair \
        --key-name "$KEY_NAME" \
        --public-key-material fileb://~/.ssh/id_rsa.pub \
        --region "$REGION"
    echo -e "${GREEN}✓${NC} Key pair created"
fi

# Launch instance
echo ""
echo "Launching Graviton 4 instance..."
INSTANCE_ID=$(aws ec2 run-instances \
    --image-id "$AMI_ID" \
    --instance-type "$INSTANCE_TYPE" \
    --key-name "$KEY_NAME" \
    --region "$REGION" \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=50,VolumeType=gp3}' \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$INSTANCE_NAME}]" \
    --query 'Instances[0].InstanceId' \
    --output text)

echo -e "${GREEN}✓${NC} Instance launched: $INSTANCE_ID"
echo ""

# Wait for instance to be running
echo "Waiting for instance to start..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID" --region "$REGION"
echo -e "${GREEN}✓${NC} Instance running"

# Get public IP
PUBLIC_IP=$(aws ec2 describe-instances \
    --instance-ids "$INSTANCE_ID" \
    --region "$REGION" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text)

echo -e "${GREEN}✓${NC} Public IP: $PUBLIC_IP"

# Wait for SSH to be available
echo ""
echo "Waiting for SSH to be available (this may take 1-2 minutes)..."
for i in {1..30}; do
    if ssh -o StrictHostKeyChecking=no -o ConnectTimeout=5 ubuntu@$PUBLIC_IP exit &>/dev/null; then
        echo -e "${GREEN}✓${NC} SSH ready"
        break
    fi
    echo -n "."
    sleep 10
done
echo ""

# Package code
echo ""
echo "Packaging code for transfer..."
cd "$(dirname "$0")"
tar czf /tmp/bwa-mem2-arm.tar.gz \
    --exclude='.git' \
    --exclude='bwa-mem2/.git' \
    --exclude='*.o' \
    --exclude='bwa-mem2' \
    --exclude='phase4-test-results' \
    .

echo -e "${GREEN}✓${NC} Code packaged: /tmp/bwa-mem2-arm.tar.gz"

# Transfer code
echo ""
echo "Transferring code to Graviton 4..."
scp -o StrictHostKeyChecking=no /tmp/bwa-mem2-arm.tar.gz ec2-user@$PUBLIC_IP:~/
echo -e "${GREEN}✓${NC} Code transferred"

# Install dependencies and run test
echo ""
echo "=========================================="
echo "Running Deployment Script on Graviton 4"
echo "=========================================="
echo ""

ssh -o StrictHostKeyChecking=no ec2-user@$PUBLIC_IP << 'ENDSSH'
    set -e
    echo "Extracting code..."
    mkdir -p bwa-mem2-arm
    cd bwa-mem2-arm
    tar xzf ../bwa-mem2-arm.tar.gz

    echo "Installing dependencies (Amazon Linux 2023)..."
    sudo yum update -y -q
    sudo yum install -y -q gcc gcc-c++ make zlib-devel bc time

    echo ""
    echo "=========================================="
    echo "Running ARM Optimization Tests"
    echo "=========================================="
    echo ""

    # Run deployment script
    ./DEPLOY_TO_GRAVITON4.sh 2>&1 | tee deployment_results.log

    echo ""
    echo "=========================================="
    echo "Test Complete!"
    echo "=========================================="
ENDSSH

# Save instance info
echo ""
echo "=========================================="
echo "Instance Information"
echo "=========================================="
echo ""
echo "Instance ID: $INSTANCE_ID"
echo "Public IP: $PUBLIC_IP"
echo "SSH: ssh ec2-user@$PUBLIC_IP"
echo "Region: $REGION"
echo ""
echo "Saved to: graviton4_instance_info.txt"

cat > graviton4_instance_info.txt << EOF
Graviton 4 Test Instance
========================
Instance ID: $INSTANCE_ID
Public IP: $PUBLIC_IP
Region: $REGION
Instance Type: $INSTANCE_TYPE
Launched: $(date)

SSH Command:
ssh ec2-user@$PUBLIC_IP

Terminate Command:
AWS_PROFILE=$AWS_PROFILE aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION

Download Results:
scp ec2-user@$PUBLIC_IP:~/bwa-mem2-arm/deployment_results.log ./
EOF

echo ""
echo "=========================================="
echo "Next Steps"
echo "=========================================="
echo ""
echo "1. Review results above"
echo "2. SSH to instance for more testing:"
echo "   ssh ec2-user@$PUBLIC_IP"
echo ""
echo "3. When done, terminate instance:"
echo "   aws ec2 terminate-instances --instance-ids $INSTANCE_ID --region $REGION"
echo ""
echo "4. Or use the helper script:"
echo "   AWS_PROFILE=$AWS_PROFILE ./terminate_graviton4.sh $INSTANCE_ID"
echo ""
