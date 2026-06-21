#!/bin/bash

# 核心框架 - 极简版

PROJECT_NAME="hamster-scripts"
PROJECT_VERSION="2.0.0"
PROJECT_AUTHOR="CS"

# 获取项目根目录
获取项目根目录() {
    if [[ -n "${PROJECT_ROOT:-}" ]]; then
        echo "$PROJECT_ROOT"
        return 0
    fi

    local script_path="${BASH_SOURCE[0]}"
    local dir
    dir="$(cd "$(dirname "$script_path")/.." && pwd)"
    if [[ -f "$dir/lib/core.sh" ]]; then
        echo "$dir"
        return 0
    fi

    if [[ -n "${HAMSTER_ROOT:-}" && -f "${HAMSTER_ROOT}/lib/core.sh" ]]; then
        echo "$HAMSTER_ROOT"
        return 0
    fi

    echo "$dir"
}

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(获取项目根目录)"
fi
export PROJECT_ROOT HAMSTER_ROOT="${HAMSTER_ROOT:-$PROJECT_ROOT}" PROJECT_NAME PROJECT_VERSION PROJECT_AUTHOR

# 目录定义
LIB_DIR="$PROJECT_ROOT/lib"
APP_DIR="$PROJECT_ROOT/app"
TOOLS_DIR="$PROJECT_ROOT/tools"

# 全局关联数组（-g：从 bin 引导函数内 source 时也必须是全局）
declare -gA CONFIG

# 加载库
加载库() {
    local lib_name="$1"
    local lib_file="$LIB_DIR/${lib_name}.sh"
    if [[ -f "$lib_file" ]]; then
        source "$lib_file"
    else
        echo "Error: Library not found: $lib_file" >&2
        return 1
    fi
}

# 加载应用模块
加载模块() {
    local module_name="$1"
    local module_file="$APP_DIR/${module_name}.sh"
    if [[ -f "$module_file" ]]; then
        source "$module_file"
    else
        echo "Error: Module not found: $module_file" >&2
        return 1
    fi
}

# 加载所有库
加载全部库() {
    local libs=("log" "config" "ui" "pkg" "chromium" "github" "sys" "service" "firewall" "net" "tool" "bootstrap" "tool_entry")
    for lib in "${libs[@]}"; do
        加载库 "$lib"
    done
}

# 初始化核心
初始化核心() {
    加载全部库
    加载配置
    初始化日志
    界面初始化
}

# 工具脚本独立运行时引导（install.sh / manage.sh 子进程调用）
工具引导() {
    加载全部库
    加载配置
}

# 工具函数
命令存在() {
    command -v "$1" &>/dev/null
}

确保目录() {
    [[ ! -d "$1" ]] && mkdir -p "$1"
}
