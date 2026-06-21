#!/bin/bash

系统管理_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "⚙️ 系统管理" "请选择功能:" \
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
            1) 系统管理_信息 ;;
            2) 系统管理_系统更新 ;;
            3) 系统管理_优化菜单 ;;
            4) 系统管理_服务菜单 ;;
            5) 系统管理_安全菜单 ;;
            6) 系统管理_时间菜单 ;;
            7) 系统管理_用户菜单 ;;
            8) 系统管理_进程菜单 ;;
            9) 系统管理_磁盘菜单 ;;
            10) 系统管理_重启 ;;
            b) break ;;
        esac
    done
}

系统管理_信息() {
    界面信息 "正在获取系统信息..."
    
    local info
    info=$(系统_获取信息 2>/dev/null)
    
    界面文本 "$info" "🖥️ 系统信息"
}

系统管理_系统更新() {
    if ! 界面确认 "确定要更新系统吗？"; then
        return
    fi
    
    界面信息 "正在更新系统..."
    
    {
        echo "=== 更新软件源 ==="
        包管理_更新源
        echo ""
        echo "=== 升级软件包 ==="
        包管理_全部升级
        echo ""
        echo "=== 清理无用包 ==="
        包管理_自动移除
        echo ""
        echo "=== 清理缓存 ==="
        包管理_清理
    } 2>&1 | 界面文本 "⚙️ 系统更新"
    
    界面成功 "系统更新完成"
}

系统管理_优化菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "🧹 系统优化" "请选择功能:" \
            "1" "一键优化" \
            "2" "自定义清理")
        
        case "$choice" in
            1) 系统管理_全部优化 ;;
            2) 系统管理_自定义优化 ;;
            b) break ;;
        esac
    done
}

系统管理_全部优化() {
    if ! 界面确认 "确定要优化系统吗？\n\n将执行:\n- 清理包缓存\n- 移除无用包\n- 清理日志 (7天前)\n- 清理临时文件"; then
        return
    fi
    
    界面信息 "正在优化系统..."
    
    {
        echo "=== 清理包缓存 ==="
        包管理_清理
        echo ""
        echo "=== 移除无用包 ==="
        包管理_自动移除
        echo ""
        echo "=== 清理日志 ==="
        系统_清理日志 7
        echo ""
        echo "=== 清理临时文件 ==="
        系统_清理临时
    } 2>&1 | 界面文本 "🧹 系统优化"
    
    界面成功 "系统优化完成"
}

系统管理_自定义优化() {
    local items
    items=$(界面多选 "🧹 自定义清理" "选择清理项目:" \
        "cache" "清理包缓存" \
        "autoremove" "移除无用包" \
        "journal" "清理日志" \
        "temp" "清理临时文件")
    
    [[ -z "$items" ]] && return
    
    界面信息 "正在清理..."
    
    {
        for item in $items; do
            case "$item" in
                cache)
                    echo "=== 清理包缓存 ==="
                    包管理_清理
                    ;;
                autoremove)
                    echo "=== 移除无用包 ==="
                    包管理_自动移除
                    ;;
                journal)
                    echo "=== 清理日志 ==="
                    系统_清理日志 7
                    ;;
                temp)
                    echo "=== 清理临时文件 ==="
                    系统_清理临时
                    ;;
            esac
            echo ""
        done
    } 2>&1 | 界面文本 "🧹 自定义清理"
    
    界面成功 "清理完成"
}

