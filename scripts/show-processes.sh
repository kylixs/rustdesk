#!/usr/bin/env bash
#
# Query and display process information with PID, version, path, arguments, and network ports.
# Usage: show-processes.sh <exe-name> [-t] [-l]
#
# Options:
#   <exe-name>  Process name to search for (default: rustdesk)
#   -t          Show process tree view (default)
#   -l          Show flat list view
#   -h          Show help message
#
# Examples:
#   ./show-processes.sh                 # Query rustdesk processes (tree view)
#   ./show-processes.sh chrome          # Query chrome processes (tree view)
#   ./show-processes.sh notepad -l      # Query notepad processes (list view)
#   ./show-processes.sh rustdesk -t -l  # Query rustdesk processes (both views)

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
GRAY='\033[0;90m'
NC='\033[0m' # No Color

# Default values
PROCESS_NAME="rustdesk"
SHOW_TREE=true
SHOW_LIST=false

# Detect OS
OS_TYPE=$(uname -s)

# Parse arguments
if [[ $# -gt 0 ]]; then
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        head -n 16 "$0" | tail -n 14
        exit 0
    fi

    # First argument is process name if it doesn't start with '-'
    if [[ ! "$1" =~ ^- ]]; then
        PROCESS_NAME="$1"
        shift
    fi
fi

# Parse flags
TREE_EXPLICIT=false
LIST_EXPLICIT=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -t)
            TREE_EXPLICIT=true
            shift
            ;;
        -l)
            LIST_EXPLICIT=true
            shift
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Determine display mode
if [[ "$TREE_EXPLICIT" == true ]] && [[ "$LIST_EXPLICIT" == true ]]; then
    SHOW_TREE=true
    SHOW_LIST=true
elif [[ "$LIST_EXPLICIT" == true ]]; then
    SHOW_TREE=false
    SHOW_LIST=true
elif [[ "$TREE_EXPLICIT" == true ]]; then
    SHOW_TREE=true
    SHOW_LIST=false
fi

# Function to get process version
get_process_version() {
    local exe_path="$1"

    if [[ ! -f "$exe_path" ]]; then
        return
    fi

    # Try to get version by running --version
    local version=""
    if [[ -x "$exe_path" ]]; then
        version=$("$exe_path" --version 2>/dev/null | head -n 1 || true)
    fi

    # If that didn't work, try -version
    if [[ -z "$version" ]]; then
        version=$("$exe_path" -version 2>/dev/null | head -n 1 || true)
    fi

    # If still no version, try to extract from file
    if [[ -z "$version" ]] && command -v strings &> /dev/null; then
        version=$(strings "$exe_path" | grep -i "version" | head -n 1 || true)
    fi

    echo "$version"
}

# Function to get process ports
get_process_ports() {
    local pid="$1"

    if [[ "$OS_TYPE" == "Darwin" ]]; then
        # macOS
        lsof -nP -iTCP -sTCP:LISTEN -a -p "$pid" 2>/dev/null | awk 'NR>1 {print "    - " $9 " (LISTEN)"}' || true
        lsof -nP -iTCP -a -p "$pid" 2>/dev/null | awk 'NR>1 && $10!="(LISTEN)" {print "    - " $9}' || true
        lsof -nP -iUDP -a -p "$pid" 2>/dev/null | awk 'NR>1 {print "    - " $9}' || true
    else
        # Linux
        if command -v ss &> /dev/null; then
            ss -tulpn 2>/dev/null | grep "pid=$pid," | awk '{print "    - " $5}' || true
        elif command -v netstat &> /dev/null; then
            netstat -tulpn 2>/dev/null | grep "$pid/" | awk '{print "    - " $4}' || true
        fi
    fi
}

# Function to display process info
display_process_info() {
    local pid="$1"
    local indent="$2"

    # Get process information
    local ps_info
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        ps_info=$(ps -p "$pid" -o pid=,ppid=,comm=,args= 2>/dev/null || true)
    else
        ps_info=$(ps -p "$pid" -o pid=,ppid=,comm=,args= 2>/dev/null || true)
    fi

    if [[ -z "$ps_info" ]]; then
        return
    fi

    read -r p_pid p_ppid p_comm p_args <<< "$ps_info"

    # Get full path
    local exe_path=""
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        exe_path=$(ps -p "$pid" -o comm= 2>/dev/null | xargs which 2>/dev/null || true)
        if [[ -z "$exe_path" ]]; then
            exe_path=$(lsof -p "$pid" 2>/dev/null | awk 'NR==2 {print $9}' || true)
        fi
    else
        exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
    fi

    # Display process info
    echo -e "${indent}${CYAN}├─ PID: $pid${NC}"

    # Version
    if [[ -n "$exe_path" ]]; then
        local version=$(get_process_version "$exe_path")
        if [[ -n "$version" ]]; then
            echo -e "${indent}${BLUE}│  Version: $version${NC}"
        fi
        echo -e "${indent}${GREEN}│  Path: $exe_path${NC}"
    else
        echo -e "${indent}${GRAY}│  Path: <Unknown>${NC}"
    fi

    # Arguments
    if [[ -n "$p_args" ]]; then
        echo -e "${indent}${YELLOW}│  Args: $p_args${NC}"
    else
        echo -e "${indent}${GRAY}│  Args: <None>${NC}"
    fi

    # Ports
    local ports=$(get_process_ports "$pid")
    if [[ -n "$ports" ]]; then
        echo -e "${indent}${MAGENTA}│  Ports:${NC}"
        echo -e "${indent}${WHITE}$ports${NC}"
    fi

    echo -e "${indent}│"
}

