#!/usr/bin/env bash
# RustDesk Version Management Script
# Used to update workspace version uniformly

set -e

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

# Cross-platform sed in-place edit
sed_inplace() {
    local pattern="$1"
    local file="$2"
    if [[ "$OSTYPE" == "darwin"* ]]; then
        sed -i '' "$pattern" "$file"
    else
        sed -i "$pattern" "$file"
    fi
}

show_help() {
    echo "RustDesk Version Management Script"
    echo ""
    echo "Usage: ./scripts/set-version.sh <version> [build-number]"
    echo ""
    echo "Examples:"
    echo "  ./scripts/set-version.sh 1.4.4 62"
    echo "  ./scripts/set-version.sh 1.5.0 100"
    echo "  ./scripts/set-version.sh 1.4.3-jlc11"
    echo "  ./scripts/set-version.sh 1.4.3-rc.1+build.123 65"
    echo ""
    echo "Description:"
    echo "  This script will update version numbers in the following locations:"
    echo "  1. Cargo.toml [package] version (Rust version: x.y.z-suffix)"
    echo "  2. Cargo.toml [workspace.package] version (workspace version)"
    echo "  3. flutter/pubspec.yaml version (Flutter version: x.y.z+build)"
    echo "  4. libs/portable/Cargo.toml version"
    echo "  5. GitHub workflow files (.github/workflows/flutter-build.yml, playground.yml, winget.yml)"
    echo "  6. AppImage builder files (appimage/AppImageBuilder-*.yml)"
    echo "  7. Package spec files (res/PKGBUILD, res/*.spec)"
    echo ""
    echo "Version format:"
    echo "  - Cargo: x.y.z-suffix (e.g., 1.4.3-jlc13)"
    echo "  - Flutter: x.y.z-suffix+build (e.g., 1.4.3-jlc14+62)"
    echo "  - The script automatically uses full version for Flutter"
    echo "  - Build number is optional, defaults to auto-increment or manual input"
    exit 0
}

# Check arguments
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

NEW_VERSION="$1"
BUILD_NUMBER="$2"

# Validate version format (supports SemVer 2.0: x.y.z[-prerelease][+build])
if ! echo "$NEW_VERSION" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?(\+[0-9A-Za-z.-]+)?$'; then
    echo -e "${RED}[ERROR] Invalid version format${NC}"
    echo -e "${YELLOW}Supported formats:${NC}"
    echo -e "${GRAY}  1.4.3${NC}"
    echo -e "${GRAY}  1.4.3-alpha${NC}"
    echo -e "${GRAY}  1.4.3-jlc11${NC}"
    echo -e "${GRAY}  1.4.3-rc.1+build.123${NC}"
    exit 1
fi

# Change to repository root directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
cd "$REPO_ROOT"

CARGO_TOML="./Cargo.toml"

if [ ! -f "$CARGO_TOML" ]; then
    echo -e "${RED}[ERROR] Cargo.toml not found in repository root${NC}"
    exit 1
fi

echo -e "${BLUE}[INFO] Updating version to $NEW_VERSION...${NC}"

# Create backup
cp "$CARGO_TOML" "$CARGO_TOML.bak"

# Track change count
CHANGE_COUNT=0

# Replace version in [package] section
if sed -i.tmp '/^\[package\]/,/^\[/ s/^version = ".*"/version = "'"$NEW_VERSION"'"/' "$CARGO_TOML" 2>/dev/null; then
    if ! diff -q "$CARGO_TOML" "$CARGO_TOML.bak" > /dev/null 2>&1; then
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "${GREEN}[OK] Updated [package] version = \"$NEW_VERSION\"${NC}"
    fi
fi

# Restore from backup for second replacement
cp "$CARGO_TOML.bak" "$CARGO_TOML"

