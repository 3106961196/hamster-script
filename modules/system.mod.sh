#!/bin/bash

system_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "⚙️ 系统管理" "请选择功能:" \
            "1" "系统信息" \
            "2" "系统更新" \
            "3" "系统优化" \
            "4" "服务管理" \
            "5" "安全加固" \
            "6" "时间管理" \
            "7" "用户管理" \
            "8" "进程管理" \
            "9" "磁盘分析" \
            "10" "重启系统")
        
        case "$choice" in
            1) system_info ;;
            2) system_update ;;
            3) system_optimize_menu ;;
            4) system_service_menu ;;
            5) system_security_menu ;;
            6) system_time_menu ;;
            7) system_user_menu ;;
            8) system_process_menu ;;
            9) system_disk_menu ;;
            10) system_reboot ;;
            b) break ;;
        esac
    done
}

system_info() {
    ui_info "正在获取系统信息..."
    
    local info
    info=$(sys_get_info 2>/dev/null)
    
    ui_text "$info" "🖥️ 系统信息"
}

system_update() {
    if ! ui_confirm "确定要更新系统吗？"; then
        return
    fi
    
    ui_info "正在更新系统..."
    
    {
        echo "=== 更新软件源 ==="
        pkg_update
        echo ""
        echo "=== 升级软件包 ==="
        pkg_upgrade_all
        echo ""
        echo "=== 清理无用包 ==="
        pkg_autoremove
        echo ""
        echo "=== 清理缓存 ==="
        pkg_clean
    } 2>&1 | ui_text "⚙️ 系统更新"
    
    ui_success "系统更新完成"
}

system_optimize_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "🧹 系统优化" "请选择功能:" \
            "1" "一键优化" \
            "2" "自定义清理")
        
        case "$choice" in
            1) system_optimize_all ;;
            2) system_optimize_custom ;;
            b) break ;;
        esac
    done
}

system_optimize_all() {
    if ! ui_confirm "确定要优化系统吗？\n\n将执行:\n- 清理包缓存\n- 移除无用包\n- 清理日志 (7天前)\n- 清理临时文件"; then
        return
    fi
    
    ui_info "正在优化系统..."
    
    {
        echo "=== 清理包缓存 ==="
        pkg_clean
        echo ""
        echo "=== 移除无用包 ==="
        pkg_autoremove
        echo ""
        echo "=== 清理日志 ==="
        sys_clean_journal 7
        echo ""
        echo "=== 清理临时文件 ==="
        sys_clean_temp
    } 2>&1 | ui_text "🧹 系统优化"
    
    ui_success "系统优化完成"
}

system_optimize_custom() {
    local items
    items=$(ui_multi_select "🧹 自定义清理" "选择清理项目:" \
        "cache" "清理包缓存" \
        "autoremove" "移除无用包" \
        "journal" "清理日志" \
        "temp" "清理临时文件")
    
    [[ -z "$items" ]] && return
    
    ui_info "正在清理..."
    
    {
        for item in $items; do
            case "$item" in
                cache)
                    echo "=== 清理包缓存 ==="
                    pkg_clean
                    ;;
                autoremove)
                    echo "=== 移除无用包 ==="
                    pkg_autoremove
                    ;;
                journal)
                    echo "=== 清理日志 ==="
                    sys_clean_journal 7
                    ;;
                temp)
                    echo "=== 清理临时文件 ==="
                    sys_clean_temp
                    ;;
            esac
            echo ""
        done
    } 2>&1 | ui_text "🧹 自定义清理"
    
    ui_success "清理完成"
}