系统管理_服务菜单() {
    界面信息 "正在获取服务列表..."
    
    local items=()
    
    if 服务_是否Systemd; then
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
        界面消息 "无法获取服务列表" "错误"
        return
    fi
    
    local selected
    selected=$(界面选择 "🔧 服务管理" "选择服务:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    系统管理_服务操作 "$selected"
}

系统管理_服务操作() {
    local service="$1"
    local is_running
    
    if 服务_是否运行中 "$service"; then
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
    action=$(界面动作 "🔧 $service ($status_text)" "${actions[@]}")
    
    case "$action" in
        start)
            界面信息 "正在启动 $service..."
            服务_启动 "$service" && 界面成功 "$service 已启动" || 界面错误 "启动失败"
            ;;
        stop)
            if 界面确认 "确定要停止 $service 吗？"; then
                界面信息 "正在停止 $service..."
                服务_停止 "$service" && 界面成功 "$service 已停止" || 界面错误 "停止失败"
            fi
            ;;
        restart)
            if 界面确认 "确定要重启 $service 吗？"; then
                界面信息 "正在重启 $service..."
                服务_重启 "$service" && 界面成功 "$service 已重启" || 界面错误 "重启失败"
            fi
            ;;
        status)
            local status
            status=$(服务_状态 "$service" 2>/dev/null)
            界面文本 "$status" "🔧 $service 状态"
            ;;
        logs)
            local logs
            if 服务_是否Systemd; then
                logs=$(journalctl -u "$service" -n 100 --no-pager 2>/dev/null)
            else
                logs=$(tail -100 "/var/log/${service}.log" 2>/dev/null || echo "未找到日志")
            fi
            界面文本 "$logs" "📋 $service 日志"
            ;;
        enable)
            界面信息 "正在启用 $service 开机自启..."
            systemctl enable "$service" 2>/dev/null && 界面成功 "已启用开机自启" || 界面错误 "启用失败"
            ;;
        disable)
            界面信息 "正在禁用 $service 开机自启..."
            systemctl disable "$service" 2>/dev/null && 界面成功 "已禁用开机自启" || 界面错误 "禁用失败"
            ;;
    esac
}

系统管理_安全菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "🔒 安全加固" "请选择功能:" \
            "1" "防火墙状态" \
            "2" "启用防火墙" \
            "3" "禁用防火墙" \
            "4" "开放端口" \
            "5" "安全检查")
        
        case "$choice" in
            1) 系统管理_防火墙状态 ;;
            2) 系统管理_防火墙启用 ;;
            3) 系统管理_防火墙禁用 ;;
            4) 系统管理_防火墙开放端口 ;;
            5) 系统管理_安全检查 ;;
            b) break ;;
        esac
    done
}

系统管理_防火墙状态() {
    local status
    status=$(防火墙_状态 2>/dev/null)
    界面文本 "$status" "🔥 防火墙状态"
}

系统管理_防火墙启用() {
    if 界面确认 "确定要启用防火墙吗？"; then
        界面信息 "正在启用防火墙..."
        防火墙_启用 2>&1 && 界面成功 "防火墙已启用" || 界面错误 "启用失败"
    fi
}

系统管理_防火墙禁用() {
    if 界面确认 "确定要禁用防火墙吗？\n这可能会降低系统安全性"; then
        界面信息 "正在禁用防火墙..."
        防火墙_禁用 2>&1 && 界面成功 "防火墙已禁用" || 界面错误 "禁用失败"
    fi
}

系统管理_防火墙开放端口() {
    local port
    port=$(界面输入 "请输入要开放的端口号")
    
    [[ -z "$port" ]] && return
    
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then
        界面错误 "端口号必须是数字"
        return
    fi
    
    if 界面确认 "确定要开放端口 $port 吗？"; then
        界面信息 "正在开放端口 $port..."
        防火墙_开放端口 "$port" 2>&1 && 界面成功 "端口 $port 已开放" || 界面错误 "开放失败"
    fi
}

系统管理_安全检查() {
    界面信息 "正在进行安全检查..."
    
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
        防火墙_状态 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 开放端口 ==="
        网络_获取开放端口 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 最近登录 ==="
        last -n 5 2>/dev/null || echo "无法获取"
        
        echo ""
        echo "=== 失败登录尝试 ==="
        lastb -n 5 2>/dev/null || echo "无记录"
    })
    
    界面文本 "$result" "🔒 安全检查"
}

系统管理_时间菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "🕐 时间管理" "请选择功能:" \
            "1" "当前时间" \
            "2" "设置时区" \
            "3" "同步时间")
        
        case "$choice" in
            1) 系统管理_显示时间 ;;
            2) 系统管理_设置时区 ;;
            3) 系统管理_同步时间 ;;
            b) break ;;
        esac
    done
}

系统管理_显示时间() {
    local time_info
    time_info=$({
        echo "当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "时区: $(timedatectl show --property=Timezone --value 2>/dev/null || { cat /etc/timezone 2>/dev/null;} || echo '未知'; )" 
        echo "运行时间: $(uptime -p 2>/dev/null || uptime)"
    })
    
    界面文本 "$time_info" "🕐 当前时间"
}

