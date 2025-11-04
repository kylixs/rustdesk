#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Query and display process information with PID, user, session ID, version, path, arguments, and network ports.
    Usage: show-processes.ps1 <exe-name> [-t] [-l]

.DESCRIPTION
    This script finds all processes matching the specified name and displays them in a tree structure
    showing:
    - Process ID (PID)
    - User name (Domain\Username)
    - Session ID
    - Version number (from executable file info)
    - Executable path
    - Command line arguments
    - TCP listening ports and connections
    - UDP endpoints

.PARAMETER ProcessName
    The name of the process to search for (case-insensitive). Default is "rustdesk".

.PARAMETER Tree
    Show process tree view. This is the default if neither -Tree nor -List is specified.

.PARAMETER List
    Show flat list view.

.NOTES
    - If neither -Tree nor -List is specified, tree view is shown by default
    - If both -Tree and -List are specified, both views are shown

.EXAMPLE
    .\show-processes.ps1
    Query RustDesk processes with tree view (default)

.EXAMPLE
    .\show-processes.ps1 chrome
    Query Chrome processes with tree view

.EXAMPLE
    .\show-processes.ps1 notepad -l
    Query Notepad processes in list view only

.EXAMPLE
    .\show-processes.ps1 rustdesk -t
    Query RustDesk processes in tree view only

.EXAMPLE
    .\show-processes.ps1 chrome -t -l
    Query Chrome processes with both tree and list views
#>

param(
    [Parameter(Position = 0)]
    [string]$ProcessName = "rustdesk",

    [Alias("t")]
    [switch]$Tree,

    [Alias("l")]
    [switch]$List
)

function Get-ProcessPorts {
    param(
        [int]$ProcessId
    )

    $ports = @{
        TCP = @()
        UDP = @()
    }

    # Get TCP connections
    try {
        $tcpConnections = Get-NetTCPConnection -OwningProcess $ProcessId -ErrorAction SilentlyContinue
        foreach ($conn in $tcpConnections) {
            $portInfo = "$($conn.LocalAddress):$($conn.LocalPort)"
            if ($conn.State -eq "Listen") {
                $portInfo += " (LISTEN)"
            } else {
                $portInfo += " -> $($conn.RemoteAddress):$($conn.RemotePort) ($($conn.State))"
            }
            $ports.TCP += $portInfo
        }
    } catch {
        # Silently ignore errors
    }

    # Get UDP endpoints
    try {
        $udpEndpoints = Get-NetUDPEndpoint -OwningProcess $ProcessId -ErrorAction SilentlyContinue
        foreach ($endpoint in $udpEndpoints) {
            $ports.UDP += "$($endpoint.LocalAddress):$($endpoint.LocalPort)"
        }
    } catch {
        # Silently ignore errors
    }

    return $ports
}

function Get-ProcessVersion {
    param(
        [string]$ExecutablePath
    )

    if (-not $ExecutablePath -or -not (Test-Path $ExecutablePath)) {
        return $null
    }

    try {
        $versionInfo = [System.Diagnostics.FileVersionInfo]::GetVersionInfo($ExecutablePath)
        if ($versionInfo.FileVersion) {
            return $versionInfo.FileVersion
        } elseif ($versionInfo.ProductVersion) {
            return $versionInfo.ProductVersion
        }
    } catch {
        # Silently ignore errors
    }

    return $null
}

function Get-ProcessTree {
    param(
        [int]$ProcessId,
        [int]$Indent = 0
    )

    $process = Get-WmiObject Win32_Process -Filter "ProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if (-not $process) {
        return
    }

    $indentStr = "  " * $Indent
    $path = $process.ExecutablePath
    $commandLine = $process.CommandLine

    # Get user name
    $owner = $process.GetOwner()
    $userName = if ($owner.Domain -and $owner.User) {
        "$($owner.Domain)\$($owner.User)"
    } elseif ($owner.User) {
        $owner.User
    } else {
        "<Unknown>"
    }

    # Get session ID
    $sessionId = if ($null -ne $process.SessionId) {
        $process.SessionId
    } else {
        "N/A"
    }

    # Display process information
    Write-Host "${indentStr}├─ PID: $ProcessId | User: $userName | Session: $sessionId" -ForegroundColor Cyan

    # Get and display version
    if ($path) {
        $version = Get-ProcessVersion -ExecutablePath $path
        if ($version) {
            Write-Host "${indentStr}│  Version: $version" -ForegroundColor White
        }
        Write-Host "${indentStr}│  Path: $path" -ForegroundColor Green
    } else {
        Write-Host "${indentStr}│  Path: <Unknown>" -ForegroundColor DarkGray
    }

    if ($commandLine) {
        Write-Host "${indentStr}│  Args: $commandLine" -ForegroundColor Yellow
    } else {
        Write-Host "${indentStr}│  Args: <None>" -ForegroundColor DarkGray
    }

    # Get and display ports
    $ports = Get-ProcessPorts -ProcessId $ProcessId
    if ($ports.TCP.Count -gt 0) {
        Write-Host "${indentStr}│  TCP Ports:" -ForegroundColor Magenta
        foreach ($tcpPort in $ports.TCP) {
            Write-Host "${indentStr}│    - $tcpPort" -ForegroundColor White
        }
    }
    if ($ports.UDP.Count -gt 0) {
        Write-Host "${indentStr}│  UDP Ports:" -ForegroundColor Magenta
        foreach ($udpPort in $ports.UDP) {
            Write-Host "${indentStr}│    - $udpPort" -ForegroundColor White
        }
    }

    Write-Host "${indentStr}│"

    # Get child processes
    $children = Get-WmiObject Win32_Process -Filter "ParentProcessId=$ProcessId" -ErrorAction SilentlyContinue
    if ($children) {
        foreach ($child in $children) {
            Get-ProcessTree -ProcessId $child.ProcessId -Indent ($Indent + 1)
        }
    }
}

