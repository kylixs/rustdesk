# RustDesk Portable Package Verification Script
# Checks file versions, MD5 hashes, and sizes
# Output format: one file per line for easy comparison

param(
    [Parameter(Position=0)]
    [string]$PortableDir,
    [switch]$Csv,
    [switch]$Json,
    [switch]$AutoDetect,
    [switch]$Help
)

# Set output encoding to UTF-8 for better compatibility with redirection
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8

# Show help
if ($Help) {
    Write-Host "RustDesk Portable Package Verification Script"
    Write-Host ""
    Write-Host "Usage: .\scripts\check-portable.ps1 [OPTIONS] [PATH]"
    Write-Host ""
    Write-Host "Arguments:"
    Write-Host "  [PATH]       Portable directory path"
    Write-Host ""
    Write-Host "Options:"
    Write-Host "  -AutoDetect  Auto-detect portable extraction directory"
    Write-Host "  -Csv         Output in CSV format"
    Write-Host "  -Json        Output in JSON format"
    Write-Host "  -Help        Show this help message"
    Write-Host ""
    Write-Host "Detection methods (in priority order):"
    Write-Host "  1. Running RustDesk process directory (via process name)"
    Write-Host "  2. RustDesk port (21118/21119) process detection"
    Write-Host "  3. Standard portable extraction path: %LOCALAPPDATA%\rustdesk\"
    Write-Host ""
    Write-Host "Default mode uses silent process detection."
    Write-Host "-AutoDetect shows verbose detection progress."
    Write-Host ""
    Write-Host "Examples:"
    Write-Host "  .\scripts\check-portable.ps1"
    Write-Host "  .\scripts\check-portable.ps1 -AutoDetect"
    Write-Host "  .\scripts\check-portable.ps1 .\rustdesk"
    Write-Host "  .\scripts\check-portable.ps1 C:\path\to\rustdesk -Csv > files.csv"
    Write-Host "  .\scripts\check-portable.ps1 -AutoDetect -Json > files.json"
    Write-Host ""
    Write-Host "Output format (text):"
    Write-Host "  filename | version | md5 | size"
    exit 0
}

# Function to find portable directory by detecting running RustDesk process
function Find-PortableDirectory {
    Write-Host "Searching for portable directory..." -ForegroundColor Yellow

    # Method 1: Find running rustdesk.exe process and get its directory
    Write-Host "  Method 1: Detecting running RustDesk process..." -ForegroundColor Gray
    $rustdeskProcesses = Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue

    if ($rustdeskProcesses) {
        foreach ($proc in $rustdeskProcesses) {
            try {
                $exePath = $proc.Path
                if ($exePath) {
                    $procDir = Split-Path -Parent $exePath
                    Write-Host "    Found process: $exePath" -ForegroundColor Gray

                    # Check if this looks like a portable extraction directory
                    # Portable extracts to a directory containing rustdesk.exe and data/
                    if ((Test-Path (Join-Path $procDir "rustdesk.exe")) -and
                        (Test-Path (Join-Path $procDir "data"))) {
                        Write-Host "  Found: $procDir (from running process)" -ForegroundColor Green
                        return $procDir
                    }
                }
            } catch {
                # Process might have exited or access denied
                continue
            }
        }
    } else {
        Write-Host "    No running RustDesk process found" -ForegroundColor Gray
    }

    # Method 2: Check listening port 21118/21119 to find process directory
    Write-Host "  Method 2: Checking RustDesk ports (21118, 21119)..." -ForegroundColor Gray
    try {
        $connections = Get-NetTCPConnection -LocalPort 21118,21119 -ErrorAction SilentlyContinue |
                       Where-Object { $_.State -eq "Listen" }

        foreach ($conn in $connections) {
            $processId = $conn.OwningProcess
            $proc = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($proc -and $proc.Path) {
                $procDir = Split-Path -Parent $proc.Path
                Write-Host "    Found process on port $($conn.LocalPort): $($proc.Path)" -ForegroundColor Gray

                if ((Test-Path (Join-Path $procDir "rustdesk.exe")) -and
                    (Test-Path (Join-Path $procDir "data"))) {
                    Write-Host "  Found: $procDir (from port detection)" -ForegroundColor Green
                    return $procDir
                }
            }
        }
    } catch {
        Write-Host "    Port detection failed (requires admin privileges)" -ForegroundColor Gray
    }

    # Method 3: Fallback to standard portable extraction path
    Write-Host "  Method 3: Checking standard portable extraction path..." -ForegroundColor Gray
    $portableDir = "$env:LOCALAPPDATA\rustdesk"
    Write-Host "    Checking: $portableDir" -ForegroundColor Gray

    if (Test-Path $portableDir) {
        if (Test-Path (Join-Path $portableDir "rustdesk.exe")) {
            Write-Host "  Found: $portableDir (standard location)" -ForegroundColor Green
            return $portableDir
        }
    }

    Write-Error "Portable directory not found"
    Write-Host ""
    Write-Host "Tried methods:"
    Write-Host "  1. Running RustDesk process detection"
    Write-Host "  2. Port 21118/21119 process detection"
    Write-Host "  3. Standard path: $portableDir"
    Write-Host ""
    Write-Host "Please specify the directory manually:"
    Write-Host "  .\scripts\check-portable.ps1 <path>"
    exit 1
}

