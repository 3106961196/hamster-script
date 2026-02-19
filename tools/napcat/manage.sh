#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
NAPCAT_CONFIG_FILE="$CONFIG_DIR/napcat.yaml"
INSTALL_DIR=$(find /root/cs -maxdepth 1 -type d -iname "napcat" 2>/dev/null | head -1)

load_config() {
    if [ -f "$NAPCAT_CONFIG_FILE" ]; then
        INSTALL_DIR=$(grep "install_dir:" "$NAPCAT_CONFIG_FILE" | awk '{print $2}')
        PORT=$(grep "port:" "$NAPCAT_CONFIG_FILE" | awk '{print $2}')
        QQ_NUMBER=$(grep "qq_number:" "$NAPCAT_CONFIG_FILE" | awk '{print $2}')
    fi
}

is_running() {
    pgrep -f "napcat.sh" > /dev/null 2>&1
}

napcat_start() {
    if is_running; then
        dialog --title "提示" --msgbox "NapCat 已在运行中" 10 40
        return 0
    fi
    
    if [ ! -d "$INSTALL_DIR" ]; then
        dialog --title "错误" --msgbox "NapCat 未安装" 10 40
        return 1
    fi
    
    cd "$INSTALL_DIR"
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3
    
    if is_running; then
        dialog --title "启动成功" --msgbox "NapCat 已启动！\n请查看终端中的二维码进行扫码登录。" 10 50
    else
        dialog --title "启动失败" --msgbox "NapCat 启动失败" 10 40
    fi
}

napcat_restart() {
    if ! is_running && [ ! -d "$INSTALL_DIR" ]; then
        dialog --title "提示" --msgbox "NapCat 未安装" 10 40
        return 0
    fi
    
    dialog --title "重启服务" --yes-label "确定" --no-label "取消" --yesno "确定要重启 NapCat 服务吗？" 10 50
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    if is_running; then
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi
    
    if [ -d "$INSTALL_DIR" ]; then
        cd "$INSTALL_DIR"
        nohup ./napcat.sh > /dev/null 2>&1 &
        sleep 3
        
        if is_running; then
            dialog --title "重启成功" --msgbox "NapCat 已重启！" 10 40
        else
            dialog --title "重启失败" --msgbox "NapCat 启动失败" 10 40
        fi
    fi
}

napcat_reconfig() {
    if [ ! -d "$INSTALL_DIR" ]; then
        dialog --title "错误" --msgbox "NapCat 未安装" 10 40
        return 1
    fi
    
    dialog --title "重新配置" --yes-label "确定" --no-label "取消" --yesno "重新配置将会重启服务，确定继续？" 10 50
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    if is_running; then
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi
    
    local qq_number=$(get_qq_number)
    if [ $? -ne 0 ] || [ -z "$qq_number" ]; then
        return 1
    fi
    
    local port=$(get_port "$PORT")
    if [ $? -ne 0 ] || [ -z "$port" ]; then
        return 1
    fi
    
    load_config
    
    cat > "$NAPCAT_CONFIG_FILE" << EOF
napcat:
  name: "NapCat"
  install_dir: "$INSTALL_DIR"
  qq_number: "$qq_number"
  port: $port
  status: "installed"
  installed_at: "$(date +"%Y-%m-%d %H:%M:%S")"
EOF
    
    cd "$INSTALL_DIR"
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3
    
    if is_running; then
        dialog --title "配置完成" --msgbox "配置已更新并重启服务！\n请查看终端中的二维码进行扫码登录。" 10 50
    else
        dialog --title "启动失败" --msgbox "服务启动失败" 10 40
    fi
}

get_qq_number() {
    local default_qq=$QQ_NUMBER
    local qq=""
    while true; do
        qq=$(dialog --title "QQ 配置" --ok-label "确定" --cancel-label "返回" --inputbox "请输入要登录的 QQ 号:" 10 50 "$default_qq" 2>&1 >/dev/tty)
        
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        if [ -z "$qq" ]; then
            dialog --title "错误" --msgbox "QQ 号不能为空" 10 50
            continue
        fi
        
        if ! [[ "$qq" =~ ^[0-9]+$ ]]; then
            dialog --title "错误" --msgbox "QQ 号必须是数字" 10 50
            continue
        fi
        
        if [ "$qq" -lt 10000 ]; then
            dialog --title "错误" --msgbox "QQ 号格式不正确" 10 50
            continue
        fi
        
        echo "$qq"
        return 0
    done
}

