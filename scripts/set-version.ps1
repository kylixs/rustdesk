# RustDesk Version Management Script
# Used to update workspace version uniformly

param(
    [Parameter(Position=0)]
    [string]$NewVersion,
    [Parameter(Position=1)]
    [string]$BuildNumber,
    [switch]$Help
)

if ($Help -or $NewVersion -eq "-h" -or $NewVersion -eq "--help" -or [string]::IsNullOrEmpty($NewVersion)) {
    Write-Host "RustDesk Version Management Script"
    Write-Host ""
    Write-Host "Usage: .\scripts\set-version.ps1 <version> [build-number]"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\set-version.ps1 1.4.4 62"
    Write-Host "  .\scripts\set-version.ps1 1.5.0 100"
    Write-Host "  .\scripts\set-version.ps1 1.4.3-jlc11"
    Write-Host "  .\scripts\set-version.ps1 1.4.3-rc.1+build.123 65"
    Write-Host ""
    Write-Host "Description:"
    Write-Host "  This script will update version numbers in the following locations:"
    Write-Host "  1. Cargo.toml [package] version (Rust version: x.y.z-suffix)"
    Write-Host "  2. Cargo.toml [workspace.package] version (workspace version)"
    Write-Host "  3. flutter/pubspec.yaml version (Flutter version: x.y.z+build)"
    Write-Host "  4. libs/portable/Cargo.toml version"
    Write-Host "  5. GitHub workflow files (.github/workflows/flutter-build.yml, playground.yml, winget.yml)"
    Write-Host "  6. AppImage builder files (appimage/AppImageBuilder-*.yml)"
    Write-Host "  7. Package spec files (res/PKGBUILD, res/*.spec)"
    Write-Host ""
    Write-Host "Version format:"
    Write-Host "  - Cargo: x.y.z-suffix (e.g., 1.4.3-jlc13)"
    Write-Host "  - Flutter: x.y.z+build (e.g., 1.4.3+62)"
    Write-Host "  - The script automatically extracts x.y.z for Flutter"
    Write-Host "  - Build number is optional, defaults to auto-increment or manual input"
    exit 0
}

# Validate version format (supports SemVer 2.0: x.y.z[-prerelease][+build])
if ($NewVersion -notmatch '^\d+\.\d+\.\d+(-[0-9A-Za-z\-.]+)?(\+[0-9A-Za-z\-.]+)?$') {
    Write-Host "[ERROR] Invalid version format" -ForegroundColor Red
    Write-Host "Supported formats:" -ForegroundColor Yellow
    Write-Host "  1.4.3" -ForegroundColor Gray
    Write-Host "  1.4.3-alpha" -ForegroundColor Gray
    Write-Host "  1.4.3-jlc11" -ForegroundColor Gray
    Write-Host "  1.4.3-rc.1+build.123" -ForegroundColor Gray
    exit 1
}

# Change to repository root directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Split-Path -Parent $scriptDir
Set-Location $repoRoot

$CargoToml = ".\Cargo.toml"

if (-not (Test-Path $CargoToml)) {
    Write-Host "[ERROR] Cargo.toml not found in repository root" -ForegroundColor Red
    exit 1
}

Write-Host "[INFO] Updating version to $NewVersion..." -ForegroundColor Blue

# Read file content
$content = Get-Content $CargoToml -Raw

# Track change count
$changeCount = 0

# Replace version in [package] section
$newContent = $content -replace '(?m)^(\[package\][\s\S]*?version\s*=\s*)"[^"]*"', "`${1}`"$NewVersion`""
if ($newContent -ne $content) {
    $changeCount++
    Write-Host "[OK] Updated [package] version = `"$NewVersion`"" -ForegroundColor Green
    $content = $newContent
}

# Replace version in [workspace.package] section
$newContent = $content -replace '(?m)^(\[workspace\.package\][\s\S]*?version\s*=\s*)"[^"]*"', "`${1}`"$NewVersion`""
if ($newContent -ne $content) {
    $changeCount++
    Write-Host "[OK] Updated [workspace.package] version = `"$NewVersion`"" -ForegroundColor Green
    $content = $newContent
}

if ($changeCount -eq 0) {
    Write-Host "[WARNING] No version to update found" -ForegroundColor Yellow
    exit 1
}

