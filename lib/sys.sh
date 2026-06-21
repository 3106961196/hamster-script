#!/bin/bash

# 系统信息

系统_获取信息() {
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

系统_获取CPU使用() {
    local cpu_usage
    if 命令存在 top; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
        echo "$cpu_usage%"
    else
        echo "N/A"
    fi
}

系统_获取内存使用() {
    local mem_info
    mem_info=$(free -m | grep "Mem:")
    local total=$(echo "$mem_info" | awk '{print $2}')
    local used=$(echo "$mem_info" | awk '{print $3}')
    local percent=$((used * 100 / total))
    echo "${used}MB / ${total}MB (${percent}%)"
}

系统_获取磁盘使用() {
    local path="${1:-/}"
    df -h "$path" | tail -1 | awk '{print $3 " / " $2 " (" $5 " 已用)"}'
}

# 时区管理

系统_设置时区() {
    local timezone="$1"
    if [[ -f "/usr/share/zoneinfo/$timezone" ]]; then
        ln -sf "/usr/share/zoneinfo/$timezone" /etc/localtime
        echo "$timezone" > /etc/timezone
        日志成功 "时区已设置为: $timezone"
    else
        日志错误 "无效的时区: $timezone"
        return 1
    fi
}

系统_获取时区() {
    timedatectl show 2>/dev/null | grep Timezone | cut -d= -f2 || cat /etc/timezone 2>/dev/null
}

系统_从API获取时区() {
    local timezone
    if 命令存在 curl; then
        timezone=$(curl -s http://ip-api.com/json | grep -oP '"timezone":"\K[^"]+')
        if [[ -n "$timezone" ]]; then
            echo "$timezone"
            return 0
        fi
    fi
    echo "Asia/Shanghai"  # 默认时区
    return 1
}

系统_同步时间() {
    # 先通过API获取正确的时区
    local api_timezone
    api_timezone=$(系统_从API获取时区)
    if [[ -n "$api_timezone" ]]; then
        系统_设置时区 "$api_timezone"
    fi
    
    if 命令存在 timedatectl; then
        timedatectl set-ntp true
        日志成功 "已启用 NTP 时间同步"
    elif 命令存在 ntpdate; then
        ntpdate pool.ntp.org
    else
        日志错误 "未找到时间同步工具"
        return 1
    fi
}

# 系统清理

系统_清理日志() {
    local days="${1:-7}"
    if 命令存在 journalctl; then
        journalctl --vacuum-time="${days}d"
        日志成功 "已清理 ${days} 天前的日志"
    fi
}

系统_清理临时() {
    local temp_dirs=("/tmp" "/var/tmp")
    for dir in "${temp_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            find "$dir" -type f -mtime +7 -delete 2>/dev/null
            find "$dir" -type d -empty -delete 2>/dev/null
        fi
    done
    日志成功 "已清理临时文件"
}
