#!/bin/bash

system_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "系统管理" "请选择功能:"
            "1" "系统信息"
            "2" "系统更新"
            "3" "系统优化"
            "4" "安全加固"
            "5" "时间管理"
            "6" "用户管理"
            "7" "进程管理"
            "8" "磁盘分析"
            "9" "界面设置"
            "10" "重启系统")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) system_info ;;
            2) system_update ;;
            3) system_optimize ;;
            4) system_secure ;;
            5) system_time_menu ;;
            6) system_user_menu ;;
            7) system_process_menu ;;
            8) system_disk_menu ;;
            9) system_ui_settings ;;
            10) system_reboot ;;
        esac
    done
}

system_info() {
    local temp_log="${CONFIG[temp_dir]}/system_info.log"
    sys_get_info > "$temp_log" 2>&1
    ui_textbox "$temp_log" "系统信息"
}

system_update() {
    if ui_confirm "确定要更新系统吗？"; then
        ui_info "正在更新系统..."
        
        local temp_log="${CONFIG[temp_dir]}/system_update.log"
        {
            echo "=== 更新软件源 ==="
            pkg_update
            echo ""
            echo "=== 升级软件包 ==="
            pkg_upgrade
            echo ""
            echo "=== 清理无用包 ==="
            pkg_autoremove
            pkg_clean
        } 2>&1 | tee "$temp_log"
        
        ui_msg "系统更新完成"
    fi
}

system_optimize() {
    while true; do
        local choice
        choice=$(ui_submenu "系统优化" "请选择功能:"
            "1" "一键优化 (推荐)"
            "2" "清理包缓存"
            "3" "移除无用包"
            "4" "清理日志"
            "5" "清理临时文件")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) system_optimize_all ;;
            2) system_optimize_pkg_cache ;;
            3) system_optimize_autoremove ;;
            4) system_optimize_journal ;;
            5) system_optimize_temp ;;
        esac
    done
}

system_optimize_all() {
    if ui_confirm "确定要优化系统吗？\n\n将执行:\n- 清理包缓存\n- 移除无用包\n- 清理日志 (7天前)\n- 清理临时文件"; then
        ui_info "正在优化系统..."
        
        local temp_log="${CONFIG[temp_dir]}/system_optimize.log"
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
        } 2>&1 | tee "$temp_log"
        
        ui_msg "系统优化完成"
    fi
}

system_optimize_pkg_cache() {
    ui_info "正在清理包缓存..."
    local temp_log="${CONFIG[temp_dir]}/pkg_clean.log"
    if pkg_clean 2>&1 | tee "$temp_log"; then
        ui_msg "包缓存清理完成"
    else
        ui_msg "包缓存清理失败" "错误"
    fi
}

system_optimize_autoremove() {
    ui_info "正在移除无用包..."
    local temp_log="${CONFIG[temp_dir]}/autoremove.log"
    if pkg_autoremove 2>&1 | tee "$temp_log"; then
        ui_msg "无用包移除完成"
    else
        ui_msg "无用包移除失败" "错误"
    fi
}

system_optimize_journal() {
    local days
    days=$(ui_input "请输入要保留的天数" "7")
    
    if [[ ! "$days" =~ ^[0-9]+$ ]]; then
        ui_msg "天数必须是数字" "错误"
        return
    fi
    
    ui_info "正在清理 $days 天前的日志..."
    local temp_log="${CONFIG[temp_dir]}/journal_clean.log"
    if sys_clean_journal "$days" 2>&1 | tee "$temp_log"; then
        ui_msg "日志清理完成"
    else
        ui_msg "日志清理失败" "错误"
    fi
}

system_optimize_temp() {
    ui_info "正在清理临时文件..."
    local temp_log="${CONFIG[temp_dir]}/temp_clean.log"
    if sys_clean_temp 2>&1 | tee "$temp_log"; then
        ui_msg "临时文件清理完成"
    else
        ui_msg "临时文件清理失败" "错误"
    fi
}

system_secure() {
    while true; do
        local choice
        choice=$(ui_submenu "安全加固" "请选择功能:"
            "1" "防火墙状态"
            "2" "启用防火墙"
            "3" "禁用防火墙"
            "4" "开放端口"
            "5" "安全检查")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) secure_firewall_status ;;
            2) secure_firewall_enable ;;
            3) secure_firewall_disable ;;
            4) secure_open_port ;;
            5) secure_check ;;
        esac
    done
}

