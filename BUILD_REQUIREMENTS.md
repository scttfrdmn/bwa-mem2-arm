# BWA-MEM2 ARM Build Requirements

## Compiler Requirements

### ⚠️ GCC 14 Required for Full ARM Support

**For complete Graviton support (including ARMv9 for Graviton 4), you MUST use GCC 14 or later.**

| Graviton Generation | Min GCC | Recommended | Reason |
|---------------------|---------|-------------|--------|
| Graviton 2 | GCC 8+ | **GCC 14+** | Dotprod, optimal code generation |
| Graviton 3/3E | GCC 10+ | **GCC 14+** | SVE, bf16, i8mm support |
| Graviton 4 | **GCC 12+** | **GCC 14+** | **ARMv9-a architecture** |

### Why GCC 14?

1. **Native ARMv9-a Support**: GCC 14 supports `-march=armv9-a` for Graviton 4 (Neoverse V2)
2. **Better Code Generation**: Improved NEON and SVE optimization
3. **Neoverse V2 Tuning**: Enhanced `-mtune=neoverse-v2` support
4. **Future Proof**: Ready for Phase 3/4 SVE/SVE2 implementation

### GCC 11 Limitations

If you only have GCC 11 (default on older AL2023):
- ✅ Works for Graviton 2/3/3E
- ⚠️ Graviton 4 uses workaround flags (`-march=armv8.6-a` instead of `armv9-a`)
- ⚠️ Suboptimal code generation
- ❌ Not recommended for production

---

## Installation

### Amazon Linux 2023 (Recommended)

AL2023.10 or later includes GCC 14 in repos:

```bash
# Update to latest AL2023
sudo yum update -y

# Install GCC 14
sudo yum install -y gcc14 gcc14-c++ make zlib-devel git python3

# Verify installation
gcc14-gcc --version
# Should show: gcc14-gcc (GCC) 14.2.1 or later

# Verify ARMv9 support
echo 'int main(){}' | gcc14-g++ -march=armv9-a -x c++ -c - -o /dev/null && echo "✅ ARMv9 supported"
```

### Ubuntu 22.04+

```bash
# Add Ubuntu Toolchain PPA (if needed)
sudo add-apt-repository ppa:ubuntu-toolchain-r/test
sudo apt update

# Install GCC 14
sudo apt install -y gcc-14 g++-14 make zlib1g-dev git python3 wget

# Set as default
sudo update-alternatives --install /usr/bin/gcc gcc /usr/bin/gcc-14 100
sudo update-alternatives --install /usr/bin/g++ g++ /usr/bin/g++-14 100
```

### Build from Source (Last Resort)

Only if GCC 14 is not available in your distro repos:

```bash
# Download GCC 14.2.0
wget https://ftp.gnu.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz
tar xf gcc-14.2.0.tar.xz
cd gcc-14.2.0

# Download prerequisites
./contrib/download_prerequisites

# Configure (C/C++ only for faster build)
mkdir build && cd build
../configure \
    --prefix=/opt/gcc-14 \
    --enable-languages=c,c++ \
    --disable-multilib \
    --disable-bootstrap

# Build (takes 30-60 minutes on 4 cores)
make -j4

# Install
sudo make install

# Set environment
export PATH=/opt/gcc-14/bin:$PATH
export LD_LIBRARY_PATH=/opt/gcc-14/lib64:$LD_LIBRARY_PATH
export CC=/opt/gcc-14/bin/gcc
export CXX=/opt/gcc-14/bin/g++
```

---

## Build Instructions

### With GCC 14 (Recommended)

```bash
cd bwa-mem2

# Option 1: Build all Graviton versions (multi-binary + dispatcher)
make multi CXX=gcc14-g++ CC=gcc14-gcc

# Option 2: Build single generation
make arch="-march=armv9-a+sve2 -mtune=neoverse-v2" CXX=gcc14-g++ CC=gcc14-gcc

# Option 3: Default (baseline ARMv8-a)
make CXX=gcc14-g++ CC=gcc14-gcc
```

### With GCC 11 (Not Recommended)

If you must use GCC 11, the Makefile will automatically use `armv8.6-a` workaround for Graviton 4:

```bash
# This works but is suboptimal
make multi CXX=g++ CC=gcc
```

