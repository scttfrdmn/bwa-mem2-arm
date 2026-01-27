# macOS Build Issue

**Date:** January 26, 2026
**Status:** Known Issue - Workaround Available

## Problem

macOS build fails with conflicting `memset_s` declarations:

```
ext/safestringlib/include/safe_mem_lib.h:96:16: error: conflicting types for 'memset_s'
   96 | extern errno_t memset_s(void *dest, rsize_t dmax, uint8_t value);
      |                ^
/Applications/Xcode.app/Contents/Developer/.../usr/include/_string.h:176:9: note: previous declaration is here
  176 | errno_t memset_s(void *_LIBC_SIZE(__smax) __s, rsize_t __smax, int __c, rsize_t __n)
```

## Root Cause

- macOS SDK (since 10.9) provides its own `memset_s` function with different signature
- safestringlib also defines `memset_s` with different signature
- Conflict when both headers are included

## Workaround

Build on Linux (AWS Graviton3) instead of macOS. The code compiles successfully on Linux.

## Proper Fix (TODO)

Add conditional compilation to safestringlib or BWA-MEM2 headers:

```cpp
#ifdef __APPLE__
#define memset_s safe_memset_s  // Rename safestringlib version on macOS
#endif
```

Or use `#ifdef` guards to avoid redefinition on macOS.

## Impact

- **Development:** Can still compile individual ARM NEON files locally
- **Testing:** Must be done on AWS Linux anyway (correct architecture)
- **Workaround:** Local development OK, final build on AWS

## Priority

Low - Does not affect production builds on AWS Graviton3 (target platform).