function Show-ProcessesTree {
    param(
        [string]$Name,
        [string]$Mode
    )

    Write-Host "`n=== Process Information for: $Name ===" -ForegroundColor Magenta
    Write-Host ""

    # Find all matching processes (case-insensitive)
    $processes = Get-Process | Where-Object {
        $_.ProcessName -match $Name
    }

    if ($processes.Count -eq 0) {
        Write-Host "No processes matching '$Name' found." -ForegroundColor Yellow
        return
    }

    Write-Host "Found $($processes.Count) process(es) matching '$Name'" -ForegroundColor Green
    Write-Host ""

    # Show tree view if requested
    if ($Mode -eq "tree" -or $Mode -eq "both") {
        Write-Host "=== Process Tree View ===" -ForegroundColor Magenta
        Write-Host ""

        # Track processes we've already displayed (to avoid duplicates in tree)
        $displayedProcessIds = @()

        # First, find root processes (those whose parent is not in the matching set)
        $rootProcesses = @()
        foreach ($proc in $processes) {
            $parent = Get-WmiObject Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue
            if ($parent) {
                $parentProc = $processes | Where-Object { $_.Id -eq $parent.ParentProcessId }
                if (-not $parentProc) {
                    $rootProcesses += $proc
                }
            } else {
                $rootProcesses += $proc
            }
        }

        # Display each root process and its tree
        foreach ($proc in $rootProcesses) {
            if ($proc.Id -notin $displayedProcessIds) {
                Write-Host "Process Tree for: $($proc.ProcessName)" -ForegroundColor Magenta
                Get-ProcessTree -ProcessId $proc.Id
                $displayedProcessIds += $proc.Id
                Write-Host ""
            }
        }
    }

    # Show list view if requested
    if ($Mode -eq "list" -or $Mode -eq "both") {
        if ($Mode -eq "both") {
            Write-Host ""
        }

        Write-Host "=== Flat List View ===" -ForegroundColor Magenta
        Write-Host ""

        foreach ($proc in $processes | Sort-Object Id) {
            $wmiProc = Get-WmiObject Win32_Process -Filter "ProcessId=$($proc.Id)" -ErrorAction SilentlyContinue

            # Get user name
            if ($wmiProc) {
                $owner = $wmiProc.GetOwner()
                $userName = if ($owner.Domain -and $owner.User) {
                    "$($owner.Domain)\$($owner.User)"
                } elseif ($owner.User) {
                    $owner.User
                } else {
                    "<Unknown>"
                }

                # Get session ID
                $sessionId = if ($null -ne $wmiProc.SessionId) {
                    $wmiProc.SessionId
                } else {
                    "N/A"
                }

                Write-Host "PID: $($proc.Id) | Name: $($proc.ProcessName) | User: $userName | Session: $sessionId" -ForegroundColor Cyan
            } else {
                Write-Host "PID: $($proc.Id) | Name: $($proc.ProcessName)" -ForegroundColor Cyan
            }

            if ($wmiProc) {
                # Display version
                if ($wmiProc.ExecutablePath) {
                    $version = Get-ProcessVersion -ExecutablePath $wmiProc.ExecutablePath
                    if ($version) {
                        Write-Host "  Version: $version" -ForegroundColor White
                    }
                    Write-Host "  Path: $($wmiProc.ExecutablePath)" -ForegroundColor Green
                }

                if ($wmiProc.CommandLine) {
                    Write-Host "  Args: $($wmiProc.CommandLine)" -ForegroundColor Yellow
                }

                Write-Host "  Parent PID: $($wmiProc.ParentProcessId)" -ForegroundColor DarkCyan

                # Display ports
                $ports = Get-ProcessPorts -ProcessId $proc.Id
                if ($ports.TCP.Count -gt 0) {
                    Write-Host "  TCP Ports:" -ForegroundColor Magenta
                    foreach ($tcpPort in $ports.TCP) {
                        Write-Host "    - $tcpPort" -ForegroundColor White
                    }
                }
                if ($ports.UDP.Count -gt 0) {
                    Write-Host "  UDP Ports:" -ForegroundColor Magenta
                    foreach ($udpPort in $ports.UDP) {
                        Write-Host "    - $udpPort" -ForegroundColor White
                    }
                }
            }
            Write-Host ""
        }
    }

    Write-Host "Total: $($processes.Count) process(es)" -ForegroundColor Green
}

# Main execution
try {
    # Determine display mode based on switches
    $displayMode = "tree"  # Default

    if ($Tree -and $List) {
        $displayMode = "both"
    } elseif ($List) {
        $displayMode = "list"
    } elseif ($Tree) {
        $displayMode = "tree"
    }

    Show-ProcessesTree -Name $ProcessName -Mode $displayMode
} catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