---

## Verification

### Check GCC Version

```bash
# AL2023
gcc14-gcc --version | head -1
# Expected: gcc14-gcc (GCC) 14.2.1 20250110 or later

# Ubuntu/other
gcc --version | head -1
# Expected: gcc (GCC) 14.2.0 or later
```

### Check ARMv9 Support

```bash
# This should succeed without errors
echo 'int main(){}' | gcc14-g++ -march=armv9-a -x c++ -c - -o /dev/null

# If it fails with "unknown value 'armv9-a'", your GCC version is too old
```

### Check Graviton CPU Detection

```bash
# On Graviton 2 (Neoverse N1)
grep "CPU part" /proc/cpuinfo | head -1
# Expected: CPU part	: 0xd0c

# On Graviton 3/3E (Neoverse V1)
# Expected: CPU part	: 0xd40

# On Graviton 4 (Neoverse V2)
# Expected: CPU part	: 0xd4f
```

---

## Additional Dependencies

### Required

```bash
# AL2023
sudo yum install -y make zlib-devel git python3 wget

# Ubuntu
sudo apt install -y make zlib1g-dev git python3 wget
```

### Optional (for testing)

```bash
# AWS CLI (for multi-generation testing)
curl "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install
```

---

## Known Issues

### safestringlib with GCC 14

GCC 14 treats implicit function declarations as errors. Fix:

```bash
# After cloning safestringlib
sed -i '/#include "safe_str_lib.h"/a #include <ctype.h>' \
    ext/safestringlib/safeclib/strcasecmp_s.c
sed -i '/#include "safe_str_lib.h"/a #include <ctype.h>' \
    ext/safestringlib/safeclib/strcasestr_s.c
```

This is automatically handled by `test-all-graviton-gcc14.sh` script.

---

## FAQ

### Q: Can I use GCC 13?
A: Yes, GCC 13 has ARMv9 support. However, GCC 14 has better Neoverse V2 tuning and optimization.

### Q: What about Clang/LLVM?
A: Clang 17+ also supports ARMv9-a. However, GCC 14 is recommended as it's been more extensively tested for this project.

### Q: Do I need GCC 14 for Graviton 2/3?
A: No, GCC 11 is sufficient for Graviton 2/3. However, GCC 14 provides better code generation and is recommended for all generations.

### Q: Does ARM Compiler for Linux (ACfL) work?
A: Yes, ACfL 24.10+ supports ARMv9 and provides excellent code generation. However, it's more complex to install than GCC 14 from repos.

### Q: What if I'm on macOS (Apple Silicon)?
A: Use the default Clang compiler (Apple Clang 15+). The codebase detects `arm64` architecture and uses appropriate flags.

---

## Build Matrix

| Platform | Compiler | ARMv9 Support | Notes |
|----------|----------|---------------|-------|
| **AL2023.10+** | GCC 14.2.1 | ✅ Yes | **Recommended** |
| AL2023 (older) | GCC 11.5.0 | ❌ No | Workaround used |
| Ubuntu 22.04+ | GCC 14.2.0 | ✅ Yes | Via PPA |
| Amazon Linux 2 | GCC 7.3.1 | ❌ No | Not supported |
| ARM Compiler | ACfL 24.10+ | ✅ Yes | Complex install |
| macOS | Apple Clang 15+ | ⚠️ N/A | Uses armv8-a |

---

## Version History

| Date | GCC Version | ARMv9 | Notes |
|------|-------------|-------|-------|
| 2026-01-26 | **14.2.1** | ✅ Yes | **Current** (all Graviton validated) |
| 2026-01-24 | 11.5.0 | ❌ No | Initial testing (armv8.6-a workaround) |
| 2025-12-xx | 11.5.0 | ❌ No | Week 1 implementation |

---

## Support

For build issues:
1. Check GCC version: `gcc14-gcc --version`
2. Verify ARMv9 support: `gcc14-g++ -march=armv9-a -E - < /dev/null`
3. See `WEEK2_COMPLETE_SUCCESS.md` for validation results
4. Check GitHub issues: https://github.com/bwa-mem2/bwa-mem2/issues

---

**Summary**: **Use GCC 14+ for full ARM Graviton support**, especially for Graviton 4 ARMv9 architecture.
