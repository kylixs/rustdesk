# RustDesk Development Environment Setup Script (PowerShell for Windows)
# Based on .docs/build/Windows_Flutter_Build_Steps.md and tasks.md
# Automatically download and install all required components

param(
    [switch]$SkipPython,
    [switch]$SkipLLVM,
    [switch]$SkipRust,
    [switch]$SkipFlutter,
    [switch]$SkipVcpkg,
    [switch]$Help
)

# Stop on errors
$ErrorActionPreference = "Stop"

# Color functions
function Write-InfoMsg {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Blue
}

function Write-SuccessMsg {
    param([string]$Message)
    Write-Host "[SUCCESS] $Message" -ForegroundColor Green
}

function Write-WarningMsg {
    param([string]$Message)
    Write-Host "[WARNING] $Message" -ForegroundColor Yellow
}

function Write-ErrorMsg {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Section {
    param([string]$Message)
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    Write-Host "========================================" -ForegroundColor Green
}

# Show help
if ($Help) {
    Write-Host "RustDesk Development Environment Setup Script"
    Write-Host ""
    Write-Host "Usage: .\setup-env.ps1 [Options]"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -SkipPython    Skip Python installation"
    Write-Host "  -SkipLLVM      Skip LLVM installation"
    Write-Host "  -SkipRust      Skip Rust installation"
    Write-Host "  -SkipFlutter   Skip Flutter installation"
    Write-Host "  -SkipVcpkg     Skip vcpkg installation"
    Write-Host "  -Help          Show this help message"
    exit 0
}

# Environment variables
$env:VERSION = if ($env:VERSION) { $env:VERSION } else { "1.4.3" }
$env:FLUTTER_VERSION = if ($env:FLUTTER_VERSION) { $env:FLUTTER_VERSION } else { "3.24.5" }
$env:LLVM_VERSION = if ($env:LLVM_VERSION) { $env:LLVM_VERSION } else { "15.0.6" }
$env:RUST_VERSION = if ($env:RUST_VERSION) { $env:RUST_VERSION } else { "1.75" }
$env:PYTHON_VERSION = if ($env:PYTHON_VERSION) { $env:PYTHON_VERSION } else { "3.11.9" }
$VCPKG_COMMIT_ID = if ($env:VCPKG_COMMIT_ID) { $env:VCPKG_COMMIT_ID } else { "120deac3062162151622ca4860575a33844ba10b" }
$VCPKG_ROOT = if ($env:VCPKG_ROOT) { $env:VCPKG_ROOT } else { "C:\vcpkg" }
$env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

# Temp download directory
$TEMP_DIR = ".\temp\setup"
if (-not (Test-Path $TEMP_DIR)) {
    New-Item -ItemType Directory -Path $TEMP_DIR -Force | Out-Null
}

Write-Section "RustDesk Development Environment Setup"
Write-InfoMsg "Version: $($env:VERSION)"
Write-InfoMsg "Flutter: $($env:FLUTTER_VERSION)"
Write-InfoMsg "LLVM: $($env:LLVM_VERSION)"
Write-InfoMsg "Rust: $($env:RUST_VERSION)"
Write-InfoMsg "Python: $($env:PYTHON_VERSION)"
Write-InfoMsg "Temp directory: $TEMP_DIR"

# Helper function: Check if command exists
function Test-CommandExists {
    param([string]$Command)
    try {
        if (Get-Command $Command -ErrorAction SilentlyContinue) {
            return $true
        }
    } catch {
        return $false
    }
    return $false
}

# Helper function: Download file
function Download-File {
    param(
        [string]$Url,
        [string]$Output,
        [string]$Description = "file"
    )

    Write-InfoMsg "Downloading $Description..."
    Write-InfoMsg "URL: $Url"

    try {
        Import-Module BitsTransfer
        Start-BitsTransfer -Source $Url -Destination $Output -Description "Downloading $Description"
        Write-SuccessMsg "Download complete: $Output"
        return $true
    } catch {
        Write-WarningMsg "BITS transfer failed, trying Invoke-WebRequest..."
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $Url -OutFile $Output -UseBasicParsing
            $ProgressPreference = 'Continue'
            Write-SuccessMsg "Download complete: $Output"
            return $true
        } catch {
            Write-ErrorMsg "Download failed: $_"
            return $false
        }
    }
}

