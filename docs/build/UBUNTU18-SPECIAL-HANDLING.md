# Ubuntu 18.04 Special Handling in Build Scripts

This document describes the special handling required for building RustDesk on Ubuntu 18.04.

## Overview

The `install-vcpkg-for-ubuntu18.sh` script contains several Ubuntu 18.04-specific workarounds that are automatically applied when building.

## Special Handling Details

### 1. Python Version Upgrade (Lines 69-94)

**Problem**: Ubuntu 18.04 ships with Python 3.6, but vcpkg requires Python 3.7+

**Solution**:
```bash
# Check Python version
PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP '\d+\.\d+' | head -1)

if [ "$(echo "$PYTHON_VERSION < 3.7" | bc -l)" -eq 1 ]; then
    # Add deadsnakes PPA and install Python 3.8
    sudo add-apt-repository -y ppa:deadsnakes/ppa
    sudo apt install -y python3.8 python3.8-dev python3.8-distutils

    # Set Python 3.8 as default
    sudo update-alternatives --set python3 /usr/bin/python3.8
fi
```

**Impact**: vcpkg cmake scripts require Python 3.7+ to parse JSON files

### 2. AOM Overlay Port (Lines 140-190)

**Problem**: Ubuntu 18.04 GCC doesn't support `_mm256_set_m128i` intrinsic used in AOM's AVX2 code

**Solution**: Custom overlay port with AVX2 compatibility fix
```cmake
vcpkg_replace_string("${SOURCE_PATH}/aom_dsp/flow_estimation/x86/disflow_avx2.c"
    "#include \"aom_dsp/flow_estimation/disflow.h\""
    "#include \"aom_dsp/flow_estimation/disflow.h\"
#ifndef _mm256_set_m128i
#define _mm256_set_m128i(hi, lo) _mm256_insertf128_si256(_mm256_castsi128_si256(lo), (hi), 1)
#endif"
)
```

**Files Created**:
- `res/vcpkg/aom/portfile.cmake`
- `res/vcpkg/aom/vcpkg.json`

**Why**: The `_mm256_set_m128i` intrinsic was added in GCC 7, but Ubuntu 18.04 uses GCC 7.5 which has incomplete support

### 3. libyuv Overlay Port (Lines 210-256)

**Problem**: Default vcpkg libyuv uses incompatible version for Ubuntu 18.04

**Solution**: Custom overlay port pointing to compatible fork
```cmake
vcpkg_from_github(
    OUT_SOURCE_PATH SOURCE_PATH
    REPO kylixs/libyuv
    REF main
    SHA512 9ee540f088882d598457c65d736c01c8786723a05aaa8dec6257550657bbc646...
    HEAD_REF main
)
```

**Files Created**:
- `res/vcpkg/libyuv/portfile.cmake`
- `res/vcpkg/libyuv/vcpkg.json`

### 4. Opus Portfile PIC Fix (Lines 260-278)

**Problem**: Default opus portfile doesn't pass `-DPIC` macro to assembly code

**Solution**: Add CMAKE_POSITION_INDEPENDENT_CODE to opus portfile
```cmake
# Check if already fixed
if ! grep -q "CMAKE_POSITION_INDEPENDENT_CODE" "$OPUS_PORTFILE"; then
    # Add after -DOPUS_BUILD_TESTING=OFF
    sed -i '/DOPUS_BUILD_TESTING=OFF/a\        -DCMAKE_POSITION_INDEPENDENT_CODE=ON' "$OPUS_PORTFILE"
fi
```

**Why**: Required for shared library linking (`liblibrustdesk.so`)

### 5. Complete vcpkg Cache Cleanup (Lines 96-135)

**Why**: vcpkg aggressively caches builds, and changing triplet flags requires full rebuild

**What Gets Cleaned**:
- `installed/$VCPKG_TRIPLET/` - Installed libraries
- `buildtrees/` - Build artifacts and object files (CRITICAL)
- `packages/` - Package staging area
- `installed/vcpkg/status` - Installation status database (CRITICAL)

**Code**:
```bash
# Clean build trees (contains cached object files)
rm -rf buildtrees/*

# Clean status database (prevents vcpkg from skipping reinstall)
rm -f installed/vcpkg/status
```

**Note**: Without cleaning `status` file, vcpkg will skip reinstallation even after triplet changes

### 6. Dependency Verification (Lines 331-394)

**Checks**:
- Library files exist: `libaom.a`, `libyuv.a`, `libvpx.a`, `libopus.a`
- Header files exist: `aom/aom_image.h`, `libyuv.h`, `vpx/vpx_codec.h`, `opus/opus.h`
- File sizes are non-zero

**Failure Handling**:
- Lists all missing files
- Suggests checking install logs
- Exits with error code 1

### 7. PIC Verification (Lines 396-428)

**What It Does**:
- Extracts object file from `libopus.a`
- Checks for absolute relocations using `readelf -r`
- Counts `R_X86_64_32` relocations

**Expected Result**: 0 absolute relocations (indicates correct PIC compilation)

**Code**:
```bash
ABSOLUTE_RELOCS=$(readelf -r "$OBJ_FILE" 2>/dev/null | grep -c "R_X86_64_32" || true)

if [ "$ABSOLUTE_RELOCS" -eq 0 ]; then
    echo "✓ 无绝对重定位（PIC 编译正确）"
else
    echo "⚠️  发现 $ABSOLUTE_RELOCS 个绝对重定位"
fi
```

## Integration with build-for-ubuntu18.sh

The `build-for-ubuntu18.sh` script doesn't directly call `install-vcpkg-for-ubuntu18.sh`. Instead, it assumes vcpkg dependencies are already installed.