secure_firewall_status() {
    local temp_log="${CONFIG[temp_dir]}/firewall_status.log"
    
    if command_exists ufw; then
        ufw status verbose > "$temp_log" 2>&1
    elif command_exists firewall-cmd; then
        firewall-cmd --state > "$temp_log" 2>&1
        echo "" >> "$temp_log"
        firewall-cmd --list-all >> "$temp_log" 2>&1
    else
        echo "未检测到防火墙" > "$temp_log"
    fi
    
    ui_textbox "$temp_log" "防火墙状态"
}

secure_firewall_enable() {
    if command_exists ufw; then
        if ui_confirm "确定要启用 ufw 防火墙吗？"; then
            ufw enable 2>&1
            ui_msg "防火墙已启用"
        fi
    elif command_exists firewall-cmd; then
        if ui_confirm "确定要启用 firewalld 防火墙吗？"; then
            systemctl start firewalld
            systemctl enable firewalld
            ui_msg "防火墙已启用"
        fi
    else
        ui_msg "未检测到支持的防火墙"
    fi
}

secure_firewall_disable() {
    if command_exists ufw; then
        if ui_confirm "确定要禁用 ufw 防火墙吗？"; then
            ufw disable 2>&1
            ui_msg "防火墙已禁用"
        fi
    elif command_exists firewall-cmd; then
        if ui_confirm "确定要禁用 firewalld 防火墙吗？"; then
            systemctl stop firewalld
            systemctl disable firewalld
            ui_msg "防火墙已禁用"
        fi
    else
        ui_msg "未检测到支持的防火墙"
    fi
}

secure_open_port() {
    local port
    port=$(ui_input "请输入要开放的端口号:")
    
    if [[ -z "$port" ]]; then
        return
    fi
    
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [[ "$port" -lt 1 ]] || [[ "$port" -gt 65535 ]]; then
        ui_msg "端口号必须是 1-65535 之间的数字" "错误"
        return
    fi
    
    if command_exists ufw; then
        ufw allow "$port" 2>&1
        ui_msg "端口 $port 已开放"
    elif command_exists firewall-cmd; then
        firewall-cmd --permanent --add-port="$port/tcp"
        firewall-cmd --reload
        ui_msg "端口 $port 已开放"
    else
        ui_msg "未检测到支持的防火墙"
    fi
}

secure_check() {
    local temp_log="${CONFIG[temp_dir]}/security_check.log"
    
    {
        echo "=== 安全检查报告 ==="
        echo ""
        echo "1. SSH 配置"
        if [[ -f /etc/ssh/sshd_config ]]; then
            echo "   - Root 登录: $(grep -E '^PermitRootLogin' /etc/ssh/sshd_config | awk '{print $2}')"
            echo "   - 密码认证: $(grep -E '^PasswordAuthentication' /etc/ssh/sshd_config | awk '{print $2}')"
            echo "   - 端口: $(grep -E '^Port' /etc/ssh/sshd_config | awk '{print $2}')"
        fi
        echo ""
        echo "2. 防火墙状态"
        if command_exists ufw; then
            ufw status | head -5
        elif command_exists firewall-cmd; then
            firewall-cmd --state
        else
            echo "   未安装防火墙"
        fi
        echo ""
        echo "3. 开放端口"
        sys_get_open_ports | head -20
        echo ""
        echo "4. 最近登录"
        last -n 5 2>/dev/null || echo "   无法获取"
        echo ""
        echo "5. 失败的登录尝试"
        lastb -n 5 2>/dev/null || echo "   无记录"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "安全检查"
}

system_time_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "时间管理" "请选择功能:"
            "1" "查看时间"
            "2" "自定义时区"
            "3" "同步时间"
            "4" "手动设置时间")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) time_show ;;
            2) time_set_timezone ;;
            3) time_sync ;;
            4) time_manual ;;
        esac
    done
}

