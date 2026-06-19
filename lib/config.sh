#!/bin/bash

# 配置管理

# 用户可覆盖的路径键
_CONFIG_PATH_KEYS=(log_dir backup_dir temp_dir config_dir data_dir install_dir work_dir)

# YAML 解析
parse_yaml() {
    local yaml_file="$1"
    local prefix="${2:-}"
    
    if [[ ! -f "$yaml_file" ]]; then
        echo "配置文件不存在: $yaml_file" >&2
        return 1
    fi
    
    local current_path=""
    local indent_level=0
    local -a path_stack=()
    local -a indent_stack=(0)
    
    while IFS= read -r line; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue
        
        local stripped="${line#"${line%%[![:space:]]*}"}"
        local indent=$(( ${#line} - ${#stripped} }))
        
        while [[ ${#indent_stack[@]} -gt 1 ]] && [[ $indent -le ${indent_stack[-1]} ]]; do
            unset 'indent_stack[-1]'
            unset 'path_stack[-1]'
        done
        
        if [[ "$stripped" =~ ^([a-zA-Z_][a-zA-Z0-9_-]*)[[:space:]]*:[[:space:]]*(.*)[[:space:]]*$ ]]; then
            local key="${BASH_REMATCH[1]}"
            local value="${BASH_REMATCH[2]}"
            
            value="${value%"${value##*[![:space:]]}"}"
            
            local full_key=""
            if [[ ${#path_stack[@]} -gt 0 ]]; then
                full_key=$(IFS='.'; echo "${path_stack[*]}")
                full_key="${full_key:+$full_key.}$key"
            else
                full_key="$key"
            fi
            
            if [[ -n "$prefix" ]]; then
                full_key="${prefix}.${full_key}"
            fi
            
            if [[ -z "$value" ]]; then
                path_stack+=("$key")
                indent_stack+=("$indent")
            else
                value="${value#\"}"
                value="${value%\"}"
                value="${value#\'}"
                value="${value%\'}"
                
                CONFIG["$full_key"]="$value"
            fi
        elif [[ "$stripped" =~ ^-[[:space:]]*(.*)[[:space:]]*$ ]]; then
            local value="${BASH_REMATCH[1]}"
            value="${value%"${value##*[![:space:]]}"}"
            
            if [[ ${#path_stack[@]} -gt 0 ]]; then
                local array_key
                array_key=$(IFS='.'; echo "${path_stack[*]}")
                if [[ -n "$prefix" ]]; then
                    array_key="${prefix}.${array_key}"
                fi
                
                local current="${CONFIG[$array_key]:-}"
                if [[ -n "$current" ]]; then
                    CONFIG["$array_key"]="$current|$value"
                else
                    CONFIG["$array_key"]="$value"
                fi
            fi
        fi
    done < "$yaml_file"
    
    return 0
}

# 加载配置文件（默认 → 系统 → 用户，后者覆盖前者）
config_load() {
    local default_config="$PROJECT_ROOT/config/config.yaml"
    local system_config="/etc/hamster-scripts/config.yaml"
    local user_config="$HOME/.config/${PROJECT_NAME}/config.yaml"
    local loaded=0
    
    if [[ -f "$default_config" ]]; then
        parse_yaml "$default_config"
        loaded=1
    fi
    
    if [[ -f "$system_config" ]]; then
        parse_yaml "$system_config"
        loaded=1
    fi
    
    if [[ -f "$user_config" ]]; then
        parse_yaml "$user_config"
        loaded=1
    fi
    
    if [[ $loaded -eq 0 ]]; then
        log_warn "未找到配置文件，使用内置默认值"
        return 1
    fi
    
    return 0
}

# 获取配置值
config_get() {
    local key="$1"
    local default="${2:-}"
    
    echo "${CONFIG[$key]:-$default}"
}

# 获取安装目录
get_install_dir() {
    config_get "install_dir" "/cs"
}

# 获取工作目录
get_work_dir() {
    config_get "work_dir" "/root/cs"
}

# 设置配置值
config_set() {
    local key="$1"
    local value="$2"
    
    CONFIG["$key"]="$value"
}

# 保存用户覆盖配置
save_user_config() {
    local user_config="$HOME/.config/${PROJECT_NAME}/config.yaml"
    ensure_dir "$(dirname "$user_config")"
    
    {
        echo "# Hamster Script 用户配置覆盖"
        echo "# 由快捷设置自动生成"
        for key in "${_CONFIG_PATH_KEYS[@]}"; do
            if [[ -n "${CONFIG[$key]:-}" ]]; then
                echo "$key: ${CONFIG[$key]}"
            fi
        done
    } > "$user_config"
}

# 保存配置到文件
config_save() {
    local config_file="${1:-$PROJECT_ROOT/config/config.yaml}"
    
    ensure_dir "$(dirname "$config_file")"
    
    > "$config_file"
    
    for key in "${!CONFIG[@]}"; do
        local value="${CONFIG[$key]}"
        echo "$key: $value" >> "$config_file"
    done
}
