#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"
CONFIG_DIR="$PROJECT_ROOT/config"
NAPCAT_CONFIG_FILE="$CONFIG_DIR/napcat.yaml"
INSTALL_DIR=$(find /root/cs -maxdepth 1 -type d -iname "napcat" 2>/dev/null | head -1)

COMMON_PORTS=(80 443 22 3306 5432 6379 8080 3000 5000 8000 9000 27017)

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

get_port() {
    local default_port=$1
    local port=""
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

get_qq_number() {
    local qq=""
    while true; do
        qq=$(dialog --title "QQ 配置" --ok-label "确定" --cancel-label "返回" --inputbox "请输入要登录的 QQ 号:" 10 50 "" 2>&1 >/dev/tty)
        
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

check_dependencies() {
    echo "正在检查依赖..."
    if ! command -v git >/dev/null 2>&1; then
        echo "错误: git 未安装"
        dialog --title "错误" --msgbox "git 未安装，请先安装 git" 10 50
        return 1
    fi
    
    if ! command -v node >/dev/null 2>&1; then
        echo "错误: Node.js 未安装"
        dialog --title "错误" --msgbox "Node.js 未安装，请先安装 Node.js" 10 50
        return 1
    fi
    
    if ! command -v pnpm >/dev/null 2>&1; then
        echo "错误: pnpm 未安装"
        dialog --title "错误" --msgbox "pnpm 未安装，请先安装 pnpm (npm install -g pnpm)" 10 50
        return 1
    fi
    
    local node_version=$(node -v 2>/dev/null | sed 's/v//')
    local major_version=$(echo "$node_version" | cut -d. -f1)
    if [ "$major_version" -lt 18 ]; then
        echo "警告: Node.js 版本可能过低，建议使用 v18 或更高版本"
    fi
    
    return 0
}

napcat_install() {
    local auto_mode=false
    if [ "$NAPCAT_INSTALL" == "true" ]; then
        auto_mode=true
    fi
    
    if ! $auto_mode && [ -d "$INSTALL_DIR" ]; then
        dialog --title "NapCat 已安装" --yesno "NapCat 已安装在 $INSTALL_DIR，是否重新安装？" 10 60
        if [ $? -ne 0 ]; then
            return 0
        fi
    fi
    
    clear
    echo "========================================"
    echo "          NapCat 安装程序"
    echo "========================================"
    echo ""
    
    if ! check_dependencies; then
        return 1
    fi
    
    echo "获取配置信息..."
    local qq_number=$(get_qq_number)
    if [ $? -ne 0 ] || [ -z "$qq_number" ]; then
        return 1
    fi
    
    local port=$(get_port 5800)
    if [ $? -ne 0 ] || [ -z "$port" ]; then
        return 1
    fi
    
    dialog --title "确认安装" --yes-label "确定" --no-label "取消" --yesno "确认开始安装 NapCat？\n\nQQ 号: $qq_number\n端口: $port\n安装目录: $INSTALL_DIR" 12 60
    if [ $? -ne 0 ]; then
        return 0
    fi
    
    echo ""
    echo "========================================"
    echo "          开始安装"
    echo "========================================"
    echo ""
    
    if $auto_mode; then
        echo "项目管理模式：源码已下载，跳过克隆步骤"
    else
        if [ -d "$INSTALL_DIR" ]; then
            echo "备份现有配置..."
            if [ -f "$NAPCAT_CONFIG_FILE" ]; then
                cp "$NAPCAT_CONFIG_FILE" "$NAPCAT_CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
            fi
            rm -rf "$INSTALL_DIR"
        fi
        
        mkdir -p "$INSTALL_DIR"
        
        echo "克隆 NapCat 源码..."
        if ! git clone --depth 1 https://gh-proxy.org/https://github.com/NapNeko/NapCatQQ.git "$INSTALL_DIR" 2>&1; then
            echo "错误: 克隆源码失败"
            dialog --title "错误" --msgbox "克隆源码失败，请检查网络连接" 10 50
            rm -rf "$INSTALL_DIR"
            return 1
        fi
    fi
    
    if [ ! -d "$INSTALL_DIR" ]; then
        mkdir -p "$INSTALL_DIR"
    fi
    
    echo "安装依赖..."
    cd "$INSTALL_DIR"
    if ! pnpm install 2>&1; then
        echo "错误: 安装依赖失败"
        dialog --title "错误" --msgbox "安装依赖失败" 10 50
        return 1
    fi
    
    echo "生成配置文件..."
    mkdir -p "$(dirname "$NAPCAT_CONFIG_FILE")"
    
    cat > "$NAPCAT_CONFIG_FILE" << EOF
napcat:
  name: "NapCat"
  install_dir: "$INSTALL_DIR"
  qq_number: "$qq_number"
  port: $port
  status: "installed"
  installed_at: "$(date +"%Y-%m-%d %H:%M:%S")"
EOF
    
    echo "创建启动脚本..."
    cat > "$INSTALL_DIR/napcat.sh" << 'START_SCRIPT'
#!/bin/bash
cd "$(dirname "$0")"
while true; do
    echo "启动 NapCat $(date)"
    node .
    echo "NapCat 已退出，5 秒后自动重启..."
    sleep 5
done
START_SCRIPT
    chmod +x "$INSTALL_DIR/napcat.sh"
    
    echo ""
    echo "========================================"
    echo "          安装完成"
    echo "========================================"
    echo ""
    
    dialog --title "安装完成" --yes-label "启动服务" --no-label "返回" --yesno "NapCat 安装完成！\n\n现在启动服务并扫码登录？" 10 50
    if [ $? -eq 0 ]; then
        cd "$INSTALL_DIR"
        nohup ./napcat.sh > /dev/null 2>&1 &
        sleep 3
        
        if pgrep -f "napcat.sh" > /dev/null; then
            dialog --title "服务已启动" --msgbox "NapCat 服务已启动！\n\n请查看终端中的二维码进行扫码登录。" 10 50
            bash "$SCRIPT_DIR/manage.sh"
        else
            dialog --title "启动失败" --msgbox "NapCat 启动失败，请查看日志排查问题" 10 50
        fi
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    napcat_install
fi
