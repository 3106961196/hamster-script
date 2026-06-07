#!/bin/bash
# NapCat 管理脚本
# 供 project.mod.sh 通过 --auto 接口调用；无参数时进入交互菜单

# 加载项目 UI 库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"
source "$PROJECT_ROOT/lib/core.sh" 2>/dev/null || true
if ! type ui_init &>/dev/null; then
    source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null || true
fi
if ! type log_info &>/dev/null; then
    source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null || true
fi

CONFIG_DIR="$PROJECT_ROOT/config"
NAPCAT_CONFIG_FILE="$CONFIG_DIR/napcat.yaml"
INSTALL_DIR=$(find /root/cs -maxdepth 1 -type d -iname "napcat" 2>/dev/null | head -1)
: "${INSTALL_DIR:=/root/cs/NapCat}"

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

# ─── 启动 ─────────────────────────────────────────────────────

napcat_start() {
    if is_running; then
        ui_msg "NapCat 已在运行中" "提示"
        return 0
    fi

    if [ ! -d "$INSTALL_DIR" ]; then
        ui_msg "NapCat 未安装" "错误"
        return 1
    fi

    ui_info "正在启动 NapCat..."
    cd "$INSTALL_DIR"
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3

    if is_running; then
        ui_success "NapCat 已启动！请查看终端中的二维码进行扫码登录。"
    else
        ui_error "NapCat 启动失败"
        return 1
    fi
}

# ─── 停止 ─────────────────────────────────────────────────────

napcat_stop() {
    if ! is_running; then
        ui_msg "NapCat 未在运行" "提示"
        return 0
    fi

    ui_info "正在停止 NapCat..."
    pkill -f "napcat.sh" 2>/dev/null
    sleep 2
    ui_success "NapCat 已停止"
}

# ─── 重启 ─────────────────────────────────────────────────────

napcat_restart() {
    if [ ! -d "$INSTALL_DIR" ]; then
        ui_msg "NapCat 未安装" "错误"
        return 1
    fi

    if ! ui_confirm "确定要重启 NapCat 吗？"; then
        return 0
    fi

    if is_running; then
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi

    ui_info "正在重启 NapCat..."
    cd "$INSTALL_DIR"
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3

    if is_running; then
        ui_success "NapCat 已重启！"
    else
        ui_error "NapCat 启动失败"
        return 1
    fi
}

# ─── 重装（更新源码） ─────────────────────────────────────────

napcat_update() {
    if [ ! -d "$INSTALL_DIR" ]; then
        ui_msg "NapCat 未安装" "错误"
        return 1
    fi

    if ! ui_confirm "更新 NapCat 将会:\n1. 停止当前服务\n2. 更新源码\n3. 重新安装依赖\n4. 保留配置文件\n\n确定继续？"; then
        return 0
    fi

    if is_running; then
        ui_info "停止 NapCat 服务..."
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi

    ui_info "备份配置文件..."
    if [ -f "$NAPCAT_CONFIG_FILE" ]; then
        cp "$NAPCAT_CONFIG_FILE" "$NAPCAT_CONFIG_FILE.backup.$(date +%Y%m%d%H%M%S)"
    fi

    ui_info "更新源码..."
    cd "$INSTALL_DIR"
    git fetch --all
    git reset --hard origin/main

    ui_info "安装依赖..."
    pnpm install

    ui_info "恢复配置文件..."
    if [ -f "$NAPCAT_CONFIG_FILE.backup" ]; then
        cp "$NAPCAT_CONFIG_FILE.backup" "$NAPCAT_CONFIG_FILE"
    fi

    ui_info "启动服务..."
    nohup ./napcat.sh > /dev/null 2>&1 &
    sleep 3

    if is_running; then
        ui_success "NapCat 已更新并启动！"
    else
        ui_error "NapCat 启动失败"
        return 1
    fi
}

# ─── 卸载 ─────────────────────────────────────────────────────

napcat_uninstall() {
    if [ ! -d "$INSTALL_DIR" ]; then
        ui_msg "NapCat 未安装" "提示"
        return 0
    fi

    if ! ui_confirm "卸载 NapCat 将会:\n1. 停止服务\n2. 删除安装目录\n3. 删除配置文件\n\n确定继续？"; then
        return 0
    fi

    if is_running; then
        pkill -f "napcat.sh" 2>/dev/null
        sleep 2
    fi

    rm -rf "$INSTALL_DIR"
    rm -f "$NAPCAT_CONFIG_FILE"
    ui_success "NapCat 已卸载"
}

# ─── 辅助函数（供 --auto 使用） ──────────────────────────────

show_status() {
    if is_running; then
        echo "运行中"
    else
        echo "已停止"
    fi
}

# ─── 交互式菜单 ──────────────────────────────────────────────

napcat_manage() {
    load_config

    while true; do
        local status="已停止"
        is_running && status="运行中"

        local choice
        choice=$(ui_submenu "📁 NapCat 管理" "请选择操作:" \
            "1" "🚀 启动 NapCat" \
            "2" "🛑 停止 NapCat" \
            "3" "🔄 重启 NapCat" \
            "4" "⬆️  重装 NapCat" \
            "5" "🗑️  卸载 NapCat")

        case "$choice" in
            1) napcat_start ;;
            2) napcat_stop ;;
            3) napcat_restart ;;
            4) napcat_update ;;
            5) napcat_uninstall ;;
            b) break ;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    load_config
    case "$2" in
        start)   napcat_start > /dev/null 2>&1 ;;
        stop)    napcat_stop > /dev/null 2>&1 ;;
        restart)
            napcat_stop > /dev/null 2>&1
            sleep 1
            napcat_start > /dev/null 2>&1
            ;;
        status)  show_status ;;
        is-installed) [ -d "$INSTALL_DIR" ] && echo "yes" || echo "no" ;;
        *)
            echo "用法: manage.sh --auto {start|stop|restart|status|is-installed}"
            exit 1
            ;;
    esac
else
    napcat_manage
fi
