# Git Commit Guide for Phase 1

## Recommended Commit Strategy

### Option 1: Single Atomic Commit (Recommended)

```bash
cd /Users/scttfrdmn/src/bwa-mem2-arm

# Stage all Phase 1 changes
git add bwa-mem2/Makefile
git add bwa-mem2/src/simd/simd_arm_neon.h
git add bwa-mem2/src/runsimd_arm.cpp
git add bwa-mem2/ext/safestringlib/safeclib/abort_handler_s.c

# Stage documentation
git add PHASE1_IMPLEMENTATION.md
git add PHASE1_SUMMARY.md
git add AWS_TESTING_GUIDE.md
git add IMPLEMENTATION_STATUS.md
git add README_PHASE1.md
git add test-phase1.sh
git add COMMIT_GUIDE.md

# Commit with detailed message
git commit -m "Implement Phase 1: Compiler flags + optimized movemask

Phase 1 ARM/Graviton optimization targeting 40-50% performance improvement.

Changes:
- Add Graviton2/3/4 specific compiler flags to Makefile
- Enable fast movemask implementation (5-7 vs 15-20 instructions)
- Implement ARM CPU dispatcher with runtime detection
- Add comprehensive testing and documentation

Expected performance:
- Baseline: 2.587s (4 threads, Graviton3)
- Phase 1:  ~2.0s (1.29x speedup)
- Gap closure: 1.84x slower → 1.42x slower vs x86

Testing:
- Run ./test-phase1.sh full on AWS c7g.xlarge
- Expected: ≥1.25x speedup with zero correctness regression

Files modified:
- bwa-mem2/Makefile
- bwa-mem2/src/simd/simd_arm_neon.h
- bwa-mem2/ext/safestringlib/safeclib/abort_handler_s.c

Files created:
- bwa-mem2/src/runsimd_arm.cpp
- Documentation and test scripts (7 files)

Status: Code complete, awaiting AWS validation
Risk: Low - proven techniques, minimal invasive changes"
```

### Option 2: Multiple Focused Commits

```bash
# Commit 1: Makefile changes
git add bwa-mem2/Makefile
git commit -m "Add Graviton2/3/4 multi-version build support

- Add generation-specific compiler flags
- Implement multi-version build for ARM
- Add dispatcher compilation step"

# Commit 2: Optimized movemask
git add bwa-mem2/src/simd/simd_arm_neon.h
git commit -m "Enable optimized movemask for ARM

- Activate _mm_movemask_epi8_fast implementation
- Reduces from 15-20 to 5-7 instructions
- Expected 25-30% speedup in hot paths"

# Commit 3: ARM dispatcher
git add bwa-mem2/src/runsimd_arm.cpp
git commit -m "Add ARM CPU dispatcher with runtime detection

- Detect Graviton generation via /proc/cpuinfo
- Check CPU features via getauxval(AT_HWCAP)
- Launch optimal binary for detected CPU
- Fallback gracefully if binary not found"

# Commit 4: Bug fix
git add bwa-mem2/ext/safestringlib/safeclib/abort_handler_s.c
git commit -m "Fix implicit declaration warning in safestringlib

Add #include <stdlib.h> for abort() declaration"

# Commit 5: Documentation
git add *.md *.sh
git commit -m "Add Phase 1 documentation and test infrastructure

- Automated test script (test-phase1.sh)
- Implementation documentation
- AWS testing guide
- Project status tracking"
```

### Option 3: Feature Branch (Best Practice)

```bash
# Create feature branch
git checkout -b phase1-arm-optimization

# Make all changes and commit
git add -A
git commit -m "Phase 1: ARM/Graviton compiler optimization + fast movemask

See PHASE1_SUMMARY.md for complete details.

Expected: 40-50% performance improvement
Status: Ready for AWS validation"

# Push feature branch
git push origin phase1-arm-optimization

# After validation passes, merge to main:
git checkout main
git merge --no-ff phase1-arm-optimization
git push origin main
```

---

## Current Git Status

