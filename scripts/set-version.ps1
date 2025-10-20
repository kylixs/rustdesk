# RustDesk Version Management Script
# Used to update workspace version uniformly

param(
    [Parameter(Position=0)]
    [string]$NewVersion,
    [switch]$Help
)

if ($Help -or $NewVersion -eq "-h" -or $NewVersion -eq "--help" -or [string]::IsNullOrEmpty($NewVersion)) {
    Write-Host "RustDesk Version Management Script"
    Write-Host ""
    Write-Host "Usage: .\scripts\set-version.ps1 <version>"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\set-version.ps1 1.4.4"
    Write-Host "  .\scripts\set-version.ps1 1.5.0"
    Write-Host "  .\scripts\set-version.ps1 1.4.3-jlc11"
    Write-Host "  .\scripts\set-version.ps1 1.4.3-rc.1+build.123"
    Write-Host ""
    Write-Host "Description:"
    Write-Host "  This script will update version numbers in the following locations:"
    Write-Host "  1. Cargo.toml [package] version (main program version)"
    Write-Host "  2. Cargo.toml [workspace.package] version (workspace version)"
    Write-Host "  3. All subcomponents automatically inherit workspace version (version.workspace = true)"
    Write-Host "  4. GitHub workflow files (.github/workflows/flutter-build.yml, playground.yml, winget.yml)"
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

        # Update VERSION: "x.x.x" pattern
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

Write-Host ""
Write-Host "[SUCCESS] Version successfully updated to $NewVersion" -ForegroundColor Green
Write-Host ""
Write-Host "Updated locations:" -ForegroundColor Cyan
Write-Host "  - Cargo.toml [package] version"
Write-Host "  - Cargo.toml [workspace.package] version"
Write-Host "  - .github/workflows/flutter-build.yml"
Write-Host "  - .github/workflows/playground.yml"
Write-Host "  - .github/workflows/winget.yml"
Write-Host ""
Write-Host "Subcomponents inheriting workspace version (version.workspace = true):"
Write-Host "  - libs/portable (rustdesk-portable-packer)"
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Verify changes: git diff Cargo.toml .github/workflows/"
Write-Host "  2. Test build: .\build.ps1"
Write-Host "  3. Commit changes: git add Cargo.toml .github/workflows/ && git commit -m `"chore: bump version to $NewVersion`""