系统管理_设置时区() {
    local timezones=(
        "Asia/Shanghai" "亚洲/上海"
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
    selected=$(界面选择 "🌏 设置时区" "选择时区:" "${timezones[@]}")
    
    [[ -z "$selected" ]] && return
    
    界面信息 "正在设置时区为 $selected..."
    timedatectl set-timezone "$selected" 2>/dev/null && 界面成功 "时区已设置为 $selected" || 界面错误 "设置失败"
}

系统管理_同步时间() {
    界面信息 "正在同步时间..."
    
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true 2>/dev/null
    fi
    
    系统_同步时间 2>/dev/null && 界面成功 "时间同步成功" || 界面错误 "时间同步失败"
}

系统管理_用户菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "👤 用户管理" "请选择功能:" \
            "1" "用户列表" \
            "2" "添加用户" \
            "3" "删除用户" \
            "4" "修改密码")
        
        case "$choice" in
            1) 系统管理_用户列表 ;;
            2) 系统管理_添加用户 ;;
            3) 系统管理_删除用户 ;;
            4) 系统管理_用户改密 ;;
            b) break ;;
        esac
    done
}

系统管理_用户列表() {
    local users
    users=$(cat /etc/passwd | awk -F: '$3 >= 1000 || $3 == 0 {printf "%-15s UID:%-5s Shell: %s\n", $1, $3, $7}')
    界面文本 "$users" "👤 用户列表"
}

系统管理_添加用户() {
    local username
    username=$(界面输入 "请输入新用户名")
    
    [[ -z "$username" ]] && return
    
    if id "$username" &>/dev/null; then
        界面消息 "用户 $username 已存在" "错误"
        return
    fi
    
    界面信息 "正在创建用户 $username..."
    useradd -m -s /bin/bash "$username" 2>&1 && 界面成功 "用户 $username 创建成功" || 界面错误 "创建失败"
}

系统管理_删除用户() {
    local users=()
    while IFS= read -r line; do
        local name uid
        name=$(echo "$line" | cut -d: -f1)
        uid=$(echo "$line" | cut -d: -f3)
        if [[ "$uid" -ge 1000 ]]; then
            users+=("$name" "UID: $uid")
        fi
    done < /etc/passwd
    
    local selected
    selected=$(界面选择 "👤 删除用户" "选择要删除的用户:" "${users[@]}")
    
    [[ -z "$selected" ]] && return
    
    if 界面确认 "确定要删除用户 $selected 吗？\n这将同时删除用户主目录"; then
        userdel -r "$selected" 2>&1 && 界面成功 "用户 $selected 已删除" || 界面错误 "删除失败"
    fi
}

系统管理_用户改密() {
    local users=()
    while IFS= read -r line; do
        local name uid
        name=$(echo "$line" | cut -d: -f1)
        uid=$(echo "$line" | cut -d: -f3)
        if [[ "$uid" -ge 1000 ]]; then
            users+=("$name" "UID: $uid")
        fi
    done < /etc/passwd
    
    local selected
    selected=$(界面选择 "👤 修改密码" "选择用户:" "${users[@]}")
    
    [[ -z "$selected" ]] && return
    
    界面消息 "请在终端中输入新密码"
    passwd "$selected"
}

系统管理_进程菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "📊 进程管理" "请选择功能:" \
            "1" "进程列表" \
            "2" "搜索进程")
        
        case "$choice" in
            1) 系统管理_进程列表 ;;
            2) 系统管理_搜索进程 ;;
            b) break ;;
        esac
    done
}

系统管理_进程列表() {
    local items_data
    items_data=$(网络_解析进程列表 "$(ps aux --sort=-%cpu | head -31)" 30)
    
    if [[ -z "$items_data" ]]; then
        界面消息 "无法获取进程列表" "错误"
        return
    fi
    
    local items_array=()
    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] && items_array+=("$key" "$value")
    done <<< "$items_data"
    
    local selected
    selected=$(界面选择 "📊 进程列表 (TOP 30 CPU)" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    系统管理_进程操作 "$selected"
}

