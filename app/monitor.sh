#!/bin/bash

监控_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "📊 系统监控" "请选择功能:" \
            "1" "系统概览" \
            "2" "资源监控" \
            "3" "网络监控" \
            "4" "实时监控")
        
        case "$choice" in
            1) 监控_概览 ;;
            2) 监控_资源 ;;
            3) 监控_网络 ;;
            4) 监控_实时 ;;
            b) break ;;
        esac
    done
}

监控_概览() {
    local content

    界面清屏
    printf '正在获取系统概览...\n\n' >&2
    content=$({
        echo "🖥️  系统: $(grep PRETTY_NAME  /etc/os-release 2>/dev/null | cut -d'"' -f2 || uname -a)"
        echo "📅  时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "⏱️   运行: $(uptime -p 2>/dev/null || uptime)"
        echo ""
        echo "💻  CPU: $(系统_获取CPU使用 2>/dev/null || echo 'N/A')"
        echo "    核心: $(nproc 2>/dev/null || echo 'N/A')"
        echo "    负载: $(awk '{print $1, $2, $3}' < /proc/loadavg 2>/dev/null || echo 'N/A')"
        echo ""
        echo "🧠  内存: $(free -h 2>/dev/null | grep Mem | awk '{print $3 "/" $2}' || echo 'N/A')"
        echo "    Swap: $(free -h 2>/dev/null | grep Swap | awk '{print $3 "/" $2}' || echo 'N/A')"
        echo ""
        echo "💾  磁盘:"
        df -h / 2>/dev/null | tail -1 | awk '{print "    /: "$3" / "$2" ("$5" 已用)"}'
        echo ""
        echo "🌐  网络:"
        echo "    本地 IP: $(网络_获取本地IP 2>/dev/null || echo 'N/A')"
        echo "    公网 IP: $(网络_获取公网IP 2>/dev/null || echo 'N/A')"
    })
    界面清屏

    界面文本 "$content" "📊 系统概览"
}

监控_资源() {
    while true; do
        local choice
        choice=$(界面子菜单 "📊 资源监控" "请选择功能:" \
            "1" "CPU 使用率" \
            "2" "内存使用率" \
            "3" "磁盘使用率" \
            "4" "进程列表")
        
        case "$choice" in
            1) 监控_CPU ;;
            2) 监控_内存 ;;
            3) 监控_磁盘 ;;
            4) 监控_进程 ;;
            b) break ;;
        esac
    done
}

监控_CPU() {
    local content
    content=$({
        echo "💻 CPU 使用率: $(系统_获取CPU使用 2>/dev/null || echo 'N/A')"
        echo ""
        echo "CPU 信息:"
        lscpu 2>/dev/null | grep -E "^(Model name|CPU\(s\)|CPU MHz|CPU cores)" || echo "无法获取"
        echo ""
        echo "系统负载:"
        awk '{print $1, $2, $3}' < /proc/loadavg 2>/dev/null || echo "无法获取"
    })
    
    界面文本 "$content" "💻 CPU 监控"
}

监控_内存() {
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
    
    界面文本 "$content" "🧠 内存监控"
}

监控_磁盘() {
    local content
    content=$({
        echo "💾 磁盘使用:"
        df -h 2>/dev/null || echo "无法获取"
        echo ""
        echo "磁盘分区:"
        lsblk 2>/dev/null || fdisk -l 2>/dev/null | head -20 || echo "无法获取"
    })
    
    界面文本 "$content" "💾 磁盘监控"
}

监控_进程() {
    local items_data
    items_data=$(网络_解析进程列表 "$(ps aux --sort=-%cpu | head -21)" 20)
    
    if [[ -z "$items_data" ]]; then
        界面消息 "无法获取进程列表" "错误"
        return
    fi
    
    local items_array=()
    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] && items_array+=("$key" "$value")
    done <<< "$items_data"
    
    local selected
    selected=$(界面选择 "📊 进程列表 (TOP 20)" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    local action
    action=$(界面动作 "📊 进程 $selected" \
        "kill" "终止进程" \
        "info" "查看详情")
    
    界面已取消 "$action" && return
    
    case "$action" in
        kill)
            if 界面确认 "确定要终止进程 $selected 吗？"; then
                kill "$selected" 2>&1 && 界面成功 "进程 $selected 已终止" || 界面错误 "终止失败"
            fi
            ;;
        info)
            local info
            info=$(ps -p "$selected" -o pid,ppid,user,%cpu,%mem,stat,start,time,comm 2>/dev/null || echo "进程不存在")
            界面文本 "$info" "📊 进程详情"
            ;;
    esac
}

监控_网络() {
    while true; do
        local choice
        choice=$(界面子菜单 "🌐 网络监控" "请选择功能:" \
            "1" "网络接口" \
            "2" "网络连接" \
            "3" "开放端口" \
            "4" "网络测试")
        
        case "$choice" in
            1) 监控_网络接口 ;;
            2) 监控_网络连接 ;;
            3) 监控_网络端口 ;;
            4) 监控_网络测试 ;;
            b) break ;;
        esac
    done
}

监控_网络接口() {
    local content
    content=$({
        echo "🌐 网络接口:"
        ip addr show 2>/dev/null || ifconfig 2>/dev/null || echo "无法获取"
        echo ""
        echo "本地 IP: $(网络_获取本地IP 2>/dev/null || echo 'N/A')"
        echo "公网 IP: $(网络_获取公网IP 2>/dev/null || echo 'N/A')"
    })
    
    界面文本 "$content" "🌐 网络接口"
}

监控_网络连接() {
    local content
    content=$({
        echo "🌐 网络连接:"
        if command -v ss &>/dev/null; then
            ss -tuln 2>/dev/null
        else
            netstat -tuln 2>/dev/null
        fi || echo "无法获取"
    })
    
    界面文本 "$content" "🌐 网络连接"
}

监控_网络端口() {
    local content
    content=$({
        echo "🌐 开放端口:"
        网络_获取开放端口 2>/dev/null || echo "无法获取"
    })
    
    界面文本 "$content" "🌐 开放端口"
}

监控_网络测试() {
    local host
    host=$(界面输入 "请输入要测试的主机" "8.8.8.8")
    
    [[ -z "$host" ]] && return
    
    local content
    content=$({
        echo "🌐 测试连接: $host"
        echo ""
        ping -c 4 "$host" 2>/dev/null || echo "测试失败"
    })
    
    界面文本 "$content" "🌐 网络测试"
}

监控_实时() {
    if command -v htop &>/dev/null; then
        界面清屏
        htop
    elif command -v top &>/dev/null; then
        界面清屏
        top
    else
        界面消息 "htop 或 top 未安装\n\n请安装后使用:\napt install htop" "提示"
    fi
}
