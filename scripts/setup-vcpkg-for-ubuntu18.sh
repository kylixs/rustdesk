#!/bin/bash
set -e

# Get script directory and project root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Step 5: Setup vcpkg
echo ""
echo "Setting up vcpkg..."
export VCPKG_COMMIT_ID="120deac3062162151622ca4860575a33844ba10b"
export VCPKG_TRIPLET="${VCPKG_TRIPLET:-x64-linux}"
export VCPKG_ROOT="$PROJECT_ROOT/vcpkg"
VCPKG_INSTALLED="$VCPKG_ROOT/installed/$VCPKG_TRIPLET"

if [ ! -d "$VCPKG_ROOT" ]; then
    cd $PROJECT_ROOT
    git clone https://github.com/Microsoft/vcpkg.git
    cd vcpkg
    git checkout $VCPKG_COMMIT_ID
    ./bootstrap-vcpkg.sh
    sudo chmod -R 755 $VCPKG_ROOT
else
    echo "vcpkg already exists at $VCPKG_ROOT"
fi

echo "✓ vcpkg ready: $(cd $VCPKG_ROOT && git rev-parse --short HEAD)"

# Step 5.5: Configure vcpkg triplet for PIC (Position Independent Code)
echo ""
echo "Step 5.5: Configuring vcpkg triplet with -fPIC..."
TRIPLET_FILE="$VCPKG_ROOT/triplets/$VCPKG_TRIPLET.cmake"

# Backup original triplet file if not already backed up
if [ ! -f "$TRIPLET_FILE.backup" ]; then
    cp "$TRIPLET_FILE" "$TRIPLET_FILE.backup"
    echo "✓ Original triplet backed up to $TRIPLET_FILE.backup"
fi

# Check if -fPIC is already configured
if ! grep -q "VCPKG_C_FLAGS.*-fPIC" "$TRIPLET_FILE"; then
    echo "" >> "$TRIPLET_FILE"
    echo "# Force PIC for static libraries so they can be linked into shared libraries (librustdesk.so)" >> "$TRIPLET_FILE"
    echo "set(VCPKG_C_FLAGS \"-fPIC\")" >> "$TRIPLET_FILE"
    echo "set(VCPKG_CXX_FLAGS \"-fPIC\")" >> "$TRIPLET_FILE"
    echo "✓ Added -fPIC flags to triplet configuration"
else
    echo "✓ -fPIC already configured in triplet"
fi

# Display current triplet configuration
echo "Current triplet configuration:"
cat "$TRIPLET_FILE"
echo ""