# Use Perl for more complex regex replacement (works on both Linux and macOS)
perl -i -pe '
    BEGIN { $in_package = 0; $in_workspace_package = 0; $package_done = 0; $workspace_done = 0; }
    if (/^\[package\]/) { $in_package = 1; $in_workspace_package = 0; }
    elsif (/^\[workspace\.package\]/) { $in_workspace_package = 1; $in_package = 0; }
    elsif (/^\[/) { $in_package = 0; $in_workspace_package = 0; }

    if ($in_package && /^version\s*=\s*"[^"]*"/ && !$package_done) {
        s/^version\s*=\s*"[^"]*"/version = "'"$NEW_VERSION"'"/;
        $package_done = 1;
    }
    if ($in_workspace_package && /^version\s*=\s*"[^"]*"/ && !$workspace_done) {
        s/^version\s*=\s*"[^"]*"/version = "'"$NEW_VERSION"'"/;
        $workspace_done = 1;
    }
' "$CARGO_TOML"

# Count changes
if ! diff -q "$CARGO_TOML" "$CARGO_TOML.bak" > /dev/null 2>&1; then
    CHANGE_COUNT=2
fi

# Clean up temporary files
rm -f "$CARGO_TOML.tmp" "$CARGO_TOML.bak"

if [ $CHANGE_COUNT -eq 0 ]; then
    echo -e "${YELLOW}[WARNING] No version to update found${NC}"
    exit 1
fi

# Update Flutter pubspec.yaml
PUBSPEC_FILE="./flutter/pubspec.yaml"
if [ -f "$PUBSPEC_FILE" ]; then
    # Determine build number
    if [ -z "$BUILD_NUMBER" ]; then
        # Read current build number from pubspec.yaml
        if grep -qE 'version:\s*[0-9.]+[^+]*\+[0-9]+' "$PUBSPEC_FILE"; then
            CURRENT_BUILD=$(grep -oE 'version:\s*[0-9.]+[^+]*\+([0-9]+)' "$PUBSPEC_FILE" | sed -E 's/.*\+([0-9]+)/\1/')
            BUILD_NUMBER=$((CURRENT_BUILD + 1))
            echo -e "${CYAN}[INFO] Auto-incrementing build number: $CURRENT_BUILD -> $BUILD_NUMBER${NC}"
        else
            BUILD_NUMBER=1
            echo -e "${CYAN}[INFO] No existing build number found, using: $BUILD_NUMBER${NC}"
        fi
    fi

    # Use full version including suffix (e.g., 1.4.3-jlc14)
    FLUTTER_VERSION="$NEW_VERSION+$BUILD_NUMBER"

    # Create backup
    cp "$PUBSPEC_FILE" "$PUBSPEC_FILE.bak"

    # Update version in pubspec.yaml
    # Use sed for simple replacement: version: X.Y.Z+BUILD -> version: NEW_VERSION+BUILD
    sed_inplace 's|^version: *[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*.*|version: '"$FLUTTER_VERSION"'|' "$PUBSPEC_FILE"

    # Check if file was changed
    if ! diff -q "$PUBSPEC_FILE" "$PUBSPEC_FILE.bak" > /dev/null 2>&1; then
        CHANGE_COUNT=$((CHANGE_COUNT + 1))
        echo -e "${GREEN}[OK] Updated flutter/pubspec.yaml version = \"$FLUTTER_VERSION\"${NC}"
    fi

    # Clean up backup
    rm -f "$PUBSPEC_FILE.bak"
else
    echo -e "${YELLOW}[WARNING] flutter/pubspec.yaml not found${NC}"
fi

# Update GitHub workflow files
WORKFLOW_FILES=(
    "./.github/workflows/flutter-build.yml"
    "./.github/workflows/playground.yml"
    "./.github/workflows/winget.yml"
)

