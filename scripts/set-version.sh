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

show_help() {
    echo "RustDesk Version Management Script"
    echo ""
    echo "Usage: ./scripts/set-version.sh <version>"
    echo ""
    echo "Examples:"
    echo "  ./scripts/set-version.sh 1.4.4"
    echo "  ./scripts/set-version.sh 1.5.0"
    echo "  ./scripts/set-version.sh 1.4.3-jlc11"
    echo "  ./scripts/set-version.sh 1.4.3-rc.1+build.123"
    echo ""
    echo "Description:"
    echo "  This script will update version numbers in the following locations:"
    echo "  1. Cargo.toml [package] version (main program version)"
    echo "  2. Cargo.toml [workspace.package] version (workspace version)"
    echo "  3. All subcomponents automatically inherit workspace version (version.workspace = true)"
    echo "  4. GitHub workflow files (.github/workflows/flutter-build.yml, playground.yml, winget.yml)"
    exit 0
}

# Check arguments
if [ $# -eq 0 ] || [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
fi

NEW_VERSION="$1"

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

# Update GitHub workflow files
WORKFLOW_FILES=(
    "./.github/workflows/flutter-build.yml"
    "./.github/workflows/playground.yml"
    "./.github/workflows/winget.yml"
)

for WORKFLOW_FILE in "${WORKFLOW_FILES[@]}"; do
    if [ -f "$WORKFLOW_FILE" ]; then
        WORKFLOW_CHANGED=0

        # Create backup
        cp "$WORKFLOW_FILE" "$WORKFLOW_FILE.bak"

        # Update VERSION: "x.x.x" pattern
        perl -i -pe 's/^(\s*VERSION:\s*)"[^"]*"/\1"'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Update version: "x.x.x" pattern (for winget.yml)
        perl -i -pe 's/^(\s*version:\s*)"[^"]*"/\1"'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Update release-tag: "x.x.x" pattern (for winget.yml)
        perl -i -pe 's/^(\s*release-tag:\s*)"[^"]*"/\1"'"$NEW_VERSION"'"/' "$WORKFLOW_FILE"

        # Check if file was changed
        if ! diff -q "$WORKFLOW_FILE" "$WORKFLOW_FILE.bak" > /dev/null 2>&1; then
            WORKFLOW_CHANGED=1
            CHANGE_COUNT=$((CHANGE_COUNT + 1))
            FILE_NAME=$(basename "$WORKFLOW_FILE")
            echo -e "${GREEN}[OK] Updated $FILE_NAME version = \"$NEW_VERSION\"${NC}"
        fi

        # Clean up backup
        rm -f "$WORKFLOW_FILE.bak"
    fi
done

echo ""
echo -e "${GREEN}[SUCCESS] Version successfully updated to $NEW_VERSION${NC}"
echo ""
echo -e "${CYAN}Updated locations:${NC}"
echo "  - Cargo.toml [package] version"
echo "  - Cargo.toml [workspace.package] version"
echo "  - .github/workflows/flutter-build.yml"
echo "  - .github/workflows/playground.yml"
echo "  - .github/workflows/winget.yml"
echo ""
echo -e "${CYAN}Subcomponents inheriting workspace version (version.workspace = true):${NC}"
echo "  - libs/portable (rustdesk-portable-packer)"
echo ""
echo -e "${CYAN}Next steps:${NC}"
echo "  1. Verify changes: git diff Cargo.toml .github/workflows/"
echo "  2. Test build: ./build.sh (or build.ps1 on Windows)"
echo "  3. Commit changes: git add Cargo.toml .github/workflows/ && git commit -m \"chore: bump version to $NEW_VERSION\""
