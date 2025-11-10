# Compilation and Linking Issue Analysis Guide

A comprehensive guide for diagnosing and resolving compilation and linking issues in RustDesk builds, with focus on vcpkg, Rust, Flutter, system libraries, and PIC requirements.

## Table of Contents
- [1. Library and Include Search Paths](#1-library-and-include-search-paths)
- [2. Linking Principles](#2-linking-principles)
  - [2.1 Static vs Dynamic Linking](#21-static-vs-dynamic-linking)
  - [2.2 Symbol Resolution](#22-symbol-resolution)
  - [2.3 Position Independent Code (PIC)](#23-position-independent-code-pic)
  - [2.4 Executable Linking Types](#24-executable-linking-types)
    - [2.4.1 Fully Static Linking](#241-fully-static-linking)
    - [2.4.2 Dynamic Linking](#242-dynamic-linking)
    - [2.4.3 Hybrid Linking (Static libs into Shared Object)](#243-hybrid-linking-static-libs-into-shared-object)
    - [2.4.4 Comparison Table](#244-comparison-table)
    - [2.4.5 Common Linking Errors](#245-common-linking-errors)
    - [2.4.6 Determining Binary Linking Type](#246-determining-binary-linking-type)
    - [2.4.7 Best Practices for RustDesk Ubuntu 18.04](#247-best-practices-for-rustdesk-ubuntu-1804)
- [3. Step-by-Step Checking Methods](#3-step-by-step-checking-methods)
- [4. Essential Tools](#4-essential-tools)
- [5. vcpkg Integration](#5-vcpkg-integration)
- [6. Rust Linking](#6-rust-linking)
- [7. Flutter Compilation](#7-flutter-compilation)
- [8. System Library Conflicts](#8-system-library-conflicts)
- [9. PIC Verification](#9-pic-verification)
- [10. Checking .a and .o Files](#10-checking-a-and-o-files)

---

## 1. Library and Include Search Paths

Understanding search paths is critical for diagnosing linking issues.

### 1.1 Library Search Paths

Libraries are searched in the following order:

#### **Compile-time linking** (when building):
1. **`-L` flags**: Explicit paths passed to the linker via `-L /path/to/libs`
2. **`LIBRARY_PATH`**: Environment variable for GCC/G++ linker search
3. **Default system paths**: `/usr/lib`, `/usr/local/lib`, `/lib`

#### **Runtime linking** (when executing):
1. **`RPATH`/`RUNPATH`**: Embedded in the binary during compilation
2. **`LD_LIBRARY_PATH`**: Environment variable (highest priority)
3. **`/etc/ld.so.conf`**: System-wide library configuration
4. **Default system paths**: `/usr/lib`, `/usr/local/lib`, `/lib`

#### **Example in build-for-ubuntu18.sh**:
```bash
# Compile-time library search (vcpkg first to override system libs)
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LIBRARY_PATH"

# Runtime library search (for running build tools)
export LD_LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu:$LD_LIBRARY_PATH"

# Rust linker flags (vcpkg first)
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"
```

**Why vcpkg first?**
- System libraries on Ubuntu 18.04 lack PIC (Position Independent Code)
- vcpkg libraries are compiled with `-fPIC -DPIC`
- Linker uses the FIRST matching library found
- Therefore vcpkg paths must come BEFORE system paths

#### **Checking library search order**:
```bash
# Check compile-time search paths
gcc -print-search-dirs | grep libraries

# Check runtime search paths for a binary
ldd /path/to/binary

# Check which library will be used
ld --verbose | grep SEARCH_DIR
```

### 1.2 Include Search Paths

Header files are searched in the following order:

#### **C Compiler (gcc)**:
1. **`-I` flags**: Explicit paths via `-I /path/to/includes`
2. **Current directory**: `.` (for `#include "file.h"`)
3. **`C_INCLUDE_PATH`**: Environment variable
4. **`CPATH`**: Environment variable (both C and C++)
5. **Default system paths**: `/usr/include`, `/usr/local/include`
6. **GCC internal paths**: `/usr/lib/gcc/x86_64-linux-gnu/7/include`

#### **C++ Compiler (g++)**:
1. **`-I` flags**: Explicit paths via `-I /path/to/includes`
2. **Current directory**: `.`
3. **`CPLUS_INCLUDE_PATH`**: Environment variable (C++ specific)
4. **`CPATH`**: Environment variable (both C and C++)
5. **Default C++ paths**: `/usr/include/c++/7`, `/usr/include/x86_64-linux-gnu/c++/7`
6. **Default system paths**: `/usr/include`, `/usr/local/include`

#### **Example in build-for-ubuntu18.sh**:
```bash
# Append vcpkg includes (system defaults have priority)
export C_INCLUDE_PATH="$C_INCLUDE_PATH:$VCPKG_INSTALLED/include"
export CPLUS_INCLUDE_PATH="$CPLUS_INCLUDE_PATH:$VCPKG_INSTALLED/include"

# For Flutter Linux build
export CPATH="/usr/include/c++/7:/usr/include/x86_64-linux-gnu/c++/7"
```

**Why append instead of prepend?**
- System headers are usually correct and should be used first
- vcpkg headers are only needed for libraries not available on system
- Prevents conflicts with system headers

#### **Checking include search order**:
```bash
# Check C include paths
gcc -x c -E -v - < /dev/null 2>&1 | grep '^ '

# Check C++ include paths
g++ -x c++ -E -v - < /dev/null 2>&1 | grep '^ '

# Check for specific header
gcc -H -c test.c -o /dev/null
```

### 1.3 pkg-config Search Paths

pkg-config helps find library and include paths:

```bash
# pkg-config search paths (highest to lowest priority)
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig:$PKG_CONFIG_PATH"

# Check what pkg-config finds
pkg-config --libs libavcodec
pkg-config --cflags libavcodec
pkg-config --modversion libavcodec

# Debug pkg-config search
PKG_CONFIG_DEBUG_SPEW=1 pkg-config --libs libavcodec
```

### 1.4 Common Search Path Issues

| Issue | Symptom | Solution |
|-------|---------|----------|
| Wrong library version used | Links to system lib instead of vcpkg | Put vcpkg in `LIBRARY_PATH` first |
| Header not found | `fatal error: xxx.h: No such file` | Add to `C_INCLUDE_PATH` or `-I` |
| Wrong header used | Compilation works but linking fails | Check include search order with `-H` |
| Runtime library not found | `error while loading shared libraries` | Set `LD_LIBRARY_PATH` or use RPATH |
| pkg-config not finding library | `Package xxx was not found` | Add .pc file location to `PKG_CONFIG_PATH` |

---

## 2. Linking Principles

### 2.1 Static vs Dynamic Linking

**Static Linking** (`.a` files):
- Library code copied into final binary
- No runtime dependency
- Larger binary size
- Requires PIC for shared library inclusion

**Dynamic Linking** (`.so` files):
- Binary references external library
- Smaller binary size
- Shared between processes
- Requires library at runtime

### 2.2 Symbol Resolution

Linker resolves symbols in order:
1. Already defined symbols (skip)
2. Search object files (`.o`)
3. Search static libraries (`.a`) - in order specified
4. Search dynamic libraries (`.so`) - in search path order

**Important**: Order matters! Library B depends on A? Link as: `-lB -lA`

### 2.3 Position Independent Code (PIC)

**What is PIC?**
- Code that can run at any memory address
- Required for shared libraries (`.so`)
- Compiled with `-fPIC` flag
- Uses relative addressing instead of absolute

**Why PIC matters for RustDesk Ubuntu 18.04:**
- System libraries (libopus, libaom, libvpx) not compiled with PIC
- Rust builds shared library `liblibrustdesk.so`
- Cannot include non-PIC code in shared library
- vcpkg libraries must be built with `-fPIC -DPIC`

**PIC Error Example:**
```
error: could not compile `magnum-opus`
relocation R_X86_64_32 against `.rodata' can not be used when making a shared object
```

This means: Found non-PIC code (absolute relocation) when building shared library.

### 2.4 Executable Linking Types

Understanding different linking strategies is crucial for building various types of binaries.

#### **2.4.1 Fully Static Linking**

**What is it?**
- All libraries (including libc) compiled into the executable
- No external .so dependencies at runtime
- Single self-contained binary

**How to create:**
```bash
# C/C++
gcc -static main.c -o myapp
g++ -static main.cpp -o myapp

# Rust
cargo build --target x86_64-unknown-linux-musl  # Uses musl libc (static)
# or
RUSTFLAGS="-C target-feature=+crt-static" cargo build --release
```

**Advantages:**
- ✓ No runtime dependencies
- ✓ Works on any Linux system (same architecture)
- ✓ No library version conflicts
- ✓ Easy distribution

**Disadvantages:**
- ✗ Very large binary size (10-100MB+)
- ✗ Cannot use system libraries (NSS, PAM, etc.)
- ✗ No security updates without recompilation
- ✗ Higher memory usage (no sharing between processes)

**When to use:**
- Embedded systems
- Containerized applications (scratch/distroless images)
- Distribution to unknown environments
- Tools that must work without dependencies

**Example:**
```bash
# Static binary example
gcc -static hello.c -o hello
file hello
# Output: ELF 64-bit LSB executable, x86-64, statically linked

ldd hello
# Output: not a dynamic executable

ls -lh hello
# Size: ~800KB (vs ~16KB for dynamic)
```

#### **2.4.2 Dynamic Linking**

**What is it?**
- Executable references external .so files
- Libraries loaded at runtime by dynamic linker
- Most common linking method on Linux

**How to create:**
```bash
# C/C++ (default behavior)
gcc main.c -o myapp
g++ main.cpp -o myapp

# Rust (default)
cargo build --release
```

**Library search at runtime:**
```
1. RPATH/RUNPATH (embedded in binary)
2. LD_LIBRARY_PATH environment variable
3. /etc/ld.so.cache (from /etc/ld.so.conf)
4. /lib, /usr/lib (default system paths)
```

**Advantages:**
- ✓ Small binary size
- ✓ Shared memory between processes
- ✓ Security updates without recompilation
- ✓ Plugins and modules support

**Disadvantages:**
- ✗ Requires libraries at runtime
- ✗ Library version conflicts ("DLL hell")
- ✗ Dependency management needed

**When to use:**
- Desktop applications
- System utilities
- Applications on controlled environments
- When using system libraries (GTK, Qt, etc.)

**Example:**
```bash
# Dynamic binary example
gcc hello.c -o hello
file hello
# Output: ELF 64-bit LSB executable, x86-64, dynamically linked

ldd hello
# Output:
#   linux-vdso.so.1 =>  (0x00007fff1234abcd)
#   libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x00007f1234567890)
#   /lib64/ld-linux-x86-64.so.2 (0x00007f9876543210)

ls -lh hello
# Size: ~16KB
```

#### **2.4.3 Hybrid Linking (Static libs into Shared Object)**

**What is it?**
- Build shared library (.so) that includes static libraries (.a)
- Final .so contains code from .a files
- RustDesk uses this approach!

**How it works:**

```
Source Code          Static Libs         Shared Library
  (Rust)               (.a)                 (.so)
    ↓                   ↓                     ↓
  *.rs    →  [rustc] → *.o  ┐
                             ├→ [linker] → liblibrustdesk.so
  libopus.a     ──────────→ ┘
  libaom.a      ──────────→ ┘
  libvpx.a      ──────────→ ┘
```

**Critical requirement: ALL static libraries MUST be PIC!**

**Why PIC is required:**
- Shared libraries (.so) are loaded at arbitrary memory addresses
- Code must use position-independent addressing
- Non-PIC code has absolute memory references → fails
- This is THE cause of Ubuntu 18.04 PIC errors

**Building .so with static libraries:**

```bash
# Compile static libraries with PIC
gcc -c -fPIC -DPIC opus_encoder.c -o opus_encoder.o
ar rcs libopus.a opus_encoder.o

# Link static library into shared library
gcc -shared -fPIC -o libmylib.so mycode.o -L. -lopus

# Rust example (RustDesk case)
# 1. Static libs: libopus.a, libaom.a, libvpx.a (all with PIC)
# 2. Rust code compiles to .o files
# 3. Linker creates liblibrustdesk.so including static lib code
cargo build --release  # Produces target/release/liblibrustdesk.so
```

**Checking if .so contains code from .a:**

```bash
# Extract symbols from static library
nm libopus.a | grep "T opus_encode"

# Check if symbol exists in .so
nm liblibrustdesk.so | grep "opus_encode"
# If found → static library code is included

# Check .so size (will be larger)
ls -lh liblibrustdesk.so
# Size includes all static library code
```

**Advantages:**
- ✓ Specific library versions bundled
- ✓ Control over library builds (e.g., PIC flags)
- ✓ Fewer runtime dependencies
- ✓ Still shareable between processes

**Disadvantages:**
- ✗ Larger .so size
- ✗ Static lib code not updated independently
- ✗ All static libs MUST be PIC (strict requirement)

**When to use:**
- Custom-built libraries (vcpkg)
- Libraries needing special compile flags
- Bundling specific versions
- Avoiding system library conflicts

**RustDesk Example:**

```bash
# vcpkg builds PIC static libraries
vcpkg install opus:x64-linux  # Creates libopus.a with -fPIC -DPIC

# Rust links static libs into shared library
RUSTFLAGS="-L vcpkg/installed/x64-linux/lib" cargo build --release

# Result: liblibrustdesk.so contains opus, aom, vpx code
file target/release/liblibrustdesk.so
# Output: ELF 64-bit LSB shared object, x86-64

nm target/release/liblibrustdesk.so | grep opus_encode
# Output: 00000000012abcd0 T opus_encode  (symbol present)

ls -lh target/release/liblibrustdesk.so
# Size: ~50MB (includes all static library code)
```

#### **2.4.4 Comparison Table**

| Aspect | Fully Static | Dynamic | Hybrid (Static→.so) |
|--------|-------------|---------|---------------------|
| Binary Size | Very Large (MB) | Small (KB) | Large (MB) |
| Runtime Deps | None | Many .so files | Fewer .so files |
| PIC Required | No | N/A (for .so: yes) | **YES (critical!)** |
| Sharing | No sharing | Shared memory | Shared memory |
| Updates | Recompile | Independent | Mixed |
| Use Case | Embedded/containers | Desktop apps | Custom lib bundling |
| RustDesk | No | No | **Yes (current)** |

#### **2.4.5 Common Linking Errors**

| Error | Linking Type | Cause | Solution |
|-------|-------------|-------|----------|
| `relocation R_X86_64_32 against '.rodata'` | Static→.so | Non-PIC static lib | Rebuild .a with `-fPIC -DPIC` |
| `undefined reference to 'symbol'` | Any | Missing library or wrong order | Add library, check `-l` order |
| `error while loading shared libraries` | Dynamic | .so not found at runtime | Set `LD_LIBRARY_PATH` or RPATH |
| `cannot find -lxxx` | Any | Library not in search path | Add to `LIBRARY_PATH` or `-L` |
| Binary too large | Fully static | All code included | Use dynamic or hybrid |
| `GLIBC_2.XX not found` | Dynamic | Built on newer system | Build on older system or static |

#### **2.4.6 Determining Binary Linking Type**

```bash
# Check if static or dynamic
file mybinary
# "statically linked" → fully static
# "dynamically linked" → dynamic or hybrid

# Check dependencies
ldd mybinary
# "not a dynamic executable" → fully static
# Lists .so files → dynamic or hybrid

# Check if .so contains static lib code
nm -D libmylib.so | grep symbol_from_static_lib
# Symbol found → hybrid (static code included)
# Symbol not found → pure dynamic

# Check for PIC in .so
readelf -d libmylib.so | grep TEXTREL
# No output → PIC compliant ✓
# TEXTREL present → non-PIC ✗ (will fail)
```

#### **2.4.7 Best Practices for RustDesk Ubuntu 18.04**

**Problem**: System static libraries lack PIC → cannot link into .so

**Solution**: vcpkg with PIC flags

```bash
# 1. Build vcpkg libraries with PIC
vcpkg/triplets/x64-linux.cmake:
  set(VCPKG_C_FLAGS "-fPIC -DPIC")
  set(VCPKG_CXX_FLAGS "-fPIC -DPIC")

# 2. Install PIC libraries
vcpkg install opus:x64-linux --overlay-ports=res/vcpkg/opus

# 3. Verify PIC
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep "R_X86_64_32[^S]"
# Should be empty or minimal

# 4. Link with correct path order (vcpkg FIRST)
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# 5. Build
cargo build --release

# 6. Verify final .so
readelf -d target/release/liblibrustdesk.so | grep TEXTREL
# No output → Success ✓
```

**Why this approach?**
- RustDesk needs shared library for Flutter integration
- Must include codec libraries (opus, aom, vpx)
- System libs on Ubuntu 18.04 not PIC-compliant
- vcpkg builds custom PIC versions
- Hybrid linking: static codec libs → liblibrustdesk.so

---

## 3. Step-by-Step Checking Methods

### 3.1 Diagnosis Workflow

```
Issue Occurs
    ↓
Is it a compile error?
    ↓ YES
    Check include paths (Section 1.2)
    Check compiler flags (Section 7)
    ↓ NO
Is it a linking error?
    ↓ YES
    Check library search paths (Section 1.1)
    Check library format (.a vs .so) (Section 4.3)
    Check for PIC issues (Section 9)
    ↓ NO
Is it a runtime error?
    ↓ YES
    Check LD_LIBRARY_PATH (Section 1.1)
    Check RPATH in binary (Section 4.5)
    Check library dependencies (Section 4.6)
```

### 3.2 Common Error Patterns

| Error Pattern | Likely Cause | Check Method |
|---------------|--------------|--------------|
| `cannot find -lxxx` | Library not in search path | Check `LIBRARY_PATH`, use `find` |
| `undefined reference to 'xxx'` | Missing library or wrong order | Use `nm` to find symbol, reorder libs |
| `relocation R_X86_64_32` | Non-PIC code in shared library | Check with `readelf -r`, rebuild with PIC |
| `xxx.h: No such file` | Missing include path | Check `C_INCLUDE_PATH`, use `gcc -H` |
| `version 'GLIBC_2.XX' not found` | Binary compiled for newer glibc | Rebuild on older system or use compat |

---

## 4. Essential Tools

### 4.1 `file` - Identify File Type

```bash
# Check file type
file target/release/liblibrustdesk.so
# Output: ELF 64-bit LSB shared object, x86-64

# Check if library is 32-bit or 64-bit
file vcpkg/installed/x64-linux/lib/libopus.a
# Output: current ar archive (indicates static library)

# Batch check
find vcpkg/installed/x64-linux/lib -name "*.a" -exec file {} \;
```

### 4.2 `nm` - List Symbols

```bash
# List all symbols in object file
nm libopus.a

# Show only defined symbols
nm -g libopus.a | grep " T "

# Show only undefined symbols
nm -u hwcodec.o

# Search for specific symbol
nm -A vcpkg/installed/x64-linux/lib/*.a | grep opus_encode

# Check if symbol exists
nm libopus.a | grep "T opus_encoder_create"
```

**Symbol Types:**
- `T` - Text section (code) - defined
- `U` - Undefined (needs to be resolved)
- `D` - Initialized data
- `B` - Uninitialized data (BSS)
- `R` - Read-only data
- `W` - Weak symbol

### 4.3 `ar` - Archive Tool

```bash
# List contents of .a file
ar -t libopus.a

# Extract object files from archive
ar -x libopus.a

# Extract specific file
ar -x libopus.a opus_encoder.o

# Create static library
ar rcs libmylib.a file1.o file2.o
```

### 4.4 `readelf` - ELF Information

```bash
# Check if compiled with PIC (look for TEXTREL)
readelf -d libopus.a | grep TEXTREL
# No output = PIC, TEXTREL present = non-PIC

# Show relocations (absolute relocations = non-PIC)
readelf -r opus_encoder.o | grep R_X86_64_32

# Check library dependencies
readelf -d liblibrustdesk.so | grep NEEDED

# Show sections
readelf -S libopus.a

# Show symbols (like nm)
readelf -s libopus.a
```

### 4.5 `objdump` - Object Dump

```bash
# Disassemble code
objdump -d libopus.a

# Show all headers
objdump -x libopus.a

# Check relocations
objdump -r opus_encoder.o

# Show dynamic section
objdump -p liblibrustdesk.so

# Check if PIC (look for @PLT calls)
objdump -d libopus.a | grep @PLT
```

### 4.6 `ldd` - List Dynamic Dependencies

```bash
# Show runtime library dependencies
ldd target/release/liblibrustdesk.so

# Show all dependencies including indirect
ldd -v target/release/liblibrustdesk.so

# Check for missing dependencies
ldd target/release/liblibrustdesk.so | grep "not found"

# Show which library is actually loaded
LD_DEBUG=libs ldd target/release/liblibrustdesk.so
```

### 4.7 `pkg-config` - Library Configuration

```bash
# Get compile flags
pkg-config --cflags libavcodec

# Get link flags
pkg-config --libs libavcodec

# Check version
pkg-config --modversion libavcodec

# Check if package exists
pkg-config --exists libavcodec && echo "Found" || echo "Not found"

# Debug search
PKG_CONFIG_DEBUG_SPEW=1 pkg-config --libs libavcodec
```

### 4.8 `strings` - Extract Strings

```bash
# Find strings in binary
strings libopus.a | grep -i version

# Search for specific text
strings target/release/liblibrustdesk.so | grep opus
```

### 4.9 Combined Checking Script

```bash
#!/bin/bash
# check-library.sh - Comprehensive library check

LIB=$1

echo "===== File Type ====="
file "$LIB"

echo -e "\n===== Symbols (first 20) ====="
nm -g "$LIB" | head -20

echo -e "\n===== PIC Check (TEXTREL = bad) ====="
readelf -d "$LIB" 2>/dev/null | grep TEXTREL || echo "✓ No TEXTREL (PIC compliant)"

echo -e "\n===== Relocations (R_X86_64_32 = non-PIC) ====="
readelf -r "$LIB" 2>/dev/null | grep -E "R_X86_64_(32|PC32)" | head -5 || echo "✓ No absolute relocations"

if [[ "$LIB" == *.so ]]; then
    echo -e "\n===== Dependencies ====="
    ldd "$LIB" | head -10
fi
```

Usage:
```bash
bash check-library.sh vcpkg/installed/x64-linux/lib/libopus.a
```

---

## 5. vcpkg Integration

### 5.1 vcpkg Library Structure

```
vcpkg/
├── installed/
│   └── x64-linux/
│       ├── lib/              # Static libraries (.a)
│       ├── include/          # Headers
│       ├── share/            # CMake configs, pkg-config files
│       └── debug/lib/        # Debug libraries
├── packages/                 # Build artifacts
├── buildtrees/               # Build directories
└── downloads/                # Source downloads
```

### 5.2 vcpkg Triplet Configuration

Triplets define how libraries are built. For Ubuntu 18.04, we use `x64-linux`:

**`vcpkg/triplets/x64-linux.cmake`**:
```cmake
set(VCPKG_TARGET_ARCHITECTURE x64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)  # Build static libraries

set(VCPKG_CMAKE_SYSTEM_NAME Linux)

# CRITICAL: Add PIC flags for Ubuntu 18.04
set(VCPKG_C_FLAGS "-fPIC -DPIC")
set(VCPKG_CXX_FLAGS "-fPIC -DPIC")
set(VCPKG_C_FLAGS_RELEASE "-O3 -DNDEBUG -fPIC -DPIC")
set(VCPKG_CXX_FLAGS_RELEASE "-O3 -DNDEBUG -fPIC -DPIC")
```

**Why `-DPIC` macro?**
- Some build systems check `#ifdef PIC` to enable PIC-specific code
- `-fPIC` is compiler flag, `-DPIC` is preprocessor macro
- Both are needed for full PIC compliance

### 5.3 Overlay Ports for Ubuntu 18.04

Overlay ports override default vcpkg ports with custom builds:

```bash
# Install with overlay
vcpkg install opus:x64-linux --overlay-ports=res/vcpkg/opus

# Overlay port structure
res/vcpkg/
├── opus/
│   ├── portfile.cmake       # Build instructions with -DPIC
│   └── vcpkg.json           # Package metadata
├── aom/
└── libyuv/
```

**Example `portfile.cmake` for opus**:
```cmake
vcpkg_configure_make(
    SOURCE_PATH "${SOURCE_PATH}"
    OPTIONS
        --disable-shared
        --enable-static
        --enable-float-approx
        CFLAGS=-fPIC\ -DPIC
        CXXFLAGS=-fPIC\ -DPIC
)
```

### 5.4 Verifying vcpkg Libraries

```bash
# Check if vcpkg library has PIC
readelf -d vcpkg/installed/x64-linux/lib/libopus.a | grep TEXTREL
# Should output nothing (PIC compliant)

# Check relocations
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep R_X86_64_32
# Should be minimal or none

# Verify all vcpkg libraries
for lib in vcpkg/installed/x64-linux/lib/*.a; do
    echo "Checking $lib..."
    readelf -r "$lib" | grep -q "R_X86_64_32[^S]" && echo "  ✗ Non-PIC" || echo "  ✓ PIC"
done
```

### 5.5 Rebuilding vcpkg Libraries

```bash
# Clean specific library
cd vcpkg
rm -rf packages/opus_x64-linux
rm -rf buildtrees/opus
rm -rf installed/x64-linux/lib/libopus.*

# Rebuild with PIC
CFLAGS="-fPIC -DPIC" CXXFLAGS="-fPIC -DPIC" \
  ./vcpkg install opus:x64-linux --overlay-ports=../res/vcpkg/opus

# Verify rebuild
readelf -d installed/x64-linux/lib/libopus.a | grep TEXTREL
```

---

## 6. Rust Linking

### 6.1 Rust Linker Behavior

Rust uses system linker (ld) with additional configuration:

```bash
# Check which linker Rust uses
rustc --print cfg | grep target

# Verbose linking output
cargo build --verbose
# Shows full linker command
```

### 6.2 RUSTFLAGS

Control linker behavior via `RUSTFLAGS`:

```bash
# Add library search paths (highest priority)
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# Link specific library
export RUSTFLAGS="-L /path/to/lib -l static=mylib"

# Verbose linking
export RUSTFLAGS="-C link-arg=-Wl,--verbose"

# Check what Rust will use
cargo rustc -- --print native-static-libs
```

**Library search order in RUSTFLAGS:**
- First `-L` path has highest priority
- Therefore: vcpkg path BEFORE system path

### 6.3 build.rs Scripts

Cargo dependencies can use `build.rs` to configure linking:

**Example from magnum-opus**:
```rust
// magnum-opus build.rs
fn main() {
    pkg_config::Config::new()
        .atleast_version("1.1")
        .probe("opus")
        .unwrap();
}
```

This uses pkg-config to find opus. **Problem**: If `PKG_CONFIG_PATH` is wrong, it finds system libopus (non-PIC) instead of vcpkg libopus (PIC).

**Solution**: Set correct PKG_CONFIG_PATH:
```bash
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"
# System first for GTK/X11, vcpkg second for codecs
```

### 6.4 Debugging Rust Linking Errors

```bash
# See full compiler commands
cargo build -vv 2>&1 | tee build-verbose.log

# Find which library is being linked
grep "libopus" build-verbose.log

# Check if PIC error
grep "relocation R_X86_64" build-verbose.log

# See linker command
grep "^\s*rustc.*--crate-type" build-verbose.log

# Extract linker flags
grep -o -- "-L [^ ]*" build-verbose.log | sort -u
```

### 6.5 Common Rust Linking Issues

| Error | Cause | Solution |
|-------|-------|----------|
| `could not compile 'hwcodec'` with PIC error | Non-PIC FFmpeg libraries | Rebuild vcpkg FFmpeg with PIC |
| `could not compile 'magnum-opus'` with PIC error | Non-PIC opus library | Use vcpkg opus, fix `PKG_CONFIG_PATH` |
| `ld: cannot find -lopus` | opus not in library search path | Add to `RUSTFLAGS` or `LIBRARY_PATH` |
| Build uses system lib instead of vcpkg | Wrong search path order | Put vcpkg FIRST in all paths |

### 6.6 Cargo Cache Issues

Cargo caches build results. After fixing PIC issues, clean cache:

```bash
# Clean specific dependency
rm -rf target/release/deps/libhwcodec*
rm -rf target/release/deps/libmagnum_opus*
rm -rf target/release/build/hwcodec-*
rm -rf target/release/build/magnum-opus-*

# Clean git dependencies
rm -rf ~/.cargo/git/checkouts/hwcodec-*/
rm -rf ~/.cargo/git/checkouts/magnum-opus-*/

# Full clean (last resort)
cargo clean
```

---

## 7. Flutter Compilation

### 7.1 Flutter Native Library Integration

Flutter desktop apps load Rust library at runtime:

```
flutter/build/linux/x64/release/bundle/
├── rustdesk                    # Flutter executable
├── lib/
│   └── liblibrustdesk.so      # Rust shared library (copied from target/release/)
└── data/
```

Flutter expects `liblibrustdesk.so` in `lib/` directory.

### 7.2 Flutter Build Process

```bash
# Flutter build calls:
flutter build linux --release

# Internally runs:
1. cmake (configure build)
2. make (compile C++ wrapper)
3. Copies liblibrustdesk.so from target/release/
4. Packages into bundle/
```

### 7.3 C++ Include Path Issues

Flutter uses C++, needs standard library headers:

```bash
# Common error
fatal error: cstdlib: No such file or directory

# Solution: Set CPATH
GCC_VERSION=$(gcc -dumpversion | cut -d. -f1)
export CPATH="/usr/include/c++/${GCC_VERSION}:/usr/include/x86_64-linux-gnu/c++/${GCC_VERSION}"
```

**Why this happens:**
- Flutter build system doesn't auto-detect C++ paths
- Ubuntu 18.04 GCC 7 has non-standard header locations
- Setting `CPATH` adds to include search

### 7.4 Flutter Build Script Dependencies

```bash
# scripts/flutter_build.sh
python3 ./build.py --flutter --skip-cargo

# build.py requirements:
# - target/release/liblibrustdesk.so must exist
# - Flutter SDK in PATH
# - C++ include paths set
```

### 7.5 Debugging Flutter Build

```bash
# Verbose Flutter build
flutter build linux --release --verbose

# Check CMake configuration
cat build/linux/x64/release/CMakeCache.txt

# Check which libraries Flutter links
ldd build/linux/x64/release/bundle/rustdesk

# Check if Rust library is found
ls -lh build/linux/x64/release/bundle/lib/liblibrustdesk.so
```

---

## 8. System Library Conflicts

### 8.1 Ubuntu 18.04 System Library Issues

**Problem**: System libraries not compiled with PIC:

```bash
# Check system opus
readelf -r /usr/lib/x86_64-linux-gnu/libopus.a | grep R_X86_64_32
# Output: Many R_X86_64_32 relocations (non-PIC)

# Check vcpkg opus
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep R_X86_64_32
# Output: None or minimal (PIC)
```

### 8.2 Library Search Priority

**Critical**: vcpkg must come FIRST:

```bash
# ✗ WRONG - system first
export LIBRARY_PATH="/usr/lib/x86_64-linux-gnu:$VCPKG_INSTALLED/lib"
# Result: Links non-PIC system library → PIC error

# ✓ CORRECT - vcpkg first
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
# Result: Links PIC vcpkg library → success
```

### 8.3 Mixed System/vcpkg Strategy

Some libraries should use system, others vcpkg:

| Library | Source | Reason |
|---------|--------|--------|
| GTK | System | System integration, no PIC issue |
| X11 | System | System integration, no PIC issue |
| pulse | System | Audio system integration |
| opus | vcpkg | System version non-PIC |
| aom | vcpkg | System version non-PIC |
| vpx | vcpkg | System version non-PIC |
| FFmpeg | vcpkg | System version non-PIC, needs custom config |

**Implementation**:
```bash
# pkg-config: system first (for GTK/X11)
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"

# Library linking: vcpkg first (overrides system codecs)
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
```

### 8.4 Detecting Which Library is Used

```bash
# Method 1: Verbose build
cargo build --verbose 2>&1 | grep "libopus"

# Method 2: Check pkg-config
pkg-config --libs opus
# -L/.../vcpkg/installed/x64-linux/lib = vcpkg ✓
# -L/usr/lib/x86_64-linux-gnu = system ✗

# Method 3: Check build.rs output
RUST_LOG=debug cargo build 2>&1 | grep opus

# Method 4: After build, check dependencies
ldd target/release/liblibrustdesk.so | grep opus
```

---

## 9. PIC Verification

### 9.1 What to Check

PIC compliance requires:
1. Compiled with `-fPIC` flag
2. Has `-DPIC` macro defined (for some codebases)
3. No TEXTREL in dynamic section
4. Minimal absolute relocations (R_X86_64_32)

### 9.2 Check Static Library (.a)

```bash
LIB=vcpkg/installed/x64-linux/lib/libopus.a

# Method 1: Check for TEXTREL (dynamic libraries only)
# For .a files, extract .o first:
mkdir /tmp/check-pic
cd /tmp/check-pic
ar -x "$LIB"
readelf -d *.o 2>/dev/null | grep TEXTREL
# No output = good

# Method 2: Check relocations
readelf -r "$LIB" | grep "R_X86_64_32[^S]"
# Should be none or very few

# Method 3: Check objdump
objdump -r "$LIB" | grep "R_X86_64_32[^S]"
# Minimal output = PIC

# Method 4: Check for PIC code patterns
objdump -d "$LIB" | grep "@PLT" | head -5
# Presence of @PLT (Procedure Linkage Table) = PIC
```

**Note**: `R_X86_64_32S` is OK, `R_X86_64_32` (without S) is non-PIC.

### 9.3 Check Shared Library (.so)

```bash
LIB=target/release/liblibrustdesk.so

# Method 1: Check TEXTREL
readelf -d "$LIB" | grep TEXTREL
# No output = PIC ✓
# Has TEXTREL = non-PIC ✗

# Method 2: Check relocations
readelf -r "$LIB" | grep "R_X86_64_32[^S]"
# Should be none

# Method 3: Check with file
file "$LIB"
# Should say "LSB shared object" not "LSB executable"
```

### 9.4 Check Object File (.o)

```bash
OBJ=target/release/deps/rustdesk-abc123.o

# Check relocations
readelf -r "$OBJ" | grep "R_X86_64_32[^S]"

# Check symbols
nm "$OBJ" | grep "U "  # Undefined symbols
```

### 9.5 Automated PIC Check Script

```bash
#!/bin/bash
# check-pic.sh - Check if library is PIC-compliant

check_pic() {
    local file=$1
    local type=$(file "$file")

    echo "Checking: $file"
    echo "Type: $type"

    if [[ "$type" == *"ar archive"* ]]; then
        # Static library - extract and check objects
        local tmpdir=$(mktemp -d)
        cd "$tmpdir"
        ar -x "$file"

        local non_pic=0
        for obj in *.o; do
            if readelf -r "$obj" 2>/dev/null | grep -q "R_X86_64_32[^S]"; then
                echo "  ✗ $obj: Contains non-PIC relocations"
                non_pic=1
            fi
        done

        cd - > /dev/null
        rm -rf "$tmpdir"

        if [ $non_pic -eq 0 ]; then
            echo "  ✓ PIC compliant"
            return 0
        else
            echo "  ✗ NOT PIC compliant"
            return 1
        fi

    elif [[ "$type" == *"shared object"* ]]; then
        # Shared library - check TEXTREL
        if readelf -d "$file" 2>/dev/null | grep -q TEXTREL; then
            echo "  ✗ Has TEXTREL (non-PIC)"
            return 1
        else
            echo "  ✓ No TEXTREL (PIC)"
            return 0
        fi
    else
        echo "  ? Unknown file type"
        return 2
    fi
}

# Usage
check_pic vcpkg/installed/x64-linux/lib/libopus.a
check_pic target/release/liblibrustdesk.so
```

### 9.6 Fixing Non-PIC Libraries

If library is non-PIC:

```bash
# For vcpkg libraries
cd vcpkg
rm -rf packages/PACKAGE_x64-linux
rm -rf buildtrees/PACKAGE
rm -rf installed/x64-linux/lib/libPACKAGE.*

# Rebuild with PIC using overlay port
CFLAGS="-fPIC -DPIC" CXXFLAGS="-fPIC -DPIC" \
  ./vcpkg install PACKAGE:x64-linux --overlay-ports=../res/vcpkg/PACKAGE

# For system libraries - use vcpkg instead
# Cannot fix system libraries, must use vcpkg replacement
```

---

## 10. Checking .a and .o Files

### 10.1 Static Library (.a) Structure

A `.a` file is an archive of `.o` object files:

```bash
# List contents
ar -t libopus.a
# Output:
# opus_encoder.o
# opus_decoder.o
# opus_multistream.o
# ...

# Extract all
ar -x libopus.a

# Extract specific file
ar -x libopus.a opus_encoder.o
```

### 10.2 Comparing .a Files

Check if two libraries are compatible:

```bash
# Check architecture
file lib1.a lib2.a
# Both should be "current ar archive" and same arch (x86-64)

# Compare symbols
nm -g lib1.a | sort > lib1-symbols.txt
nm -g lib2.a | sort > lib2-symbols.txt
diff lib1-symbols.txt lib2-symbols.txt

# Check PIC compliance
readelf -r lib1.a | grep "R_X86_64_32[^S]" > lib1-reloc.txt
readelf -r lib2.a | grep "R_X86_64_32[^S]" > lib2-reloc.txt
```

### 10.3 Checking .o Files

Object files are the compiled units:

```bash
# Get file info
file opus_encoder.o
# Output: ELF 64-bit LSB relocatable, x86-64

# List symbols
nm opus_encoder.o
# T = defined text (code)
# U = undefined (needs linking)
# D = defined data

# Check relocations
readelf -r opus_encoder.o

# Check sections
readelf -S opus_encoder.o
```

### 10.4 Match Checking Between Files

Verify if object file matches library:

```bash
# Extract library object
ar -x libopus.a opus_encoder.o
mv opus_encoder.o opus_encoder_lib.o

# Compare with compiled object
cmp opus_encoder_lib.o /path/to/compiled/opus_encoder.o
# No output = identical

# Compare symbols
nm opus_encoder_lib.o | sort > lib-symbols.txt
nm /path/to/compiled/opus_encoder.o | sort > compiled-symbols.txt
diff lib-symbols.txt compiled-symbols.txt

# Check if .o file is in .a
ar -t libopus.a | grep opus_encoder.o
```

### 10.5 Comprehensive Library Check

```bash
#!/bin/bash
# full-library-check.sh - Complete library analysis

LIB=$1
echo "=========================================="
echo "Library Analysis: $LIB"
echo "=========================================="

# 1. File type
echo -e "\n1. FILE TYPE"
file "$LIB"

# 2. Architecture
echo -e "\n2. ARCHITECTURE"
readelf -h "$LIB" 2>/dev/null | grep "Class\|Machine" || ar -t "$LIB" | head -1 | xargs file

# 3. Contents (for .a)
if [[ "$LIB" == *.a ]]; then
    echo -e "\n3. ARCHIVE CONTENTS (first 10)"
    ar -t "$LIB" | head -10
fi

# 4. Symbols (first 20 defined)
echo -e "\n4. DEFINED SYMBOLS (first 20)"
nm -g "$LIB" | grep " T " | head -20

# 5. PIC check
echo -e "\n5. PIC COMPLIANCE"
if [[ "$LIB" == *.a ]]; then
    tmpdir=$(mktemp -d)
    cd "$tmpdir"
    ar -x "$LIB"

    non_pic_count=0
    for obj in *.o; do
        if readelf -r "$obj" 2>/dev/null | grep -q "R_X86_64_32[^S]"; then
            ((non_pic_count++))
        fi
    done

    total=$(ls -1 *.o | wc -l)
    echo "Objects: $total total, $non_pic_count non-PIC"

    if [ $non_pic_count -eq 0 ]; then
        echo "✓ All objects are PIC compliant"
    else
        echo "✗ $non_pic_count objects contain non-PIC code"
    fi

    cd - > /dev/null
    rm -rf "$tmpdir"

elif [[ "$LIB" == *.so ]]; then
    if readelf -d "$LIB" | grep -q TEXTREL; then
        echo "✗ Has TEXTREL (non-PIC)"
    else
        echo "✓ No TEXTREL (PIC compliant)"
    fi
fi

# 6. Dependencies (for .so)
if [[ "$LIB" == *.so ]]; then
    echo -e "\n6. DEPENDENCIES"
    ldd "$LIB" 2>/dev/null || readelf -d "$LIB" | grep NEEDED
fi

# 7. Relocations sample
echo -e "\n7. RELOCATIONS (first 10)"
readelf -r "$LIB" 2>/dev/null | head -20 || echo "No relocation info"

echo -e "\n=========================================="
echo "Analysis complete"
echo "=========================================="
```

Usage:
```bash
bash full-library-check.sh vcpkg/installed/x64-linux/lib/libopus.a
bash full-library-check.sh target/release/liblibrustdesk.so
```

### 10.6 Quick Reference Commands

```bash
# Extract and check all objects in .a for PIC
ar -x libopus.a && for f in *.o; do echo "$f:"; readelf -r "$f" | grep -c "R_X86_64_32[^S]"; done

# Find which .a contains symbol
for lib in vcpkg/installed/x64-linux/lib/*.a; do
    nm -A "$lib" | grep -q "opus_encode" && echo "$lib"
done

# Compare two .a files
diff <(ar -t lib1.a | sort) <(ar -t lib2.a | sort)

# Check all .o files in directory for PIC
find . -name "*.o" -exec sh -c 'readelf -r {} | grep -q "R_X86_64_32[^S]" && echo "{}: non-PIC"' \;

# Extract specific object from .a for inspection
ar -x libopus.a opus_encoder.o && nm opus_encoder.o | grep opus_encode
```

---

## 11. Real-World Example: Ubuntu 18.04 PIC Issue

### 11.1 Problem

```
error: could not compile `magnum-opus` (lib)
relocation R_X86_64_32 against `.rodata' can not be used when making a shared object
```

### 11.2 Root Cause Analysis

```bash
# Step 1: Identify which library
cargo build -vv 2>&1 | grep "libopus"
# Found: using /usr/lib/x86_64-linux-gnu/libopus.a

# Step 2: Check if system library has PIC
readelf -r /usr/lib/x86_64-linux-gnu/libopus.a | grep "R_X86_64_32[^S]"
# Output: Many relocations → non-PIC confirmed

# Step 3: Check vcpkg library
readelf -r vcpkg/installed/x64-linux/lib/libopus.a | grep "R_X86_64_32[^S]"
# Output: None → PIC compliant
```

### 11.3 Solution Steps

```bash
# 1. Verify vcpkg library exists and is PIC
bash full-library-check.sh vcpkg/installed/x64-linux/lib/libopus.a

# 2. Fix library search order
export LIBRARY_PATH="$VCPKG_INSTALLED/lib:/usr/lib/x86_64-linux-gnu"
export RUSTFLAGS="-L $VCPKG_INSTALLED/lib -L /usr/lib/x86_64-linux-gnu"

# 3. Fix pkg-config order (for build.rs that uses pkg-config)
export PKG_CONFIG_PATH="/usr/lib/x86_64-linux-gnu/pkgconfig:$VCPKG_INSTALLED/lib/pkgconfig"

# 4. Clean cargo cache
rm -rf target/release/deps/libmagnum_opus*
rm -rf target/release/build/magnum-opus-*

# 5. Rebuild
cargo build --release

# 6. Verify success
grep "libopus" build.log
# Should show vcpkg path, not system path
```

### 11.4 Verification

```bash
# Check final binary has no TEXTREL
readelf -d target/release/liblibrustdesk.so | grep TEXTREL
# No output = success

# Check dependencies
ldd target/release/liblibrustdesk.so | grep opus
# Should not show system libopus (statically linked)

# Verify PIC
bash check-pic.sh target/release/liblibrustdesk.so
# Should output: ✓ No TEXTREL (PIC)
```

---

## 12. Troubleshooting Checklist

When encountering linking issues:

- [ ] Check library search paths (`LIBRARY_PATH`, `LD_LIBRARY_PATH`, `RUSTFLAGS`)
- [ ] Check include search paths (`C_INCLUDE_PATH`, `CPLUS_INCLUDE_PATH`, `CPATH`)
- [ ] Verify pkg-config paths (`PKG_CONFIG_PATH`)
- [ ] Confirm library architecture matches (x86_64 vs x86, 32-bit vs 64-bit)
- [ ] Check PIC compliance of all static libraries
- [ ] Verify vcpkg libraries are built with `-fPIC -DPIC`
- [ ] Ensure vcpkg paths come FIRST in all search paths
- [ ] Clean cargo cache after fixing dependencies
- [ ] Use verbose build to see actual commands
- [ ] Check which library is actually being used (system vs vcpkg)
- [ ] Verify symbol existence with `nm`
- [ ] Check relocations with `readelf -r`
- [ ] Test library loading with `ldd`

---

## 13. Summary

### Key Principles

1. **Search Path Order Matters**: First path wins
2. **PIC is Required**: For shared libraries on modern Linux
3. **vcpkg Must Come First**: To override non-PIC system libraries
4. **Clean Cache After Changes**: Cargo and vcpkg cache aggressively
5. **Verify, Don't Assume**: Always check which library is actually used

### Essential Commands

```bash
# Find library
find /usr/lib /opt -name "libopus.*" 2>/dev/null

# Check PIC
readelf -d libfile.a | grep TEXTREL

# Check symbols
nm -g libfile.a | grep symbol_name

# Check dependencies
ldd binary

# Verbose build
cargo build -vv 2>&1 | tee build.log

# Check pkg-config
pkg-config --libs --cflags libname
```

### Quick Diagnosis

| Symptom | Check | Fix |
|---------|-------|-----|
| Compile error: header not found | `gcc -H -c test.c` | Add to `C_INCLUDE_PATH` |
| Link error: cannot find -lxxx | `find /usr/lib -name libxxx.*` | Add to `LIBRARY_PATH` |
| Link error: PIC relocation | `readelf -r libxxx.a \| grep R_X86_64_32` | Rebuild with `-fPIC -DPIC` |
| Runtime: library not found | `ldd binary` | Set `LD_LIBRARY_PATH` or RPATH |
| Wrong library used | `cargo build -vv` | Fix path order (vcpkg first) |

---

## References

- **vcpkg Documentation**: https://vcpkg.io/
- **Rust Linking**: https://doc.rust-lang.org/rustc/linker-plugin-lto.html
- **Position Independent Code**: https://wiki.gentoo.org/wiki/Hardened/Textrels_Guide
- **ELF Format**: `man elf`
- **Linker**: `man ld`
- **pkg-config**: `man pkg-config`

---

**Document Version**: 1.0
**Last Updated**: 2025-11-01
**Based on**: RustDesk Ubuntu 18.04 Build Experience
