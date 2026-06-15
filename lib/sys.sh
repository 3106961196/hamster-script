#!/bin/bash

# 系统信息

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

# 时区管理

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

sys_get_timezone_from_api() {
    local timezone
    if command_exists curl; then
        timezone=$(curl -s http://ip-api.com/json | grep -oP '"timezone":"\K[^"]+')
        if [[ -n "$timezone" ]]; then
            echo "$timezone"
            return 0
        fi
    fi
    echo "Asia/Shanghai"  # 默认时区
    return 1
}

sys_sync_time() {
    # 先通过API获取正确的时区
    local api_timezone
    api_timezone=$(sys_get_timezone_from_api)
    if [[ -n "$api_timezone" ]]; then
        sys_set_timezone "$api_timezone"
    fi
    
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

# 系统清理

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
