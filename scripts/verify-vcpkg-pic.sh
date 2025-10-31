#!/bin/bash
# vcpkg -fPIC 配置验证脚本
# 用于验证 vcpkg 编译的静态库是否使用了 -fPIC

set -e

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VCPKG_ROOT="${VCPKG_ROOT:-$PROJECT_ROOT/vcpkg}"
TRIPLET="${VCPKG_TRIPLET:-x64-linux}"

echo "========================================"
echo "vcpkg -fPIC Configuration Verification"
echo "========================================"
echo ""
echo "VCPKG_ROOT: $VCPKG_ROOT"
echo "TRIPLET: $TRIPLET"
echo ""

# Check 1: Verify triplet configuration
echo "Check 1: Triplet Configuration"
echo "--------------------------------"
TRIPLET_FILE="$VCPKG_ROOT/triplets/$TRIPLET.cmake"

if [ ! -f "$TRIPLET_FILE" ]; then
    echo "❌ Triplet file not found: $TRIPLET_FILE"
    exit 1
fi

echo "Triplet file: $TRIPLET_FILE"
echo ""
echo "Content:"
cat "$TRIPLET_FILE"
echo ""

if grep -q "VCPKG_C_FLAGS.*-fPIC" "$TRIPLET_FILE"; then
    echo "✅ -fPIC is configured in C flags"
else
    echo "❌ -fPIC is NOT configured in C flags"
    echo ""
    echo "Fix: Run 'bash scripts/setup-for-ubuntu18.sh' to configure -fPIC"
    exit 1
fi

if grep -q "VCPKG_CXX_FLAGS.*-fPIC" "$TRIPLET_FILE"; then
    echo "✅ -fPIC is configured in CXX flags"
else
    echo "❌ -fPIC is NOT configured in CXX flags"
    exit 1
fi

echo ""

# Check 2: Verify installed libraries
echo "Check 2: Installed Libraries"
echo "--------------------------------"
INSTALLED_DIR="$VCPKG_ROOT/installed/$TRIPLET"

if [ ! -d "$INSTALLED_DIR" ]; then
    echo "⚠️  vcpkg dependencies not yet installed"
    echo "   Run: \$VCPKG_ROOT/vcpkg install --triplet $TRIPLET"
    exit 0
fi

# Check critical libraries
LIBS=("opus" "yuv" "vpx" "aom")
for lib in "${LIBS[@]}"; do
    LIB_PATH="$INSTALLED_DIR/lib/lib${lib}.a"
    if [ -f "$LIB_PATH" ]; then
        echo "✅ lib${lib}.a found"
    else
        echo "❌ lib${lib}.a NOT found"
    fi
done

echo ""

# Check 3: Verify object files have PIC (advanced check)
echo "Check 3: Object File Relocation Check"
echo "--------------------------------"

# Extract and check an object file from libopus.a
OPUS_LIB="$INSTALLED_DIR/lib/libopus.a"
if [ -f "$OPUS_LIB" ]; then
    echo "Analyzing: $OPUS_LIB"

    # Create temp directory
    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR"

    # Extract first object file
    ar x "$OPUS_LIB" opus.c.o 2>/dev/null || ar x "$OPUS_LIB" $(ar t "$OPUS_LIB" | head -1) 2>/dev/null

    OBJ_FILE=$(ls *.o 2>/dev/null | head -1)

    if [ -n "$OBJ_FILE" ]; then
        echo "Object file: $OBJ_FILE"

        # Check for absolute relocations (bad for PIC)
        ABSOLUTE_RELOCS=$(readelf -r "$OBJ_FILE" 2>/dev/null | grep -c "R_X86_64_32" || true)

        if [ "$ABSOLUTE_RELOCS" -eq 0 ]; then
            echo "✅ No absolute relocations found (good for PIC)"
        else
            echo "⚠️  Found $ABSOLUTE_RELOCS absolute relocations"
            echo "   This might cause linking issues with shared libraries"
            echo ""
            echo "Sample relocations:"
            readelf -r "$OBJ_FILE" 2>/dev/null | grep "R_X86_64_32" | head -5
        fi
    fi

    # Cleanup
    cd - > /dev/null
    rm -rf "$TEMP_DIR"
else
    echo "⚠️  libopus.a not found, skipping object file check"
fi

echo ""

# Summary
echo "========================================"
echo "Verification Summary"
echo "========================================"
echo ""

if grep -q "VCPKG_C_FLAGS.*-fPIC" "$TRIPLET_FILE" && \
   grep -q "VCPKG_CXX_FLAGS.*-fPIC" "$TRIPLET_FILE"; then
    echo "✅ vcpkg triplet is correctly configured with -fPIC"
    echo ""
    echo "Next steps:"
    echo "  1. If you haven't installed vcpkg dependencies:"
    echo "     \$VCPKG_ROOT/vcpkg install --triplet $TRIPLET"
    echo ""
    echo "  2. Build RustDesk:"
    echo "     cargo build --release"
    echo ""
    echo "  3. Check for librustdesk.so:"
    echo "     ls -lh target/release/librustdesk.so"
    exit 0
else
    echo "❌ Configuration incomplete"
    echo ""
    echo "Run: bash scripts/setup-for-ubuntu18.sh"
    exit 1
fi
