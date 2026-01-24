# SSE to NEON Intrinsics Mapping

## Overview

BWA-MEM2 uses SSE2/SSE4.1 intrinsics extensively. This document maps them to ARM NEON equivalents.

## Data Types

| SSE | NEON | Description |
|-----|------|-------------|
| `__m128i` | `int8x16_t`, `int16x8_t`, `int32x4_t` | 128-bit integer vector |
| `__m128` | `float32x4_t` | 128-bit float vector |

## Common Operations

### Load/Store

| SSE | NEON | Notes |
|-----|------|-------|
| `_mm_load_si128()` | `vld1q_s32()` | Aligned load |
| `_mm_loadu_si128()` | `vld1q_s32()` | Unaligned load (same on NEON) |
| `_mm_store_si128()` | `vst1q_s32()` | Aligned store |
| `_mm_storeu_si128()` | `vst1q_s32()` | Unaligned store |

### Arithmetic

| SSE | NEON | Notes |
|-----|------|-------|
| `_mm_add_epi8()` | `vaddq_s8()` | 8-bit add |
| `_mm_adds_epu8()` | `vqaddq_u8()` | Saturating add (unsigned) |
| `_mm_subs_epu8()` | `vqsubq_u8()` | Saturating sub (unsigned) |
| `_mm_max_epu8()` | `vmaxq_u8()` | Maximum (unsigned) |
| `_mm_min_epu8()` | `vminq_u8()` | Minimum (unsigned) |

### Comparison

| SSE | NEON | Notes |
|-----|------|-------|
| `_mm_cmpeq_epi8()` | `vceqq_s8()` | Compare equal |
| `_mm_cmpgt_epi8()` | `vcgtq_s8()` | Compare greater than |
| `_mm_movemask_epi8()` | `vshrn_n_u16() + vget_lane_u64()` | Extract sign bits (complex) |

### Shifts

| SSE | NEON | Notes |
|-----|------|-------|
| `_mm_slli_si128()` | `vextq_s8(vzero, v, 16-n)` | Byte shift left |
| `_mm_srli_si128()` | `vextq_s8(v, vzero, n)` | Byte shift right |
| `_mm_slli_epi32()` | `vshlq_n_s32()` | Element shift left |
| `_mm_srli_epi32()` | `vshrq_n_s32()` | Element shift right |

## Complex Operations

### Movemask (Sign Bit Extraction)

SSE:
```cpp
int mask = _mm_movemask_epi8(v);
```

NEON (requires multiple instructions):
```cpp
uint8x16_t tmp = vshrq_n_u8(vreinterpretq_u8_s8(v), 7);
uint16x8_t tmp16 = vpaddlq_u8(tmp);
uint32x4_t tmp32 = vpaddlq_u16(tmp16);
uint64x2_t tmp64 = vpaddlq_u32(tmp32);
uint64_t mask = vgetq_lane_u64(tmp64, 0) | (vgetq_lane_u64(tmp64, 1) << 8);
```

## BWA-MEM2 Specific Patterns

### Smith-Waterman (bandedSWA.cpp)

Key operation: `_mm_max_epu8()` for tracking max scores
- NEON equivalent: `vmaxq_u8()`
- Performance: Nearly identical

### FM-Index Search

Key operations: Comparisons and bit manipulation
- Need careful handling of `_mm_movemask_epi8()`
- Consider restructuring algorithm for ARM

## Performance Considerations

1. **NEON is in-order** vs x86 out-of-order: May need more instruction-level parallelism
2. **No AVX-512**: Graviton3E SVE provides 256-bit, not 512-bit
3. **Cache differences**: Graviton3 has different cache hierarchy than x86

## Next Steps

1. Audit all SSE usage in BWA-MEM2
2. Create compatibility layer (`arm_compat.h`)
3. Benchmark individual operations
4. Profile hottest code paths
