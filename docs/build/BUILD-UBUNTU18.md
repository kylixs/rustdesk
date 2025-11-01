# Building RustDesk on Ubuntu 18.04

This guide documents the process for building RustDesk on Ubuntu 18.04 in a Docker environment, including solutions for the `-fPIC` linking issue.

## Prerequisites

- Docker environment with Ubuntu 18.04
- Root access for initial setup
- User account (UID 1000 recommended) for building

## Quick Start

For a quick setup, use the provided automation script:

```bash
# Inside Docker container as user (not root)
cd /data/work/projects/rustdesk
bash scripts/setup-for-ubuntu18.sh
```

This script will:
1. Install all required dependencies
2. Configure vcpkg with `-fPIC` support
3. Set up Rust 1.75 toolchain
4. Set up Flutter 3.24.5
5. Install vcpkg dependencies (aom, libyuv, opus, vpx, etc.)

## Building

After setup is complete, build with:

```bash
# Export required environment variable
export VCPKG_ROOT=/data/work/projects/rustdesk/vcpkg

# Build release version
cargo build --features hwcodec,flutter,unix-file-copy-paste --release
```

Build artifacts will be in `target/release/`:
- `rustdesk` - Main application binary (5.5MB)
- `service` - Background service binary (427KB)
- `naming` - Naming service binary (487KB)
- `liblibrustdesk.so` - Shared library for Flutter FFI (40MB)

## Technical Details: The `-fPIC` Issue

### Problem

When building RustDesk for Ubuntu 18.04, you may encounter this linking error:

