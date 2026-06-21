#!/bin/bash
# XRK-AGT 管理脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
工具引导

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── 状态检测 ────────────────────────────────────────────────

_XRK_是否已安装() {
    工具_是否已安装 "xrk-agt"
}

_XRK_检查依赖() {
    # 检查并启动 Redis
    if ! command -v redis-cli &>/dev/null || ! redis-cli ping 2>/dev/null | grep -q "PONG"; then
        包管理_确保Redis
    fi

    # 检查并启动 MongoDB
    if ! command -v mongosh &>/dev/null || ! mongosh --eval "db.runCommand({ping:1})" --quiet 2>/dev/null; then
        包管理_确保MongoDB
    fi

    # 检查并安装 Chromium
    包管理_确保Chromium
}

_XRK_启动服务() {
    if ! _XRK_是否已安装; then
        界面消息 "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _XRK_检查依赖

    cd "$TOOL_INSTALL_DIR"
    界面信息 "正在启动 XRK-AGT..."
    node app.js
}

_XRK_启动调试() {
    if ! _XRK_是否已安装; then
        界面消息 "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    _XRK_检查依赖

    cd "$TOOL_INSTALL_DIR"
    界面信息 "正在以 Debug 模式启动 XRK-AGT..."
    node debug.js
}

_XRK_重装项目() {
    if ! _XRK_是否已安装; then
        界面消息 "XRK-AGT 未安装，请先使用安装功能" "错误"
        return 1
    fi

    if ! 界面确认 "重装 XRK-AGT 将会:\n1. 拉取最新代码\n2. 重新安装依赖\n\n确定继续？"; then
        return 0
    fi

    工具_更新 "xrk-agt"
    界面成功 "XRK-AGT 重装完成！请手动启动服务"
}

_XRK_卸载项目() {
    if ! _XRK_是否已安装; then
        界面消息 "XRK-AGT 未安装" "提示"
        return 0
    fi

    if ! 界面确认 "卸载 XRK-AGT 将会删除安装目录\n\n确定继续？"; then
        return 0
    fi

    工具_卸载 "xrk-agt"
}

# ─── 交互式菜单 ──────────────────────────────────────────────

XRK_管理() {
    while true; do
        local choice
        choice=$(界面子菜单 "📁 XRK-AGT 管理" "请选择操作:" \
            "1" "🚀 启动 XRK-AGT" \
            "2" "🐛 Debug 启动 XRK-AGT" \
            "3" "🔄 重装 XRK-AGT" \
            "4" "🗑️  卸载 XRK-AGT")

        case "$choice" in
            1) _XRK_启动服务 ;;
            2) _XRK_启动调试 ;;
            3) _XRK_重装项目 ;;
            4) _XRK_卸载项目 && exit 0 ;;
            b) exit 0;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)        _XRK_启动服务 ;;
        debug)        _XRK_启动调试 ;;
        reinstall)    _XRK_重装项目 ;;
        is-installed) _XRK_是否已安装 && echo "yes" || echo "no" ;;
        uninstall)    _XRK_卸载项目 ;;
        *)
            echo "用法: manage.sh --auto {start|debug|reinstall|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    XRK_管理
fi