# Function to display process tree recursively
display_process_tree() {
    local pid="$1"
    local indent="$2"

    display_process_info "$pid" "$indent"

    # Find child processes
    local children
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        children=$(ps -A -o pid=,ppid= | awk -v ppid="$pid" '$2 == ppid {print $1}')
    else
        children=$(ps -A -o pid=,ppid= | awk -v ppid="$pid" '$2 == ppid {print $1}')
    fi

    if [[ -n "$children" ]]; then
        while IFS= read -r child_pid; do
            display_process_tree "$child_pid" "  $indent"
        done <<< "$children"
    fi
}

# Function to show tree view
show_tree_view() {
    local pids=("$@")

    echo -e "\n${MAGENTA}=== Process Tree View ===${NC}\n"

    # Find root processes (those whose parent is not in the matching set)
    local root_pids=()
    for pid in "${pids[@]}"; do
        local ppid
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | xargs)
        else
            ppid=$(ps -p "$pid" -o ppid= 2>/dev/null | xargs)
        fi

        # Check if parent is in the list
        local parent_in_list=false
        for p in "${pids[@]}"; do
            if [[ "$p" == "$ppid" ]]; then
                parent_in_list=true
                break
            fi
        done

        if [[ "$parent_in_list" == false ]]; then
            root_pids+=("$pid")
        fi
    done

    # Display each root process tree
    for pid in "${root_pids[@]}"; do
        local pname
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            pname=$(ps -p "$pid" -o comm= 2>/dev/null)
        else
            pname=$(ps -p "$pid" -o comm= 2>/dev/null)
        fi
        echo -e "${MAGENTA}Process Tree for: $pname${NC}"
        display_process_tree "$pid" ""
        echo ""
    done
}

# Function to show list view
show_list_view() {
    local pids=("$@")

    echo -e "\n${MAGENTA}=== Flat List View ===${NC}\n"

    # Sort PIDs
    IFS=$'\n' sorted_pids=($(sort -n <<<"${pids[*]}"))
    unset IFS

    for pid in "${sorted_pids[@]}"; do
        # Get process information
        local ps_info
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            ps_info=$(ps -p "$pid" -o pid=,ppid=,comm=,args= 2>/dev/null || true)
        else
            ps_info=$(ps -p "$pid" -o pid=,ppid=,comm=,args= 2>/dev/null || true)
        fi

        if [[ -z "$ps_info" ]]; then
            continue
        fi

        read -r p_pid p_ppid p_comm p_args <<< "$ps_info"

        echo -e "${CYAN}PID: $pid | Name: $p_comm${NC}"

        # Get full path
        local exe_path=""
        if [[ "$OS_TYPE" == "Darwin" ]]; then
            exe_path=$(ps -p "$pid" -o comm= 2>/dev/null | xargs which 2>/dev/null || true)
            if [[ -z "$exe_path" ]]; then
                exe_path=$(lsof -p "$pid" 2>/dev/null | awk 'NR==2 {print $9}' || true)
            fi
        else
            exe_path=$(readlink -f "/proc/$pid/exe" 2>/dev/null || true)
        fi

        # Version
        if [[ -n "$exe_path" ]]; then
            local version=$(get_process_version "$exe_path")
            if [[ -n "$version" ]]; then
                echo -e "  ${BLUE}Version: $version${NC}"
            fi
            echo -e "  ${GREEN}Path: $exe_path${NC}"
        fi

        # Arguments
        if [[ -n "$p_args" ]]; then
            echo -e "  ${YELLOW}Args: $p_args${NC}"
        fi

        # Parent PID
        echo -e "  ${CYAN}Parent PID: $p_ppid${NC}"

        # Ports
        local ports=$(get_process_ports "$pid")
        if [[ -n "$ports" ]]; then
            echo -e "  ${MAGENTA}Ports:${NC}"
            echo -e "${WHITE}$ports${NC}"
        fi

        echo ""
    done
}

# Main execution
main() {
    echo -e "\n${MAGENTA}=== Process Information for: $PROCESS_NAME ===${NC}\n"

    # Find all matching processes
    local pids=()
    if [[ "$OS_TYPE" == "Darwin" ]]; then
        pids=($(pgrep -i "$PROCESS_NAME" 2>/dev/null || true))
    else
        pids=($(pgrep -i "$PROCESS_NAME" 2>/dev/null || true))
    fi

    if [[ ${#pids[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No processes matching '$PROCESS_NAME' found.${NC}"
        exit 0
    fi

    echo -e "${GREEN}Found ${#pids[@]} process(es) matching '$PROCESS_NAME'${NC}\n"

    # Show requested views
    if [[ "$SHOW_TREE" == true ]]; then
        show_tree_view "${pids[@]}"
    fi

    if [[ "$SHOW_LIST" == true ]]; then
        show_list_view "${pids[@]}"
    fi

    echo -e "${GREEN}Total: ${#pids[@]} process(es)${NC}"
}

main