# Helper function: Refresh environment variables
function Refresh-EnvironmentVariables {
    $machinePath = [System.Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [System.Environment]::GetEnvironmentVariable("Path", "User")
    $env:Path = "$machinePath;$userPath"
}

# Task 1: Check Git
Write-Section "Task 1: Check Git"

if (Test-CommandExists git) {
    $GitVersion = git --version
    Write-SuccessMsg "Git installed: $GitVersion"
} else {
    Write-ErrorMsg "Git not installed"
    Write-InfoMsg "Git is required, please install: https://git-scm.com/download/win"
    exit 1
}

# Task 1.5: Initialize Git submodules
Write-Section "Task 1.5: Initialize Git submodules"

# Check if we're in a git repository
$IsGitRepo = git rev-parse --is-inside-work-tree 2>&1
if ($IsGitRepo -eq "true") {
    Write-InfoMsg "Checking Git submodules..."

    # Get submodule status
    $SubmoduleStatus = git submodule status 2>&1

    if ($SubmoduleStatus) {
        # Check if any submodules are uninitialized (marked with -)
        $UninitializedSubmodules = $SubmoduleStatus | Where-Object { $_ -match '^-' }

        if ($UninitializedSubmodules) {
            Write-WarningMsg "Found uninitialized submodules"
            Write-InfoMsg "Initializing and updating submodules..."

            try {
                git submodule update --init --recursive

                if ($LASTEXITCODE -eq 0) {
                    Write-SuccessMsg "Git submodules initialized successfully"
                } else {
                    Write-ErrorMsg "Failed to initialize Git submodules"
                    Write-InfoMsg "Please run manually: git submodule update --init --recursive"
                    exit 1
                }
            } catch {
                Write-ErrorMsg "Error initializing submodules: $_"
                exit 1
            }
        } else {
            Write-SuccessMsg "Git submodules already initialized"
        }

        # Verify critical submodule exists
        if (Test-Path "libs\hbb_common\Cargo.toml") {
            Write-SuccessMsg "Critical submodule 'hbb_common' verified"
        } else {
            Write-ErrorMsg "Critical submodule 'hbb_common' missing"
            Write-InfoMsg "Please run: git submodule update --init --recursive"
            exit 1
        }
    } else {
        Write-InfoMsg "No submodules found in repository"
    }
} else {
    Write-WarningMsg "Not in a Git repository, skipping submodule check"
}

# Task 2: Check and install Python
if (-not $SkipPython) {
    Write-Section "Task 2: Check and install Python"

    $InstallPython = $false

    # First, try to add Python to PATH if it exists but not in PATH
    $PythonMajorMinorNoDot = ($env:PYTHON_VERSION -split '\.')[0,1] -join ''
    $PossiblePythonPaths = @(
        "$env:LOCALAPPDATA\Programs\Python\Python$PythonMajorMinorNoDot",
        "C:\Python$PythonMajorMinorNoDot",
        "C:\Program Files\Python$PythonMajorMinorNoDot"
    )

    foreach ($PyPath in $PossiblePythonPaths) {
        if ((Test-Path "$PyPath\python.exe") -and -not (Test-CommandExists python)) {
            Write-InfoMsg "Found Python at $PyPath, adding to PATH"
            $env:Path = "$PyPath;$PyPath\Scripts;$env:Path"
            break
        }
    }

    if (Test-CommandExists python) {
        try {
            $PythonCurrentVersion = (python --version 2>&1) -replace 'Python ',''
            Write-SuccessMsg "Python installed and working: $PythonCurrentVersion"

            $PythonMajorMinor = ($PythonCurrentVersion -split '\.')[0,1] -join '.'
            $TargetMajorMinor = ($env:PYTHON_VERSION -split '\.')[0,1] -join '.'

            if ($PythonMajorMinor -ne $TargetMajorMinor) {
                Write-WarningMsg "Python version mismatch, expected: $($env:PYTHON_VERSION)"
                $Response = Read-Host "Install Python $($env:PYTHON_VERSION)? (y/N)"
                if ($Response -match '^[Yy]$') {
                    $InstallPython = $true
                } else {
                    Write-InfoMsg "Using existing Python $PythonCurrentVersion"
                }
            } else {
                Write-InfoMsg "Python $PythonMajorMinor is already installed, skipping download"
            }
        } catch {
            Write-WarningMsg "Python command exists but not working properly"
            $InstallPython = $true
        }
    } else {
        Write-WarningMsg "Python not found in PATH or common install locations"
        $InstallPython = $true
    }

    if ($InstallPython) {
        Write-InfoMsg "Preparing to install Python $($env:PYTHON_VERSION)..."

        $PythonInstaller = "python-$($env:PYTHON_VERSION)-amd64.exe"
        $PythonUrl = "https://www.python.org/ftp/python/$($env:PYTHON_VERSION)/$PythonInstaller"
        $PythonInstallerPath = Join-Path $TEMP_DIR $PythonInstaller

        if (-not (Test-Path $PythonInstallerPath)) {
            Download-File -Url $PythonUrl -Output $PythonInstallerPath -Description "Python $($env:PYTHON_VERSION) installer"
        } else {
            Write-InfoMsg "Using cached installer: $PythonInstaller"
        }

        Write-InfoMsg "Installing Python $($env:PYTHON_VERSION)..."
        Write-WarningMsg "Installation dialog will appear, please follow the prompts"

        $InstallArgs = @("/passive", "InstallAllUsers=0", "PrependPath=1", "Include_test=0")
        $Process = Start-Process -FilePath $PythonInstallerPath -ArgumentList $InstallArgs -Wait -PassThru

        Start-Sleep -Seconds 5

        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
            Write-SuccessMsg "Python installation complete"

            Write-InfoMsg "Refreshing environment variables..."
            Refresh-EnvironmentVariables

            $PythonMajorMinorNoDot = ($env:PYTHON_VERSION -split '\.')[0,1] -join ''
            $PossiblePythonPaths = @(
                "$env:LOCALAPPDATA\Programs\Python\Python$PythonMajorMinorNoDot",
                "C:\Python$PythonMajorMinorNoDot",
                "C:\Program Files\Python$PythonMajorMinorNoDot"
            )

            foreach ($PyPath in $PossiblePythonPaths) {
                if (Test-Path "$PyPath\python.exe") {
                    Write-InfoMsg "Found Python installation at: $PyPath"
                    $env:Path = "$PyPath;$PyPath\Scripts;$env:Path"
                    break
                }
            }

            if (Test-CommandExists python) {
                $InstalledVersion = python --version 2>&1
                Write-SuccessMsg "Python installed: $InstalledVersion"
                Write-SuccessMsg "PATH refreshed"
            } else {
                Write-WarningMsg "Python installed but not in PATH"
                Write-InfoMsg "Please restart PowerShell"
            }
        } else {
            Write-ErrorMsg "Python installation failed, exit code: $($Process.ExitCode)"
            exit 1
        }
    }

    if (Test-CommandExists python) {
        Write-InfoMsg "Upgrading pip..."
        python -m pip install --upgrade pip --quiet 2>&1 | Out-Null
        Write-SuccessMsg "pip upgraded"

        Write-InfoMsg "Installing Python dependencies..."
        python -m pip install requests argparse --quiet 2>&1 | Out-Null
        Write-SuccessMsg "Python dependencies installed"
    }
}

