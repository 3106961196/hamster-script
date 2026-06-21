#!/bin/bash

设置_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "⚙️ 系统设置" "请选择功能:" \
            "1" "查看当前配置" \
            "2" "编辑配置文件" \
            "3" "快捷设置" \
            "4" "重置配置")
        
        case "$choice" in
            1) 设置_显示 ;;
            2) 设置_编辑 ;;
            3) 设置_快捷 ;;
            4) 设置_重置 ;;
            b) break ;;
        esac
    done
}

设置_显示() {
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
    
    界面文本 "$content" "⚙️ 当前配置"
}

设置_编辑() {
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
        界面消息 "未找到可用的编辑器\n请安装 vim 或 nano" "错误"
        return
    fi
    
    界面清屏
    $editor "$config_file"
    
    界面消息 "配置已保存，重启脚本后生效" "提示"
}

设置_快捷() {
    while true; do
        local choice
        choice=$(界面子菜单 "⚙️ 快捷设置" "请选择要修改的配置:" \
            "1" "修改日志目录" \
            "2" "修改备份目录" \
            "3" "修改临时目录")
        
        case "$choice" in
            1) 设置_设置路径 "log_dir" "日志目录" ;;
            2) 设置_设置路径 "backup_dir" "备份目录" ;;
            3) 设置_设置路径 "temp_dir" "临时目录" ;;
            b) break ;;
        esac
    done
}

设置_设置路径() {
    local key="$1"
    local name="$2"
    local current="${CONFIG[$key]}"
    
    local new_value
    new_value=$(界面输入 "$name" "$current")
    
    [[ -z "$new_value" ]] && return
    
    if [[ ! -d "$new_value" ]]; then
        if 界面确认 "目录 $new_value 不存在，是否创建？"; then
            mkdir -p "$new_value"
        else
            return
        fi
    fi
    
    CONFIG[$key]="$new_value"
    保存用户配置
    
    界面成功 "$name 已修改为: $new_value"
}

设置_重置() {
    if 界面确认 "确定要重置所有配置吗？\n\n这将删除用户自定义配置，恢复为默认值"; then
        local user_config="$HOME/.config/${PROJECT_NAME}/config.yaml"
        rm -f "$user_config" 2>/dev/null
        界面成功 "配置已重置，重启脚本后生效"
    fi
}