system_service_menu() {
    ui_info "正在获取服务列表..."
    
    local items=()
    
    if sys_is_systemd; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local name status
                name=$(echo "$line" | awk '{print $1}')
                status=$(echo "$line" | awk '{print $4}')
                
                if [[ "$status" == "running" ]]; then
                    items+=("$name" "🟢 运行中")
                else
                    items+=("$name" "🔴 已停止")
                fi
            fi
        done < <(systemctl list-units --type=service --all --no-legend 2>/dev/null | head -50)
    else
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local name status
                name=$(echo "$line" | awk '{print $4}')
                status=$(echo "$line" | awk '{print $1}')
                
                if [[ "$status" == "+" ]]; then
                    items+=("$name" "🟢 运行中")
                else
                    items+=("$name" "🔴 已停止")
                fi
            fi
        done < <(service --status-all 2>&1 | head -50)
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "无法获取服务列表" "错误"
        return
    fi
    
    local selected
    selected=$(ui_select "🔧 服务管理" "选择服务:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    system_service_action "$selected"
}

system_service_action() {
    local service="$1"
    local is_running
    
    if sys_service_is_running "$service"; then
        is_running="true"
    else
        is_running="false"
    fi
    
    local status_text
    if [[ "$is_running" == "true" ]]; then
        status_text="🟢 运行中"
    else
        status_text="🔴 已停止"
    fi
    
    local actions
    if [[ "$is_running" == "true" ]]; then
        actions=(
            "stop" "停止"
            "restart" "重启"
            "status" "查看状态"
            "logs" "查看日志"
            "disable" "禁用开机自启"
        )
    else
        actions=(
            "start" "启动"
            "status" "查看状态"
            "logs" "查看日志"
            "enable" "启用开机自启"
        )
    fi
    
    local action
    action=$(ui_action "🔧 $service ($status_text)" "${actions[@]}")
    
    case "$action" in
        start)
            ui_info "正在启动 $service..."
            sys_service_start "$service" && ui_success "$service 已启动" || ui_error "启动失败"
            ;;
        stop)
            if ui_confirm "确定要停止 $service 吗？"; then
                ui_info "正在停止 $service..."
                sys_service_stop "$service" && ui_success "$service 已停止" || ui_error "停止失败"
            fi
            ;;
        restart)
            if ui_confirm "确定要重启 $service 吗？"; then
                ui_info "正在重启 $service..."
                sys_service_restart "$service" && ui_success "$service 已重启" || ui_error "重启失败"
            fi
            ;;
        status)
            local status
            status=$(sys_service_status "$service" 2>/dev/null)
            ui_text "$status" "🔧 $service 状态"
            ;;
        logs)
            local logs
            if sys_is_systemd; then
                logs=$(journalctl -u "$service" -n 100 --no-pager 2>/dev/null)
            else
                logs=$(tail -100 "/var/log/${service}.log" 2>/dev/null || echo "未找到日志")
            fi
            ui_text "$logs" "📋 $service 日志"
            ;;
        enable)
            ui_info "正在启用 $service 开机自启..."
            systemctl enable "$service" 2>/dev/null && ui_success "已启用开机自启" || ui_error "启用失败"
            ;;
        disable)
            ui_info "正在禁用 $service 开机自启..."
            systemctl disable "$service" 2>/dev/null && ui_success "已禁用开机自启" || ui_error "禁用失败"
            ;;
    esac
}

system_security_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "🔒 安全加固" "请选择功能:" \
            "1" "防火墙状态" \
            "2" "启用防火墙" \
            "3" "禁用防火墙" \
            "4" "开放端口" \
            "5" "安全检查")
        
        case "$choice" in
            1) system_firewall_status ;;
            2) system_firewall_enable ;;
            3) system_firewall_disable ;;
            4) system_firewall_open_port ;;
            5) system_security_check ;;
            b) break ;;
        esac
    done
}

system_firewall_status() {
    local status
    status=$(sys_firewall_status 2>/dev/null)
    ui_text "$status" "🔥 防火墙状态"
}

system_firewall_enable() {
    if ui_confirm "确定要启用防火墙吗？"; then
        ui_info "正在启用防火墙..."
        sys_firewall_enable 2>&1 && ui_success "防火墙已启用" || ui_error "启用失败"
    fi
}

system_firewall_disable() {
    if ui_confirm "确定要禁用防火墙吗？\n这可能会降低系统安全性"; then
        ui_info "正在禁用防火墙..."
        sys_firewall_disable 2>&1 && ui_success "防火墙已禁用" || ui_error "禁用失败"
    fi
}

system_firewall_open_port() {
    local port
    port=$(ui_input "请输入要开放的端口号")
    
    [[ -z "$port" ]] && return
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        ui_error "端口号必须是数字"
        return
    fi
    
    if ui_confirm "确定要开放端口 $port 吗？"; then
        ui_info "正在开放端口 $port..."
        sys_firewall_open_port "$port" 2>&1 && ui_success "端口 $port 已开放" || ui_error "开放失败"
    fi
}

system_security_check() {
    ui_info "正在进行安全检查..."
    
    local result
    result=$({
        echo "=== SSH 配置 ==="
        if [[ -f /etc/ssh/sshd_config ]]; then
            grep -E "^(PermitRootLogin|PasswordAuthentication|Port)" /etc/ssh/sshd_config 2>/dev/null || echo "无法读取"
        else
            echo "SSH 配置文件不存在"
        fi
        
        echo ""
        echo "=== 防火墙状态 ==="
        sys_firewall_status 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 开放端口 ==="
        sys_get_open_ports 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 最近登录 ==="
        last -n 5 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 失败登录尝试 ==="
        lastb -n 5 2>/dev/null || echo "无记录"
    })
    
    ui_text "$result" "🔒 安全检查"
}