# Task 3: Check and install LLVM/Clang
if (-not $SkipLLVM) {
    Write-Section "Task 3: Check and install LLVM/Clang"

    $InstallLLVM = $false

    # First, try to add LLVM to PATH if it exists but not in PATH
    $PossibleLLVMPaths = @(
        "C:\Program Files\LLVM\bin",
        "C:\Program Files (x86)\LLVM\bin"
    )

    foreach ($LLVMPath in $PossibleLLVMPaths) {
        if ((Test-Path "$LLVMPath\clang.exe") -and -not (Test-CommandExists clang)) {
            Write-InfoMsg "Found LLVM at $LLVMPath, adding to PATH"
            $env:Path = "$LLVMPath;$env:Path"
            break
        }
    }

    if (Test-CommandExists clang) {
        try {
            $ClangVersionOutput = clang --version 2>&1 | Select-Object -First 1
            $ClangVersion = ($ClangVersionOutput | Select-String -Pattern '\d+\.\d+\.\d+').Matches.Value | Select-Object -First 1
            Write-SuccessMsg "Clang installed and working: $ClangVersion"

            # Extract major.minor.patch from both versions for comparison
            $ClangMajorMinor = ($ClangVersion -split '\.')[0,1] -join '.'
            $TargetMajorMinor = ($env:LLVM_VERSION -split '\.')[0,1] -join '.'

            Write-InfoMsg "Comparing versions - Installed: $ClangMajorMinor, Target: $TargetMajorMinor"

            if ($ClangMajorMinor -ne $TargetMajorMinor) {
                Write-WarningMsg "LLVM version mismatch, expected: $($env:LLVM_VERSION)"
                $Response = Read-Host "Install LLVM $($env:LLVM_VERSION)? (y/N)"
                if ($Response -match '^[Yy]$') {
                    $InstallLLVM = $true
                } else {
                    Write-InfoMsg "Using existing LLVM $ClangVersion"
                }
            } else {
                Write-InfoMsg "LLVM $ClangMajorMinor is already installed and matches requirement, skipping"
            }
        } catch {
            Write-WarningMsg "Clang command exists but not working properly"
            $InstallLLVM = $true
        }
    } else {
        Write-WarningMsg "LLVM/Clang not found in PATH or common install locations"
        $InstallLLVM = $true
    }

    if ($InstallLLVM) {
        Write-InfoMsg "Preparing to install LLVM $($env:LLVM_VERSION)..."

        $LLVMInstaller = "LLVM-$($env:LLVM_VERSION)-win64.exe"
        $LLVMUrl = "https://github.com/llvm/llvm-project/releases/download/llvmorg-$($env:LLVM_VERSION)/$LLVMInstaller"
        $LLVMInstallerPath = Join-Path $TEMP_DIR $LLVMInstaller

        if (-not (Test-Path $LLVMInstallerPath)) {
            Download-File -Url $LLVMUrl -Output $LLVMInstallerPath -Description "LLVM $($env:LLVM_VERSION) installer"
        } else {
            Write-InfoMsg "Using cached installer: $LLVMInstaller"
        }

        Write-InfoMsg "Installing LLVM $($env:LLVM_VERSION)..."
        Write-WarningMsg "Silent installation in progress..."

        $Process = Start-Process -FilePath $LLVMInstallerPath -ArgumentList "/S" -Wait -PassThru

        Start-Sleep -Seconds 5

        Refresh-EnvironmentVariables
        $llvmPath = "C:\Program Files\LLVM\bin"
        $env:Path = "$llvmPath;$env:Path"

        if (Test-CommandExists clang) {
            Write-SuccessMsg "LLVM installation complete"
        } else {
            Write-WarningMsg "LLVM installed but not in PATH"
            Write-InfoMsg "Please restart PowerShell"
        }
    }
}