time_show() {
    local temp_log="${CONFIG[temp_dir]}/time_info.log"
    
    {
        echo "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
        local tz=$(sys_get_timezone)
        # 显示中英双语时区
        case "$tz" in
            Asia/Shanghai) echo "时区: Asia/Shanghai (亚洲/上海)" ;;
            Asia/Beijing) echo "时区: Asia/Beijing (亚洲/北京)" ;;
            Asia/Tokyo) echo "时区: Asia/Tokyo (亚洲/东京)" ;;
            Asia/Seoul) echo "时区: Asia/Seoul (亚洲/首尔)" ;;
            Asia/Hong_Kong) echo "时区: Asia/Hong_Kong (亚洲/香港)" ;;
            Asia/Taipei) echo "时区: Asia/Taipei (亚洲/台北)" ;;
            Asia/Singapore) echo "时区: Asia/Singapore (亚洲/新加坡)" ;;
            Asia/Dubai) echo "时区: Asia/Dubai (亚洲/迪拜)" ;;
            Europe/London) echo "时区: Europe/London (欧洲/伦敦)" ;;
            Europe/Paris) echo "时区: Europe/Paris (欧洲/巴黎)" ;;
            Europe/Berlin) echo "时区: Europe/Berlin (欧洲/柏林)" ;;
            Europe/Moscow) echo "时区: Europe/Moscow (欧洲/莫斯科)" ;;
            America/New_York) echo "时区: America/New_York (美洲/纽约)" ;;
            America/Los_Angeles) echo "时区: America/Los_Angeles (美洲/洛杉矶)" ;;
            America/Chicago) echo "时区: America/Chicago (美洲/芝加哥)" ;;
            America/Toronto) echo "时区: America/Toronto (美洲/多伦多)" ;;
            Australia/Sydney) echo "时区: Australia/Sydney (澳洲/悉尼)" ;;
            *) echo "时区: $tz" ;;
        esac
        echo "运行时间: $(sys_get_uptime)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "时间信息"
}

time_set_timezone() {
    local choice
    choice=$(ui_submenu "自定义时区" "请选择时区:"
        "1" "Asia/Shanghai (亚洲/上海)"
        "2" "Asia/Beijing (亚洲/北京)"
        "3" "Asia/Tokyo (亚洲/东京)"
        "4" "Asia/Seoul (亚洲/首尔)"
        "5" "Asia/Hong_Kong (亚洲/香港)"
        "6" "Asia/Taipei (亚洲/台北)"
        "7" "Asia/Singapore (亚洲/新加坡)"
        "8" "Asia/Dubai (亚洲/迪拜)"
        "9" "Europe/London (欧洲/伦敦)"
        "10" "Europe/Paris (欧洲/巴黎)"
        "11" "Europe/Berlin (欧洲/柏林)"
        "12" "Europe/Moscow (欧洲/莫斯科)"
        "13" "America/New_York (美洲/纽约)"
        "14" "America/Los_Angeles (美洲/洛杉矶)"
        "15" "America/Chicago (美洲/芝加哥)"
        "16" "America/Toronto (美洲/多伦多)"
        "17" "Australia/Sydney (澳洲/悉尼)"
        "18" "其他 (手动输入)")
    
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    local timezone
    case "$choice" in
        1) timezone="Asia/Shanghai" ;;
        2) timezone="Asia/Beijing" ;;
        3) timezone="Asia/Tokyo" ;;
        4) timezone="Asia/Seoul" ;;
        5) timezone="Asia/Hong_Kong" ;;
        6) timezone="Asia/Taipei" ;;
        7) timezone="Asia/Singapore" ;;
        8) timezone="Asia/Dubai" ;;
        9) timezone="Europe/London" ;;
        10) timezone="Europe/Paris" ;;
        11) timezone="Europe/Berlin" ;;
        12) timezone="Europe/Moscow" ;;
        13) timezone="America/New_York" ;;
        14) timezone="America/Los_Angeles" ;;
        15) timezone="America/Chicago" ;;
        16) timezone="America/Toronto" ;;
        17) timezone="Australia/Sydney" ;;
        18)
            # 手动输入选项
            timezone=$(ui_input "请输入时区 (如: Asia/Shanghai):")
            if [[ -z "$timezone" ]]; then
                return
            fi
            ;;
        *) return ;;
    esac
    
    if sys_set_timezone "$timezone"; then
        ui_msg "时区已设置为 $timezone"
    else
        ui_msg "时区设置失败" "错误"
    fi
}

time_sync() {
    if ui_confirm "确定要同步时间吗？"; then
        ui_info "正在同步时间..."
        if sys_sync_time; then
            ui_msg "时间同步成功"
        else
            ui_msg "时间同步失败" "错误"
        fi
    fi
}

time_manual() {
    local datetime
    datetime=$(ui_input "请输入日期时间 (格式: YYYY-MM-DD HH:MM:SS):")
    
    if [[ -n "$datetime" ]]; then
        timedatectl set-time "$datetime" 2>&1
        ui_msg "时间已设置"
    fi
}

system_user_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "用户管理" "请选择功能:"
            "1" "用户列表"
            "2" "添加用户"
            "3" "删除用户 (选择)"
            "4" "修改密码 (选择)")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) user_list ;;
            2) user_add ;;
            3) user_delete_select ;;
            4) user_password_select ;;
        esac
    done
}