```bash
# Check what's ready to commit
cd /Users/scttfrdmn/src/bwa-mem2-arm
git status
```

**Modified files**:
- bwa-mem2/Makefile
- bwa-mem2/src/simd/simd_arm_neon.h
- bwa-mem2/ext/safestringlib (submodule)

**New files**:
- bwa-mem2/src/runsimd_arm.cpp
- PHASE1_IMPLEMENTATION.md
- PHASE1_SUMMARY.md
- AWS_TESTING_GUIDE.md
- IMPLEMENTATION_STATUS.md
- README_PHASE1.md
- test-phase1.sh
- COMMIT_GUIDE.md

---

## Submodule Handling

The safestringlib is a submodule with local changes:

```bash
# Option A: Commit changes within submodule (if you own it)
cd bwa-mem2/ext/safestringlib
git add safeclib/abort_handler_s.c
git commit -m "Add stdlib.h include for macOS compatibility"
cd ../../..
git add bwa-mem2/ext/safestringlib
git commit -m "Update safestringlib submodule"

# Option B: Keep as local patch (simpler)
# Just document that this change is needed
# Users will see it as modified submodule
```

**Recommendation**: Use Option B (local patch) since safestringlib is external.

---

## Before Committing

### Pre-commit Checklist

- [ ] All files added with `git add`
- [ ] No unintended files included (check `git status`)
- [ ] No sensitive data (passwords, keys) in commits
- [ ] Commit message is clear and descriptive
- [ ] Documentation is complete

### Verify Changes

```bash
# Review what will be committed
git diff --cached

# Review commit message
git commit --dry-run --short

# If satisfied, commit
git commit
```

---

## After Committing

### Tag the Release

```bash
# After AWS validation passes
git tag -a v0.1.0-phase1 -m "Phase 1: ARM optimization complete

Performance: 1.29x speedup achieved
Status: Validated on AWS Graviton3"

git push origin v0.1.0-phase1
```

### Create GitHub Release (Optional)

If using GitHub, create a release with:
- Title: "Phase 1: ARM/Graviton Compiler Optimization"
- Description: See PHASE1_SUMMARY.md
- Attach: Benchmark results, test outputs
- Tag: v0.1.0-phase1

---

## Rollback Plan

If you need to undo Phase 1:

```bash
# View commit history
git log --oneline

# Revert to before Phase 1
git revert <commit-hash>

# Or reset (CAUTION: loses uncommitted changes)
git reset --hard <commit-before-phase1>

# Or create a revert branch
git checkout -b revert-phase1
git revert <phase1-commit-hash>
git push origin revert-phase1
```

---

## .gitignore Recommendations

Add to `.gitignore` if not already present:

```gitignore
# Build artifacts
*.o
*.a
bwa-mem2/bwa-mem2
bwa-mem2/bwa-mem2.*
bwa-mem2/libbwa.a
bwa-mem2/src/*.o

# Test results
phase1-results/
phase1-test-data/
*.sam
*.log

# Temporary files
.current-test-log
aws-test-*.log
```

---

## Recommended Git Workflow

```bash
# 1. Create feature branch
git checkout -b phase1-arm-optimization

# 2. Implement changes
# (Already done!)

# 3. Commit locally
git add <files>
git commit -m "..."

# 4. Push to remote
git push origin phase1-arm-optimization

# 5. Deploy to AWS for testing
# (Run test-phase1.sh)

# 6. If tests pass, merge to main
git checkout main
git merge --no-ff phase1-arm-optimization
git tag v0.1.0-phase1
git push origin main --tags

# 7. If tests fail, iterate on feature branch
git checkout phase1-arm-optimization
# Make fixes
git commit -m "Fix: ..."
git push origin phase1-arm-optimization
# Re-test
```

---

## Summary

**Recommended approach**:

1. Create feature branch: `phase1-arm-optimization`
2. Make single atomic commit with comprehensive message
3. Push to remote
4. Test on AWS
5. Merge to main after validation passes

This keeps history clean while allowing easy rollback if needed.
