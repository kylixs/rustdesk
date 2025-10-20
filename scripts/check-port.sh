#!/usr/bin/env bash
# Query process listening on a specific port
# Shows process name, PID, and command line arguments
#
# Usage: ./check-port.sh [port]
# Example: ./check-port.sh 21118

# Default port is 21118, but can be overridden by command line argument
PORT=${1:-21118}

echo "=== Checking port $PORT ==="
echo ""

# Check if running as root (needed for some commands)
if [ "$EUID" -ne 0 ]; then
    echo "Note: Running without root privileges. Some information may be limited."
    echo "      Run with sudo for complete process information."
    echo ""
fi

# Function to get process command line
get_process_cmdline() {
    local pid=$1
    if [ -f "/proc/$pid/cmdline" ]; then
        # Replace null bytes with spaces
        tr '\0' ' ' < "/proc/$pid/cmdline"
        echo ""
    else
        ps -p "$pid" -o args= 2>/dev/null
    fi
}

# Method 1: Using netstat (works on most systems)
echo "Method 1: Using netstat"
echo "----------------------------------------"

if command -v netstat >/dev/null 2>&1; then
    # Linux
    if netstat -tulpn 2>/dev/null | grep -q ":$PORT"; then
        netstat -tulpn 2>/dev/null | grep ":$PORT" | while read -r line; do
            echo "$line"

            # Extract PID/Program
            if [[ $line =~ ([0-9]+)/(.+)$ ]]; then
                pid="${BASH_REMATCH[1]}"
                program="${BASH_REMATCH[2]}"

                echo "  Process Name: $program"
                echo "  PID: $pid"

                # Get full command line
                cmdline=$(get_process_cmdline "$pid")
                echo "  Command Line: $cmdline"

                # Get executable path
                if [ -L "/proc/$pid/exe" ]; then
                    exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
                    echo "  Executable: $exe_path"
                fi

                echo ""
            fi
        done
    else
        # Try without sudo for non-root users
        netstat -tuln 2>/dev/null | grep ":$PORT" | while read -r line; do
            echo "$line"
            echo "  (Run with sudo to see process information)"
            echo ""
        done
    fi
else
    echo "netstat command not found"
fi

echo ""

# Method 2: Using ss (modern replacement for netstat)
echo "Method 2: Using ss"
echo "----------------------------------------"

if command -v ss >/dev/null 2>&1; then
    if ss -tulpn 2>/dev/null | grep -q ":$PORT"; then
        ss -tulpn 2>/dev/null | grep ":$PORT" | while read -r line; do
            echo "$line"

            # Extract PID and program name
            if [[ $line =~ pid=([0-9]+) ]]; then
                pid="${BASH_REMATCH[1]}"

                echo "  PID: $pid"

                # Get process name
                if [ -f "/proc/$pid/comm" ]; then
                    proc_name=$(cat "/proc/$pid/comm" 2>/dev/null)
                    echo "  Process Name: $proc_name"
                fi

                # Get full command line
                cmdline=$(get_process_cmdline "$pid")
                echo "  Command Line: $cmdline"

                # Get executable path
                if [ -L "/proc/$pid/exe" ]; then
                    exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
                    echo "  Executable: $exe_path"
                fi

                echo ""
            fi
        done
    else
        ss -tuln 2>/dev/null | grep ":$PORT"
        echo "  (Run with sudo to see process information)"
        echo ""
    fi
else
    echo "ss command not found"
fi

echo ""

# Method 3: Using lsof (if available)
echo "Method 3: Using lsof"
echo "----------------------------------------"

if command -v lsof >/dev/null 2>&1; then
    if lsof -i ":$PORT" -n -P 2>/dev/null | grep -q "LISTEN"; then
        echo "Processes listening on port $PORT:"
        echo ""

        lsof -i ":$PORT" -n -P 2>/dev/null | grep "LISTEN" | while read -r proto pid user fd type device size node name; do
            # Skip header line
            if [ "$proto" = "COMMAND" ]; then
                continue
            fi

            echo "  Process Name: $proto"
            echo "  PID: $pid"
            echo "  User: $user"
            echo "  Type: $type"
            echo "  Name: $name"

            # Get full command line
            cmdline=$(get_process_cmdline "$pid")
            echo "  Command Line: $cmdline"

            # Get executable path
            if [ -L "/proc/$pid/exe" ]; then
                exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null)
                echo "  Executable: $exe_path"
            elif command -v ps >/dev/null 2>&1; then
                exe_path=$(ps -p "$pid" -o comm= 2>/dev/null)
                echo "  Executable: $exe_path"
            fi

            echo "  ----------------------------------------"
        done
    else
        echo "No process found listening on port $PORT"
    fi
else
    echo "lsof command not found"
fi

echo ""
echo "=== Summary ==="

# Quick summary using any available tool
if command -v lsof >/dev/null 2>&1; then
    lsof -i ":$PORT" -n -P 2>/dev/null | grep "LISTEN"
elif command -v ss >/dev/null 2>&1; then
    ss -tulpn 2>/dev/null | grep ":$PORT"
elif command -v netstat >/dev/null 2>&1; then
    netstat -tulpn 2>/dev/null | grep ":$PORT"
else
    echo "No suitable network diagnostic tool found (netstat, ss, or lsof)"
fi