user_list() {
    local temp_log="${CONFIG[temp_dir]}/user_list.log"
    cat /etc/passwd | awk -F: '{print $1 " (" $3 ") - " $7}' > "$temp_log"
    ui_textbox "$temp_log" "用户列表"
}

user_add() {
    local username
    username=$(ui_input "请输入新用户名:")
    
    if [[ -z "$username" ]]; then
        return
    fi
    
    if id "$username" &>/dev/null; then
        ui_msg "用户 $username 已存在" "错误"
        return
    fi
    
    ui_info "正在创建用户 $username..."
    if useradd -m -s /bin/bash "$username" 2>&1; then
        ui_msg "用户 $username 创建成功"
    else
        ui_msg "用户创建失败" "错误"
    fi
}

user_select() {
    local temp_file="${CONFIG[temp_dir]}/user_list_select.txt"
    cat /etc/passwd | awk -F: '$3 >= 1000 || $3 == 0 {print $1}' > "$temp_file"
    
    if [[ ! -s "$temp_file" ]]; then
        ui_msg "无法获取用户列表" "错误"
        return
    fi
    
    local items=()
    while IFS= read -r username; do
        if [[ -n "$username" ]]; then
            local uid
            uid=$(id -u "$username" 2>/dev/null)
            items+=("$username" "UID: $uid")
        fi
    done < "$temp_file"
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可操作的用户" "错误"
        return
    fi
    
    local choice
    choice=$(ui_submenu "选择用户" "请选择用户:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    echo "$choice"
}

user_delete_select() {
    local username
    username=$(user_select)
    
    if [[ -z "$username" ]]; then
        return
    fi
    
    if ui_confirm "确定要删除用户 $username 吗？\n这将同时删除用户主目录"; then
        if userdel -r "$username" 2>&1; then
            ui_msg "用户 $username 已删除"
        else
            ui_msg "用户删除失败" "错误"
        fi
    fi
}

user_password_select() {
    local username
    username=$(user_select)
    
    if [[ -z "$username" ]]; then
        return
    fi
    
    ui_msg "请在终端中输入新密码"
    passwd "$username"
}

system_process_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "进程管理" "请选择功能:"
            "1" "进程列表 (CPU)"
            "2" "进程列表 (内存)"
            "3" "查找进程"
            "4" "终止进程"
            "5" "选择终止进程")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) process_list_cpu ;;
            2) process_list_mem ;;
            3) process_find ;;
            4) process_kill ;;
            5) process_kill_select ;;
        esac
    done
}

process_list_cpu() {
    local temp_log="${CONFIG[temp_dir]}/process_cpu.log"
    sys_get_top_processes cpu 20 > "$temp_log" 2>&1
    ui_textbox "$temp_log" "CPU 占用 TOP 20"
}

process_list_mem() {
    local temp_log="${CONFIG[temp_dir]}/process_mem.log"
    sys_get_top_processes mem 20 > "$temp_log" 2>&1
    ui_textbox "$temp_log" "内存占用 TOP 20"
}

process_find() {
    local name
    name=$(ui_input "请输入进程名称:")
    
    if [[ -n "$name" ]]; then
        local temp_log="${CONFIG[temp_dir]}/process_find.log"
        ps aux | grep -i "$name" | grep -v grep > "$temp_log" 2>&1
        
        if [[ -s "$temp_log" ]]; then
            ui_textbox "$temp_log" "进程查找结果"
        else
            ui_msg "未找到匹配的进程"
        fi
    fi
}

process_kill() {
    local pid
    pid=$(ui_input "请输入要终止的进程 PID:")
    
    if [[ -n "$pid" ]]; then
        if ! [[ "$pid" =~ ^[0-9]+$ ]]; then
            ui_msg "PID 必须是数字" "错误"
            return
        fi
        
        if ui_confirm "确定要终止进程 $pid 吗？"; then
            if kill "$pid" 2>&1; then
                ui_msg "进程 $pid 已终止"
            else
                ui_msg "终止进程失败，可能需要 root 权限" "错误"
            fi
        fi
    fi
}