**Typical Workflow**:
1. **Local builds**: Run `scripts/setup-for-ubuntu18.sh` (calls `install-vcpkg-for-ubuntu18.sh`)
2. **GitHub Actions**: Directly call `scripts/install-vcpkg-for-ubuntu18.sh` (Rust/Flutter already installed)
3. Run `build-for-ubuntu18.sh` (builds RustDesk)

## GitHub Actions Considerations

When integrating into GitHub Actions, these special handling steps must be accounted for:

### Option 1: Directly call install-vcpkg script in workflow (Recommended)
```yaml
install: |
  # Install Rust and Flutter in Docker container
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --default-toolchain ${{ env.RUST_VERSION }} -y
  wget https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${{ env.FLUTTER_VERSION }}-stable.tar.xz
  tar -xf flutter_linux_${{ env.FLUTTER_VERSION }}-stable.tar.xz

run: |
  cd /workspace
  # Upgrade Python (vcpkg requires 3.7+)
  apt-get install -y software-properties-common bc
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update && apt-get install -y python3.8
  update-alternatives --set python3 /usr/bin/python3.8

  bash scripts/install-vcpkg-for-ubuntu18.sh  # Only install vcpkg dependencies
  bash build-for-ubuntu18.sh
```

**Pros**: Reuses GitHub Actions for Rust/Flutter, enables vcpkg caching
**Cons**: Requires Python upgrade inside container

### Option 2: Pre-bake dependencies in Docker image
Create custom Docker image with:
- Python 3.8
- vcpkg pre-installed with all dependencies
- All overlay ports configured

**Pros**: Much faster builds
**Cons**: Requires maintaining custom Docker image

### Option 3: Use local setup script in workflow
```yaml
run: |
  cd /workspace
  bash scripts/setup-for-ubuntu18.sh  # Installs Rust, Flutter, and vcpkg
  bash build-for-ubuntu18.sh
```

**Pros**: Simple, uses tested scripts
**Cons**: Slower (duplicates Rust/Flutter installation), harder to cache

## Recommended Approach for CI

The workflow in `.github/workflows/build-ubuntu18-job.yml` implements the recommended approach:

```yaml
# 1. Add vcpkg caching BEFORE Docker container step
- name: Cache vcpkg dependencies
  uses: actions/cache@v4
  with:
    path: |
      vcpkg/installed
      vcpkg/packages
      vcpkg/buildtrees
    key: vcpkg-ubuntu18-${{ matrix.job.arch }}-${{ hashFiles('vcpkg.json', 'vcpkg/triplets/x64-linux.cmake', 'res/vcpkg/**') }}
    restore-keys: |
      vcpkg-ubuntu18-${{ matrix.job.arch }}-

# 2. Inside Docker container, upgrade Python and install vcpkg
run: |
  cd /workspace

  # Upgrade Python to 3.8 (vcpkg requires 3.7+)
  apt-get install -y software-properties-common bc
  add-apt-repository -y ppa:deadsnakes/ppa
  apt-get update
  apt-get install -y python3.8 python3.8-dev python3.8-distutils
  update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1
  update-alternatives --set python3 /usr/bin/python3.8

  # Install vcpkg dependencies (Rust and Flutter already in 'install' step)
  bash scripts/install-vcpkg-for-ubuntu18.sh

  # Build RustDesk
  bash build-for-ubuntu18.sh
```

**Why This Works**:
1. **vcpkg caching** speeds up subsequent builds (first build ~40-50 min, cached ~15-20 min)
2. **Reuses GitHub Actions** for Rust and Flutter installation (in Docker `install:` step)
3. **Python 3.8 upgrade** done inside container before vcpkg install
4. **vcpkg install script** directly applies all 7 special handling steps
5. **Cache invalidation** automatic when vcpkg.json, triplet, or overlay ports change

## Troubleshooting

### Python Version Issues
```bash
python3 --version  # Should be 3.8+
```

If wrong version, manually run:
```bash
sudo update-alternatives --config python3
# Select Python 3.8
```

### AOM Build Failures
Check for AVX2 errors:
```bash
grep "_mm256_set_m128i" vcpkg/buildtrees/aom/*/config*.log
```

Should see the macro definition from overlay port.

### Opus PIC Errors
Verify portfile has PIC flag:
```bash
grep "CMAKE_POSITION_INDEPENDENT_CODE" res/vcpkg/opus/portfile.cmake
```

Should output: `-DCMAKE_POSITION_INDEPENDENT_CODE=ON`

### vcpkg Cache Issues
If build uses old non-PIC libraries despite triplet changes:
```bash
# Full clean
rm -rf vcpkg/installed/x64-linux
rm -rf vcpkg/buildtrees
rm -rf vcpkg/packages
rm -f vcpkg/installed/vcpkg/status  # CRITICAL

# Reinstall
bash scripts/install-vcpkg-for-ubuntu18.sh
```

## Summary Table

| Issue | Ubuntu 18 Problem | Solution | Script Lines |
|-------|------------------|----------|--------------|
| Python | Version 3.6 (too old) | Upgrade to 3.8 via PPA | 69-94 |
| AOM | Missing AVX2 intrinsic | Custom overlay port | 140-190 |
| libyuv | Incompatible version | Compatible fork overlay | 210-256 |
| Opus | Missing PIC flag | Patch portfile | 260-278 |
| vcpkg Cache | Stale builds | Complete cleanup | 96-135 |
| Verification | Silent failures | Check libs/headers | 331-394 |
| PIC | Wrong compiler flags | Verify relocations | 396-428 |

All these fixes are automatically applied by `install-vcpkg-for-ubuntu18.sh` and are required for successful builds on Ubuntu 18.04.
