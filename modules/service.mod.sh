#!/bin/bash

service_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "服务管理" "请选择功能:" \
            "1" "服务列表" \
            "2" "启动服务" \
            "3" "停止服务" \
            "4" "重启服务" \
            "5" "服务状态")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) service_list ;;
            2) service_start ;;
            3) service_stop ;;
            4) service_restart ;;
            5) service_status ;;
        esac
    done
}

service_list() {
    local temp_log="${CONFIG[temp_dir]}/service_list.log"
    
    if sys_is_systemd; then
        systemctl list-units --type=service --state=running > "$temp_log" 2>&1
    else
        service --status-all 2>&1 | grep '+' > "$temp_log"
    fi
    
    ui_textbox "$temp_log" "运行中的服务"
}

service_start() {
    local service_name
    service_name=$(ui_input "请输入要启动的服务名称:")
    
    if [[ -z "$service_name" ]]; then
        return
    fi
    
    ui_info "正在启动服务 $service_name..."
    
    if sys_service_start "$service_name" 2>&1; then
        ui_msg "服务 $service_name 已启动"
    else
        ui_msg "服务启动失败" "错误"
    fi
}

service_stop() {
    local service_name
    service_name=$(ui_input "请输入要停止的服务名称:")
    
    if [[ -z "$service_name" ]]; then
        return
    fi
    
    if ui_confirm "确定要停止服务 $service_name 吗？"; then
        ui_info "正在停止服务 $service_name..."
        
        if sys_service_stop "$service_name" 2>&1; then
            ui_msg "服务 $service_name 已停止"
        else
            ui_msg "服务停止失败" "错误"
        fi
    fi
}

service_restart() {
    local service_name
    service_name=$(ui_input "请输入要重启的服务名称:")
    
    if [[ -z "$service_name" ]]; then
        return
    fi
    
    if ui_confirm "确定要重启服务 $service_name 吗？"; then
        ui_info "正在重启服务 $service_name..."
        
        if sys_service_restart "$service_name" 2>&1; then
            ui_msg "服务 $service_name 已重启"
        else
            ui_msg "服务重启失败" "错误"
        fi
    fi
}

service_status() {
    local service_name
    service_name=$(ui_input "请输入服务名称:")
    
    if [[ -z "$service_name" ]]; then
        return
    fi
    
    local temp_log="${CONFIG[temp_dir]}/service_status.log"
    sys_service_status "$service_name" > "$temp_log" 2>&1
    ui_textbox "$temp_log" "服务状态"
}