get_port() {
    local default_port=$1
    local port=""
    local COMMON_PORTS=(80 443 22 3306 5432 6379 8080 3000 5000 8000 9000 27017)
    
    is_port_available() {
        local port=$1
        if command -v ss >/dev/null 2>&1; then
            ss -tuln 2>/dev/null | grep -q ":$port " && return 1
        elif command -v netstat >/dev/null 2>&1; then
            netstat -tuln 2>/dev/null | grep -q ":$port " && return 1
        fi
        return 0
    }
    
    is_common_port() {
        local port=$1
        for common_port in "${COMMON_PORTS[@]}"; do
            if [ "$port" -eq "$common_port" ]; then
                return 0
            fi
        done
        return 1
    }
    
    while true; do
        port=$(dialog --title "端口配置" --ok-label "确定" --cancel-label "返回" --inputbox "请输入 NapCat API 服务端口 (1-65535):" 10 60 "$default_port" 2>&1 >/dev/tty)
        
        if [ $? -ne 0 ]; then
            return 1
        fi
        
        if [ -z "$port" ]; then
            dialog --title "错误" --msgbox "端口号不能为空" 10 50
            continue
        fi
        
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            dialog --title "错误" --msgbox "端口号必须是 1-65535 之间的数字" 10 50
            continue
        fi
        
        if ! is_port_available "$port"; then
            if is_common_port "$port"; then
                dialog --title "端口冲突" --yesno "端口 $port 是常用端口，可能已被占用。建议更换其他端口。\n\n是否使用此端口？" 12 60
                if [ $? -ne 0 ]; then
                    continue
                fi
            else
                dialog --title "端口冲突" --msgbox "端口 $port 已被占用，请使用其他端口" 10 50
                continue
            fi
        fi
        
        echo "$port"
        return 0
    done
}

napcat_update() {
    if [ ! -d "$INSTALL_DIR" ]; then
        dialog --title "错误" --msgbox "NapCat 未安装" 10 40
        return 1
    fi
    
    dialog --title "更新 NapCat" --yes-label "确定" --no-label "取消" --yesno "更新 NapCat 将会:\n1. 停止当前服务\n2. 更新源码\n3. 重新安装依赖\n4. 保留配置文件\n\n确定继续？" 15 60
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    if is_running; then
        echo "停止 NapCat 服务..."
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi
    
    echo "备份配置文件..."
    if [ -f "$NAPCAT_CONFIG_FILE" ]; then
        cp "$NAPCAT_CONFIG_FILE" "$NAPCAT_CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi
    
    echo "更新源码..."
    cd "$INSTALL_DIR"
    git fetch --all
    git reset --hard origin/main
    
    echo "安装依赖..."
    pnpm install
    
    echo "恢复配置文件..."
    if [ -f "$NAPCAT_CONFIG_FILE.backup" ]; then
        cp "$NAPCAT_CONFIG_FILE.backup" "$NAPCAT_CONFIG_FILE"
    fi
    
    echo "启动服务..."
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3
    
    if is_running; then
        dialog --title "更新成功" --msgbox "NapCat 已更新并启动！" 10 40
    else
        dialog --title "启动失败" --msgbox "服务启动失败" 10 40
    fi
}

napcat_uninstall() {
    if [ ! -d "$INSTALL_DIR" ]; then
        dialog --title "提示" --msgbox "NapCat 未安装" 10 40
        return 0
    fi
    
    dialog --title "卸载 NapCat" --yes-label "确定" --no-label "取消" --yesno "卸载 NapCat 将会:\n1. 停止服务\n2. 删除安装目录\n3. 删除配置文件\n\n确定继续？" 15 60
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    if is_running; then
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi
    
    rm -rf "$INSTALL_DIR"
    rm -f "$NAPCAT_CONFIG_FILE"
    
    dialog --title "卸载完成" --msgbox "NapCat 已卸载" 10 40
}

napcat_manage() {
    load_config
    
    while true; do
        local status="已停止"
        local status_num=1
        if is_running; then
            status="运行中"
            status_num=2
        fi
        
        choice=$(dialog --title "NapCat 管理 - $status" --ok-label "确定" --cancel-label "返回" --menu "请选择操作:" 15 50 6 \
            1 "启动服务" \
            2 "重启服务" \
            3 "重新配置" \
            4 "更新版本" \
            5 "卸载项目" \
            b "返回" 2>&1 >/dev/tty)
        
        if [ $? -ne 0 ] || [ "$choice" == "b" ]; then
            break
        fi
        
        case $choice in
            1) napcat_start ;;
            2) napcat_restart ;;
            3) napcat_reconfig ;;
            4) napcat_update ;;
            5) napcat_uninstall; if [ $? -eq 0 ]; then break; fi ;;
        esac
    done
}

if [ "$1" == "--auto" ]; then
    load_config
    case "$2" in
        start) napcat_start ;;
        restart) napcat_restart ;;
        stop) pkill -f "napcat.sh" 2>/dev/null ;;
        status) is_running && echo "运行中" || echo "已停止" ;;
        *) echo "用法: manage.sh {start|restart|stop|status}" ;;
    esac
else
    napcat_manage
fi