# Task 4: Check and install Rust
if (-not $SkipRust) {
    Write-Section "Task 4: Check and install Rust"

    $InstallRust = $false

    # First, try to add Rust to PATH if it exists but not in PATH
    $CargoPath = "$env:USERPROFILE\.cargo\bin"
    if ((Test-Path "$CargoPath\rustc.exe") -and -not (Test-CommandExists rustc)) {
        Write-InfoMsg "Found Rust at $CargoPath, adding to PATH"
        $env:Path = "$CargoPath;$env:Path"
    }

    if (Test-CommandExists rustc) {
        try {
            $RustcVersion = (rustc --version 2>&1) -replace 'rustc ','' -replace ' \(.*\)',''
            Write-SuccessMsg "Rust installed and working: $RustcVersion"
            Write-InfoMsg "Rust is already installed, skipping download"

            # Check and add required targets/components
            $Targets = rustup target list --installed 2>&1
            if ($Targets -match "x86_64-pc-windows-msvc") {
                Write-SuccessMsg "x86_64-pc-windows-msvc target installed"
            } else {
                Write-InfoMsg "Adding x86_64-pc-windows-msvc target..."
                rustup target add x86_64-pc-windows-msvc
            }

            $Components = rustup component list --installed 2>&1
            if ($Components -match "rustfmt") {
                Write-SuccessMsg "rustfmt installed"
            } else {
                Write-InfoMsg "Adding rustfmt component..."
                rustup component add rustfmt
            }
        } catch {
            Write-WarningMsg "Rust command exists but not working properly"
            $InstallRust = $true
        }
    } else {
        Write-WarningMsg "Rust not found in PATH or common install locations"
        $InstallRust = $true
    }

    if ($InstallRust) {
        Write-InfoMsg "Preparing to install Rust..."

        $RustupInstaller = "rustup-init.exe"
        $RustupUrl = "https://win.rustup.rs/x86_64"
        $RustupInstallerPath = Join-Path $TEMP_DIR $RustupInstaller

        if (-not (Test-Path $RustupInstallerPath)) {
            Download-File -Url $RustupUrl -Output $RustupInstallerPath -Description "Rustup installer"
        } else {
            Write-InfoMsg "Using cached installer: $RustupInstaller"
        }

        Write-InfoMsg "Installing Rust $($env:RUST_VERSION)..."
        Write-WarningMsg "Silent installation in progress..."

        $InstallArgs = @("-y", "--default-toolchain", "$($env:RUST_VERSION)-x86_64-pc-windows-msvc")
        $Process = Start-Process -FilePath $RustupInstallerPath -ArgumentList $InstallArgs -Wait -PassThru

        Start-Sleep -Seconds 5

        Refresh-EnvironmentVariables
        $cargoPath = "$env:USERPROFILE\.cargo\bin"
        $env:Path = "$cargoPath;$env:Path"

        if (Test-CommandExists rustc) {
            Write-SuccessMsg "Rust installation complete"

            Write-InfoMsg "Adding required components..."
            rustup target add x86_64-pc-windows-msvc
            rustup component add rustfmt

            Write-SuccessMsg "Rust configuration complete"
        } else {
            Write-WarningMsg "Rust installed but not in PATH"
            Write-InfoMsg "Please restart PowerShell"
        }
    }
}

# Task 5: Check and install Flutter
if (-not $SkipFlutter) {
    Write-Section "Task 5: Check and install Flutter"

    $InstallFlutter = $false

    # First, try to add Flutter to PATH if it exists but not in PATH
    $PossibleFlutterPaths = @(
        "C:\flutter\bin",
        "$env:USERPROFILE\flutter\bin",
        "C:\src\flutter\bin"
    )

    foreach ($FlutterPath in $PossibleFlutterPaths) {
        if ((Test-Path "$FlutterPath\flutter.bat") -and -not (Test-CommandExists flutter)) {
            Write-InfoMsg "Found Flutter at $FlutterPath, adding to PATH"
            $env:Path = "$FlutterPath;$env:Path"
            break
        }
    }

    if (Test-CommandExists flutter) {
        try {
            $FlutterCurrentVersion = (flutter --version 2>&1 | Select-String "Flutter").Line -replace '.*Flutter ([0-9.]+).*','$1'
            Write-SuccessMsg "Flutter installed and working: $FlutterCurrentVersion"

            if ($FlutterCurrentVersion -ne $env:FLUTTER_VERSION) {
                Write-WarningMsg "Flutter version mismatch, expected: $($env:FLUTTER_VERSION)"
                $Response = Read-Host "Install Flutter $($env:FLUTTER_VERSION)? (y/N)"
                if ($Response -match '^[Yy]$') {
                    $InstallFlutter = $true
                } else {
                    Write-InfoMsg "Using existing Flutter $FlutterCurrentVersion"
                }
            } else {
                Write-InfoMsg "Flutter $($env:FLUTTER_VERSION) is already installed, skipping download"
            }
        } catch {
            Write-WarningMsg "Flutter command exists but not working properly"
            $InstallFlutter = $true
        }
    } else {
        Write-WarningMsg "Flutter not found in PATH or common install locations"
        $InstallFlutter = $true
    }

    if ($InstallFlutter) {
        Write-InfoMsg "Installing Flutter $($env:FLUTTER_VERSION)..."

        $FlutterZip = "flutter_windows_$($env:FLUTTER_VERSION)-stable.zip"
        $FlutterUrl = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/$FlutterZip"
        $FlutterZipPath = Join-Path $TEMP_DIR $FlutterZip
        $FlutterInstallDir = "C:\flutter"

        # Download if not cached
        if (-not (Test-Path $FlutterZipPath)) {
            Download-File -Url $FlutterUrl -Output $FlutterZipPath -Description "Flutter $($env:FLUTTER_VERSION) SDK"
        } else {
            Write-InfoMsg "Using cached Flutter archive: $FlutterZip"
        }

        # Extract Flutter SDK
        Write-InfoMsg "Extracting Flutter SDK (this may take a few minutes)..."
        if (Test-Path $FlutterInstallDir) {
            Write-WarningMsg "Backing up existing Flutter installation..."
            $BackupName = "C:\flutter.backup." + (Get-Date -Format "yyyyMMddHHmmss")
            Rename-Item $FlutterInstallDir $BackupName
            Write-InfoMsg "Backup created at: $BackupName"
        }

        Expand-Archive -Path $FlutterZipPath -DestinationPath "C:\" -Force
        Write-SuccessMsg "Flutter SDK extracted"

        # Add to PATH
        $flutterBinPath = "C:\flutter\bin"
        $env:Path = "$flutterBinPath;$env:Path"

        # Verify installation
        if (Test-CommandExists flutter) {
            $InstalledVersion = (flutter --version 2>&1 | Select-String "Flutter").Line -replace '.*Flutter ([0-9.]+).*','$1'
            Write-SuccessMsg "Flutter $InstalledVersion installed successfully"
        } else {
            Write-WarningMsg "Flutter installed but not in PATH"
            Write-InfoMsg "Please add C:\flutter\bin to system PATH"
        }
    }

    if (Test-CommandExists flutter) {
        Write-InfoMsg "Configuring Flutter..."
        flutter config --enable-windows-desktop | Out-Null
        flutter precache --windows | Out-Null
        Write-SuccessMsg "Flutter configuration complete"
    }
}

