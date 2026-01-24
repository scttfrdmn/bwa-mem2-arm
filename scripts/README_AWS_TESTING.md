# AWS Testing Guide for BWA-MEM2 ARM

This guide walks through using AWS to validate correctness and measure performance of the ARM port.

## Quick Start

### Prerequisites

```bash
# 1. Configure AWS CLI
aws configure --profile aws
# Enter your credentials

# 2. Set environment variables
export AWS_PROFILE=aws
export AWS_REGION=us-east-1
export AWS_KEY_NAME=your-key-name
export AWS_SECURITY_GROUP=sg-xxxxxxxxx
export AWS_SUBNET_ID=subnet-xxxxxxxxx

# 3. Ensure your security group allows SSH (port 22)
aws ec2 describe-security-groups \
  --group-ids $AWS_SECURITY_GROUP \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'
```

### Run Comparison Test

```bash
cd /Users/scttfrdmn/src/bwa-mem2-arm
./scripts/aws-comparison-test.sh
```

This will:
1. Launch 3 instances (Intel c7i, AMD c7a, ARM c7g)
2. Build BWA-MEM2 on each
3. Run identical tests in parallel
4. Download and compare results
5. Show performance comparison
6. Optionally terminate instances

**Cost**: ~$0.50-1.00 for a complete test run (30-60 minutes)

## Manual Testing

If you prefer manual control:

### 1. Launch Instances

```bash
# Intel (Sapphire Rapids)
aws ec2 run-instances \
  --instance-type c7i.xlarge \
  --image-id $(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text) \
  --key-name $AWS_KEY_NAME \
  --security-group-ids $AWS_SECURITY_GROUP \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-intel}]'

# AMD (Genoa)
aws ec2 run-instances \
  --instance-type c7a.xlarge \
  --image-id $(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-x86_64" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text) \
  --key-name $AWS_KEY_NAME \
  --security-group-ids $AWS_SECURITY_GROUP \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-amd}]'

# ARM (Graviton3)
aws ec2 run-instances \
  --instance-type c7g.xlarge \
  --image-id $(aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=al2023-ami-*-arm64" \
    --query 'Images | sort_by(@, &CreationDate) | [-1].ImageId' \
    --output text) \
  --key-name $AWS_KEY_NAME \
  --security-group-ids $AWS_SECURITY_GROUP \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=bwa-mem2-arm}]'
```

### 2. Get Instance IPs

```bash
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bwa-mem2-*" \
  --query 'Reservations[*].Instances[*].[Tags[?Key==`Name`].Value|[0],PublicIpAddress,InstanceType]' \
  --output table
```

### 3. SSH and Build

```bash
# On each instance:
ssh ec2-user@<instance-ip>

# Install dependencies
sudo yum update -y
sudo yum install -y gcc-c++ git make zlib-devel

# Clone and build
git clone https://github.com/scttfrdmn/bwa-mem2-arm.git
cd bwa-mem2-arm/bwa-mem2
git checkout arm-graviton-optimization
make arch=native CXX=g++ clean all

# Verify
./bwa-mem2 version
uname -m
```

### 4. Download Test Data

```bash
# On each instance:
cd bwa-mem2-arm/bwa-mem2
mkdir -p test_data && cd test_data

# Small test (E. coli ~4.6 MB)
wget ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz
gunzip GCF_000005845.2_ASM584v2_genomic.fna.gz
mv GCF_000005845.2_ASM584v2_genomic.fna ecoli.fa

# Test reads
wget https://github.com/lh3/bwa/raw/master/test/bwa-mem_test1.fq
wget https://github.com/lh3/bwa/raw/master/test/bwa-mem_test2.fq
```

### 5. Run Tests

```bash
# On each instance:
cd ..

# Index
/usr/bin/time -v ./bwa-mem2 index test_data/ecoli.fa 2>&1 | tee index.log

# Align
/usr/bin/time -v ./bwa-mem2 mem -t 4 test_data/ecoli.fa \
  test_data/bwa-mem_test1.fq test_data/bwa-mem_test2.fq \
  > test_data/output.sam 2>&1 | tee align.log

# Check results
grep "Elapsed" index.log align.log
wc -l test_data/output.sam
```