# Write back to file
$content | Set-Content $CargoToml -NoNewline

# Update Flutter pubspec.yaml
$pubspecFile = ".\flutter\pubspec.yaml"
if (Test-Path $pubspecFile) {
    # Determine build number
    if ([string]::IsNullOrEmpty($BuildNumber)) {
        # Read current build number from pubspec.yaml
        $pubspecContent = Get-Content $pubspecFile -Raw
        if ($pubspecContent -match 'version:\s*[\d.]+[^+]*\+(\d+)') {
            $currentBuild = [int]$matches[1]
            $BuildNumber = $currentBuild + 1
            Write-Host "[INFO] Auto-incrementing build number: $currentBuild -> $BuildNumber" -ForegroundColor Cyan
        } else {
            $BuildNumber = 1
            Write-Host "[INFO] No existing build number found, using: $BuildNumber" -ForegroundColor Cyan
        }
    }

    # Use full version including suffix (e.g., 1.4.3-jlc14)
    $flutterVersion = "$NewVersion+$BuildNumber"

    # Update version in pubspec.yaml
    # Simple replacement: match entire version line
    $pubspecContent = Get-Content $pubspecFile -Raw
    $newPubspecContent = $pubspecContent -replace '(?m)^version: .*$', "version: $flutterVersion"

    if ($newPubspecContent -ne $pubspecContent) {
        $newPubspecContent | Set-Content $pubspecFile -NoNewline
        $changeCount++
        Write-Host "[OK] Updated flutter/pubspec.yaml version = `"$flutterVersion`"" -ForegroundColor Green
    }
} else {
    Write-Host "[WARNING] flutter/pubspec.yaml not found" -ForegroundColor Yellow
}

# Update GitHub workflow files
$workflowFiles = @(
    ".\.github\workflows\flutter-build.yml",
    ".\.github\workflows\playground.yml",
    ".\.github\workflows\winget.yml"
)

foreach ($workflowFile in $workflowFiles) {
    if (Test-Path $workflowFile) {
        $workflowContent = Get-Content $workflowFile -Raw
        $workflowChanged = $false

        # Update VERSION: "x.x.x" pattern - simple replacement
        $newWorkflowContent = $workflowContent -replace '(?m)^(\s*VERSION:\s*)"[^"]*"', "`${1}`"$NewVersion`""
        if ($newWorkflowContent -ne $workflowContent) {
            $workflowChanged = $true
            $workflowContent = $newWorkflowContent
        }

        # Update version: "x.x.x" pattern (for winget.yml)
        $newWorkflowContent = $workflowContent -replace '(?m)^(\s*version:\s*)"[^"]*"', "`${1}`"$NewVersion`""
        if ($newWorkflowContent -ne $workflowContent) {
            $workflowChanged = $true
            $workflowContent = $newWorkflowContent
        }

        # Update release-tag: "x.x.x" pattern (for winget.yml)
        $newWorkflowContent = $workflowContent -replace '(?m)^(\s*release-tag:\s*)"[^"]*"', "`${1}`"$NewVersion`""
        if ($newWorkflowContent -ne $workflowContent) {
            $workflowChanged = $true
            $workflowContent = $newWorkflowContent
        }

        if ($workflowChanged) {
            $workflowContent | Set-Content $workflowFile -NoNewline
            $changeCount++
            $fileName = Split-Path $workflowFile -Leaf
            Write-Host "[OK] Updated $fileName version = `"$NewVersion`"" -ForegroundColor Green
        }
    }
}

# Update AppImage builder files
$appImageFiles = @(
    ".\appimage\AppImageBuilder-aarch64.yml",
    ".\appimage\AppImageBuilder-x86_64.yml"
)

foreach ($appImageFile in $appImageFiles) {
    if (Test-Path $appImageFile) {
        $appImageContent = Get-Content $appImageFile -Raw

        # Update version under app_info section only
        # Match exactly 4 spaces + "version:" to avoid top-level "version: 1"
        $newAppImageContent = $appImageContent -replace '(?m)^    version: .*$', "    version: $NewVersion"

        if ($newAppImageContent -ne $appImageContent) {
            $newAppImageContent | Set-Content $appImageFile -NoNewline
            $changeCount++
            $fileName = Split-Path $appImageFile -Leaf
            Write-Host "[OK] Updated $fileName version = `"$NewVersion`"" -ForegroundColor Green
        }
    }
}

