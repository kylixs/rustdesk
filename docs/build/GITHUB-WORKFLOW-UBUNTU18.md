# Adding Ubuntu 18.04 Build Job to GitHub Workflow

This document explains how to add the Ubuntu 18.04 build job to the GitHub Actions workflow.

## Overview

The `build-rustdesk-ubuntu18` job uses:
- **Docker**: Ubuntu 18.04 container via `rustdesk-org/run-on-arch-action`
- **Build Script**: Local `build-for-ubuntu18.sh` script
- **PIC Support**: Includes all `-fPIC` and `-DPIC` fixes for hwcodec and opus

## Integration Steps

### Option 1: Manual Integration

1. **Open the workflow file**:
   ```bash
   vim .github/workflows/flutter-build.yml
   ```

2. **Find the insertion point** (after `build-rustdesk-linux` job, around line 1651):
   ```yaml
   build-rustdesk-linux:
     # ... existing job content ...
     # Last step of build-rustdesk-linux job

   # INSERT HERE
   ```

3. **Copy the job definition** from `.github/workflows/build-ubuntu18-job.yml` and paste it after line 1651

4. **Verify indentation**: Ensure the job is at the same indentation level as other jobs (2 spaces)

### Option 2: Automated Integration (Recommended)

Use this Python script to automatically insert the job:

```python
#!/usr/bin/env python3
import re

# Read the job definition
with open('.github/workflows/build-ubuntu18-job.yml', 'r') as f:
    ubuntu18_job = f.read()

# Remove the comment header lines (first 3 lines)
ubuntu18_job_lines = ubuntu18_job.split('\n')[3:]
ubuntu18_job = '\n'.join(ubuntu18_job_lines)

# Read the main workflow
with open('.github/workflows/flutter-build.yml', 'r') as f:
    workflow = f.read()

# Find the insertion point (after build-rustdesk-linux job)
# Look for the pattern where build-appimage starts
insertion_point = workflow.find('\n  build-appimage:')

if insertion_point == -1:
    print("Error: Could not find insertion point")
    exit(1)

# Insert the Ubuntu 18 job before build-appimage
new_workflow = workflow[:insertion_point] + '\n' + ubuntu18_job + workflow[insertion_point:]

# Write back
with open('.github/workflows/flutter-build.yml', 'w') as f:
    f.write(new_workflow)

print("✓ Successfully added build-rustdesk-ubuntu18 job to flutter-build.yml")
```

Save as `scripts/add-ubuntu18-workflow.py` and run:
```bash
python3 scripts/add-ubuntu18-workflow.py
```

## Job Details

### Matrix Configuration

Currently only x86_64 is configured:
```yaml
matrix:
  job:
    - {
        arch: x86_64,
        target: x86_64-unknown-linux-gnu,
        distro: ubuntu18.04,
        on: ubuntu-22.04,
        deb_arch: amd64,
        vcpkg-triplet: x64-linux,
      }
```

To add aarch64 support, add:
```yaml
    - {
        arch: aarch64,
        target: aarch64-unknown-linux-gnu,
        distro: ubuntu18.04,
        on: ubuntu-22.04-arm,
        deb_arch: arm64,
        vcpkg-triplet: arm64-linux,
      }
```

### Build Process

The job executes these steps:

1. **Setup**: Export cache variables, maximize disk space, checkout code
2. **Install Rust**: Install Rust toolchain ${{ env.RUST_VERSION }}
3. **Cache vcpkg**: Restore cached vcpkg dependencies (if available)
   - Caches: `vcpkg/installed`, `vcpkg/packages`, `vcpkg/buildtrees`
   - Cache key based on: `vcpkg.json`, triplet files, and overlay ports
4. **Docker Container**: Run Ubuntu 18.04 container with:
   - **Install System Dependencies**: clang, cmake, libgtk-3-dev, etc.
   - **Install Rust and Flutter** inside container (in `install:` step)
   - **Upgrade Python**: Ubuntu 18.04 ships with Python 3.6, upgrade to 3.8 (required by vcpkg)
   - **Install vcpkg dependencies**: Directly call `scripts/install-vcpkg-for-ubuntu18.sh` with all special handling
   - **Execute Build**: `build-for-ubuntu18.sh`
5. **Post-build**: Rename deb to include `-ubuntu18` suffix
6. **Upload Artifacts**: Upload deb package and build log

### Special Handling for Ubuntu 18.04

The build includes several Ubuntu 18.04-specific workarounds:
- **Python 3.8 Upgrade**: vcpkg requires Python 3.7+
- **AOM Overlay Port**: Fixes AVX2 intrinsic compatibility
- **libyuv Overlay Port**: Uses compatible fork
- **Opus PIC Fix**: Patches portfile for proper PIC compilation
- **Complete vcpkg Cache Cleanup**: Ensures fresh build with correct flags

See [UBUNTU18-SPECIAL-HANDLING.md](UBUNTU18-SPECIAL-HANDLING.md) for details

### Environment Variables

The job uses these environment variables from the workflow:
- `RUST_VERSION`: Rust toolchain version (e.g., "1.75")
- `FLUTTER_VERSION`: Flutter version (e.g., "3.24.5")
- `VERSION`: RustDesk version (e.g., "1.4.3")

### Build Script Integration

The job runs:
```bash
bash ./build-for-ubuntu18.sh
```

This script includes:
- **Step 1**: Generate Flutter Rust Bridge
- **Step 2**: Build Rust library (with PIC fixes)
- **Step 3**: Build Flutter application
- **Step 4**: Package DEB

