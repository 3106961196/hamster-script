#!/bin/bash
# XRK-AGT 管理脚本
# 供 project.mod.sh 通过 --auto 接口调用；无参数时进入交互菜单

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
load_lib "ui" 2>/dev/null || source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null
load_lib "log" 2>/dev/null || source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null
load_lib "pkg" 2>/dev/null || source "$PROJECT_ROOT/lib/pkg.sh" 2>/dev/null

REPO_URL="https://github.com/sunflowermm/XRK-AGT"
INSTALL_DIR="/root/cs/XRK-AGT"

# ─── 状态检测 ────────────────────────────────────────────────

_xrk_is_installed() {
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/package.json" ]]
}

_xrk_check_dependencies() {
    # Redis
    if ! command -v redis-cli &>/dev/null || ! redis-cli ping 2>/dev/null | grep -q "PONG"; then
        if command -v redis-server &>/dev/null; then
            ui_info "Redis 未运行，正在启动..."
            nohup redis-server --daemonize yes > /dev/null 2>&1 &
            sleep 1
        else
            ui_info "Redis 未安装，正在安装..."
            if pkg_install "redis-server" 2>&1 || pkg_install "redis" 2>&1; then
                nohup redis-server --daemonize yes > /dev/null 2>&1 &
                sleep 1
            else
                ui_msg "Redis 安装失败，XRK-AGT 可能无法正常运行" "错误"
            fi
        fi
    fi

    # MongoDB
    local mongo_ok=false
    if command -v mongosh &>/dev/null && mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; then
        mongo_ok=true
    elif command -v mongo &>/dev/null && mongo --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; then
        mongo_ok=true
    fi

    if [[ "$mongo_ok" == "false" ]]; then
        if command -v mongod &>/dev/null; then
            ui_info "MongoDB 未运行，正在启动..."
            mkdir -p /tmp/mongodb /tmp/mongolog 2>/dev/null
            nohup mongod --dbpath /tmp/mongodb --logpath /tmp/mongolog/mongod.log --fork > /dev/null 2>&1 &
            sleep 2
        else
            ui_info "MongoDB 未安装，正在安装..."
            if pkg_install "mongodb-org" 2>&1 || pkg_install "mongodb" 2>&1 || pkg_install "mongod" 2>&1; then
                mkdir -p /tmp/mongodb /tmp/mongolog 2>/dev/null
                nohup mongod --dbpath /tmp/mongodb --logpath /tmp/mongolog/mongod.log --fork > /dev/null 2>&1 &
                sleep 2
            else
                ui_msg "MongoDB 安装失败，XRK-AGT 可能无法正常运行" "错误"
            fi
        fi
    fi
}

_xrk_start_service() {
    if ! _xrk_is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _xrk_check_dependencies

    cd "$INSTALL_DIR"
    ui_info "正在启动 XRK-AGT..."
    node app.js
}

_xrk_start_debug() {
    if ! _xrk_is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _xrk_check_dependencies

    cd "$INSTALL_DIR"
    ui_info "正在以 Debug 模式启动 XRK-AGT..."
    node debug.js
}

_xrk_reinstall_project() {
    if ! _xrk_is_installed; then    
        ui_msg "XRK-AGT 未安装，请先使用安装功能" "错误"
        return 1
    fi

    if ! ui_confirm "重装 XRK-AGT 将会:\n1. 拉取最新代码\n2. 重新安装依赖\n\n确定继续？"; then
        return 0
    fi

    ui_info "正在拉取最新代码..."
    (
        cd "$INSTALL_DIR"
        git fetch --all
        git reset --hard origin/main 2>/dev/null || git reset --hard origin/master 2>/dev/null
    ) 2>&1

    ui_info "正在安装依赖..."
    cd "$INSTALL_DIR"
    # 跳过 puppeteer 浏览器下载 + 忽略 postinstall 脚本（避免 puppeteer 尝试下载 Chrome）
    export PUPPETEER_SKIP_DOWNLOAD=true
    pnpm i --ignore-scripts || npm install --ignore-scripts

    ui_success "XRK-AGT 重装完成！请手动启动服务"
}

_xrk_uninstall_project() {
    if ! _xrk_is_installed; then    
        ui_msg "XRK-AGT 未安装" "提示"
        return 0
    fi

    if ! ui_confirm "卸载 XRK-AGT 将会删除安装目录\n\n确定继续？"; then
        return 0
    fi

    pkill -f "node app.js" 2>/dev/null || true
    sleep 1
    rm -rf "$INSTALL_DIR"
    ui_success "XRK-AGT 已卸载"
}

# ─── 交互式菜单 ──────────────────────────────────────────────

xrk_manage() {
    while true; do
        local choice
        choice=$(ui_submenu "📁 XRK-AGT 管理" "请选择操作:" \
            "1" "🚀 启动 XRK-AGT" \
            "2" " Debug 启动 XRK-AGT" \
            "3" "🔄 重装 XRK-AGT" \
            "4" "🗑️  卸载 XRK-AGT")

        case "$choice" in
            1) _xrk_start_service ;;
            2) _xrk_start_debug ;;
            3) _xrk_reinstall_project ;;
            4) _xrk_uninstall_project && exit 0 ;;
            b) exit 0;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)        _xrk_start_service ;;
        debug)        _xrk_start_debug ;;
        reinstall)    _xrk_reinstall_project ;;
        is-installed) _xrk_is_installed && echo "yes" || echo "no" ;;
        uninstall)    _xrk_uninstall_project ;; 
        *)
            echo "用法: manage.sh --auto {start|debug|reinstall|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    xrk_manage
fi
