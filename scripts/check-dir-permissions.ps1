param(
    [string]$Path = "C:\Windows\system32\config\systemprofile",
    [switch]$Help
)

function Show-Help {
    Write-Host @"
Usage: check-dir-permissions.ps1 [-Path <directory>] [-Help]

Description:
    Check directory access permissions (ACL) for specified directory and all parent directories.
    By default, checks C:\Windows\system32\config\systemprofile and its parent directories.

Parameters:
    -Path <directory>    The directory path to check (default: C:\Windows\system32\config\systemprofile)
    -Help               Show this help message

Examples:
    # Check default system profile directory and parents
    .\check-dir-permissions.ps1

    # Check a specific directory and parents
    .\check-dir-permissions.ps1 -Path "C:\Users\gongdewei\AppData\Roaming\RustDesk\log"
"@
}

if ($Help) {
    Show-Help
    exit 0
}

function Test-DirectoryAccess {
    param([string]$DirPath)

    try {
        $null = Get-ChildItem -Path $DirPath -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Get-DirectoryPermissions {
    param([string]$DirPath)

    # Check if directory exists
    if (-not (Test-Path -Path $DirPath)) {
        Write-Host "[NOT FOUND] $DirPath" -ForegroundColor Red
        return
    }

    # Test if we can access the directory
    $canAccess = Test-DirectoryAccess -DirPath $DirPath
    $accessStatus = if ($canAccess) { "[ACCESSIBLE]" } else { "[ACCESS DENIED]" }
    $accessColor = if ($canAccess) { "Green" } else { "Red" }

    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "Directory: $DirPath" -ForegroundColor Yellow
    Write-Host "Access Status: $accessStatus" -ForegroundColor $accessColor
    Write-Host "================================================================================" -ForegroundColor Cyan

    try {
        # Get ACL information
        $acl = Get-Acl -Path $DirPath -ErrorAction Stop

        Write-Host "Owner: $($acl.Owner)" -ForegroundColor White
        Write-Host "Access Rules:" -ForegroundColor White

        foreach ($access in $acl.Access) {
            $identity = $access.IdentityReference
            $rights = $access.FileSystemRights
            $type = $access.AccessControlType
            $inherited = if ($access.IsInherited) { "(Inherited)" } else { "(Explicit)" }

            $color = switch ($type) {
                "Allow" { "Green" }
                "Deny" { "Red" }
                default { "White" }
            }

            Write-Host "  - $identity" -ForegroundColor Cyan
            Write-Host "    Type: $type $inherited" -ForegroundColor $color
            Write-Host "    Rights: $rights" -ForegroundColor White
        }

        # Get current user and check permissions
        $currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        Write-Host ""
        Write-Host "Current User: $($currentUser.Name)" -ForegroundColor Magenta

        # Check if current user has read access
        $hasReadAccess = $false
        foreach ($access in $acl.Access) {
            if ($access.AccessControlType -eq "Allow") {
                # Check if rule applies to current user or their groups
                try {
                    $identity = $access.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier])
                    if ($currentUser.User -eq $identity -or $currentUser.Groups -contains $identity) {
                        if ($access.FileSystemRights -match "Read|FullControl|Modify") {
                            $hasReadAccess = $true
                            break
                        }
                    }
                }
                catch {
                    # Some identities can't be translated, skip them
                }
            }
        }

        $readStatus = if ($hasReadAccess) { "YES" } else { "NO" }
        $readColor = if ($hasReadAccess) { "Green" } else { "Yellow" }
        Write-Host "Has Read Permission: $readStatus" -ForegroundColor $readColor

    }
    catch {
        Write-Host "Error getting ACL: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ParentDirectories {
    param([string]$TargetPath)

    $directories = @()
    $currentPath = [System.IO.Path]::GetFullPath($TargetPath)

    # Add the target directory
    $directories += $currentPath

    # Traverse up to root
    while ($true) {
        $parent = [System.IO.Path]::GetDirectoryName($currentPath)
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $currentPath) {
            break
        }
        $directories += $parent
        $currentPath = $parent
    }

    # Reverse to show from root to target
    [array]::Reverse($directories)
    return $directories
}

# Main execution
Write-Host "====================================================================================" -ForegroundColor Cyan
Write-Host "Directory Permission Check Tool" -ForegroundColor Yellow
Write-Host "====================================================================================" -ForegroundColor Cyan
Write-Host "Target Path: $Path" -ForegroundColor White
Write-Host "Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor White
Write-Host ""
Write-Host "Checking directory and all parent directories..." -ForegroundColor White

# Get all parent directories from root to target
$directories = Get-ParentDirectories -TargetPath $Path

Write-Host ""
Write-Host "Directory tree (from root to target):" -ForegroundColor Cyan
for ($i = 0; $i -lt $directories.Count; $i++) {
    $indent = "  " * $i
    Write-Host "$indent$($directories[$i])" -ForegroundColor Gray
}

# Check each directory
foreach ($dir in $directories) {
    Get-DirectoryPermissions -DirPath $dir
}

Write-Host ""
Write-Host "====================================================================================" -ForegroundColor Cyan
Write-Host "Check completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Green
Write-Host "====================================================================================" -ForegroundColor Cyan