### 6. Compare Results

```bash
# Download SAM files from each instance to local machine
scp ec2-user@<intel-ip>:bwa-mem2-arm/bwa-mem2/test_data/output.sam output_intel.sam
scp ec2-user@<amd-ip>:bwa-mem2-arm/bwa-mem2/test_data/output.sam output_amd.sam
scp ec2-user@<arm-ip>:bwa-mem2-arm/bwa-mem2/test_data/output.sam output_arm.sam

# Compare
diff output_intel.sam output_amd.sam
diff output_intel.sam output_arm.sam
diff output_amd.sam output_arm.sam
```

### 7. Cleanup

```bash
# List instances
aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=bwa-mem2-*" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text

# Terminate
aws ec2 terminate-instances --instance-ids <instance-ids>
```

## Instance Pricing (us-east-1)

| Instance | vCPU | RAM | Price/hr | Arch |
|----------|------|-----|----------|------|
| c7i.xlarge | 4 | 8 GB | $0.1785 | Intel Sapphire Rapids |
| c7a.xlarge | 4 | 8 GB | $0.1530 | AMD Genoa |
| c7g.xlarge | 4 | 8 GB | $0.1445 | AWS Graviton3 |

**Total cost for 1 hour**: ~$0.48 ($0.1785 + $0.1530 + $0.1445)

## Test Datasets

### Small (< 5 min)
- **E. coli** K-12 (~4.6 MB): Good for quick validation
- Test reads from BWA repository

### Medium (30-60 min)
- **Human chromosome 22** (~51 MB)
- 1M read pairs

### Large (2-4 hours)
- **Human genome** (hg38, ~3.1 GB)
- 10M read pairs
- **Cost**: ~$2-4 for complete test

## Troubleshooting

### Can't SSH to instance
```bash
# Check security group allows your IP
aws ec2 describe-security-groups \
  --group-ids $AWS_SECURITY_GROUP \
  --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`]'

# Add your IP if needed
aws ec2 authorize-security-group-ingress \
  --group-id $AWS_SECURITY_GROUP \
  --protocol tcp \
  --port 22 \
  --cidr $(curl -s ifconfig.me)/32
```

### Build fails on ARM
```bash
# Check branch
git branch -a
git checkout arm-graviton-optimization

# Verify CPU architecture
uname -m  # Should show aarch64
cat /proc/cpuinfo | grep Features
```

### Different results on ARM
This is the main thing we're testing! If results differ:

1. Check alignment counts: `grep -v "^@" output.sam | wc -l`
2. Compare specific alignments: `diff <(head -100 output_x86.sam) <(head -100 output_arm.sam)`
3. Validate with samtools: `samtools quickcheck output.sam`
4. Check for errors in logs

## Performance Expectations

Based on 7th gen instances with NEON optimization:

| Metric | Intel c7i | AMD c7a | ARM c7g | Target |
|--------|-----------|---------|---------|--------|
| **Indexing** | Baseline | ~95-105% | ~90-100% | Within 10% |
| **Alignment** | Baseline | ~100-110% | ~85-95% | Within 15% |
| **Memory** | Baseline | Similar | Similar | Same |

## Next Steps After Validation

✅ If results match:
1. Test with larger datasets
2. Optimize hot paths identified by profiling
3. Test on Graviton3E (hpc7g) with SVE

❌ If results differ:
1. Debug SIMD implementation
2. Check specific intrinsics causing differences
3. Add unit tests for problematic functions

## Useful Commands

```bash
# Check CPU features
cat /proc/cpuinfo | grep -E "model name|flags|Features"

# Monitor resource usage during test
top -b -n 1 | head -20

# Check for SIMD being used
strings ./bwa-mem2 | grep -i simd

# Profile with perf (Linux)
perf record -g ./bwa-mem2 mem ...
perf report
```

---

**Ready to test?** Run the automated script:
```bash
./scripts/aws-comparison-test.sh
```
