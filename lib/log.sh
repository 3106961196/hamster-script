#!/bin/bash

LOG_FILE="${CONFIG[log_dir]}/${PROJECT_NAME}.log"
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

_get_log_priority() {
    echo "${LOG_PRIORITIES[$1]:-1}"
}

_should_log() {
    local level="$1"
    local current_priority
    local level_priority
    
    current_priority=$(_get_log_priority "$LOG_LEVEL")
    level_priority=$(_get_log_priority "$level")
    
    [[ $level_priority -ge $current_priority ]]
}

_format_message() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$level] [$timestamp] $message"
}

_write_to_file() {
    local message="$1"
    local log_dir
    log_dir="${CONFIG[log_dir]}"
    
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi
    
    echo "$message" >> "$LOG_FILE" 2>/dev/null || true
}

log() {
    local level="$1"
    shift
    local message="$*"
    
    if ! _should_log "$level"; then
        return 0
    fi
    
    local formatted
    formatted=$(_format_message "$level" "$message")
    
    local color="${LOG_COLORS[$level]}"
    local reset="${LOG_COLORS[RESET]}"
    
    if [[ -t 1 ]]; then
        echo -e "${color}${formatted}${reset}"
    else
        echo "$formatted"
    fi
    
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        _write_to_file "$formatted"
    fi
}

log_debug() {
    log DEBUG "$@"
}

log_info() {
    log INFO "$@"
}

log_success() {
    log SUCCESS "$@"
}

log_warn() {
    log WARN "$@"
}

log_error() {
    log ERROR "$@"
}

log_section() {
    local title="$1"
    echo ""
    echo "========================================"
    echo "  $title"
    echo "========================================"
    echo ""
}

log_progress() {
    local current="$1"
    local total="$2"
    local message="${3:-处理中}"
    local percent=$((current * 100 / total))
    printf "\r[%-50s] %d%% %s" "$(printf '#%.0s' $(seq 1 $((percent / 2))))" "$percent" "$message"
    [[ $current -eq $total ]] && echo ""
}

init_logging() {
    local log_dir="${CONFIG[log_dir]}"
    if [[ ! -d "$log_dir" ]]; then
        mkdir -p "$log_dir" 2>/dev/null || return 1
    fi
    LOG_FILE="$log_dir/${PROJECT_NAME}.log"
}

set_log_level() {
    local level="$1"
    level=$(echo "$level" | tr '[:lower:]' '[:upper:]')
    if [[ -v "LOG_PRIORITIES[$level]" ]]; then
        LOG_LEVEL="$level"
    else
        log_warn "Invalid log level: $level, using INFO"
        LOG_LEVEL="INFO"
    fi
}