for WORKFLOW_FILE in "${WORKFLOW_FILES[@]}"; do
    if [ -f "$WORKFLOW_FILE" ]; then
        # Create backup
        cp "$WORKFLOW_FILE" "$WORKFLOW_FILE.bak"

        # Update VERSION: "x.x.x" pattern
        sed_inplace 's/^\( *VERSION: *"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Update version: "x.x.x" pattern (for winget.yml)
        sed_inplace 's/^\( *version: *"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Update release-tag: "x.x.x" pattern (for winget.yml)
        sed_inplace 's/^\( *release-tag: *"\)[^"]*"/\1'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Check if file was changed
        if ! diff -q "$WORKFLOW_FILE" "$WORKFLOW_FILE.bak" > /dev/null 2>&1; then
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
            FILE_NAME=$(basename "$WORKFLOW_FILE")
            echo -e "${GREEN}[OK] Updated $FILE_NAME version = \"$NEW_VERSION\"${NC}"
        fi

        # Clean up backup
        rm -f "$WORKFLOW_FILE.bak"
    fi
done

# Update AppImage builder files
APPIMAGE_FILES=(
    "./appimage/AppImageBuilder-aarch64.yml"
    "./appimage/AppImageBuilder-x86_64.yml"
)

for APPIMAGE_FILE in "${APPIMAGE_FILES[@]}"; do
    if [ -f "$APPIMAGE_FILE" ]; then
        # Create backup
        cp "$APPIMAGE_FILE" "$APPIMAGE_FILE.bak"

        # Update version under app_info section only
        # Match exactly 4 spaces + "version:" to avoid top-level "version: 1"
        sed_inplace 's|^    version: .*|    version: '"$NEW_VERSION"'|' "$APPIMAGE_FILE"

        # Check if file was changed
        if ! diff -q "$APPIMAGE_FILE" "$APPIMAGE_FILE.bak" > /dev/null 2>&1; then
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
            FILE_NAME=$(basename "$APPIMAGE_FILE")
            echo -e "${GREEN}[OK] Updated $FILE_NAME version = \"$NEW_VERSION\"${NC}"
        fi

        # Clean up backup
        rm -f "$APPIMAGE_FILE.bak"
    fi
done

# Update libs/portable/Cargo.toml (skip if using workspace version)
PORTABLE_CARGO="./libs/portable/Cargo.toml"
if [ -f "$PORTABLE_CARGO" ]; then
    # Check if using workspace version
    if ! grep -q "version.workspace\s*=\s*true" "$PORTABLE_CARGO"; then
        # Create backup
        cp "$PORTABLE_CARGO" "$PORTABLE_CARGO.bak"

        # Update version in [package] section
        perl -i -pe '
            BEGIN { $in_package = 0; $done = 0; }
            if (/^\[package\]/) { $in_package = 1; }
            elsif (/^\[/) { $in_package = 0; }
            if ($in_package && /^version\s*=\s*"[^"]*"/ && !$done) {
                s/^version\s*=\s*"[^"]*"/version = "'"$NEW_VERSION"'"/;
                $done = 1;
            }
        ' "$PORTABLE_CARGO"

        # Check if file was changed
        if ! diff -q "$PORTABLE_CARGO" "$PORTABLE_CARGO.bak" > /dev/null 2>&1; then
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
            echo -e "${GREEN}[OK] Updated libs/portable/Cargo.toml version = \"$NEW_VERSION\"${NC}"
        fi

        # Clean up backup
        rm -f "$PORTABLE_CARGO.bak"
    else
        echo -e "${CYAN}[INFO] libs/portable/Cargo.toml uses workspace version (automatically inherits from workspace)${NC}"
    fi
fi

# Update package spec files
# Split version into base version and release suffix
# E.g., 1.4.3-jlc15 -> VERSION_BASE=1.4.3, RELEASE_SUFFIX=jlc15
if [[ "$NEW_VERSION" =~ ^([0-9]+\.[0-9]+\.[0-9]+)-(.+)$ ]]; then
    VERSION_BASE="${BASH_REMATCH[1]}"
    RELEASE_SUFFIX="${BASH_REMATCH[2]}"
    # Remove +build metadata from release suffix if present (e.g., jlc15+123 -> jlc15)
    RELEASE_SUFFIX="${RELEASE_SUFFIX%%+*}"