system_time_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "🕐 时间管理" "请选择功能:" \
            "1" "当前时间" \
            "2" "设置时区" \
            "3" "同步时间")
        
        case "$choice" in
            1) system_time_show ;;
            2) system_time_set_timezone ;;
            3) system_time_sync ;;
            b) break ;;
        esac
    done
}

system_time_show() {
    local time_info
    time_info=$({
        echo "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "时区: $(timedatectl show --property=Timezone --value 2>/dev/null || cat /etc/timezone 2>/dev/null || echo '未知')"
        echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
    })
    
    ui_text "$time_info" "🕐 当前时间"
}

system_time_set_timezone() {
    local timezones=(
        "Asia/Shanghai" "亚洲/上海"
        "Asia/Beijing" "亚洲/北京"
        "Asia/Tokyo" "亚洲/东京"
        "Asia/Seoul" "亚洲/首尔"
        "Asia/Hong_Kong" "亚洲/香港"
        "Asia/Taipei" "亚洲/台北"
        "Asia/Singapore" "亚洲/新加坡"
        "Europe/London" "欧洲/伦敦"
        "Europe/Paris" "欧洲/巴黎"
        "Europe/Berlin" "欧洲/柏林"
        "America/New_York" "美洲/纽约"
        "America/Los_Angeles" "美洲/洛杉矶"
    )
    
    local selected
    selected=$(ui_select "🌏 设置时区" "选择时区:" "${timezones[@]}")
    
    [[ -z "$selected" ]] && return
    
    ui_info "正在设置时区为 $selected..."
    timedatectl set-timezone "$selected" 2>/dev/null && ui_success "时区已设置为 $selected" || ui_error "设置失败"
}

system_time_sync() {
    ui_info "正在同步时间..."
    
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true 2>/dev/null
    fi
    
    sys_sync_time 2>/dev/null && ui_success "时间同步成功" || ui_error "时间同步失败"
}

system_user_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "👤 用户管理" "请选择功能:" \
            "1" "用户列表" \
            "2" "添加用户" \
            "3" "删除用户" \
            "4" "修改密码")
        
        case "$choice" in
            1) system_user_list ;;
            2) system_user_add ;;
            3) system_user_delete ;;
            4) system_user_password ;;
            b) break ;;
        esac
    done
}

system_user_list() {
    local users
    users=$(cat /etc/passwd | awk -F: '$3 >= 1000 || $3 == 0 {printf "%-15s UID:%-5s Shell: %s\n", $1, $3, $7}')
    ui_text "$users" "👤 用户列表"
}

system_user_add() {
    local username
    username=$(ui_input "请输入新用户名")
    
    [[ -z "$username" ]] && return
    
    if id "$username" &>/dev/null; then
        ui_msg "用户 $username 已存在" "错误"
        return
    fi
    
    ui_info "正在创建用户 $username..."
    useradd -m -s /bin/bash "$username" 2>&1 && ui_success "用户 $username 创建成功" || ui_error "创建失败"
}

system_user_delete() {
    local users=()
    while IFS= read -r line; do
        local name uid
        name=$(echo "$line" | cut -d: -f1)
        uid=$(echo "$line" | cut -d: -f3)
        if [[ "$uid" -ge 1000 ]] || [[ "$uid" -eq 0 ]]; then
            users+=("$name" "UID: $uid")
        fi
    done < /etc/passwd
    
    local selected
    selected=$(ui_select "👤 删除用户" "选择要删除的用户:" "${users[@]}")
    
    [[ -z "$selected" ]] && return
    
    if ui_confirm "确定要删除用户 $selected 吗？\n这将同时删除用户主目录"; then
        userdel -r "$selected" 2>&1 && ui_success "用户 $selected 已删除" || ui_error "删除失败"
    fi
}

system_user_password() {
    local users=()
    while IFS= read -r line; do
        local name uid
        name=$(echo "$line" | cut -d: -f1)
        uid=$(echo "$line" | cut -d: -f3)
        if [[ "$uid" -ge 1000 ]] || [[ "$uid" -eq 0 ]]; then
            users+=("$name" "UID: $uid")
        fi
    done < /etc/passwd
    
    local selected
    selected=$(ui_select "👤 修改密码" "选择用户:" "${users[@]}")
    
    [[ -z "$selected" ]] && return
    
    ui_msg "请在终端中输入新密码"
    passwd "$selected"
}

system_process_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "📊 进程管理" "请选择功能:" \
            "1" "进程列表" \
            "2" "搜索进程")
        
        case "$choice" in
            1) system_process_list ;;
            2) system_process_search ;;
            b) break ;;
        esac
    done
}

