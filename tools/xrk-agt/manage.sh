#!/bin/bash
# XRK-AGT 管理脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
load_lib "tool"
load_lib "ui"

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── 状态检测 ────────────────────────────────────────────────

_xrk_is_installed() {
    tool_is_installed "xrk-agt"
}

_xrk_check_dependencies() {
    # 检查并启动 Redis
    if ! command -v redis-cli &>/dev/null || ! redis-cli ping 2>/dev/null | grep -q "PONG"; then
        pkg_ensure_redis
    fi

    # 检查并启动 MongoDB
    if ! command -v mongosh &>/dev/null || ! mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; then
        pkg_ensure_mongodb
    fi

    # 检查并安装 Chromium
    pkg_ensure_chromium
}

_xrk_start_service() {
    if ! _xrk_is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _xrk_check_dependencies

    cd "$TOOL_INSTALL_DIR"
    ui_info "正在启动 XRK-AGT..."
    node app.js
}

_xrk_start_debug() {
    if ! _xrk_is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _xrk_check_dependencies

    cd "$TOOL_INSTALL_DIR"
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

    tool_update "xrk-agt"
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

    tool_uninstall "xrk-agt"
}

# ─── 交互式菜单 ──────────────────────────────────────────────

xrk_manage() {
    while true; do
        local choice
        choice=$(ui_submenu "📁 XRK-AGT 管理" "请选择操作:" \
            "1" "🚀 启动 XRK-AGT" \
            "2" "🐛 Debug 启动 XRK-AGT" \
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