### Artifacts

The job produces:
- **Debian Package**: `rustdesk-{VERSION}-{arch}-ubuntu18.deb`
- **Build Log**: `build.log` (uploaded on success or failure)

## vcpkg Caching

The workflow uses GitHub Actions cache to speed up subsequent builds:

```yaml
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
```

**Cache Strategy**:
- **First Build**: ~40-50 minutes (compiles all vcpkg dependencies)
- **Cached Builds**: ~15-20 minutes (reuses compiled dependencies)
- **Cache Invalidation**: Automatic when vcpkg.json, triplet files, or overlay ports change

**Cached Directories**:
- `vcpkg/installed` - Compiled libraries and headers
- `vcpkg/packages` - Package staging area
- `vcpkg/buildtrees` - Build artifacts

**Important Notes**:
- vcpkg caching works because the workflow directly calls `scripts/install-vcpkg-for-ubuntu18.sh`
- Rust and Flutter are installed in the Docker container's `install:` step (reusing GitHub Actions)
- The vcpkg install script applies all 7 special handling steps for Ubuntu 18.04
- Cache is restored before Docker container runs, so vcpkg directory is mounted into container
- If triplet or overlay ports change, cache key changes and vcpkg rebuilds from scratch

## vcpkg PIC Configuration

The build includes the critical PIC fixes:

### 1. vcpkg Triplet (vcpkg/triplets/x64-linux.cmake)
```cmake
set(VCPKG_C_FLAGS "-fPIC -DPIC")
set(VCPKG_CXX_FLAGS "-fPIC -DPIC")
```

### 2. Opus Portfile (res/vcpkg/opus/portfile.cmake)
```cmake
vcpkg_cmake_configure(
    # ...
    "-DCMAKE_C_FLAGS=${VCPKG_C_FLAGS}"
    "-DCMAKE_CXX_FLAGS=${VCPKG_CXX_FLAGS}"
)
```

### 3. Library Search Order (build-for-ubuntu18.sh)
```bash
# vcpkg MUST come first to override system libs
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"
```

## Testing the Workflow

### Local Testing with act

You can test the workflow locally using [act](https://github.com/nektos/act):

```bash
# Install act
curl -s https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash

# Run the Ubuntu 18 job locally
act -j build-rustdesk-ubuntu18 --container-architecture linux/amd64
```

### GitHub Actions Testing

1. Push to a feature branch
2. Create a pull request
3. Check the Actions tab for workflow execution
4. Download artifacts from the workflow run

## Troubleshooting

### Job Fails with "No space left on device"

Increase swap space or remove more directories in the "Maximize build space" step:
```yaml
- name: Maximize build space
  run: |
    sudo rm -rf /opt/ghc
    sudo rm -rf /usr/local/lib/android
    sudo rm -rf /usr/share/dotnet
    sudo rm -rf /usr/local/share/boost  # Add this
    df -h
```

### vcpkg Installation Fails

Check that the triplet has PIC flags:
```bash
grep -i "fPIC" vcpkg/triplets/x64-linux.cmake
```

Expected output:
```
set(VCPKG_C_FLAGS "-fPIC -DPIC")
set(VCPKG_CXX_FLAGS "-fPIC -DPIC")
```

### PIC Linking Errors

Verify library search order in `build-for-ubuntu18.sh`:
- vcpkg paths MUST come before system paths
- System Ubuntu 18 libraries do NOT have PIC

### Build Takes Too Long

The first build takes ~40-50 minutes due to vcpkg compilation. Subsequent builds use GitHub Actions cache and are much faster (~15-20 minutes).

**vcpkg caching is now enabled by default** in the workflow. The cache is automatically invalidated when:
- `vcpkg.json` changes (new dependencies)
- Triplet files change (PIC flags, compiler options)
- Overlay ports change (AOM, libyuv, opus portfiles)

To manually clear the cache:
1. Go to Actions → Caches in your GitHub repository
2. Delete caches matching `vcpkg-ubuntu18-*`
3. Next build will recompile from scratch

## Related Documentation

- [BUILD-UBUNTU18.md](BUILD-UBUNTU18.md) - Complete Ubuntu 18 build guide
- [setup-for-ubuntu18-README.md](../scripts/setup-for-ubuntu18-README.md) - Setup script documentation
- [GitHub Actions Documentation](https://docs.github.com/en/actions)
- [run-on-arch-action](https://github.com/uraimo/run-on-arch-action) - Multi-architecture Docker action

## Summary

This job enables automated Ubuntu 18.04 builds in GitHub Actions using the local build script with all necessary PIC fixes for hwcodec and opus. The job produces a Debian package tagged with `-ubuntu18` for easy identification.

**Key Features**:
- ✅ Uses local `build-for-ubuntu18.sh` script
- ✅ Reuses GitHub Actions for Rust and Flutter installation (in Docker `install:` step)
- ✅ Directly calls `scripts/install-vcpkg-for-ubuntu18.sh` with all special handling (Python upgrade, AOM/libyuv overlays, opus PIC fix)
- ✅ Includes all PIC fixes (vcpkg triplet, opus portfile, library search order)
- ✅ Runs in Ubuntu 18.04 Docker container
- ✅ **vcpkg caching enabled** - First build ~40-50 min, cached builds ~15-20 min
- ✅ Automatic cache invalidation when dependencies or triplet files change
- ✅ Produces properly tagged Debian packages
- ✅ Uploads build artifacts and logs
- ✅ Supports matrix builds for multiple architectures
