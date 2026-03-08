#!/bin/bash

service_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "服务管理" "请选择功能:" \
            "1" "运行中服务列表" \
            "2" "所有服务列表" \
            "3" "选择服务操作")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) service_list_running ;;
            2) service_list_all ;;
            3) service_select_menu ;;
        esac
    done
}

service_list_running() {
    local temp_log="${CONFIG[temp_dir]}/service_list.log"
    
    if sys_is_systemd; then
        systemctl list-units --type=service --state=running > "$temp_log" 2>&1
    else
        service --status-all 2>&1 | grep '+' > "$temp_log"
    fi
    
    ui_textbox "$temp_log" "运行中的服务"
}

service_list_all() {
    local temp_log="${CONFIG[temp_dir]}/service_list_all.log"
    
    if sys_is_systemd; then
        systemctl list-units --type=service --all --no-legend | \
            awk '{printf "%-40s %s\n", $1, ($4 == "running" ? "[运行中]" : "[" $4 "]")}' > "$temp_log" 2>&1
    else
        service --status-all 2>&1 > "$temp_log"
    fi
    
    ui_textbox "$temp_log" "所有服务"
}

service_select_menu() {
    local service_name
    service_name=$(service_select)
    
    if [[ -z "$service_name" ]]; then
        return
    fi
    
    local is_running
    is_running=$(sys_service_is_running "$service_name" && echo "true" || echo "false")
    
    while true; do
        local menu_items
        if [[ "$is_running" == "true" ]]; then
            menu_items=("1" "停止服务" "2" "重启服务" "3" "查看状态" "4" "查看日志")
        else
            menu_items=("1" "启动服务" "2" "查看状态" "3" "查看日志")
        fi
        
        local choice
        choice=$(ui_submenu "服务: $service_name [$( [[ "$is_running" == "true" ]] && echo "运行中" || echo "已停止")]" "请选择操作:" "${menu_items[@]}")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        if [[ "$is_running" == "true" ]]; then
            case "$choice" in
                1)
                    if ui_confirm "确定要停止服务 $service_name 吗？"; then
                        ui_info "正在停止服务 $service_name..."
                        if sys_service_stop "$service_name" 2>&1; then
                            ui_msg "服务 $service_name 已停止"
                            is_running="false"
                        else
                            ui_msg "服务停止失败" "错误"
                        fi
                    fi
                    ;;
                2)
                    if ui_confirm "确定要重启服务 $service_name 吗？"; then
                        ui_info "正在重启服务 $service_name..."
                        if sys_service_restart "$service_name" 2>&1; then
                            ui_msg "服务 $service_name 已重启"
                        else
                            ui_msg "服务重启失败" "错误"
                        fi
                    fi
                    ;;
                3)
                    service_show_status "$service_name"
                    ;;
                4)
                    service_show_logs "$service_name"
                    ;;
            esac
        else
            case "$choice" in
                1)
                    ui_info "正在启动服务 $service_name..."
                    if sys_service_start "$service_name" 2>&1; then
                        ui_msg "服务 $service_name 已启动"
                        is_running="true"
                    else
                        ui_msg "服务启动失败" "错误"
                    fi
                    ;;
                2)
                    service_show_status "$service_name"
                    ;;
                3)
                    service_show_logs "$service_name"
                    ;;
            esac
        fi
    done
}

service_select() {
    local temp_file="${CONFIG[temp_dir]}/services_list.txt"
    
    if sys_is_systemd; then
        systemctl list-units --type=service --all --no-legend | \
            awk '{status=($4=="running"?"运行":"停止"); print $1 "|" status}' | \
            sort -t'|' -k2 -r > "$temp_file" 2>&1
    else
        service --status-all 2>&1 | awk '{status=($1=="+"?"运行":"停止"); print $4 "|" status}' > "$temp_file"
    fi
    
    if [[ ! -s "$temp_file" ]]; then
        ui_msg "无法获取服务列表" "错误"
        return
    fi
    
    local items=()
    while IFS='|' read -r svc status; do
        if [[ -n "$svc" ]]; then
            local svc_name
            svc_name=$(echo "$svc" | sed 's/\.service$//')
            items+=("$svc_name" "[$status]")
        fi
    done < "$temp_file"
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可用的服务" "错误"
        return
    fi
    
    local choice
    choice=$(ui_submenu "选择服务" "请选择服务:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    echo "$choice"
}

service_show_status() {
    local service_name="$1"
    local temp_log="${CONFIG[temp_dir]}/service_status.log"
    sys_service_status "$service_name" > "$temp_log" 2>&1
    ui_textbox "$temp_log" "服务状态: $service_name"
}

service_show_logs() {
    local service_name="$1"
    local temp_log="${CONFIG[temp_dir]}/service_logs.log"
    
    if sys_is_systemd; then
        journalctl -u "$service_name" -n 100 --no-pager > "$temp_log" 2>&1
    else
        local log_files=(
            "/var/log/${service_name}.log"
            "/var/log/${service_name}/error.log"
            "/var/log/${service_name}/access.log"
        )
        {
            for log in "${log_files[@]}"; do
                if [[ -f "$log" ]]; then
                    echo "=== $log ==="
                    tail -50 "$log"
                    echo ""
                fi
            done
        } > "$temp_log" 2>&1
    fi
    
    if [[ -s "$temp_log" ]]; then
        ui_textbox "$temp_log" "服务日志: $service_name"
    else
        ui_msg "没有找到服务日志" "提示"
    fi
}
