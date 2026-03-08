#!/bin/bash

monitor_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "系统监控" "请选择功能:" \
            "1" "系统概览" \
            "2" "CPU 监控" \
            "3" "内存监控" \
            "4" "磁盘监控" \
            "5" "网络监控" \
            "6" "实时监控")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_overview ;;
            2) monitor_cpu ;;
            3) monitor_memory ;;
            4) monitor_disk ;;
            5) monitor_network ;;
            6) monitor_realtime ;;
        esac
    done
}

monitor_overview() {
    local temp_log="${CONFIG[temp_dir]}/monitor_overview.log"
    
    {
        echo "=== 系统概览 ==="
        echo ""
        echo "时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "运行: $(sys_get_uptime)"
        echo ""
        echo "=== CPU ==="
        echo "使用率: $(sys_get_cpu_usage)"
        echo "负载: $(sys_get_load_avg)"
        echo ""
        echo "=== 内存 ==="
        free -h | grep -E "^(Mem|Swap)"
        echo ""
        echo "=== 磁盘 ==="
        df -h / 2>/dev/null | tail -1
        echo ""
        echo "=== 网络 ==="
        echo "本地 IP: $(sys_get_local_ip)"
        echo "公网 IP: $(sys_get_public_ip)"
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "系统概览"
}

monitor_cpu() {
    while true; do
        local choice
        choice=$(ui_submenu "CPU 监控" "请选择功能:" \
            "1" "CPU 使用率" \
            "2" "CPU 信息" \
            "3" "CPU 占用进程 (可终止)" \
            "4" "系统负载")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_cpu_usage ;;
            2) monitor_cpu_info ;;
            3) monitor_cpu_process_action ;;
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

monitor_cpu_process_action() {
    local temp_file="${CONFIG[temp_dir]}/cpu_process_list.txt"
    sys_get_top_processes cpu 20 > "$temp_file" 2>&1
    
    ui_textbox "$temp_file" "CPU 占用 TOP 20"
    
    if ui_confirm "是否要终止某个进程？"; then
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
    fi
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
            "2" "内存占用进程 (可终止)" \
            "3" "交换分区")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_memory_usage ;;
            2) monitor_memory_process_action ;;
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

monitor_memory_process_action() {
    local temp_file="${CONFIG[temp_dir]}/mem_process_list.txt"
    sys_get_top_processes mem 20 > "$temp_file" 2>&1
    
    ui_textbox "$temp_file" "内存占用 TOP 20"
    
    if ui_confirm "是否要终止某个进程？"; then
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
    fi
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
            "3" "大文件查找 (可删除)")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) monitor_disk_usage ;;
            2) monitor_disk_io ;;
            3) monitor_disk_large_action ;;
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

monitor_disk_large_action() {
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
            
            if ui_confirm "是否要删除某个文件？"; then
                local file_path
                file_path=$(ui_input "请输入要删除的文件完整路径:")
                
                if [[ -n "$file_path" ]] && [[ -f "$file_path" ]]; then
                    if ui_confirm "确定要删除文件 $file_path 吗？\n\n此操作不可恢复！"; then
                        if rm -f "$file_path" 2>&1; then
                            ui_msg "文件已删除"
                        else
                            ui_msg "删除失败" "错误"
                        fi
                    fi
                else
                    ui_msg "文件不存在或路径无效" "错误"
                fi
            fi
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