```
error: linking with `cc` failed: exit status: 1
/usr/bin/ld: libmagnum_opus.rlib(opus_decoder.o): relocation R_X86_64_32S
against `.rodata' can not be used when making a shared object;
recompile with -fPIC
```

### Root Cause

RustDesk builds a shared library (`librustdesk.so`) for Flutter FFI integration. This shared library requires all statically linked dependencies to be compiled with `-fPIC` (Position Independent Code).

By default, vcpkg compiles static libraries without `-fPIC`, which causes linking failures when these libraries are incorporated into a shared library.

### Solution

The fix involves three components:

#### 1. Configure vcpkg Triplet with `-fPIC` and `-DPIC`

Modify `vcpkg/triplets/x64-linux.cmake` to add:

```cmake
# Force PIC for static libraries so they can be linked into shared libraries (librustdesk.so)
# -DPIC macro is required for FFmpeg assembly code to use PIC-compatible code paths
set(VCPKG_C_FLAGS "-fPIC -DPIC")
set(VCPKG_CXX_FLAGS "-fPIC -DPIC")
```

**Critical**: Both `-fPIC` flag AND `-DPIC` macro are required:
- `-fPIC`: Tells compiler to generate position-independent code
- `-DPIC`: Preprocessor macro that FFmpeg and opus assembly code use to select PIC-compatible code paths

This ensures all vcpkg dependencies (libopus, libyuv, libvpx, aom, FFmpeg) are compiled with position-independent code.

#### 2. Set VCPKG_ROOT Environment Variable

The `hwcodec` build script requires this variable:

```bash
export VCPKG_ROOT=/data/work/projects/rustdesk/vcpkg
```

#### 3. Fix Opus Portfile to Pass -DPIC Macro

The default opus portfile in vcpkg only sets `CMAKE_POSITION_INDEPENDENT_CODE=ON`, which adds `-fPIC` but doesn't pass the `-DPIC` macro. You need to modify `res/vcpkg/opus/portfile.cmake`:

```cmake
vcpkg_cmake_configure(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS ${FEATURE_OPTIONS}
        -DPACKAGE_VERSION=${VERSION}
        -DOPUS_STACK_PROTECTOR=${STACK_PROTECTOR}
        -DOPUS_INSTALL_PKG_CONFIG_MODULE=ON
        -DOPUS_INSTALL_CMAKE_CONFIG_MODULE=ON
        -DOPUS_BUILD_PROGRAMS=OFF
        -DOPUS_BUILD_TESTING=OFF
        -DCMAKE_POSITION_INDEPENDENT_CODE=ON
        "-DCMAKE_C_FLAGS=${VCPKG_C_FLAGS}"      # Add this line
        "-DCMAKE_CXX_FLAGS=${VCPKG_CXX_FLAGS}"  # Add this line
        ${ADDITIONAL_OPUS_OPTIONS}
```

This ensures the `-DPIC` macro from the triplet is passed to opus assembly code.

#### 4. Configure Library Search Order

**Critical**: Ubuntu 18.04 system libraries (`/usr/lib/x86_64-linux-gnu/libopus.a`, `libavcodec.a`) are NOT compiled with PIC. You must prioritize vcpkg libraries over system libraries.

In `build-for-ubuntu18.sh`, ensure vcpkg paths come FIRST:

```bash
# IMPORTANT: vcpkg libs FIRST to override system libs (system libs don't have PIC)
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# Add library paths for Rust linker (vcpkg first to override system libs without PIC)
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"
```

If system libraries are found first, cargo will link against non-PIC system libraries and cause relocation errors.

#### 5. Configure Cargo.toml Library Types

In `Cargo.toml`, ensure both `cdylib` and `rlib` are specified:

```toml
[lib]
name = "librustdesk"
crate-type = ["cdylib", "rlib"]  # Both types needed
```

- `cdylib`: Creates the shared library for Flutter
- `rlib`: Allows binary targets (rustdesk, service) to link to the library

## Rebuilding After Configuration Changes

If you need to rebuild after modifying vcpkg triplet configuration:

```bash
# Use the rebuild script (handles cache cleanup)
bash scripts/rebuild-vcpkg-with-pic.sh
```

This script:
1. Verifies `-fPIC` configuration in triplet
2. Cleans vcpkg cache (including status database)
3. Reinstalls all vcpkg dependencies with `-fPIC`
4. Verifies object files are compiled with PIC

## Verification

### Verify vcpkg Configuration

```bash
# Check triplet contains -fPIC flags
grep -i "fPIC" vcpkg/triplets/x64-linux.cmake

# Expected output:
# set(VCPKG_C_FLAGS "-fPIC")
# set(VCPKG_CXX_FLAGS "-fPIC")
```

### Verify Object Files

```bash
# Run verification script
bash scripts/verify-vcpkg-pic.sh
```

### Verify Built Shared Library

```bash
# Check for TEXTREL warnings (should have none)
readelf -d target/release/liblibrustdesk.so | grep TEXTREL

# If no output, PIC is correct
```

## Common Issues

### Issue: vcpkg Doesn't Rebuild After Triplet Change

**Symptom**: Still getting `-fPIC` errors after modifying triplet.

**Cause**: vcpkg status database caches installation state and skips reinstallation.

**Solution**:
```bash
# Remove status database (critical step)
rm -f vcpkg/installed/vcpkg/status

# Clean and rebuild
bash scripts/rebuild-vcpkg-with-pic.sh
```

### Issue: hwcodec Build Fails with "NotPresent" Error

**Symptom**: Build fails when compiling `hwcodec` crate.

**Cause**: Missing `VCPKG_ROOT` environment variable.

**Solution**:
```bash
export VCPKG_ROOT=/data/work/projects/rustdesk/vcpkg
```

### Issue: Binary Targets Fail to Compile

**Symptom**: `rustdesk` or `service` binaries fail with module resolution errors.

**Cause**: `Cargo.toml` only specifies `cdylib`, missing `rlib`.

**Solution**: Ensure `Cargo.toml` has:
```toml
crate-type = ["cdylib", "rlib"]
```

### Issue: Still Getting PIC Errors After vcpkg Rebuild

**Symptom**: PIC relocation errors persist even after rebuilding vcpkg libraries with `-fPIC -DPIC`.

**Root Cause**: Ubuntu 18.04 system libraries at `/usr/lib/x86_64-linux-gnu/` (libopus.a, libavcodec.a, libavutil.a) are NOT compiled with PIC. If library search order has system paths before vcpkg paths, cargo will use non-PIC system libraries.

**Solution**: Ensure library search order prioritizes vcpkg in `build-for-ubuntu18.sh`:
```bash
# vcpkg MUST come before system paths
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"
```

**Verification**: Check which library is being used:
```bash
# Extract and verify system library (should show relocations)
cd /usr/lib/x86_64-linux-gnu
ar x libopus.a celt.o
readelf -r celt.o | grep "R_X86_64_32" && echo "System library has NO PIC"

# Extract and verify vcpkg library (should show no relocations)
cd $VCPKG_ROOT/installed/x64-linux/lib
ar x libopus.a celt.c.o
readelf -r celt.c.o | grep "R_X86_64_32" || echo "vcpkg library has PIC"
```

### Issue: Opus Still Has PIC Errors After Triplet Fix

**Symptom**: FFmpeg PIC errors are fixed, but opus still has relocation errors.

**Cause**: The default opus portfile doesn't pass `CMAKE_C_FLAGS` and `CMAKE_CXX_FLAGS`, so the `-DPIC` macro from the triplet is not passed to opus.

**Solution**: Modify `res/vcpkg/opus/portfile.cmake` to add:
```cmake
"-DCMAKE_C_FLAGS=${VCPKG_C_FLAGS}"
"-DCMAKE_CXX_FLAGS=${VCPKG_CXX_FLAGS}"
```

Then rebuild opus:
```bash
cd vcpkg
rm -rf buildtrees/opus packages/opus_x64-linux installed/x64-linux/lib/libopus.*
./vcpkg install opus:x64-linux --overlay-ports=../res/vcpkg/opus
```

## Why Position Independent Code (PIC)?

| Link Target | Needs -fPIC? | Reason |
|-------------|--------------|--------|
| **Executable** (`rustdesk`) | ❌ No | Fixed load address at link time |
| **Static Library** (`.rlib`, `.a`) | ❌ No | Just packaging, linking happens later |
| **Shared Library** (`librustdesk.so`) | ✅ **Required** | Loaded at runtime at variable addresses |

Shared libraries must support:
- Multiple processes sharing the same code segment
- Loading at different virtual addresses per process
- Runtime relocation without modifying code segments

This requires position-independent code generation.

## Performance Impact

PIC code has minimal performance overhead:
- Slightly larger code size (extra GOT/PLT indirection tables)
- Negligible CPU overhead (< 5% in most cases)
- No noticeable impact on remote desktop performance

## Build Time

First-time build on Ubuntu 18.04:
- vcpkg install: ~15-25 minutes (compiles aom, ffmpeg, opus, vpx, yuv)
- cargo build --release: ~10-15 minutes
- **Total**: ~30-40 minutes

Subsequent incremental builds are much faster.

## Docker Setup Example

```bash
# Start Ubuntu 18.04 container with project mounted
docker run -it --name ubuntu-1804 \
  -v /path/to/rustdesk:/data/work/projects/rustdesk \
  ubuntu:18.04 bash

# Inside container, create user
useradd -m -u 1000 -s /bin/bash gongdewei

# Switch to user and run setup
su - gongdewei
cd /data/work/projects/rustdesk
bash scripts/setup-for-ubuntu18.sh
```

## Install rustdesk deb for ubuntu18

```bash
# Install gstreamer1.0-pipewire
./scripts/install-gstreamer1.0-pipewire.sh

# Install rustdesk deb
sudo dpkg -i rustdesk-*ubuntu18*.deb

# fix broken
sudo apt --fix-broken install -y
```

## Additional Resources

- [setup-for-ubuntu18-README.md](../scripts/setup-for-ubuntu18-README.md) - Detailed setup guide
- [REBUILD-GUIDE.md](../scripts/REBUILD-GUIDE.md) - Rebuild instructions
- [vcpkg Triplets Documentation](https://vcpkg.io/en/docs/users/triplets.html)
- [Position Independent Code (Wikipedia)](https://en.wikipedia.org/wiki/Position-independent_code)

## CI Integration

For GitHub Actions or CI/CD pipelines:

```yaml
- name: Configure vcpkg with PIC
  run: |
    echo 'set(VCPKG_C_FLAGS "-fPIC")' >> vcpkg/triplets/x64-linux.cmake
    echo 'set(VCPKG_CXX_FLAGS "-fPIC")' >> vcpkg/triplets/x64-linux.cmake

- name: Install vcpkg dependencies
  run: |
    export VCPKG_ROOT=${{ github.workspace }}/vcpkg
    export CFLAGS="-fPIC"
    export CXXFLAGS="-fPIC"
    $VCPKG_ROOT/vcpkg install --triplet x64-linux

- name: Build RustDesk
  run: |
    export VCPKG_ROOT=${{ github.workspace }}/vcpkg
    cargo build --features hwcodec,flutter,unix-file-copy-paste --release
```

## Troubleshooting

If you encounter issues:

1. **Check vcpkg triplet configuration**: `cat vcpkg/triplets/x64-linux.cmake`
2. **Verify environment**: `echo $VCPKG_ROOT`
3. **Check Cargo.toml**: Verify `crate-type = ["cdylib", "rlib"]`
4. **Clean build**: `cargo clean && bash scripts/rebuild-vcpkg-with-pic.sh`
5. **Review logs**: Check vcpkg logs in `vcpkg/buildtrees/*/config-*.log`

## Summary

The key to building RustDesk on Ubuntu 18.04 is ensuring all static libraries are compiled with PIC (Position Independent Code) support. This requires **five critical steps**:

1. **Configure vcpkg triplet with `-fPIC -DPIC`**: Both the compiler flag AND preprocessor macro are required
   - `-fPIC`: Compiler flag for position-independent code generation
   - `-DPIC`: Preprocessor macro for FFmpeg/opus assembly code to use PIC-compatible paths

2. **Fix opus portfile**: Pass `CMAKE_C_FLAGS` and `CMAKE_CXX_FLAGS` to ensure `-DPIC` macro reaches opus assembly code

3. **Prioritize vcpkg libraries over system libraries**: Ubuntu 18.04 system libraries are NOT compiled with PIC
   - vcpkg paths MUST come first in `LIBRARY_PATH`, `LD_LIBRARY_PATH`, and `RUSTFLAGS`
   - System library libopus.a has absolute relocations that break shared library linking

4. **Set `VCPKG_ROOT` environment variable**: Required by hwcodec build script

5. **Include both `cdylib` and `rlib` in Cargo.toml**: Required for both Flutter FFI and binary targets

These changes enable successful compilation of the shared library (`librustdesk.so`) required for Flutter FFI integration.
