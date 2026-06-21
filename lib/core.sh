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
    echo "$dir"
}

if [[ -z "${PROJECT_ROOT:-}" ]]; then
    PROJECT_ROOT="$(获取项目根目录)"
fi
export PROJECT_ROOT PROJECT_NAME PROJECT_VERSION PROJECT_AUTHOR

# 目录定义
LIB_DIR="$PROJECT_ROOT/lib"
APP_DIR="$PROJECT_ROOT/app"
TOOLS_DIR="$PROJECT_ROOT/tools"

# 全局关联数组（必须在 加载全部库 之前声明，避免 source 在函数内导致局部作用域）
declare -A CONFIG

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
    local libs=("log" "config" "ui" "pkg" "sys" "service" "firewall" "net" "tool")
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

文件存在() {
    [[ -f "$1" ]]
}

目录存在() {
    [[ -d "$1" ]]
}

确保目录() {
    [[ ! -d "$1" ]] && mkdir -p "$1"
}

是否Root() {
    [[ $EUID -eq 0 ]]
}

去空白() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

随机字符串() {
    local length="${1:-8}"
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
}

清理临时目录() {
    local temp_dir="/tmp/${PROJECT_NAME}"
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"/* 2>/dev/null || true
    fi
}

添加退出陷阱() {
    local handler="$1"
    local existing_handler
    existing_handler=$(trap -p EXIT | sed "s/^trap -- '\(.*\)' EXIT$/\1/")
    if [[ -n "$existing_handler" ]]; then
        trap "$existing_handler; $handler" EXIT
    else
        trap "$handler" EXIT
    fi
}
