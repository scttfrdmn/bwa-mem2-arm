# Launch AWS Instance and Run Tests

## Step-by-Step Instructions

### Step 1: Launch AWS Instance

**Via AWS Console**:
1. Go to https://console.aws.amazon.com/ec2
2. Click "Launch Instance"
3. Configure:
   - **Name**: bwa-mem2-phase1-test
   - **AMI**: Amazon Linux 2023 ARM64
   - **Instance Type**: c7g.xlarge
   - **Key pair**: Select your existing key (or create new)
   - **Security group**: Allow SSH (port 22)
4. Click "Launch Instance"
5. Wait ~1 minute for instance to start
6. Note the **Public IPv4 address**

**Via AWS CLI** (if you have it configured):
```bash
aws ec2 run-instances \
  --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64 \
  --instance-type c7g.xlarge \
  --key-name YOUR_KEY_NAME \
  --security-group-ids YOUR_SG_ID \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-phase1-test}]'
```

---

### Step 2: Transfer Deployment Package

```bash
# Set your variables
INSTANCE_IP="<paste-your-instance-ip-here>"
KEY_FILE="~/.ssh/your-key.pem"

# Transfer deployment package
cd /Users/scttfrdmn/src/bwa-mem2-arm
scp -i $KEY_FILE phase1-deploy.tar.gz ec2-user@$INSTANCE_IP:~/

# Should take ~10 seconds (3.8 MB file)
```

---

### Step 3: Connect and Run Tests

```bash
# SSH into instance
ssh -i $KEY_FILE ec2-user@$INSTANCE_IP

# Once connected, run the automated setup and test script
curl -sSL https://raw.githubusercontent.com/YOUR_REPO/main/aws-run-commands.sh | bash

# OR manually run commands:
sudo yum update -y
sudo yum install -y gcc gcc-c++ make zlib-devel python3 wget
tar xzf phase1-deploy.tar.gz
cd bwa-mem2-arm
cd bwa-mem2 && git submodule update --init --recursive && cd ..
chmod +x test-phase1.sh
./test-phase1.sh full
```

**Expected runtime**: 15-20 minutes

---

### Step 4: Check Results

After the test completes, you should see:

```
════════════════════════════════════════════════════════════════
                  PHASE 1 PERFORMANCE COMPARISON
════════════════════════════════════════════════════════════════
Baseline time:  2.587s
Phase 1 time:   2.012s
Speedup:        1.29x
Improvement:    22.2%
────────────────────────────────────────────────────────────────
✅ PASS: Achieved ≥1.25x speedup target!

CORRECTNESS CHECK:
Baseline alignments: 61,888
Phase 1 alignments:  61,888
✅ PASS: Alignment counts match
════════════════════════════════════════════════════════════════
```

**View detailed results**:
```bash
cat phase1-results/*_summary.txt
```

---

### Step 5: Download Results (Optional)

From your local machine:
```bash
# Download all results
scp -i $KEY_FILE -r ec2-user@$INSTANCE_IP:~/bwa-mem2-arm/phase1-results ./phase1-results-$(date +%Y%m%d)

# View locally
cat phase1-results-*/baseline_summary.txt
cat phase1-results-*/phase1_summary.txt
```

---

### Step 6: Cleanup

**Terminate instance when done**:
```bash
# Via AWS Console
# 1. Go to EC2 → Instances
# 2. Select "bwa-mem2-phase1-test"
# 3. Actions → Instance State → Terminate

# Via AWS CLI
aws ec2 terminate-instances --instance-ids <instance-id>
```

---

## Quick Copy/Paste Commands

### On Your Local Machine:
```bash
# Transfer to AWS (replace INSTANCE_IP and KEY_FILE)
cd /Users/scttfrdmn/src/bwa-mem2-arm
scp -i ~/.ssh/your-key.pem phase1-deploy.tar.gz ec2-user@INSTANCE_IP:~/
ssh -i ~/.ssh/your-key.pem ec2-user@INSTANCE_IP
```

### On AWS Instance:
```bash
sudo yum install -y gcc gcc-c++ make zlib-devel python3 wget
tar xzf phase1-deploy.tar.gz && cd bwa-mem2-arm
cd bwa-mem2 && git submodule update --init --recursive && cd ..
./test-phase1.sh full
```

---

## Troubleshooting

**Cannot connect to instance**:
- Check security group allows SSH (port 22)
- Verify you're using correct key file
- Instance may still be starting up (wait 1-2 minutes)

**Transfer fails**:
- Check file exists: `ls -lh phase1-deploy.tar.gz`
- Verify key permissions: `chmod 400 ~/.ssh/your-key.pem`

**Build fails**:
- Check all dependencies installed
- Try: `cd bwa-mem2 && git submodule update --init --recursive`

**Test fails**:
- Check available disk space: `df -h`
- Check memory: `free -h` (need ~4GB)
- Review logs in `phase1-results/`

---

## Alternative: Use Existing Repository

If you've pushed to GitHub:
```bash
# On AWS instance
git clone https://github.com/YOUR_USERNAME/bwa-mem2-arm.git
cd bwa-mem2-arm
cd bwa-mem2 && git submodule update --init --recursive && cd ..
./test-phase1.sh full
```

---

**Ready to test!** The deployment package is prepared and waiting.