# Determine portable directory
if (-not $PortableDir) {
    if ($AutoDetect) {
        $PortableDir = Find-PortableDirectory
    } else {
        # Silently try to detect from running process first
        $rustdeskProcesses = Get-Process -Name "rustdesk" -ErrorAction SilentlyContinue
        $found = $false

        if ($rustdeskProcesses) {
            foreach ($proc in $rustdeskProcesses) {
                try {
                    $exePath = $proc.Path
                    if ($exePath) {
                        $procDir = Split-Path -Parent $exePath
                        if ((Test-Path (Join-Path $procDir "rustdesk.exe")) -and
                            (Test-Path (Join-Path $procDir "data"))) {
                            $PortableDir = $procDir
                            $found = $true
                            break
                        }
                    }
                } catch {
                    continue
                }
            }
        }

        # Fallback to standard location if process detection failed
        if (-not $found) {
            $PortableDir = "$env:LOCALAPPDATA\rustdesk"

            if (-not (Test-Path $PortableDir)) {
                Write-Error "Portable directory not found at: $PortableDir"
                Write-Host "No running RustDesk process detected. Use -AutoDetect for detailed search or specify path manually." -ForegroundColor Yellow
                exit 1
            }

            if (-not (Test-Path (Join-Path $PortableDir "rustdesk.exe"))) {
                Write-Error "rustdesk.exe not found in: $PortableDir"
                Write-Host "This doesn't appear to be a valid portable extraction directory." -ForegroundColor Yellow
                exit 1
            }
        }
    }
}

# Check if directory exists
if (-not (Test-Path $PortableDir)) {
    Write-Error "Directory not found: $PortableDir"
    exit 1
}

# Function to get file version (PE files only)
function Get-FileVersionString {
    param([string]$FilePath)

    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($FilePath)
        if ($versionInfo.FileVersion) {
            return $versionInfo.FileVersion.Trim()
        }
    } catch {
        # Not a PE file or no version info
    }
    return "-"
}

# Function to get MD5 hash
function Get-FileMD5 {
    param([string]$FilePath)

    try {
        $md5 = New-Object -TypeName System.Security.Cryptography.MD5CryptoServiceProvider
        $hash = [System.BitConverter]::ToString($md5.ComputeHash([System.IO.File]::ReadAllBytes($FilePath)))
        return $hash.Replace("-", "").ToLower()
    } catch {
        return "error"
    }
}

# Function to format file size
function Format-FileSize {
    param([long]$Size)

    if ($Size -ge 1GB) {
        return "{0:N2}GB" -f ($Size / 1GB)
    } elseif ($Size -ge 1MB) {
        return "{0:N2}MB" -f ($Size / 1MB)
    } elseif ($Size -ge 1KB) {
        return "{0:N2}KB" -f ($Size / 1KB)
    } else {
        return "{0}B" -f $Size
    }
}

# Collect file information
$fullPath = (Resolve-Path $PortableDir).Path

# Only show progress to console (stderr) if not redirecting output
if (-not $Csv -and -not $Json) {
    Write-Host "Scanning directory: $fullPath" -ForegroundColor Blue
}

$files = Get-ChildItem -Path $PortableDir -Recurse -File | ForEach-Object {
    # Get relative path
    $relativePath = $_.FullName.Substring($fullPath.Length).TrimStart('\', '/')

    [PSCustomObject]@{
        Path = $relativePath
        Version = Get-FileVersionString $_.FullName
        MD5 = Get-FileMD5 $_.FullName
        Size = $_.Length
        SizeFormatted = Format-FileSize $_.Length
    }
} | Sort-Object Path

$fileCount = $files.Count

# Only show progress to console (stderr) if not redirecting output
if (-not $Csv -and -not $Json) {
    Write-Host "Found $fileCount files" -ForegroundColor Blue
    Write-Host ""
}

# Output based on format
if ($Json) {
    # JSON output
    $output = @{
        directory = $PortableDir
        timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        file_count = $fileCount
        files = $files | ForEach-Object {
            @{
                path = $_.Path
                version = $_.Version
                md5 = $_.MD5
                size = $_.Size
            }
        }
    }
    $output | ConvertTo-Json -Depth 10

} elseif ($Csv) {
    # CSV output
    Write-Output "Path,Version,MD5,Size"
    $files | ForEach-Object {
        Write-Output "$($_.Path),$($_.Version),$($_.MD5),$($_.Size)"
    }

} else {
    # Text output (default) - one file per line
    # Header
    Write-Output ("=" * 120)
    Write-Output ("{0,-50} {1,-20} {2,-32} {3,10}" -f "File", "Version", "MD5", "Size")
    Write-Output ("=" * 120)

    # Files
    $files | ForEach-Object {
        Write-Output ("{0,-50} {1,-20} {2,-32} {3,10}" -f `
            $_.Path, `
            $_.Version, `
            $_.MD5, `
            $_.SizeFormatted)
    }

    # Footer
    Write-Output ("=" * 120)
    Write-Output "Total: $fileCount files"

    # Calculate total size
    $totalSize = ($files | Measure-Object -Property Size -Sum).Sum
    Write-Output "Total size: $(Format-FileSize $totalSize)"
}
