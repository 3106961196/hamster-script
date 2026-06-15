#!/bin/bash

settings_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "⚙️ 系统设置" "请选择功能:" \
            "1" "查看当前配置" \
            "2" "编辑配置文件" \
            "3" "快捷设置" \
            "4" "重置配置")
        
        case "$choice" in
            1) settings_show ;;
            2) settings_edit ;;
            3) settings_quick ;;
            4) settings_reset ;;
            b) break ;;
        esac
    done
}

settings_show() {
    local content
    content=$({
        echo "📁 路径配置:"
        echo "  日志目录: ${CONFIG[log_dir]}"
        echo "  备份目录: ${CONFIG[backup_dir]}"
        echo "  临时目录: ${CONFIG[temp_dir]}"
        echo "  配置目录: ${CONFIG[config_dir]}"
        echo "  数据目录: ${CONFIG[data_dir]}"
        echo "  安装目录: ${CONFIG[install_dir]}"
        echo ""
        echo "📦 项目信息:"
        echo "  名称: $PROJECT_NAME"
        echo "  版本: $PROJECT_VERSION"
        echo "  作者: $PROJECT_AUTHOR"
        echo "  根目录: $PROJECT_ROOT"
    })
    
    ui_text "$content" "⚙️ 当前配置"
}

settings_edit() {
    local config_file="${CONFIG[config_dir]}/config.yaml"
    
    if [[ ! -f "$config_file" ]]; then
        config_file="$PROJECT_ROOT/config/config.yaml"
    fi
    
    local editors=("vim" "nano" "vi")
    local editor
    
    for e in "${editors[@]}"; do
        if command -v "$e" &>/dev/null; then
            editor="$e"
            break
        fi
    done
    
    if [[ -z "$editor" ]]; then
        ui_msg "未找到可用的编辑器\n请安装 vim 或 nano" "错误"
        return
    fi
    
    ui_clear
    $editor "$config_file"
    
    ui_msg "配置已保存，重启脚本后生效" "提示"
}

settings_quick() {
    while true; do
        local choice
        choice=$(ui_submenu "⚙️ 快捷设置" "请选择要修改的配置:" \
            "1" "修改日志目录" \
            "2" "修改备份目录" \
            "3" "修改临时目录")
        
        case "$choice" in
            1) settings_set_path "log_dir" "日志目录" ;;
            2) settings_set_path "backup_dir" "备份目录" ;;
            3) settings_set_path "temp_dir" "临时目录" ;;
            b) break ;;
        esac
    done
}

settings_set_path() {
    local key="$1"
    local name="$2"
    local current="${CONFIG[$key]}"
    
    local new_value
    new_value=$(ui_input "$name" "$current")
    
    [[ -z "$new_value" ]] && return
    
    if [[ ! -d "$new_value" ]]; then
        if ui_confirm "目录 $new_value 不存在，是否创建？"; then
            mkdir -p "$new_value"
        else
            return
        fi
    fi
    
    CONFIG[$key]="$new_value"
    save_user_config
    
    ui_success "$name 已修改为: $new_value"
}

settings_reset() {
    if ui_confirm "确定要重置所有配置吗？\n\n这将删除用户自定义配置，恢复为默认值"; then
        local user_config="$HOME/.config/${PROJECT_NAME}/config.yaml"
        rm -f "$user_config" 2>/dev/null
        ui_success "配置已重置，重启脚本后生效"
    fi
}
