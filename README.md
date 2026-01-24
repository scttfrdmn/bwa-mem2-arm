# BWA-MEM2 ARM/Graviton Optimization Project

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen)](https://github.com/scttfrdmn/bwa-mem2-arm)
[![Platform](https://img.shields.io/badge/platform-ARM64%20%7C%20x86__64-blue)](https://github.com/scttfrdmn/bwa-mem2-arm)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)

**Native ARM SIMD support for BWA-MEM2** targeting AWS Graviton processors and Apple Silicon.

## 🎯 Mission

Extend BWA-MEM2 with high-performance ARM optimizations:
- **NEON** (128-bit): Graviton2, Graviton3, Graviton4, Apple M-series
- **SVE** (256-bit): Graviton3E HPC instances (hpc7g)
- **SVE2** (variable): Future Graviton generations

## 📊 Status

**✅ Phase 1 Complete** - ARM builds successfully!

- ✅ NEON baseline implementation (800+ intrinsics)
- ✅ Builds on Apple M4 Pro
- ✅ Cross-platform SIMD abstraction layer
- ⏳ Performance validation pending
- ⏳ AWS Graviton testing pending
- ⏳ SVE implementation for Graviton3E

## 🚀 Quick Start

### Prerequisites

```bash
# macOS (Apple Silicon)
xcode-select --install

# Linux (AWS Graviton)
sudo yum install -y gcc-c++ git make zlib-devel  # Amazon Linux
# or
sudo apt install -y build-essential git zlib1g-dev  # Ubuntu
```

### Build

```bash
git clone https://github.com/scttfrdmn/bwa-mem2-arm.git
cd bwa-mem2-arm/bwa-mem2
git checkout arm-graviton-optimization

# Build for ARM
make arch=native CXX=clang++  # or g++

# Verify
./bwa-mem2 version
file ./bwa-mem2
```

### Test

```bash
# Index a reference genome
./bwa-mem2 index reference.fa

# Align reads
./bwa-mem2 mem reference.fa reads_1.fq reads_2.fq > output.sam
```

## 🏗️ Architecture

### SIMD Abstraction Layer

```
bwa-mem2/src/simd/
├── simd.h              # Cross-platform selector
├── simd_common.h       # Shared utilities (malloc, prefetch)
├── simd_arm_neon.h     # ARM NEON implementations
├── simd_arm_sve.h      # ARM SVE (Graviton3E - future)
└── simd_x86.h          # x86 SSE/AVX wrapper
```

**Key Features:**
- Transparent SSE→NEON translation
- Platform-agnostic API (`_mm_*` functions work everywhere)
- Compile-time architecture selection
- Zero overhead on x86 (direct passthrough)

### Platform Compatibility

```
bwa-mem2/src/platform_compat.h
```

- High-resolution timing (RDTSC on x86, CNTVCT_EL0 on ARM)
- CPU feature detection (CPUID on x86, HWCAP/sysctl on ARM)
- Cross-platform abstractions

## 📈 Performance Targets

| Platform | SIMD | Target Performance |
|----------|------|-------------------|
| **Graviton2** | NEON 128-bit | 90-100% of x86 SSE4.1 |
| **Graviton3** | NEON 128-bit (enhanced) | 95-105% of x86 SSE4.1 |
| **Graviton3E** | SVE 256-bit | 90-100% of x86 AVX2 |
| **Graviton4** | NEON (Neoverse V2) | Approach x86 AVX-512 |
| **Apple M4** | NEON + DotProd | Graviton3-class |

## 🧪 Testing

### Local (Apple Silicon)

```bash
# Build and test
make arch=native CXX=clang++ clean all

# Profile
instruments -t "Time Profiler" ./bwa-mem2 mem ...

# Verify ARM features
sysctl hw.optional.arm | grep -E "NEON|DotProd"
```

### AWS Graviton

```bash
# Launch Graviton3 instance
aws ec2 run-instances \
  --instance-type c7g.xlarge \
  --image-id ami-xxx \
  --key-name your-key

# SSH and build
ssh ec2-user@<instance-ip>
git clone https://github.com/scttfrdmn/bwa-mem2-arm.git
cd bwa-mem2-arm/bwa-mem2
make arch=native CXX=g++ clean all

# Check CPU features
cat /proc/cpuinfo | grep Features
```

## 📁 Project Structure

```
bwa-mem2-arm/
├── README.md                       # This file
├── MILESTONE_ARM_BUILD_SUCCESS.md  # Build achievement log
├── docs/
│   ├── SSE_TO_NEON_MAPPING.md     # Intrinsics reference
│   └── BUILD_PLAN.md               # 12-week implementation plan
├── scripts/
│   └── setup-arm-dev.sh            # AWS environment setup
└── bwa-mem2/                       # Fork with ARM support
    ├── src/simd/                   # SIMD abstraction layer
    ├── src/platform_compat.h       # Platform utilities
    └── [modified core files]
```

## 🔧 Implementation Details

### SSE Intrinsics Mapped

- **Memory**: `_mm_malloc`, `_mm_free`, `_mm_load_si128`, `_mm_store_si128`
- **Arithmetic**: `_mm_add_epi*`, `_mm_sub_epi*`, `_mm_adds_ep*`, `_mm_subs_ep*`
- **Comparison**: `_mm_cmpeq_epi*`, `_mm_cmpgt_epi*`, `_mm_cmplt_epi*`
- **Logic**: `_mm_and_si128`, `_mm_or_si128`, `_mm_xor_si128`, `_mm_andnot_si128`
- **Min/Max**: `_mm_max_ep*`, `_mm_min_ep*`
- **Blend**: `_mm_blendv_epi*`
- **Shifts**: `_mm_slli_si128`, `_mm_srli_si128`
- **Extract**: `_mm_extract_epi*`, `_mm_movemask_epi8`
- **Prefetch**: `_mm_prefetch`

### Core Files Modified

- `bandedSWA.h/cpp` - Smith-Waterman alignment (main hotspot)
- `FMI_search.h/cpp` - FM-Index search operations
- `ksw.h/cpp`, `kswv.h/cpp` - KSW alignment kernels
- `bwamem.h/cpp` - Core BWA-MEM algorithm
- `fastmap.cpp` - Main processing pipeline

## 📚 Documentation

- [SSE to NEON Mapping Guide](docs/SSE_TO_NEON_MAPPING.md)
- [12-Week Build Plan](docs/BUILD_PLAN.md)
- [ARM Build Success Milestone](MILESTONE_ARM_BUILD_SUCCESS.md)

## 🤝 Contributing

This is a research project aiming for upstream contribution to [bwa-mem2/bwa-mem2](https://github.com/bwa-mem2/bwa-mem2).

**Current branch**: `arm-graviton-optimization` in [scttfrdmn/bwa-mem2](https://github.com/scttfrdmn/bwa-mem2)

### Development Workflow

1. Fork this repo
2. Create a feature branch from `arm-graviton-optimization`
3. Make changes
4. Test on ARM (M-series Mac or Graviton instance)
5. Submit PR

## 📊 Benchmarking

Coming soon! We'll compare:
- x86 SSE4.1 vs ARM NEON (128-bit)
- x86 AVX2 vs ARM SVE (256-bit, Graviton3E)
- Graviton2 vs Graviton3 vs Graviton4
- Apple M4 vs AWS Graviton3

## 🙏 Acknowledgments

- **BWA-MEM2 Team**: Vasimuddin Md, Sanchit Misra, Heng Li
- **ARM Architecture**: ARM NEON and SVE intrinsics guides
- **AWS Graviton**: Performance optimization guides

## 📄 License

MIT License - See [LICENSE](LICENSE) file

Original BWA-MEM2 is also MIT licensed.

## 🔗 Links

- **Project Repo**: https://github.com/scttfrdmn/bwa-mem2-arm
- **BWA-MEM2 Fork**: https://github.com/scttfrdmn/bwa-mem2
- **Upstream BWA-MEM2**: https://github.com/bwa-mem2/bwa-mem2
- **AWS Graviton**: https://aws.amazon.com/ec2/graviton/

---

**Status**: Active Development | **Last Updated**: January 2026
