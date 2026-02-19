#!/bin/bash

monitor_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "系统监控" "请选择功能:" \
            "1" "CPU 监控" \
            "2" "内存监控" \
            "3" "磁盘监控" \
            "4" "网络监控" \
            "5" "实时监控")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_cpu ;;
            2) monitor_memory ;;
            3) monitor_disk ;;
            4) monitor_network ;;
            5) monitor_realtime ;;
        esac
    done
}

monitor_cpu() {
    while true; do
        local choice
        choice=$(ui_submenu "CPU 监控" "请选择功能:" \
            "1" "CPU 使用率" \
            "2" "CPU 信息" \
            "3" "CPU 占用进程" \
            "4" "系统负载")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_cpu_usage ;;
            2) monitor_cpu_info ;;
            3) monitor_cpu_process ;;
            4) monitor_cpu_load ;;
        esac
    done
}

monitor_cpu_usage() {
    local temp_log="${CONFIG[temp_dir]}/cpu_usage.log"
    
    {
        echo "CPU 使用率:"
        echo ""
        if command_exists top; then
            top -bn1 | head -5
        else
            echo "当前: $(sys_get_cpu_usage)"
        fi
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "CPU 使用率"
}

monitor_cpu_info() {
    local temp_log="${CONFIG[temp_dir]}/cpu_info.log"
    
    {
        echo "CPU 信息:"
        echo ""
        lscpu 2>/dev/null || cat /proc/cpuinfo
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "CPU 信息"
}

monitor_cpu_process() {
    local temp_log="${CONFIG[temp_dir]}/cpu_process.log"
    sys_get_top_processes cpu 20 > "$temp_log" 2>&1
    ui_textbox "$temp_log" "CPU 占用 TOP 20"
}

monitor_cpu_load() {
    local temp_log="${CONFIG[temp_dir]}/cpu_load.log"
    
    {
        echo "系统负载:"
        echo ""
        uptime
        echo ""
        echo "负载平均值: $(sys_get_load_avg)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "系统负载"
}

monitor_memory() {
    while true; do
        local choice
        choice=$(ui_submenu "内存监控" "请选择功能:" \
            "1" "内存使用" \
            "2" "内存占用进程" \
            "3" "交换分区")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_memory_usage ;;
            2) monitor_memory_process ;;
            3) monitor_memory_swap ;;
        esac
    done
}

monitor_memory_usage() {
    local temp_log="${CONFIG[temp_dir]}/memory_usage.log"
    
    {
        echo "内存使用:"
        echo ""
        free -h
        echo ""
        echo "当前使用: $(sys_get_memory_usage)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "内存使用"
}

monitor_memory_process() {
    local temp_log="${CONFIG[temp_dir]}/memory_process.log"
    sys_get_top_processes mem 20 > "$temp_log" 2>&1
    ui_textbox "$temp_log" "内存占用 TOP 20"
}

monitor_memory_swap() {
    local temp_log="${CONFIG[temp_dir]}/memory_swap.log"
    
    {
        echo "交换分区:"
        echo ""
        swapon --show 2>/dev/null || cat /proc/swaps
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "交换分区"
}

monitor_disk() {
    while true; do
        local choice
        choice=$(ui_submenu "磁盘监控" "请选择功能:" \
            "1" "磁盘使用" \
            "2" "磁盘 IO" \
            "3" "大文件查找")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_disk_usage ;;
            2) monitor_disk_io ;;
            3) monitor_disk_large ;;
        esac
    done
}

monitor_disk_usage() {
    local temp_log="${CONFIG[temp_dir]}/disk_usage.log"
    
    {
        echo "磁盘使用:"
        echo ""
        df -h
        echo ""
        echo "根目录使用: $(sys_get_disk_usage /)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "磁盘使用"
}

monitor_disk_io() {
    local temp_log="${CONFIG[temp_dir]}/disk_io.log"
    
    {
        echo "磁盘 IO:"
        echo ""
        if command_exists iostat; then
            iostat -x 1 3
        else
            echo "iostat 未安装，显示基本信息:"
            cat /proc/diskstats | head -20
        fi
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "磁盘 IO"
}

monitor_disk_large() {
    local path
    path=$(ui_input "请输入搜索路径" "/")
    
    local size
    size=$(ui_input "请输入最小文件大小" "100M")
    
    if [[ -d "$path" ]]; then
        ui_info "正在搜索大文件..."
        local temp_log="${CONFIG[temp_dir]}/large_files.log"
        find "$path" -type f -size "+$size" -exec ls -lh {} \; 2>/dev/null | head -50 > "$temp_log"
        
        if [[ -s "$temp_log" ]]; then
            ui_textbox "$temp_log" "大文件列表"
        else
            ui_msg "未找到大于 $size 的文件"
        fi
    else
        ui_msg "目录不存在" "错误"
    fi
}

monitor_network() {
    while true; do
        local choice
        choice=$(ui_submenu "网络监控" "请选择功能:" \
            "1" "网络接口" \
            "2" "网络连接" \
            "3" "开放端口" \
            "4" "网络测试")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_network_interface ;;
            2) monitor_network_connections ;;
            3) monitor_network_ports ;;
            4) monitor_network_test ;;
        esac
    done
}

monitor_network_interface() {
    local temp_log="${CONFIG[temp_dir]}/network_interface.log"
    
    {
        echo "网络接口:"
        echo ""
        ip addr show
        echo ""
        echo "本地 IP: $(sys_get_local_ip)"
        echo "公网 IP: $(sys_get_public_ip)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "网络接口"
}

monitor_network_connections() {
    local temp_log="${CONFIG[temp_dir]}/network_connections.log"
    
    {
        echo "网络连接:"
        echo ""
        if command_exists ss; then
            ss -tuln
        else
            netstat -tuln
        fi
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "网络连接"
}

monitor_network_ports() {
    local temp_log="${CONFIG[temp_dir]}/network_ports.log"
    
    {
        echo "开放端口:"
        echo ""
        sys_get_open_ports
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "开放端口"
}

monitor_network_test() {
    local host
    host=$(ui_input "请输入要测试的主机" "8.8.8.8")
    
    if [[ -n "$host" ]]; then
        local temp_log="${CONFIG[temp_dir]}/network_test.log"
        
        {
            echo "测试连接: $host"
            echo ""
            ping -c 4 "$host"
        } > "$temp_log" 2>&1
        
        ui_textbox "$temp_log" "网络测试"
    fi
}

monitor_realtime() {
    if command_exists htop; then
        ui_clear
        htop
    elif command_exists top; then
        ui_clear
        top
    else
        ui_msg "htop 或 top 未安装\n\n请安装后使用:\napt install htop"
    fi
}
