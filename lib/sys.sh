#!/bin/bash

sys_get_info() {
    echo "=== 系统信息 ==="
    echo ""
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "系统: $PRETTY_NAME"
    fi
    
    echo "内核: $(uname -r)"
    echo "架构: $(uname -m)"
    echo "主机名: $(hostname)"
    echo ""
    
    echo "=== CPU 信息 ==="
    if [[ -f /proc/cpuinfo ]]; then
        local cpu_model
        cpu_model=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
        local cpu_cores
        cpu_cores=$(grep -c "processor" /proc/cpuinfo)
        echo "型号: $cpu_model"
        echo "核心: $cpu_cores"
    fi
    echo ""
    
    echo "=== 内存信息 ==="
    free -h
    echo ""
    
    echo "=== 磁盘信息 ==="
    df -h / 2>/dev/null
    echo ""
    
    echo "=== 系统负载 ==="
    uptime
}

sys_get_uptime() {
    local uptime_str
    uptime_str=$(cat /proc/uptime | cut -d' ' -f1)
    local uptime_int=${uptime_str%.*}
    local days=$((uptime_int / 86400))
    local hours=$(( (uptime_int % 86400) / 3600 ))
    local minutes=$(( (uptime_int % 3600) / 60 ))
    echo "${days}天 ${hours}小时 ${minutes}分钟"
}

sys_get_cpu_usage() {
    local cpu_usage
    if command_exists top; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        echo "$cpu_usage%"
    else
        echo "N/A"
    fi
}

sys_get_memory_usage() {
    local mem_info
    mem_info=$(free -m | grep "Mem:")
    local total=$(echo "$mem_info" | awk '{print $2}')
    local used=$(echo "$mem_info" | awk '{print $3}')
    local percent=$((used * 100 / total))
    echo "${used}MB / ${total}MB (${percent}%)"
}

sys_get_disk_usage() {
    local path="${1:-/}"
    df -h "$path" | tail -1 | awk '{print $3 " / " $2 " (" $5 " 已用)"}'
}

sys_get_load_avg() {
    cat /proc/loadavg | awk '{print $1 ", " $2 ", " $3}'
}

sys_is_systemd() {
    command_exists systemctl && [[ -d /run/systemd/system ]]
}

sys_service_list() {
    if sys_is_systemd; then
        systemctl list-units --type=service --state=running
    else
        service --status-all 2>/dev/null | grep +
    fi
}

sys_service_start() {
    local service="$1"
    if sys_is_systemd; then
        systemctl start "$service"
    else
        service "$service" start
    fi
}

sys_service_stop() {
    local service="$1"
    if sys_is_systemd; then
        systemctl stop "$service"
    else
        service "$service" stop
    fi
}

sys_service_restart() {
    local service="$1"
    if sys_is_systemd; then
        systemctl restart "$service"
    else
        service "$service" restart
    fi
}

sys_service_status() {
    local service="$1"
    if sys_is_systemd; then
        systemctl status "$service"
    else
        service "$service" status
    fi
}

sys_service_is_running() {
    local service="$1"
    if sys_is_systemd; then
        systemctl is-active --quiet "$service"
    else
        service "$service" status &>/dev/null
    fi
}

sys_reboot() {
    local delay="${1:-0}"
    if [[ $delay -gt 0 ]]; then
        log_info "系统将在 ${delay} 秒后重启..."
        sleep "$delay"
    fi
    
    if command_exists systemctl; then
        systemctl reboot
    else
        reboot
    fi
}

sys_shutdown() {
    local delay="${1:-0}"
    if [[ $delay -gt 0 ]]; then
        log_info "系统将在 ${delay} 秒后关机..."
        sleep "$delay"
    fi
    
    if command_exists systemctl; then
        systemctl poweroff
    else
        poweroff
    fi
}

sys_set_timezone() {
    local timezone="$1"
    if [[ -f "/usr/share/zoneinfo/$timezone" ]]; then
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
        log_success "时区已设置为: $timezone"
    else
        log_error "无效的时区: $timezone"
        return 1
    fi
}

sys_get_timezone() {
    timedatectl show 2>/dev/null | grep Timezone | cut -d= -f2 || cat /etc/timezone 2>/dev/null
}

sys_sync_time() {
    if command_exists timedatectl; then
        timedatectl set-ntp true
        log_success "已启用 NTP 时间同步"
    elif command_exists ntpdate; then
        ntpdate pool.ntp.org
    else
        log_error "未找到时间同步工具"
        return 1
    fi
}

sys_get_public_ip() {
    local ip
    if command_exists curl; then
        ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    elif command_exists wget; then
        ip=$(wget -qO- ifconfig.me 2>/dev/null || wget -qO- icanhazip.com 2>/dev/null)
    fi
    echo "$ip"
}

sys_get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 | awk '{print $7; exit}'
}

sys_check_port() {
    local port="$1"
    if command_exists ss; then
        ss -tuln | grep -q ":$port "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":$port "
    else
        return 1
    fi
}

sys_get_open_ports() {
    if command_exists ss; then
        ss -tuln | awk 'NR>1 {print $5}' | cut -d: -f2 | sort -n | uniq
    elif command_exists netstat; then
        netstat -tuln | awk 'NR>2 {print $4}' | cut -d: -f2 | sort -n | uniq
    fi
}

sys_kill_process() {
    local process_name="$1"
    local signal="${2:-TERM}"
    pkill -"$signal" "$process_name"
}

sys_get_top_processes() {
    local sort_by="${1:-cpu}"
    local count="${2:-10}"
    
    case "$sort_by" in
        cpu) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
        mem) ps aux --sort=-%mem | head -n $((count + 1)) ;;
        *) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
    esac
}

sys_clean_journal() {
    local days="${1:-7}"
    if command_exists journalctl; then
        journalctl --vacuum-time="${days}d"
        log_success "已清理 ${days} 天前的日志"
    fi
}

sys_clean_temp() {
    local temp_dirs=("/tmp" "/var/tmp")
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -mtime +7 -delete 2>/dev/null
            find "$dir" -type d -empty -delete 2>/dev/null
        fi
    done
    log_success "已清理临时文件"
}
