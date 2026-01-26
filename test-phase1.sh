#!/bin/bash
################################################################################
# BWA-MEM2 ARM Phase 1 Test Script
#
# Tests Phase 1 optimizations (compiler flags + optimized movemask)
# Expected improvement: 40-50% speedup over baseline
#
# Usage: ./test-phase1.sh [baseline|phase1|compare]
################################################################################

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BWA_DIR="$SCRIPT_DIR/bwa-mem2"
TEST_DIR="$SCRIPT_DIR/phase1-test-data"
RESULTS_DIR="$SCRIPT_DIR/phase1-results"

# Test parameters
THREADS=4
ITERATIONS=5
REFERENCE="ecoli.fa"
READS_1="reads_1.fq"
READS_2="reads_2.fq"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

################################################################################
# Helper Functions
################################################################################

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_cpu() {
    log_info "Detecting CPU..."

    if [ ! -f /proc/cpuinfo ]; then
        log_error "Not running on Linux. This script requires Linux ARM."
        exit 1
    fi

    ARCH=$(uname -m)
    if [ "$ARCH" != "aarch64" ]; then
        log_error "Not running on ARM64 (detected: $ARCH)"
        exit 1
    fi

    # Detect Graviton generation
    CPU_PART=$(grep "CPU part" /proc/cpuinfo | head -1 | awk '{print $4}')
    case "$CPU_PART" in
        0xd0c)
            CPU_GEN="Graviton2 (Neoverse N1)"
            ;;
        0xd40)
            CPU_GEN="Graviton3/3E (Neoverse V1)"
            ;;
        0xd4f)
            CPU_GEN="Graviton4 (Neoverse V2)"
            ;;
        *)
            CPU_GEN="Unknown ARM CPU (part: $CPU_PART)"
            ;;
    esac

    log_info "CPU: $CPU_GEN"

    # Check for features
    log_info "CPU Features:"
    grep -q asimd /proc/cpuinfo && echo "  ✓ NEON" || echo "  ✗ NEON"
    grep -q asimddp /proc/cpuinfo && echo "  ✓ Dot Product" || echo "  ✗ Dot Product"
    grep -q sve /proc/cpuinfo && echo "  ✓ SVE" || echo "  ✗ SVE"
    grep -q sve2 /proc/cpuinfo && echo "  ✓ SVE2" || echo "  ✗ SVE2"
    echo ""
}

build_phase1() {
    log_info "Building Phase 1 binaries..."

    cd "$BWA_DIR"

    # Clean previous build
    make clean

    # Build multi-version
    log_info "Running 'make multi'..."
    make multi -j$(nproc)

    # Verify binaries exist
    if [ ! -f "bwa-mem2" ]; then
        log_error "Dispatcher binary 'bwa-mem2' not created!"
        exit 1
    fi

    # Check which generation-specific binaries were created
    log_info "Generated binaries:"
    ls -lh bwa-mem2* 2>/dev/null || log_warn "No binaries found"

    # Test dispatcher
    log_info "Testing dispatcher:"
    ./bwa-mem2 2>&1 | head -20 || true

    cd "$SCRIPT_DIR"
}

setup_test_data() {
    log_info "Setting up test data..."

    mkdir -p "$TEST_DIR"
    cd "$TEST_DIR"

    # Check if reference exists
    if [ ! -f "$REFERENCE" ]; then
        log_info "Downloading E. coli reference genome..."
        wget -q -O ecoli.fa.gz \
            "ftp://ftp.ncbi.nlm.nih.gov/genomes/all/GCF/000/005/845/GCF_000005845.2_ASM584v2/GCF_000005845.2_ASM584v2_genomic.fna.gz"
        gunzip ecoli.fa.gz
    fi

    # Check if index exists
    if [ ! -f "${REFERENCE}.bwt.2bit.64" ]; then
        log_info "Indexing reference..."
        "$BWA_DIR/bwa-mem2" index "$REFERENCE"
    fi

    # Check if reads exist
    if [ ! -f "$READS_1" ] || [ ! -f "$READS_2" ]; then
        log_warn "Test reads not found. Please provide:"
        log_warn "  - $TEST_DIR/$READS_1"
        log_warn "  - $TEST_DIR/$READS_2"
        log_warn "You can use wgsim or similar tools to generate synthetic reads."
        exit 1
    fi

    log_info "Test data ready."
    cd "$SCRIPT_DIR"
}

