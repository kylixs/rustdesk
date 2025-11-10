# Query process listening on a specific port
# Shows process name, PID, and command line arguments
#
# Usage: .\check-port.ps1 [port]
# Example: .\check-port.ps1 21118

param(
    [Parameter(Position=0)]
    [int]$Port = 21118
)

Write-Host "=== Checking port $Port ===" -ForegroundColor Cyan
Write-Host ""

# Find process using port
$port = $Port
$connections = Get-NetTCPConnection -LocalPort $port -ErrorAction SilentlyContinue

if ($connections) {
    Write-Host "Found processes listening on port ${port}:" -ForegroundColor Green
    Write-Host ""

    foreach ($conn in $connections) {
        $processId = $conn.OwningProcess

        # Get process details
        $process = Get-Process -Id $processId -ErrorAction SilentlyContinue

        if ($process) {
            Write-Host "Process Name: " -NoNewline -ForegroundColor Yellow
            Write-Host $process.ProcessName

            Write-Host "PID: " -NoNewline -ForegroundColor Yellow
            Write-Host $processId

            Write-Host "Executable Path: " -NoNewline -ForegroundColor Yellow
            Write-Host $process.Path

            # Get command line arguments using WMI
            $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $processId"
            if ($wmiProcess) {
                Write-Host "Command Line: " -NoNewline -ForegroundColor Yellow
                Write-Host $wmiProcess.CommandLine
            }

            Write-Host "Local Address: " -NoNewline -ForegroundColor Yellow
            Write-Host "$($conn.LocalAddress):$($conn.LocalPort)"

            Write-Host "State: " -NoNewline -ForegroundColor Yellow
            Write-Host $conn.State

            Write-Host "----------------------------------------"
        }
    }
} else {
    Write-Host "No process found listening on port $port" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Alternative method using netstat ===" -ForegroundColor Cyan
Write-Host ""

# Alternative: Use netstat
$netstatOutput = netstat -ano | Select-String ":$port"
if ($netstatOutput) {
    Write-Host "Netstat output for port ${port}:" -ForegroundColor Green
    foreach ($line in $netstatOutput) {
        Write-Host $line

        # Extract PID from netstat output
        if ($line -match '\s+(\d+)\s*$') {
            $processId = $Matches[1]
            $process = Get-Process -Id $processId -ErrorAction SilentlyContinue
            if ($process) {
                $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $processId"
                Write-Host "  -> Process: $($process.ProcessName) ($($process.Path))" -ForegroundColor Cyan
                if ($wmiProcess) {
                    Write-Host "  -> Command: $($wmiProcess.CommandLine)" -ForegroundColor Cyan
                }
            }
        }
    }
} else {
    Write-Host "No connections found on port $port using netstat" -ForegroundColor Red
}

Write-Host ""
Write-Host "=== Process Hierarchy Tree ===" -ForegroundColor Cyan
Write-Host ""

# Function to print process tree
function Get-ProcessTree {
    param(
        [int]$ProcessId,
        [int]$Level = 0,
        [hashtable]$Visited = @{}
    )

    # Avoid infinite loops
    if ($Visited.ContainsKey($ProcessId)) {
        return
    }
    $Visited[$ProcessId] = $true

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) {
            return
        }

        $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if (-not $wmiProcess) {
            return
        }

        # Print indentation
        $indent = "  " * $Level
        $prefix = if ($Level -gt 0) { "└─ " } else { "" }

        # Print current process
        Write-Host "${indent}${prefix}" -NoNewline
        Write-Host "$($process.ProcessName)" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $ProcessId)" -ForegroundColor Yellow

        # Print command line if available
        if ($wmiProcess.CommandLine) {
            Write-Host "${indent}   Command: " -NoNewline -ForegroundColor DarkGray
            Write-Host $wmiProcess.CommandLine -ForegroundColor Gray
        }

        # Get parent process ID
        $parentId = $wmiProcess.ParentProcessId
        if ($parentId -and $parentId -ne 0 -and $parentId -ne $ProcessId) {
            # Recursively print parent
            Get-ProcessTree -ProcessId $parentId -Level ($Level + 1) -Visited $Visited
        }

    } catch {
        # Silently ignore errors (e.g., access denied)
    }
}

# Function to print child processes
function Get-ChildProcessTree {
    param(
        [int]$ProcessId,
        [int]$Level = 0,
        [hashtable]$Visited = @{}
    )

    # Avoid infinite loops
    if ($Visited.ContainsKey($ProcessId)) {
        return
    }
    $Visited[$ProcessId] = $true

    try {
        $process = Get-Process -Id $ProcessId -ErrorAction SilentlyContinue
        if (-not $process) {
            return
        }

        $wmiProcess = Get-WmiObject Win32_Process -Filter "ProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if (-not $wmiProcess) {
            return
        }

        # Print indentation
        $indent = "  " * $Level
        $prefix = if ($Level -gt 0) { "├─ " } else { "" }

        # Print current process
        Write-Host "${indent}${prefix}" -NoNewline
        Write-Host "$($process.ProcessName)" -ForegroundColor Green -NoNewline
        Write-Host " (PID: $ProcessId)" -ForegroundColor Yellow

        # Print command line if available
        if ($wmiProcess.CommandLine) {
            Write-Host "${indent}   Command: " -NoNewline -ForegroundColor DarkGray
            Write-Host $wmiProcess.CommandLine -ForegroundColor Gray
        }

        # Get child processes
        $children = Get-WmiObject Win32_Process -Filter "ParentProcessId = $ProcessId" -ErrorAction SilentlyContinue
        if ($children) {
            $childCount = if ($children -is [array]) { $children.Count } else { 1 }
            $currentChild = 0
            foreach ($child in $children) {
                $currentChild++
                $isLast = ($currentChild -eq $childCount)
                Get-ChildProcessTree -ProcessId $child.ProcessId -Level ($Level + 1) -Visited $Visited
            }
        }

    } catch {
        # Silently ignore errors
    }
}

# Print process tree for each unique PID found
$uniquePids = @{}
if ($connections) {
    foreach ($conn in $connections) {
        $processId = $conn.OwningProcess
        if (-not $uniquePids.ContainsKey($processId)) {
            $uniquePids[$processId] = $true

            Write-Host "Process tree for PID $processId (ancestors):" -ForegroundColor Magenta
            Get-ProcessTree -ProcessId $processId
            Write-Host ""

            Write-Host "Process tree for PID $processId (with children):" -ForegroundColor Magenta
            Get-ChildProcessTree -ProcessId $processId
            Write-Host ""
        }
    }
}