# Update libs/portable/Cargo.toml (skip if using workspace version)
$portableCargo = ".\libs\portable\Cargo.toml"
if (Test-Path $portableCargo) {
    $portableContent = Get-Content $portableCargo -Raw

    # Check if using workspace version
    if ($portableContent -notmatch 'version\.workspace\s*=\s*true') {
        # Update version in [package] section only
        $newPortableContent = $portableContent -replace '(?m)^(\[package\][\s\S]*?version\s*=\s*)"[^"]*"', "`${1}`"$NewVersion`""

        if ($newPortableContent -ne $portableContent) {
            $newPortableContent | Set-Content $portableCargo -NoNewline
            $changeCount++
            Write-Host "[OK] Updated libs/portable/Cargo.toml version = `"$NewVersion`"" -ForegroundColor Green
        }
    } else {
        Write-Host "[INFO] libs/portable/Cargo.toml uses workspace version (automatically inherits from workspace)" -ForegroundColor Cyan
    }
}

# Update package spec files
$specFiles = @(
    ".\res\PKGBUILD",
    ".\res\rpm-flutter-suse.spec",
    ".\res\rpm-flutter.spec",
    ".\res\rpm.spec"
)

foreach ($specFile in $specFiles) {
    if (Test-Path $specFile) {
        $specContent = Get-Content $specFile -Raw
        $specChanged = $false

        # Update pkgver= pattern - simple replacement
        $newSpecContent = $specContent -replace '(?m)^pkgver=.*$', "pkgver=$NewVersion"
        if ($newSpecContent -ne $specContent) {
            $specChanged = $true
            $specContent = $newSpecContent
        }

        # Update Version: pattern - simple replacement
        $newSpecContent = $specContent -replace '(?m)^Version: .*$', "Version:    $NewVersion"
        if ($newSpecContent -ne $specContent) {
            $specChanged = $true
            $specContent = $newSpecContent
        }

        if ($specChanged) {
            $specContent | Set-Content $specFile -NoNewline
            $changeCount++
            $fileName = Split-Path $specFile -Leaf
            Write-Host "[OK] Updated $fileName version = `"$NewVersion`"" -ForegroundColor Green
        }
    }
}

Write-Host ""
Write-Host "[SUCCESS] Version successfully updated!" -ForegroundColor Green
Write-Host ""
Write-Host "Updated versions:" -ForegroundColor Cyan
Write-Host "  - Rust version (Cargo.toml): $NewVersion"
if (Test-Path $pubspecFile) {
    Write-Host "  - Flutter version (pubspec.yaml): $flutterVersion"
}
Write-Host ""
Write-Host "Updated locations:" -ForegroundColor Cyan
Write-Host "  - Cargo.toml [package] version = `"$NewVersion`""
Write-Host "  - Cargo.toml [workspace.package] version = `"$NewVersion`""
if (Test-Path $pubspecFile) {
    Write-Host "  - flutter/pubspec.yaml version = `"$flutterVersion`""
}
Write-Host "  - libs/portable/Cargo.toml (inherits from workspace)"
Write-Host "  - .github/workflows/flutter-build.yml"
Write-Host "  - .github/workflows/playground.yml"
Write-Host "  - .github/workflows/winget.yml"
Write-Host "  - appimage/AppImageBuilder-aarch64.yml"
Write-Host "  - appimage/AppImageBuilder-x86_64.yml"
Write-Host "  - res/PKGBUILD"
Write-Host "  - res/rpm-flutter-suse.spec"
Write-Host "  - res/rpm-flutter.spec"
Write-Host "  - res/rpm.spec"
Write-Host ""
Write-Host "Version breakdown:" -ForegroundColor Cyan
Write-Host "  - Rust uses: $NewVersion (e.g., 1.4.3-jlc13)"
if (Test-Path $pubspecFile) {
    Write-Host "  - Flutter uses: $flutterVersion (version+build, e.g., 1.4.3+62)"
    Write-Host "  - PE file header will use: $flutterVersion (from Flutter build)"
}
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Verify changes: git diff"
Write-Host "  2. Test build: cargo build --release"
Write-Host "  3. Commit changes: git add -A && git commit -m `"chore: bump version to $NewVersion`""