process_kill_select() {
    local temp_file="${CONFIG[temp_dir]}/process_list.txt"
    ps aux --sort=-%cpu | head -30 > "$temp_file" 2>&1
    
    if [[ ! -s "$temp_file" ]]; then
        ui_msg "无法获取进程列表" "错误"
        return
    fi
    
    local items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ ! "$line" =~ ^USER ]]; then
            local pid pcpu pmem comm
            pid=$(echo "$line" | awk '{print $2}')
            pcpu=$(echo "$line" | awk '{print $3}')
            pmem=$(echo "$line" | awk '{print $4}')
            comm=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i " "; print ""}' | xargs)
            if [[ -n "$pid" ]]; then
                local desc="CPU:${pcpu}% MEM:${pmem}% - ${comm:0:30}"
                items+=("$pid" "$desc")
            fi
        fi
    done < "$temp_file"
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可显示的进程"
        return
    fi
    
    local choice
    choice=$(ui_submenu "选择终止进程" "请选择要终止的进程:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    if ui_confirm "确定要终止进程 $choice 吗？"; then
        if kill "$choice" 2>&1; then
            ui_msg "进程 $choice 已终止"
        else
            ui_msg "终止进程失败，可能需要 root 权限" "错误"
        fi
    fi
}

system_disk_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "磁盘分析" "请选择功能:"
            "1" "磁盘使用"
            "2" "目录大小"
            "3" "大文件查找")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) disk_usage ;;
            2) disk_dir_size ;;
            3) disk_find_large ;;
        esac
    done
}

disk_usage() {
    local temp_log="${CONFIG[temp_dir]}/disk_usage.log"
    df -h > "$temp_log" 2>&1
    ui_textbox "$temp_log" "磁盘使用"
}

disk_dir_size() {
    local path
    path=$(ui_input "请输入目录路径" "/")
    
    if [[ -d "$path" ]]; then
        local temp_log="${CONFIG[temp_dir]}/dir_size.log"
        du -sh "$path"/* 2>/dev/null | sort -hr | head -20 > "$temp_log"
        ui_textbox "$temp_log" "目录大小 TOP 20"
    else
        ui_msg "目录不存在" "错误"
    fi
}

disk_find_large() {
    local path
    path=$(ui_input "请输入搜索路径" "/")
    
    local size
    size=$(ui_input "请输入最小文件大小 (如: 100M)" "100M")
    
    if [[ -d "$path" ]]; then
        ui_info "正在搜索大文件..."
        local temp_log="${CONFIG[temp_dir]}/large_files.log"
        find "$path" -type f -size "+$size" -exec ls -lh {} \; 2>/dev/null > "$temp_log"
        
        if [[ -s "$temp_log" ]]; then
            ui_textbox "$temp_log" "大文件列表"
        else
            ui_msg "未找到大于 $size 的文件"
        fi
    else
        ui_msg "目录不存在" "错误"
    fi
}

system_reboot() {
    if ui_confirm "确定要重启系统吗？\n\n此操作会立即重启服务器！"; then
        ui_info "系统将在 3 秒后重启..."
        sys_reboot 3
    fi
}

system_ui_settings() {
    while true; do
        local choice
        choice=$(ui_submenu "界面设置" "请选择功能:"
            "1" "查看当前配置"
            "2" "重置为默认配置"
            "3" "自定义颜色"
            "4" "查看美化效果")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) ui_settings_show ;;
            2) ui_settings_reset ;;
            3) ui_settings_custom ;;
            4) ui_settings_preview ;;
        esac
    done
}

ui_settings_show() {
    local dialogrc="${CONFIG[config_dir]}/dialogrc"
    if [[ -f "$dialogrc" ]]; then
        ui_textbox "$dialogrc" "Dialog 配置"
    else
        ui_msg "配置文件不存在" "错误"
    fi
}

ui_settings_reset() {
    if ui_confirm "确定要重置为默认配置吗？"; then
        local default_config="$PROJECT_ROOT/config/dialogrc"
        if [[ -f "$default_config" ]]; then
            cp "$default_config" "${CONFIG[config_dir]}/dialogrc"
            ui_msg "配置已重置为默认值"
        else
            ui_msg "默认配置文件不存在" "错误"
        fi
    fi
}

ui_settings_custom() {
    local dialogrc="${CONFIG[config_dir]}/dialogrc"
    if [[ ! -f "$dialogrc" ]]; then
        ui_msg "配置文件不存在，请先重置为默认配置" "错误"
        return
    fi
    
    local temp_config=$(mktemp)
    cp "$dialogrc" "$temp_config"
    
    # 这里可以添加更复杂的颜色自定义功能
    ui_msg "自定义功能开发中\n\n当前版本仅支持重置默认配置"
    
    rm -f "$temp_config"
}

ui_settings_preview() {
    # 显示一个预览对话框
    ui_msg "🎨 界面美化效果预览\n\n当前使用的是 Hamster Script 美化配置\n\n- 绿色边框和蓝色标题\n- 深色背景和白色文字\n- 橙色激活按钮\n- 阴影效果边框\n\n效果如何？" "美化预览"
}
