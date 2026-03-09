#!/bin/bash

monitor_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "📊 系统监控" "请选择功能:" \
            "1" "系统概览" \
            "2" "资源监控" \
            "3" "网络监控" \
            "4" "实时监控")
        
        case "$choice" in
            1) monitor_overview ;;
            2) monitor_resources ;;
            3) monitor_network ;;
            4) monitor_realtime ;;
            b) break ;;
        esac
    done
}

monitor_overview() {
    ui_info "正在获取系统概览..."
    
    local content
    content=$({
        echo "🖥️  系统: $(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d'"' -f2 || uname -a)"
        echo "📅  时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "⏱️   运行: $(uptime -p 2>/dev/null || uptime)"
        echo ""
        echo "💻  CPU: $(sys_get_cpu_usage 2>/dev/null || echo 'N/A')"
        echo "    核心: $(nproc 2>/dev/null || echo 'N/A')"
        echo "    负载: $(cat /proc/loadavg 2>/dev/null | awk '{print $1, $2, $3}' || echo 'N/A')"
        echo ""
        echo "🧠  内存: $(free -h 2>/dev/null | grep Mem | awk '{print $3 "/" $2}' || echo 'N/A')"
        echo "    Swap: $(free -h 2>/dev/null | grep Swap | awk '{print $3 "/" $2}' || echo 'N/A')"
        echo ""
        echo "💾  磁盘:"
        df -h / 2>/dev/null | tail -1 | awk '{print "    /: "$3" / "$2" ("$5" 已用)"}'
        echo ""
        echo "🌐  网络:"
        echo "    本地 IP: $(sys_get_local_ip 2>/dev/null || echo 'N/A')"
        echo "    公网 IP: $(sys_get_public_ip 2>/dev/null || echo 'N/A')"
    })
    
    ui_text "$content" "📊 系统概览"
}

monitor_resources() {
    while true; do
        local choice
        choice=$(ui_submenu "📊 资源监控" "请选择功能:" \
            "1" "CPU 使用率" \
            "2" "内存使用率" \
            "3" "磁盘使用率" \
            "4" "进程列表")
        
        case "$choice" in
            1) monitor_cpu ;;
            2) monitor_memory ;;
            3) monitor_disk ;;
            4) monitor_processes ;;
            b) break ;;
        esac
    done
}

monitor_cpu() {
    local content
    content=$({
        echo "💻 CPU 使用率: $(sys_get_cpu_usage 2>/dev/null || echo 'N/A')"
        echo ""
        echo "CPU 信息:"
        lscpu 2>/dev/null | grep -E "^(Model name|CPU\(s\)|CPU MHz|CPU cores)" || echo "无法获取"
        echo ""
        echo "系统负载:"
        cat /proc/loadavg 2>/dev/null || echo "无法获取"
    })
    
    ui_text "$content" "💻 CPU 监控"
}

monitor_memory() {
    local content
    content=$({
        echo "🧠 内存使用:"
        free -h 2>/dev/null || echo "无法获取"
        echo ""
        echo "内存详情:"
        echo "    总计: $(free -h 2>/dev/null | grep Mem | awk '{print $2}')"
        echo "    已用: $(free -h 2>/dev/null | grep Mem | awk '{print $3}')"
        echo "    可用: $(free -h 2>/dev/null | grep Mem | awk '{print $7}')"
    })
    
    ui_text "$content" "🧠 内存监控"
}

monitor_disk() {
    local content
    content=$({
        echo "💾 磁盘使用:"
        df -h 2>/dev/null || echo "无法获取"
        echo ""
        echo "磁盘分区:"
        lsblk 2>/dev/null || fdisk -l 2>/dev/null | head -20 || echo "无法获取"
    })
    
    ui_text "$content" "💾 磁盘监控"
}

monitor_processes() {
    local items
    items=$(sys_parse_process_list "$(ps aux --sort=-%cpu | head -21)" 20)
    
    if [[ -z "$items" ]]; then
        ui_msg "无法获取进程列表" "错误"
        return
    fi
    
    local items_array=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && items_array+=("$line")
    done <<< "$items"
    
    local selected
    selected=$(ui_select "📊 进程列表 (TOP 20)" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    local action
    action=$(ui_action "📊 进程 $selected" \
        "kill" "终止进程" \
        "info" "查看详情" \
        "cancel" "返回")
    
    case "$action" in
        kill)
            if ui_confirm "确定要终止进程 $selected 吗？"; then
                kill "$selected" 2>&1 && ui_success "进程 $selected 已终止" || ui_error "终止失败"
            fi
            ;;
        info)
            local info
            info=$(ps -p "$selected" -o pid,ppid,user,%cpu,%mem,stat,start,time,comm 2>/dev/null || echo "进程不存在")
            ui_text "$info" "📊 进程详情"
            ;;
    esac
}

monitor_network() {
    while true; do
        local choice
        choice=$(ui_submenu "🌐 网络监控" "请选择功能:" \
            "1" "网络接口" \
            "2" "网络连接" \
            "3" "开放端口" \
            "4" "网络测试")
        
        case "$choice" in
            1) monitor_network_interfaces ;;
            2) monitor_network_connections ;;
            3) monitor_network_ports ;;
            4) monitor_network_test ;;
            b) break ;;
        esac
    done
}

monitor_network_interfaces() {
    local content
    content=$({
        echo "🌐 网络接口:"
        ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "无法获取"
        echo ""
        echo "本地 IP: $(sys_get_local_ip 2>/dev/null || echo 'N/A')"
        echo "公网 IP: $(sys_get_public_ip 2>/dev/null || echo 'N/A')"
    })
    
    ui_text "$content" "🌐 网络接口"
}

monitor_network_connections() {
    local content
    content=$({
        echo "🌐 网络连接:"
        if command -v ss &>/dev/null; then
            ss -tuln 2>/dev/null
        else
            netstat -tuln 2>/dev/null
        fi || echo "无法获取"
    })
    
    ui_text "$content" "🌐 网络连接"
}

monitor_network_ports() {
    local content
    content=$({
        echo "🌐 开放端口:"
        sys_get_open_ports 2>/dev/null || echo "无法获取"
    })
    
    ui_text "$content" "🌐 开放端口"
}

monitor_network_test() {
    local host
    host=$(ui_input "请输入要测试的主机" "8.8.8.8")
    
    [[ -z "$host" ]] && return
    
    local content
    content=$({
        echo "🌐 测试连接: $host"
        echo ""
        ping -c 4 "$host" 2>/dev/null || echo "测试失败"
    })
    
    ui_text "$content" "🌐 网络测试"
}

monitor_realtime() {
    if command -v htop &>/dev/null; then
        ui_clear
        htop
    elif command -v top &>/dev/null; then
        ui_clear
        top
    else
        ui_msg "htop 或 top 未安装\n\n请安装后使用:\napt install htop" "提示"
    fi
}