else
    VERSION_BASE="$NEW_VERSION"
    RELEASE_SUFFIX="0"
fi

echo -e "${CYAN}[INFO] Package version split: Version=$VERSION_BASE, Release=$RELEASE_SUFFIX${NC}"

SPEC_FILES=(
    "./res/PKGBUILD"
    "./res/rpm-flutter-suse.spec"
    "./res/rpm-flutter.spec"
    "./res/rpm-suse.spec"
    "./res/rpm.spec"
)

for SPEC_FILE in "${SPEC_FILES[@]}"; do
    if [ -f "$SPEC_FILE" ]; then
        # Create backup
        cp "$SPEC_FILE" "$SPEC_FILE.bak"

        # Update version and release fields separately
        # For PKGBUILD: pkgver and pkgrel
        sed_inplace 's|^pkgver=.*|pkgver='"$VERSION_BASE"'|' "$SPEC_FILE"
        sed_inplace 's|^pkgrel=.*|pkgrel='"$RELEASE_SUFFIX"'|' "$SPEC_FILE"

        # For RPM spec: Version and Release
        sed_inplace 's|^Version: .*|Version:    '"$VERSION_BASE"'|' "$SPEC_FILE"
        sed_inplace 's|^Release: .*|Release:    '"$RELEASE_SUFFIX"'|' "$SPEC_FILE"

        # Check if file was changed
        if ! diff -q "$SPEC_FILE" "$SPEC_FILE.bak" > /dev/null 2>&1; then
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
            FILE_NAME=$(basename "$SPEC_FILE")
            echo -e "${GREEN}[OK] Updated $FILE_NAME (Version: $VERSION_BASE, Release: $RELEASE_SUFFIX)${NC}"
        fi

        # Clean up backup
        rm -f "$SPEC_FILE.bak"
    fi
done

echo ""
echo -e "${GREEN}[SUCCESS] Version successfully updated!${NC}"
echo ""
echo -e "${CYAN}Updated versions:${NC}"
echo "  - Rust version (Cargo.toml): $NEW_VERSION"
if [ -f "$PUBSPEC_FILE" ] && [ -n "$FLUTTER_VERSION" ]; then
    echo "  - Flutter version (pubspec.yaml): $FLUTTER_VERSION"
fi
echo ""
echo -e "${CYAN}Updated locations:${NC}"
echo "  - Cargo.toml [package] version = \"$NEW_VERSION\""
echo "  - Cargo.toml [workspace.package] version = \"$NEW_VERSION\""
if [ -f "$PUBSPEC_FILE" ] && [ -n "$FLUTTER_VERSION" ]; then
    echo "  - flutter/pubspec.yaml version = \"$FLUTTER_VERSION\""
fi
echo "  - libs/portable/Cargo.toml (inherits from workspace)"
echo "  - .github/workflows/flutter-build.yml"
echo "  - .github/workflows/playground.yml"
echo "  - .github/workflows/winget.yml"
echo "  - appimage/AppImageBuilder-aarch64.yml"
echo "  - appimage/AppImageBuilder-x86_64.yml"
echo "  - res/PKGBUILD"
echo "  - res/rpm-flutter-suse.spec"
echo "  - res/rpm-flutter.spec"
echo "  - res/rpm.spec"
echo ""
echo -e "${CYAN}Version breakdown:${NC}"
echo "  - Rust uses: $NEW_VERSION (e.g., 1.4.3-jlc13)"
if [ -f "$PUBSPEC_FILE" ] && [ -n "$FLUTTER_VERSION" ]; then
    echo "  - Flutter uses: $FLUTTER_VERSION (version+build, e.g., 1.4.3-jlc14+62)"
    echo "  - PE file header will use: $FLUTTER_VERSION (from Flutter build)"
fi
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Verify changes: git diff"
echo "  2. Test build: cargo build --release"
echo "  3. Commit changes: git add -A && git commit -m \"chore: bump version to $NEW_VERSION\""