# Task 6: Replace RustDesk custom Flutter engine
if ((-not $SkipFlutter) -and (Test-CommandExists flutter)) {
    Write-Section "Task 6: Replace RustDesk custom Flutter engine"

    $FlutterEngineZip = "windows-x64-release.zip"
    $FlutterEngineUrl = "https://github.com/rustdesk/engine/releases/download/main/$FlutterEngineZip"
    $FlutterEngineZipPath = Join-Path $TEMP_DIR $FlutterEngineZip

    # Download engine if not cached
    if (-not (Test-Path $FlutterEngineZipPath)) {
        Download-File -Url $FlutterEngineUrl -Output $FlutterEngineZipPath -Description "RustDesk Flutter engine"
    } else {
        Write-InfoMsg "Using cached engine archive: $FlutterEngineZip"
    }

    Write-InfoMsg "Replacing Flutter engine..."

    # Extract engine
    $EngineExtractDir = Join-Path $TEMP_DIR "flutter_engine"
    if (Test-Path $EngineExtractDir) {
        Remove-Item -Recurse -Force $EngineExtractDir
    }
    Expand-Archive -Path $FlutterEngineZipPath -DestinationPath $EngineExtractDir -Force

    # Replace engine files
    $FlutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
    $EnginePath = Join-Path $FlutterRoot "bin\cache\artifacts\engine\windows-x64-release"

    if (Test-Path $EnginePath) {
        Write-InfoMsg "Backing up original Flutter engine..."
        $BackupName = "$EnginePath.backup." + (Get-Date -Format "yyyyMMddHHmmss")
        Rename-Item $EnginePath $BackupName
    }

    New-Item -ItemType Directory -Path $EnginePath -Force | Out-Null
    Copy-Item -Path "$EngineExtractDir\*" -Destination $EnginePath -Recurse -Force

    Write-SuccessMsg "Flutter engine replaced with RustDesk custom version"
}

