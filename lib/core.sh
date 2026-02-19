#!/bin/bash

PROJECT_NAME="hamster-scripts"
PROJECT_VERSION="2.0.0"
PROJECT_AUTHOR="CS"

get_project_root() {
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
    PROJECT_ROOT="$(get_project_root)"
fi
export PROJECT_ROOT PROJECT_NAME PROJECT_VERSION PROJECT_AUTHOR

declare -A CONFIG=(
    [log_dir]="/var/log/${PROJECT_NAME}"
    [backup_dir]="/var/backups/${PROJECT_NAME}"
    [temp_dir]="/tmp/${PROJECT_NAME}"
    [config_dir]="/etc/${PROJECT_NAME}"
    [data_dir]="/var/lib/${PROJECT_NAME}"
    [work_dir]="/root/cs"
    [dialog_width]="60"
    [dialog_height]="15"
    [install_dir]="/cs"
)

load_config() {
    local config_file="${CONFIG[config_dir]}/main.conf"
    local user_config="$HOME/.config/${PROJECT_NAME}/main.conf"
    
    for file in "$config_file" "$user_config"; do
        if [[ -f "$file" ]]; then
            while IFS='=' read -r key value || [[ -n "$key" ]]; do
                [[ "$key" =~ ^[[:space:]]*# ]] && continue
                [[ -z "$key" ]] && continue
                key="${key//[[:space:]]/}"
                value="${value#[[:space:]]}"
                value="${value%[[:space:]]}"
                if [[ -n "$key" && -n "$value" ]]; then
                    CONFIG[$key]="$value"
                fi
            done < "$file"
        fi
    done
}

get_config() {
    local key="$1"
    local default="${2:-}"
    echo "${CONFIG[$key]:-$default}"
}

set_config() {
    local key="$1"
    local value="$2"
    CONFIG[$key]="$value"
}

ensure_dirs() {
    local dirs=("log_dir" "backup_dir" "temp_dir" "data_dir")
    for dir_key in "${dirs[@]}"; do
        local dir="${CONFIG[$dir_key]}"
        if [[ ! -d "$dir" ]]; then
            mkdir -p "$dir" 2>/dev/null || true
        fi
    done
}

LIB_DIR="$PROJECT_ROOT/lib"
MODULES_DIR="$PROJECT_ROOT/modules"
UTILS_DIR="$PROJECT_ROOT/utils"

load_lib() {
    local lib_name="$1"
    local lib_file="$LIB_DIR/${lib_name}.sh"
    if [[ -f "$lib_file" ]]; then
        source "$lib_file"
    else
        echo "Error: Library not found: $lib_file" >&2
        return 1
    fi
}

load_module() {
    local module_name="$1"
    local module_file="$MODULES_DIR/${module_name}.mod.sh"
    if [[ -f "$module_file" ]]; then
        source "$module_file"
    else
        echo "Error: Module not found: $module_file" >&2
        return 1
    fi
}

load_all_libs() {
    local libs=("log" "ui" "pkg" "sys")
    for lib in "${libs[@]}"; do
        load_lib "$lib"
    done
}

init_core() {
    load_config
    ensure_dirs
    load_all_libs
}

command_exists() {
    command -v "$1" &>/dev/null
}

file_exists() {
    [[ -f "$1" ]]
}

dir_exists() {
    [[ -d "$1" ]]
}

ensure_dir() {
    [[ ! -d "$1" ]] && mkdir -p "$1"
}

is_root() {
    [[ $EUID -eq 0 ]]
}

confirm() {
    local prompt="${1:-确认操作?}"
    local default="${2:-n}"
    local choice
    
    if [[ "$default" == "y" ]]; then
        read -r -p "$prompt (Y/n): " choice
        [[ -z "$choice" || "$choice" =~ ^[Yy] ]]
    else
        read -r -p "$prompt (y/N): " choice
        [[ "$choice" =~ ^[Yy] ]]
    fi
}

trim() {
    local var="$1"
    var="${var#"${var%%[![:space:]]*}"}"
    var="${var%"${var##*[![:space:]]}"}"
    echo "$var"
}

random_string() {
    local length="${1:-8}"
    tr -dc 'a-zA-Z0-9' </dev/urandom | head -c "$length"
}

cleanup_temp() {
    local temp_dir="${CONFIG[temp_dir]}"
    if [[ -d "$temp_dir" ]]; then
        rm -rf "$temp_dir"/* 2>/dev/null || true
    fi
}

trap_add() {
    local handler="$1"
    local existing_handler
    existing_handler=$(trap -p EXIT | sed "s/^trap -- '\(.*\)' EXIT$/\1/")
    if [[ -n "$existing_handler" ]]; then
        trap "$existing_handler; $handler" EXIT
    else
        trap "$handler" EXIT
    fi
}