run_benchmark() {
    local BINARY=$1
    local OUTPUT_PREFIX=$2
    local ITERATIONS=$3

    log_info "Running benchmark: $OUTPUT_PREFIX (${ITERATIONS}x)"

    mkdir -p "$RESULTS_DIR"
    cd "$TEST_DIR"

    local TIMES_FILE="$RESULTS_DIR/${OUTPUT_PREFIX}_times.txt"
    local SAM_OUTPUT="$RESULTS_DIR/${OUTPUT_PREFIX}_output.sam"

    # Clear previous results
    > "$TIMES_FILE"

    for i in $(seq 1 $ITERATIONS); do
        log_info "  Iteration $i/$ITERATIONS..."

        # Run with time measurement
        TIME_OUTPUT=$( { time "$BINARY" mem -t $THREADS \
            "$REFERENCE" "$READS_1" "$READS_2" > "$SAM_OUTPUT" 2>&1; } 2>&1 )

        # Extract real time (format: "real 0m2.587s")
        REAL_TIME=$(echo "$TIME_OUTPUT" | grep "^real" | awk '{print $2}')
        echo "$REAL_TIME" >> "$TIMES_FILE"

        log_info "    Time: $REAL_TIME"
    done

    # Calculate statistics
    log_info "Computing statistics..."
    python3 - <<EOF
import sys
times_file = "$TIMES_FILE"
with open(times_file) as f:
    times = []
    for line in f:
        # Parse "0m2.587s" format
        line = line.strip().replace('m', ' ').replace('s', '')
        parts = line.split()
        if len(parts) == 2:
            minutes, seconds = float(parts[0]), float(parts[1])
            times.append(minutes * 60 + seconds)

if times:
    times.sort()
    n = len(times)
    median = times[n//2] if n % 2 else (times[n//2-1] + times[n//2]) / 2
    mean = sum(times) / n
    min_time = min(times)
    max_time = max(times)

    print(f"Results for $OUTPUT_PREFIX:")
    print(f"  Iterations: {n}")
    print(f"  Mean:   {mean:.3f}s")
    print(f"  Median: {median:.3f}s")
    print(f"  Min:    {min_time:.3f}s")
    print(f"  Max:    {max_time:.3f}s")

    # Save summary
    with open("$RESULTS_DIR/${OUTPUT_PREFIX}_summary.txt", 'w') as out:
        out.write(f"{mean:.3f}\n")
else:
    print("No valid times recorded!")
    sys.exit(1)
EOF

    # Validate output
    local ALIGNMENT_COUNT=$(grep -c "^[^@]" "$SAM_OUTPUT" || true)
    log_info "Alignment count: $ALIGNMENT_COUNT"
    echo "$ALIGNMENT_COUNT" > "$RESULTS_DIR/${OUTPUT_PREFIX}_count.txt"

    cd "$SCRIPT_DIR"
}

compare_results() {
    log_info "Comparing Phase 1 vs Baseline..."

    if [ ! -f "$RESULTS_DIR/baseline_summary.txt" ]; then
        log_error "Baseline results not found. Run: $0 baseline"
        exit 1
    fi

    if [ ! -f "$RESULTS_DIR/phase1_summary.txt" ]; then
        log_error "Phase 1 results not found. Run: $0 phase1"
        exit 1
    fi

    python3 - <<EOF
baseline_time = float(open("$RESULTS_DIR/baseline_summary.txt").read().strip())
phase1_time = float(open("$RESULTS_DIR/phase1_summary.txt").read().strip())

speedup = baseline_time / phase1_time
improvement = (baseline_time - phase1_time) / baseline_time * 100

print("\n" + "="*60)
print("PHASE 1 PERFORMANCE COMPARISON")
print("="*60)
print(f"Baseline time:  {baseline_time:.3f}s")
print(f"Phase 1 time:   {phase1_time:.3f}s")
print(f"Speedup:        {speedup:.2f}x")
print(f"Improvement:    {improvement:.1f}%")
print("-"*60)

# Check if we met the target
if speedup >= 1.25:
    print("✅ PASS: Achieved ≥1.25x speedup target!")
    exit_code = 0
elif speedup >= 1.10:
    print("⚠️  PARTIAL: Modest improvement (1.1-1.24x)")
    exit_code = 0
else:
    print("❌ FAIL: Did not achieve minimum 1.1x speedup")
    exit_code = 1

# Check correctness
baseline_count = int(open("$RESULTS_DIR/baseline_count.txt").read().strip())
phase1_count = int(open("$RESULTS_DIR/phase1_count.txt").read().strip())

print("\nCORRECTNESS CHECK:")
print(f"Baseline alignments: {baseline_count}")
print(f"Phase 1 alignments:  {phase1_count}")

if baseline_count == phase1_count:
    print("✅ PASS: Alignment counts match")
else:
    print("❌ FAIL: Alignment counts differ!")
    exit_code = 1

print("="*60 + "\n")
exit(exit_code)
EOF

    EXIT_CODE=$?

    if [ $EXIT_CODE -eq 0 ]; then
        log_info "Phase 1 validation: PASSED ✅"
    else
        log_error "Phase 1 validation: FAILED ❌"
    fi

    exit $EXIT_CODE
}

################################################################################
# Main Script
################################################################################

main() {
    local MODE=${1:-help}

    case "$MODE" in
        baseline)
            log_info "=== Running BASELINE benchmark ==="
            check_cpu
            setup_test_data

            # Build baseline (single version with basic flags)
            cd "$BWA_DIR"
            make clean
            make arch="-march=armv8-a+simd"
            cd "$SCRIPT_DIR"

            run_benchmark "$BWA_DIR/bwa-mem2" "baseline" $ITERATIONS
            log_info "Baseline complete. Results in: $RESULTS_DIR"
            ;;

        phase1)
            log_info "=== Running PHASE 1 benchmark ==="
            check_cpu
            build_phase1
            setup_test_data
            run_benchmark "$BWA_DIR/bwa-mem2" "phase1" $ITERATIONS
            log_info "Phase 1 complete. Results in: $RESULTS_DIR"
            ;;

        compare)
            compare_results
            ;;

        full)
            log_info "=== Running FULL test (baseline + phase1 + compare) ==="
            $0 baseline
            $0 phase1
            $0 compare
            ;;

        clean)
            log_info "Cleaning test artifacts..."
            rm -rf "$RESULTS_DIR"
            cd "$BWA_DIR" && make clean
            log_info "Clean complete."
            ;;

        *)
            echo "BWA-MEM2 ARM Phase 1 Test Script"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  baseline  - Build and benchmark baseline (unoptimized)"
            echo "  phase1    - Build and benchmark Phase 1 (optimized)"
            echo "  compare   - Compare baseline vs phase1 results"
            echo "  full      - Run all tests (baseline + phase1 + compare)"
            echo "  clean     - Clean test artifacts"
            echo ""
            echo "Example workflow:"
            echo "  $0 full"
            echo ""
            echo "Or step-by-step:"
            echo "  $0 baseline"
            echo "  $0 phase1"
            echo "  $0 compare"
            exit 1
            ;;
    esac
}

main "$@"