system_process_list() {
    local items
    items=$(sys_parse_process_list "$(ps aux --sort=-%cpu | head -31)" 30)
    
    if [[ -z "$items" ]]; then
        ui_msg "无法获取进程列表" "错误"
        return
    fi
    
    local items_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && items_array+=("$line")
    done <<< "$items"
    
    local selected
    selected=$(ui_select "📊 进程列表 (TOP 30 CPU)" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    system_process_action "$selected"
}

system_process_search() {
    local keyword
    keyword=$(ui_input "请输入进程名称关键词")
    
    [[ -z "$keyword" ]] && return
    
    local items
    items=$(sys_parse_process_list "$(ps aux | grep -i "$keyword" | grep -v grep | head -21)" 20)
    
    if [[ -z "$items" ]]; then
        ui_msg "未找到匹配的进程" "提示"
        return
    fi
    
    local items_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && items_array+=("$line")
    done <<< "$items"
    
    local selected
    selected=$(ui_select "📊 搜索结果" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    system_process_action "$selected"
}

system_process_action() {
    local pid="$1"
    
    local action
    action=$(ui_action "📊 进程 $pid" \
        "kill" "终止进程" \
        "kill9" "强制终止" \
        "info" "查看详情" \
        "cancel" "返回")
    
    case "$action" in
        kill)
            if ui_confirm "确定要终止进程 $pid 吗？"; then
                kill "$pid" 2>&1 && ui_success "进程 $pid 已终止" || ui_error "终止失败"
            fi
            ;;
        kill9)
            if ui_confirm "确定要强制终止进程 $pid 吗？"; then
                kill -9 "$pid" 2>&1 && ui_success "进程 $pid 已强制终止" || ui_error "终止失败"
            fi
            ;;
        info)
            local info
            info=$(ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,start,time,comm 2>/dev/null || echo "进程不存在")
            ui_text "$info" "📊 进程详情"
            ;;
    esac
}

system_disk_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "💾 磁盘分析" "请选择功能:" \
            "1" "磁盘使用" \
            "2" "目录大小" \
            "3" "大文件查找")
        
        case "$choice" in
            1) system_disk_usage ;;
            2) system_disk_dir_size ;;
            3) system_disk_find_large ;;
            b) break ;;
        esac
    done
}

system_disk_usage() {
    local usage
    usage=$(df -h 2>/dev/null)
    ui_text "$usage" "💾 磁盘使用"
}

system_disk_dir_size() {
    local path
    path=$(ui_input "请输入目录路径" "/")
    
    [[ -z "$path" ]] && return
    
    if [[ ! -d "$path" ]]; then
        ui_msg "目录不存在" "错误"
        return
    fi
    
    ui_info "正在分析目录大小..."
    local result
    result=$(du -sh "$path"/* 2>/dev/null | sort -hr | head -20)
    ui_text "$result" "💾 目录大小"
}

system_disk_find_large() {
    local path size
    path=$(ui_input "请输入搜索路径" "/")
    size=$(ui_input "请输入最小文件大小" "100M")
    
    [[ -z "$path" ]] && return
    
    if [[ ! -d "$path" ]]; then
        ui_msg "目录不存在" "错误"
        return
    fi
    
    ui_info "正在搜索大文件..."
    
    local temp_file="${CONFIG[temp_dir]}/large_files.txt"
    find "$path" -type f -size "+$size" -exec ls -lh {} \; 2>/dev/null | head -50 > "$temp_file"
    
    if [[ ! -s "$temp_file" ]]; then
        ui_msg "未找到大于 $size 的文件" "提示"
        return
    fi
    
    local items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local file_path file_size
            file_size=$(echo "$line" | awk '{print $5}')
            file_path=$(echo "$line" | awk '{print $NF}')
            items+=("$file_path" "$file_size")
        fi
    done < "$temp_file"
    
    local selected
    selected=$(ui_select "💾 大文件列表" "选择文件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    local action
    action=$(ui_action "💾 $selected" \
        "delete" "删除文件" \
        "view" "查看详情" \
        "cancel" "返回")
    
    case "$action" in
        delete)
            if ui_confirm "确定要删除文件 $selected 吗？\n\n此操作不可恢复！"; then
                rm -f "$selected" 2>&1 && ui_success "文件已删除" || ui_error "删除失败"
            fi
            ;;
        view)
            local info
            info=$(ls -lah "$selected" 2>/dev/null)
            info+="\n\n文件类型: $(file "$selected" 2>/dev/null | cut -d: -f2)"
            ui_text "$info" "💾 文件详情"
            ;;
    esac
}

system_reboot() {
    if ui_confirm "确定要重启系统吗？"; then
        ui_info "3秒后重启系统..."
        sleep 3
        reboot
    fi
}
