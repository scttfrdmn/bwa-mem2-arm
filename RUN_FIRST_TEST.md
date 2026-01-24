# Running Your First AWS Test

## Quick Start (2 minutes)

```bash
cd /Users/scttfrdmn/src/bwa-mem2-arm

# 1. Review the configuration
cat .aws-test-config

# 2. Make sure your SSH key is accessible
ls -l ~/.ssh/cws-aws-west-2-key.pem

# 3. Run the test!
./run-aws-test.sh
```

That's it! The script will:
- Launch Intel + AMD + ARM instances
- Build and test in parallel
- Compare results
- Show you the comparison
- Ask if you want to terminate instances

## What You'll Get

### Correctness Results
```
✓ Intel ↔ AMD: IDENTICAL
✓ Intel ↔ ARM: IDENTICAL
✓ AMD ↔ ARM: IDENTICAL
```

### Performance Results
```
Indexing time:
  Intel (c7i): 0:02.34
  AMD   (c7a): 0:02.18
  ARM   (c7g): 0:02.56

Alignment time:
  Intel (c7i): 0:15.23
  AMD   (c7a): 0:14.87
  ARM   (c7g): 0:16.45

ARM is 92.6% of Intel speed
ARM is 90.4% of AMD speed
```

### Results Saved To
```
test_results_20260124_143045/
├── output_se_intel.sam
├── output_se_amd.sam
├── output_se_arm.sam
├── output_pe_intel.sam
├── output_pe_amd.sam
├── output_pe_arm.sam
├── index_intel.log
├── index_amd.log
├── index_arm.log
├── align_se_intel.log
├── align_se_amd.log
├── align_se_arm.log
├── align_pe_intel.log
├── align_pe_amd.log
└── align_pe_arm.log
```

## Cost Breakdown

| Instance | Type | Price/hr | Time | Cost |
|----------|------|----------|------|------|
| Intel | c7i.xlarge | $0.1785 | 0.75hr | ~$0.13 |
| AMD | c7a.xlarge | $0.1530 | 0.75hr | ~$0.11 |
| ARM | c7g.xlarge | $0.1445 | 0.75hr | ~$0.11 |
| **Total** | | | | **~$0.35** |

Plus minimal data transfer costs (~$0.01).

## Troubleshooting

### Can't SSH to instances
Check your SSH key:
```bash
ls -l ~/.ssh/cws-aws-west-2-key.pem
chmod 400 ~/.ssh/cws-aws-west-2-key.pem  # If needed
```

### Build fails
The script will show detailed error output. Common issues:
- Network timeout during git clone
- Missing dependencies (rare on Amazon Linux 2023)

### Need to stop early
Instances are tagged as `bwa-mem2-test-*`. Find and terminate:
```bash
aws ec2 describe-instances \
  --profile aws \
  --region us-west-2 \
  --filters "Name=tag:Name,Values=bwa-mem2-test-*" \
  --query 'Reservations[*].Instances[*].InstanceId' \
  --output text

# Terminate
aws ec2 terminate-instances --profile aws --region us-west-2 --instance-ids <ids>
```

## After Testing

Once you have results:

1. **If correctness passes** ✅
   - Celebrate! ARM SIMD implementation works!
   - Focus on optimizing performance
   - Profile hot paths

2. **If results differ** ⚠️
   - Compare SAM files line-by-line
   - Check specific SIMD intrinsics
   - Add debug output to narrow down

3. **Performance analysis**
   - Identify bottlenecks
   - Optimize critical intrinsics
   - Try different compiler flags

## Manual Testing

If you prefer more control, see: `scripts/README_AWS_TESTING.md`

---

Ready? Just run: `./run-aws-test.sh`