系统管理_搜索进程() {
    local keyword
    keyword=$(界面输入 "请输入进程名称关键词")
    
    [[ -z "$keyword" ]] && return
    
    local items_data
    items_data=$(网络_解析进程列表 "$(ps aux | grep -i "$keyword" | grep -v grep | head -21)" 20)
    
    if [[ -z "$items_data" ]]; then
        界面消息 "未找到匹配的进程" "提示"
        return
    fi
    
    local items_array=()
    while IFS=$'\t' read -r key value; do
        [[ -n "$key" ]] && items_array+=("$key" "$value")
    done <<< "$items_data"  
    
    local selected
    selected=$(界面选择 "📊 搜索结果" "选择进程:" "${items_array[@]}")
    
    [[ -z "$selected" ]] && return
    
    系统管理_进程操作 "$selected"
}

系统管理_进程操作() {
    local pid="$1"
    
    local action
    action=$(界面动作 "📊 进程 $pid" \
        "kill" "终止进程" \
        "kill9" "强制终止" \
        "info" "查看详情" \
        "cancel" "返回")
    
    case "$action" in
        kill)
            if 界面确认 "确定要终止进程 $pid 吗？"; then
                kill "$pid" 2>&1 && 界面成功 "进程 $pid 已终止" || 界面错误 "终止失败"
            fi
            ;;
        kill9)
            if 界面确认 "确定要强制终止进程 $pid 吗？"; then
                kill -9 "$pid" 2>&1 && 界面成功 "进程 $pid 已强制终止" || 界面错误 "终止失败"
            fi
            ;;
        info)
            local info
            info=$(ps -p "$pid" -o pid,ppid,user,%cpu,%mem,stat,start,time,comm 2>/dev/null || echo "进程不存在")
            界面文本 "$info" "📊 进程详情"
            ;;
    esac
}

系统管理_磁盘菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "💾 磁盘分析" "请选择功能:" \
            "1" "磁盘使用" \
            "2" "目录大小" \
            "3" "大文件查找")
        
        case "$choice" in
            1) 系统管理_磁盘使用 ;;
            2) 系统管理_目录大小 ;;
            3) 系统管理_查找大文件 ;;
            b) break ;;
        esac
    done
}

系统管理_磁盘使用() {
    local usage
    usage=$(df -h 2>/dev/null)
    界面文本 "$usage" "💾 磁盘使用"
}

系统管理_目录大小() {
    local path
    path=$(界面输入 "请输入目录路径" "/")
    
    [[ -z "$path" ]] && return
    
    if [[ ! -d "$path" ]]; then
        界面消息 "目录不存在" "错误"
        return
    fi
    
    界面信息 "正在分析目录大小..."
    local result
    result=$(du -sh "$path"/* 2>/dev/null | sort -hr | head -20)
    界面文本 "$result" "💾 目录大小"
}

系统管理_查找大文件() {
    local path size
    path=$(界面输入 "请输入搜索路径" "/")
    size=$(界面输入 "请输入最小文件大小" "100M")
    
    [[ -z "$path" ]] && return
    
    if [[ ! -d "$path" ]]; then
        界面消息 "目录不存在" "错误"
        return
    fi
    
    界面信息 "正在搜索大文件..."
    
    local temp_file="${CONFIG[temp_dir]}/large_files.txt"
    find "$path" -type f -size "+$size" -exec ls -lh {} \; 2>/dev/null | head -50 > "$temp_file"
    
    if [[ ! -s "$temp_file" ]]; then
        界面消息 "未找到大于 $size 的文件" "提示"
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
    selected=$(界面选择 "💾 大文件列表" "选择文件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    local action
    action=$(界面动作 "💾 $selected" \
        "delete" "删除文件" \
        "view" "查看详情" \
        "cancel" "返回")
    
    case "$action" in
        delete)
            if 界面确认 "确定要删除文件 $selected 吗？\n\n此操作不可恢复！"; then
                rm -f "$selected" 2>&1 && 界面成功 "文件已删除" || 界面错误 "删除失败"
            fi
            ;;
        view)
            local info
            info=$(ls -lah "$selected" 2>/dev/null)
            info+="\n\n文件类型: $(file "$selected" 2>/dev/null | cut -d: -f2)"
            界面文本 "$info" "💾 文件详情"
            ;;
    esac
}

系统管理_重启() {
    if 界面确认 "确定要重启系统吗？"; then
        界面信息 "3秒后重启系统..."
        sleep 3
        reboot
    fi
}
