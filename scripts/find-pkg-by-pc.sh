#!/bin/bash
# find-pkg-by-pc.sh - 根据 pkg-config 文件查找对应的软件包
#
# 用法：
#   ./find-pkg-by-pc.sh gstreamer-audio
#   ./find-pkg-by-pc.sh gstreamer-audio-1.0
#   ./find-pkg-by-pc.sh gstreamer-audio-1.0.pc
#
# 支持部分匹配，自动补全 .pc 后缀

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# pkg-config 目录
PKGCONFIG_DIR="/usr/lib/x86_64-linux-gnu/pkgconfig"

# 显示帮助信息
show_help() {
    cat << EOF
用法: $0 <pc-file-pattern>

根据 pkg-config 文件名查找对应的 Debian 软件包

参数:
  pc-file-pattern    pkg-config 文件名或部分名称
                     支持不带版本号和 .pc 后缀

示例:
  $0 gstreamer-audio              # 查找包含 gstreamer-audio 的 .pc 文件
  $0 gstreamer-audio-1.0          # 精确匹配版本
  $0 gstreamer-audio-1.0.pc       # 完整文件名
  $0 glib                         # 查找所有包含 glib 的 .pc 文件

选项:
  -h, --help         显示此帮助信息
  -l, --list         列出匹配的 .pc 文件及对应的软件包（每行一个）
  -a, --all          显示所有匹配结果（默认只显示第一个）

EOF
}

# 列出匹配的 .pc 文件
list_pc_files() {
    local pattern=$1
    local pc_files=()

    # 如果输入已经有 .pc 后缀，直接搜索（不区分大小写）
    if [[ "$pattern" == *.pc ]]; then
        pc_files=($(find "$PKGCONFIG_DIR" -iname "$pattern" 2>/dev/null))
    else
        # 否则尝试多种匹配模式（不区分大小写）
        pc_files=($(find "$PKGCONFIG_DIR" -iname "${pattern}.pc" 2>/dev/null))

        # 如果没找到，尝试模糊匹配
        if [ ${#pc_files[@]} -eq 0 ]; then
            pc_files=($(find "$PKGCONFIG_DIR" -iname "${pattern}*.pc" 2>/dev/null))
        fi

        # 如果还是没找到，尝试包含匹配
        if [ ${#pc_files[@]} -eq 0 ]; then
            pc_files=($(find "$PKGCONFIG_DIR" -iname "*${pattern}*.pc" 2>/dev/null))
        fi
    fi

    echo "${pc_files[@]}"
}

# 查找包名
find_package() {
    local pc_file=$1

    if [ ! -f "$pc_file" ]; then
        echo -e "${RED}✗ 文件不存在: $pc_file${NC}" >&2
        return 1
    fi

    # 使用 dpkg -S 查找文件所属的包
    local package=$(dpkg -S "$pc_file" 2>/dev/null | cut -d: -f1)

    if [ -z "$package" ]; then
        echo -e "${RED}✗ 未找到包含此文件的软件包${NC}" >&2
        return 1
    fi

    echo "$package"
}

# 显示包信息
show_package_info() {
    local package=$1
    local pc_file=$2

    echo -e "${GREEN}✓ PC 文件:${NC} $(basename $pc_file)"
    echo -e "${GREEN}✓ 软件包:${NC} $package"

    # 读取 .pc 文件中的描述信息
    if [ -f "$pc_file" ]; then
        local name=$(grep "^Name:" "$pc_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
        local desc=$(grep "^Description:" "$pc_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')
        local version=$(grep "^Version:" "$pc_file" 2>/dev/null | cut -d: -f2- | sed 's/^ *//')

        [ -n "$name" ] && echo -e "${BLUE}  名称:${NC} $name"
        [ -n "$version" ] && echo -e "${BLUE}  版本:${NC} $version"
        [ -n "$desc" ] && echo -e "${BLUE}  描述:${NC} $desc"
    fi

    # 显示包的安装状态
    local status=$(dpkg -l "$package" 2>/dev/null | grep "^ii" | awk '{print $3}')
    if [ -n "$status" ]; then
        echo -e "${BLUE}  已安装版本:${NC} $status"
    fi

    echo ""
}

# 主函数
main() {
    local pattern=""
    local list_only=false
    local show_all=false

    # 解析参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -l|--list)
                list_only=true
                shift
                ;;
            -a|--all)
                show_all=true
                shift
                ;;
            -*)
                echo -e "${RED}错误: 未知选项 $1${NC}" >&2
                show_help
                exit 1
                ;;
            *)
                pattern=$1
                shift
                ;;
        esac
    done

    # 检查是否提供了搜索模式
    if [ -z "$pattern" ]; then
        echo -e "${RED}错误: 请提供 pkg-config 文件名或模式${NC}" >&2
        show_help
        exit 1
    fi

    # 检查目录是否存在
    if [ ! -d "$PKGCONFIG_DIR" ]; then
        echo -e "${RED}错误: pkg-config 目录不存在: $PKGCONFIG_DIR${NC}" >&2
        exit 1
    fi

    echo -e "${YELLOW}正在搜索: $pattern${NC}"
    echo ""

    # 查找匹配的 .pc 文件
    local pc_files=($(list_pc_files "$pattern"))

    if [ ${#pc_files[@]} -eq 0 ]; then
        echo -e "${RED}✗ 未找到匹配的 .pc 文件${NC}"
        echo ""
        echo "搜索路径: $PKGCONFIG_DIR"
        exit 1
    fi

    echo -e "${GREEN}找到 ${#pc_files[@]} 个匹配的文件:${NC}"
    echo ""

    # 如果只是列出文件
    if [ "$list_only" = true ]; then
        # 显示标题栏
        printf "%-50s  %s\n" "PC File" "Package"
        printf "%-50s  %s\n" "-------" "-------"

        for pc_file in "${pc_files[@]}"; do
            local package=$(find_package "$pc_file")
            if [ $? -eq 0 ]; then
                printf "%-50s  %s\n" "$(basename $pc_file)" "$package"
            else
                printf "%-50s  %s\n" "$(basename $pc_file)" "(未找到)"
            fi
        done
        exit 0
    fi

    # 查找并显示包信息
    local count=0
    for pc_file in "${pc_files[@]}"; do
        count=$((count + 1))

        echo -e "${YELLOW}[$count/${#pc_files[@]}] 完整路径:${NC} $pc_file"

        local package=$(find_package "$pc_file")
        if [ $? -eq 0 ]; then
            show_package_info "$package" "$pc_file"
        else
            echo ""
        fi

        # 如果不是显示所有结果，只显示第一个
        if [ "$show_all" = false ] && [ $count -ge 1 ]; then
            if [ ${#pc_files[@]} -gt 1 ]; then
                echo -e "${YELLOW}提示: 还有 $((${#pc_files[@]} - 1)) 个匹配结果，使用 -a 选项查看全部${NC}"
            fi
            break
        fi
    done
}

# 运行主函数
main "$@"
