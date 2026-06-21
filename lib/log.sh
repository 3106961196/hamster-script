#!/bin/bash

# 日志系统

HAMSTER_LAST_ERROR="${HAMSTER_LAST_ERROR:-}"

# 延迟初始化 LOG_FILE
LOG_FILE=""
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_TO_FILE="${LOG_TO_FILE:-true}"

declare -A LOG_COLORS=(
    [DEBUG]="\e[1;35m"
    [INFO]="\e[1;96m"
    [SUCCESS]="\e[1;32m"
    [WARN]="\e[1;93m"
    [ERROR]="\e[1;31m"
    [RESET]="\e[0m"
)

declare -A LOG_PRIORITIES=(
    [DEBUG]=0
    [INFO]=1
    [SUCCESS]=1
    [WARN]=2
    [ERROR]=3
)

# 终端颜色（供更新模块等使用）
COLOR_PURPLE='\033[0;35m'
COLOR_GREEN='\033[0;32m'
COLOR_RESET='\033[0m'

_获取日志优先级() {
    echo "${LOG_PRIORITIES[$1]:-1}"
}

_是否应记录日志() {
    local level="$1"
    local current_priority
    local level_priority
    
    current_priority=$(_获取日志优先级 "$LOG_LEVEL")
    level_priority=$(_获取日志优先级 "$level")
    
    [[ $level_priority -ge $current_priority ]]
}

_格式化日志消息() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$level] [$timestamp] $message"
}

_写入日志文件() {
    local message="$1"
    
    # 延迟初始化 LOG_FILE
    if [[ -z "$LOG_FILE" ]]; then
        local log_dir="${CONFIG[log_dir]:-/var/log}"
        if [[ ! -d "$log_dir" ]]; then
            mkdir -p "$log_dir" 2>/dev/null || return 1
        fi
        LOG_FILE="$log_dir/${PROJECT_NAME}.log"
    fi
    
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi
    
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

写日志() {
    local level="$1"
    shift
    local message="$*"
    
    if ! _是否应记录日志 "$level"; then
        return 0
    fi
    
    local formatted
    formatted=$(_格式化日志消息 "$level" "$message")
    
    local color="${LOG_COLORS[$level]}"
    local reset="${LOG_COLORS[RESET]}"

    if [[ "$level" == "ERROR" ]]; then
        HAMSTER_LAST_ERROR="$message"
    fi

    if [[ -n "${HAMSTER_UI_TASK:-}" ]]; then
        # 任务模式：进度信息也写到 /dev/tty，避免 apt 结束后长时间无输出像卡住
        if [[ "$level" != "DEBUG" ]] && [[ -e /dev/tty ]]; then
            echo -e "${color}${formatted}${reset}" >/dev/tty
        fi
    elif [[ -t 1 ]]; then
        echo -e "${color}${formatted}${reset}"
    else
        echo "$formatted"
    fi
    
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        _写入日志文件 "$formatted"
    fi
}

日志调试() {
    写日志 DEBUG "$@"
}

日志信息() {
    写日志 INFO "$@"
}

日志成功() {
    写日志 SUCCESS "$@"
}

日志警告() {
    写日志 WARN "$@"
}

日志错误() {
    写日志 ERROR "$@"
}

日志分节() {
    local title="$1"
    echo ""
    echo "========================================"
    echo "  $title"
    echo "========================================"
    echo ""
}

初始化日志() {
    local log_dir="${CONFIG[log_dir]}"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi
    LOG_FILE="$log_dir/${PROJECT_NAME}.log"
}

设置日志级别() {
    local level="$1"
    level=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    if [[ -v "LOG_PRIORITIES[$level]" ]]; then
        LOG_LEVEL="$level"
    else
        日志警告 "Invalid log level: $level, using INFO"
        LOG_LEVEL="INFO"
    fi
}