# Task 7: Apply Flutter patch
if ((-not $SkipFlutter) -and (Test-CommandExists flutter) -and ($env:FLUTTER_VERSION -eq "3.24.5")) {
    Write-Section "Task 7: Apply Flutter patch"

    $PatchFile = ".\.github\patches\flutter_3.24.4_dropdown_menu_enableFilter.diff"

    if (-not (Test-Path $PatchFile)) {
        Write-ErrorMsg "Patch file not found: $PatchFile"
        Write-ErrorMsg "Please ensure you are running this script from the RustDesk project root directory"
        exit 1
    }

    $FlutterRoot = Split-Path -Parent (Split-Path -Parent (Get-Command flutter).Source)
    $TargetFile = Join-Path $FlutterRoot "packages\flutter\lib\src\material\dropdown_menu.dart"

    # Check if patch target file exists
    if (-not (Test-Path $TargetFile)) {
        Write-ErrorMsg "Flutter target file not found: $TargetFile"
        Write-ErrorMsg "Flutter installation may be incomplete"
        exit 1
    }

    Write-InfoMsg "Applying Flutter patch..."
    $PatchFileName = Split-Path $PatchFile -Leaf
    $PatchFullPath = Resolve-Path $PatchFile

    try {
        Push-Location $FlutterRoot

        # First check if patch can be applied
        Write-InfoMsg "Checking if patch can be applied..."
        $CheckOutput = git apply --check $PatchFullPath 2>&1

        if ($LASTEXITCODE -eq 0) {
            # Patch can be applied
            Write-InfoMsg "Applying patch to Flutter..."
            $ApplyOutput = git apply $PatchFullPath 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMsg "Flutter patch applied successfully"
            } else {
                Write-ErrorMsg "Flutter patch failed to apply"
                Write-ErrorMsg "Error: $($ApplyOutput -join "`n")"
                throw "Patch application failed"
            }
        } else {
            # Check if patch was already applied
            Write-InfoMsg "Patch cannot be applied, checking if already applied..."
            $ReverseCheckOutput = git apply --reverse --check $PatchFullPath 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMsg "Flutter patch already applied, skipping"
            } else {
                # Patch cannot be applied and was not already applied
                # This might be due to version mismatch or manual changes
                Write-Host ""
                Write-Host "========================================" -ForegroundColor Yellow
                Write-WarningMsg "FLUTTER PATCH CANNOT BE APPLIED"
                Write-Host "========================================" -ForegroundColor Yellow
                Write-WarningMsg "Reason: Version mismatch or file already modified"
                Write-InfoMsg "Expected: Flutter 3.24.4/3.24.5"
                Write-InfoMsg "This is not critical - continuing installation..."
                Write-Host "========================================" -ForegroundColor Yellow
                Write-Host ""
                Start-Sleep -Seconds 2
            }
        }
    } catch {
        Write-ErrorMsg "Error applying Flutter patch: $_"
        # exit 1
    } finally {
        # Always return to original directory
        Pop-Location
    }
}

# Task 8: Check and install Visual Studio Build Tools
Write-Section "Task 8: Check and install Visual Studio Build Tools"

$InstallBuildTools = $false
$MSBuildFound = $false

# First, try to find MSBuild in PATH
if (Get-Command msbuild -ErrorAction SilentlyContinue) {
    $MSBuildVersion = & msbuild -version 2>&1 | Select-Object -Last 1
    Write-SuccessMsg "MSBuild installed and in PATH: $MSBuildVersion"
    $MSBuildFound = $true
} else {
    # MSBuild not in PATH, search common installation locations
    Write-InfoMsg "MSBuild not found in PATH, searching common installation locations..."

    $PossibleMSBuildPaths = @(
        "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe",
        "C:\Program Files (x86)\Microsoft Visual Studio\2019\Community\MSBuild\Current\Bin\msbuild.exe"
    )

    foreach ($MSBuildPath in $PossibleMSBuildPaths) {
        if (Test-Path $MSBuildPath) {
            Write-SuccessMsg "Found MSBuild at: $MSBuildPath"
            $MSBuildVersion = & $MSBuildPath -version 2>&1 | Select-Object -Last 1
            Write-SuccessMsg "MSBuild version: $MSBuildVersion"

            # Add to PATH for current session
            $MSBuildDir = Split-Path -Parent $MSBuildPath
            $env:Path = "$MSBuildDir;$env:Path"

            Write-InfoMsg "Added MSBuild to PATH for current session"
            $MSBuildFound = $true
            break
        }
    }

    if (-not $MSBuildFound) {
        Write-WarningMsg "MSBuild not found"
        $InstallBuildTools = $true
    }
}

if ($InstallBuildTools) {
    Write-InfoMsg "Visual Studio Build Tools required"
    Write-InfoMsg ""
    Write-InfoMsg "Required components:"
    Write-InfoMsg "  - MSVC v143 - VS 2022 C++ x64/x86 build tools"
    Write-InfoMsg "  - Windows 10/11 SDK"
    Write-InfoMsg "  - C++ CMake tools"
    Write-InfoMsg "  - MSBuild"
    Write-InfoMsg "  - NuGet package manager"
    Write-InfoMsg ""

    $Response = Read-Host "Download and install Visual Studio Build Tools? (y/N)"
    if ($Response -match '^[Yy]$') {
        $BuildToolsInstaller = "vs_BuildTools.exe"
        $BuildToolsUrl = "https://aka.ms/vs/17/release/vs_buildtools.exe"
        $BuildToolsInstallerPath = Join-Path $TEMP_DIR $BuildToolsInstaller

        # Download installer if not cached
        if (-not (Test-Path $BuildToolsInstallerPath)) {
            Download-File -Url $BuildToolsUrl -Output $BuildToolsInstallerPath -Description "Visual Studio Build Tools installer"
        } else {
            Write-InfoMsg "Using cached installer: $BuildToolsInstaller"
        }

        Write-InfoMsg "Installing Visual Studio Build Tools..."
        Write-WarningMsg "This will install required C++ build tools and may take 10-30 minutes"
        Write-WarningMsg "A GUI installer window will appear - please wait for it to complete"

        # Install with required workloads
        $InstallArgs = @(
            "--quiet",
            "--wait",
            "--norestart",
            "--add", "Microsoft.VisualStudio.Workload.VCTools",
            "--add", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
            "--add", "Microsoft.VisualStudio.Component.Windows11SDK.22000",
            "--add", "Microsoft.VisualStudio.Component.VC.CMake.Project",
            "--includeRecommended"
        )

        $Process = Start-Process -FilePath $BuildToolsInstallerPath -ArgumentList $InstallArgs -Wait -PassThru

        if ($Process.ExitCode -eq 0 -or $Process.ExitCode -eq 3010) {
            Write-SuccessMsg "Visual Studio Build Tools installation complete"

            if ($Process.ExitCode -eq 3010) {
                Write-WarningMsg "A system restart is recommended"
            }

            # Refresh environment variables
            Write-InfoMsg "Refreshing environment variables..."
            Refresh-EnvironmentVariables

            # Add common MSBuild paths
            $PossibleMSBuildPaths = @(
                "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin",
                "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin",
                "C:\Program Files (x86)\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin",
                "C:\Program Files\Microsoft Visual Studio\2022\Community\MSBuild\Current\Bin"
            )

            foreach ($MSBuildPath in $PossibleMSBuildPaths) {
                if (Test-Path "$MSBuildPath\msbuild.exe") {
                    Write-InfoMsg "Found MSBuild at: $MSBuildPath"
                    $env:Path = "$MSBuildPath;$env:Path"
                    break
                }
            }

            # Verify installation
            if (Get-Command msbuild -ErrorAction SilentlyContinue) {
                $MSBuildVersion = & msbuild -version 2>&1 | Select-Object -Last 1
                Write-SuccessMsg "MSBuild now available: $MSBuildVersion"
            } else {
                Write-WarningMsg "MSBuild installed but not in PATH"
                Write-InfoMsg "Please restart PowerShell or add MSBuild to PATH manually"
            }
        } else {
            Write-ErrorMsg "Visual Studio Build Tools installation failed, exit code: $($Process.ExitCode)"
            Write-InfoMsg "You can install manually from: https://visualstudio.microsoft.com/downloads/"
        }
    } else {
        Write-InfoMsg "Skipping Visual Studio Build Tools installation"
        Write-InfoMsg "Manual download: https://visualstudio.microsoft.com/downloads/"
        Write-WarningMsg "Build Tools are required - please install manually and rerun this script"
    }
}

# Task 9-10: Configure and install vcpkg
if (-not $SkipVcpkg) {
    Write-Section "Task 9-10: Configure and install vcpkg"

    if (-not (Test-Path $VCPKG_ROOT)) {
        Write-InfoMsg "Cloning vcpkg to $VCPKG_ROOT..."
        git clone https://github.com/Microsoft/vcpkg.git $VCPKG_ROOT

        Write-InfoMsg "Checking out commit: $VCPKG_COMMIT_ID"
        try {
            Push-Location $VCPKG_ROOT
            git checkout $VCPKG_COMMIT_ID

            Write-InfoMsg "Bootstrapping vcpkg..."
            .\bootstrap-vcpkg.bat

            Write-SuccessMsg "vcpkg installed"
        } catch {
            Write-ErrorMsg "Error setting up vcpkg: $_"
            exit 1
        } finally {
            Pop-Location
        }
    } else {
        Write-SuccessMsg "vcpkg exists: $VCPKG_ROOT"

        try {
            Push-Location $VCPKG_ROOT
            $CurrentCommit = git rev-parse HEAD

            if ($CurrentCommit -ne $VCPKG_COMMIT_ID) {
                Write-WarningMsg "vcpkg version mismatch"
                Write-InfoMsg "Current: $CurrentCommit"
                Write-InfoMsg "Expected: $VCPKG_COMMIT_ID"

                $Response = Read-Host "Switch to specified version? (y/N)"
                if ($Response -match '^[Yy]$') {
                    git checkout $VCPKG_COMMIT_ID
                    .\bootstrap-vcpkg.bat
                }
            }
        } catch {
            Write-ErrorMsg "Error checking vcpkg version: $_"
            exit 1
        } finally {
            Pop-Location
        }
    }

    $env:VCPKG_ROOT = $VCPKG_ROOT
    $env:VCPKG_DEFAULT_HOST_TRIPLET = "x64-windows-static"

    Write-Section "Installing vcpkg dependencies"
    Write-WarningMsg "This may take 30-60 minutes, please be patient..."

    # 检查是否在 RustDesk 项目目录
    if (-not (Test-Path ".\vcpkg.json")) {
        Write-WarningMsg "vcpkg.json not found in current directory"
        Write-InfoMsg "Skipping vcpkg dependencies installation"
        Write-InfoMsg "Please run this script from RustDesk project root directory"
        Write-InfoMsg "Or run scripts\install-vcpkg-deps.ps1 manually later"
    } else {
        try {
            Write-InfoMsg "Installing dependencies from vcpkg.json..."
            Write-InfoMsg "Working directory: $(Get-Location)"

            # 在项目根目录运行 vcpkg install，这样它会自动读取 vcpkg.json
            $VcpkgExe = Join-Path $VCPKG_ROOT "vcpkg.exe"
            & $VcpkgExe install --triplet x64-windows-static --x-install-root="$VCPKG_ROOT\installed"

            if ($LASTEXITCODE -eq 0) {
                Write-SuccessMsg "vcpkg dependencies installed"

                # 验证关键文件
                $OpusHeader = Join-Path $VCPKG_ROOT "installed\x64-windows-static\include\opus\opus_multistream.h"
                if (Test-Path $OpusHeader) {
                    Write-SuccessMsg "Verified: opus library installed correctly"
                } else {
                    Write-WarningMsg "opus library may not be installed correctly"
                }
            } else {
                Write-ErrorMsg "vcpkg dependencies installation failed"
                Write-InfoMsg "Check logs:"
                if (Test-Path "$VCPKG_ROOT\buildtrees") {
                    Get-ChildItem "$VCPKG_ROOT\buildtrees" -Filter "*.log" -Recurse -ErrorAction SilentlyContinue |
                        Select-Object -First 5 |
                        ForEach-Object {
                            Write-Host "  - $($_.FullName)"
                        }
                }

                $Response = Read-Host "Continue? (y/N)"
                if ($Response -notmatch '^[Yy]$') {
                    exit 1
                }
            }
        } catch {
            Write-ErrorMsg "Error installing vcpkg dependencies: $_"
            Write-InfoMsg "You can run scripts\install-vcpkg-deps.ps1 manually later"
            $Response = Read-Host "Continue? (y/N)"
            if ($Response -notmatch '^[Yy]$') {
                exit 1
            }
        }
    }
}

# Task 11: Install Cargo tools
if (Test-CommandExists cargo) {
    Write-Section "Task 11: Install Cargo tools"

    $CargoList = cargo install --list

    Write-InfoMsg "Checking flutter_rust_bridge_codegen..."
    if ($CargoList -match "flutter_rust_bridge_codegen") {
        Write-SuccessMsg "flutter_rust_bridge_codegen installed"
    } else {
        Write-InfoMsg "Installing flutter_rust_bridge_codegen..."
        cargo install flutter_rust_bridge_codegen --version 1.80.1 --features "uuid" --locked
        Write-SuccessMsg "flutter_rust_bridge_codegen installed"
    }

    Write-InfoMsg "Checking cargo-expand..."
    if ($CargoList -match "cargo-expand") {
        Write-SuccessMsg "cargo-expand installed"
    } else {
        Write-InfoMsg "Installing cargo-expand..."
        cargo install cargo-expand --version 1.0.95 --locked
        Write-SuccessMsg "cargo-expand installed"
    }
}

# Environment variables configuration
Write-Section "Environment variables configuration"

Write-InfoMsg "Recommended environment variables:"
Write-Host ""
Write-Host "# RustDesk build environment"
Write-Host "VCPKG_ROOT = $VCPKG_ROOT"
Write-Host "VCPKG_DEFAULT_HOST_TRIPLET = x64-windows-static"
Write-Host "VERSION = $($env:VERSION)"
Write-Host ""
Write-Host "Add to PATH:"
Write-Host "  C:\flutter\bin"
Write-Host "  $env:USERPROFILE\.cargo\bin"
Write-Host "  C:\Program Files\LLVM\bin"

# Find MSBuild location if it was detected
$MSBuildPathToAdd = $null
if ($MSBuildFound) {
    # Check if MSBuild is in PATH now
    $MSBuildCmd = Get-Command msbuild -ErrorAction SilentlyContinue
    if ($MSBuildCmd) {
        $MSBuildPathToAdd = Split-Path -Parent $MSBuildCmd.Source
        Write-Host "  $MSBuildPathToAdd"
    }
}
Write-Host ""

$Response = Read-Host "Automatically add to user environment variables? (Y/n)"
if ($Response -notmatch '^[Nn]$') {
    [Environment]::SetEnvironmentVariable("VCPKG_ROOT", $VCPKG_ROOT, "User")
    [Environment]::SetEnvironmentVariable("VCPKG_DEFAULT_HOST_TRIPLET", "x64-windows-static", "User")
    [Environment]::SetEnvironmentVariable("VERSION", $env:VERSION, "User")

    $UserPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $PathsToAdd = @(
        "C:\flutter\bin",
        "$env:USERPROFILE\.cargo\bin",
        "C:\Program Files\LLVM\bin"
    )

    # Add MSBuild path if found
    if ($MSBuildPathToAdd) {
        $PathsToAdd += $MSBuildPathToAdd
    }

    foreach ($PathToAdd in $PathsToAdd) {
        if ($UserPath -notlike "*$PathToAdd*") {
            $UserPath = "$PathToAdd;$UserPath"
        }
    }

    [Environment]::SetEnvironmentVariable("Path", $UserPath, "User")

    Write-SuccessMsg "Environment variables added"
    Write-InfoMsg "Please restart PowerShell for changes to take effect"
}

# Cleanup temp files
# Write-Section "Cleanup temporary files"

# $Response = Read-Host "Delete temporary download files? (Y/n)"
# if ($Response -notmatch '^[Nn]$') {
#     Remove-Item -Recurse -Force $TEMP_DIR -ErrorAction SilentlyContinue
#     Write-SuccessMsg "Temporary files deleted"
# } else {
#     Write-InfoMsg "Keeping temporary files: $TEMP_DIR"
# }

# Final summary
Write-Section "Environment initialization complete"

Write-SuccessMsg "Development environment setup successful!"
Write-Host ""
Write-InfoMsg "Toolchain version summary:"

if (Test-CommandExists git) {
    Write-Host "  [OK] Git: $(git --version)"
}
if (Test-CommandExists python) {
    Write-Host "  [OK] Python: $(python --version 2>&1)"
}
if (Test-CommandExists rustc) {
    Write-Host "  [OK] Rust: $(rustc --version)"
}
if (Test-CommandExists flutter) {
    $FlutterVer = (flutter --version | Select-Object -First 1)
    Write-Host "  [OK] Flutter: $FlutterVer"
}
if (Test-CommandExists clang) {
    $ClangVer = (clang --version | Select-Object -First 1)
    Write-Host "  [OK] Clang: $ClangVer"
}
if (Get-Command msbuild -ErrorAction SilentlyContinue) {
    $MSBuildVer = & msbuild -version 2>&1 | Select-Object -Last 1
    Write-Host "  [OK] MSBuild: $MSBuildVer"
} else {
    Write-Host "  [X] MSBuild: Not installed (manual installation required)"
}

Write-Host ""
Write-InfoMsg "Next steps:"
Write-Host "  1. Restart PowerShell if new tools were installed"
Write-Host "  2. Ensure Visual Studio Build Tools is installed"
Write-Host "  3. Run build script: .\build-rustdesk.ps1"
Write-Host "  4. Check docs: .docs\build\tasks.md"
Write-Host ""

Write-WarningMsg "Notes:"
Write-Host "  - First build may take 2-4 hours"
Write-Host "  - Ensure sufficient disk space (at least 20GB)"
Write-Host "  - Some components may require PowerShell restart"
Write-Host ""

Write-SuccessMsg "Setup script execution complete!"
