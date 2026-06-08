#!/bin/bash
# XRK-AGT 管理脚本
# 供 project.mod.sh 通过 --auto 接口调用；无参数时进入交互菜单

# 加载项目 UI 库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

# 加载项目 UI 库
source "$PROJECT_ROOT/lib/core.sh"
load_lib "ui" 2>/dev/null || source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null
load_lib "log" 2>/dev/null || source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null

REPO_URL="https://github.com/sunflowermm/XRK-AGT"
INSTALL_DIR="/root/cs/XRK-AGT"
LOG_DIR="${PROJECT_ROOT}/log"
LOG_FILE="${LOG_DIR}/xrk-agt.log"
PID_FILE="/tmp/xrk-agt.pid"

ensure_log_dir() {
    mkdir -p "$LOG_DIR"
}

# ─── 状态检测 ────────────────────────────────────────────────

is_installed() {
    [[ -d "$INSTALL_DIR" && -f "$INSTALL_DIR/package.json" ]]
}

is_running() {
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null)
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            # 验证 PID 确实指向 node app.js 进程
            local cmdline
            cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
            if echo "$cmdline" | grep -q "node.*app\.js"; then
                return 0
            fi
        fi
        # PID_FILE 中的 PID 无效，清理
        rm -f "$PID_FILE"
    fi
    return 1
}

get_pid() {
    if [[ -f "$PID_FILE" ]]; then
        cat "$PID_FILE" 2>/dev/null
    else
        echo ""
    fi
}

# ─── 启动 ─────────────────────────────────────────────────────

start_service() {
    if ! is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    cd "$INSTALL_DIR"

    ui_info "正在启动 XRK-AGT..."
    node app.js
}

# ─── Debug 启动 ─────────────────────────────────────────────────────

start_debug() {
    if ! is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    cd "$INSTALL_DIR"

    ui_info "正在以 Debug 模式启动 XRK-AGT..."
    node debug.js
}

# ─── 停止 ─────────────────────────────────────────────────────

stop_service() {
    if ! is_running; then
        ui_msg "XRK-AGT 未在运行" "提示"
        return 0
    fi

    if ! ui_confirm "确定要停止 XRK-AGT 吗？"; then
        return 0
    fi

    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        sleep 1
        # 如果没杀掉，强杀
        kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi

    # 兜底：防止 PID_FILE 不准
    pkill -f "node app.js" 2>/dev/null || true
    sleep 1

    ui_success "XRK-AGT 已停止"
}

# ─── 重启 ─────────────────────────────────────────────────────

restart_service() {
    # 停止现有进程
    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null || true
        rm -f "$PID_FILE"
    fi
    pkill -f "node app.js" 2>/dev/null || true
    sleep 1

    cd "$INSTALL_DIR"

    ui_info "正在重启 XRK-AGT..."
    node app.js
}

# ─── 重装 ─────────────────────────────────────────────────────

reinstall_project() {
    if ! is_installed; then
        ui_msg "XRK-AGT 未安装，请先使用安装功能" "错误"
        return 1
    fi

    if ! ui_confirm "重装 XRK-AGT 将会:\n1. 停止当前服务\n2. 拉取最新代码\n3. 重新安装依赖\n\n确定继续？"; then
        return 0
    fi

    # 停止服务
    if is_running; then
        if [[ -f "$PID_FILE" ]]; then
            local pid
            pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
        fi
        pkill -f "node app.js" 2>/dev/null || true
        sleep 1
    fi

    ui_info "正在拉取最新代码..."
    (
        cd "$INSTALL_DIR"
        git fetch --all
        git reset --hard origin/main 2>/dev/null || git reset --hard origin/master 2>/dev/null
    ) 2>&1

    ui_info "正在安装依赖..."
    cd "$INSTALL_DIR"
    if [[ -f "pnpm-lock.yaml" ]]; then
        pnpm install
    elif [[ -f "yarn.lock" ]]; then
        yarn install
    else
        npm install
    fi

    ui_success "XRK-AGT 重装完成！请手动启动服务"
}

# ─── 卸载 ─────────────────────────────────────────────────────

uninstall_project() {
    if ! is_installed; then
        ui_msg "XRK-AGT 未安装" "提示"
        return 0
    fi

    if ! ui_confirm "卸载 XRK-AGT 将会:\n1. 停止服务\n2. 删除安装目录\n\n确定继续？"; then
        return 0
    fi

    if is_running; then
        if [[ -f "$PID_FILE" ]]; then
            local pid
            pid=$(cat "$PID_FILE")
            kill "$pid" 2>/dev/null; sleep 1; kill -9 "$pid" 2>/dev/null || true
            rm -f "$PID_FILE"
        fi
        # 兜底
        pkill -f "node app.js" 2>/dev/null || true
        sleep 1
    fi

    rm -rf "$INSTALL_DIR"
    ui_success "XRK-AGT 已卸载"
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

xrk_manage() {
    while true; do
        local status="已停止"
        is_running && status="运行中"

        local choice
        choice=$(ui_submenu "📁 XRK-AGT 管理" "请选择操作:" \
            "1" "🚀 启动 XRK-AGT" \
            "2" "🛑 停止 XRK-AGT" \
            "3" "🔄 重启 XRK-AGT" \
            "6" "🐛 Debug 启动 XRK-AGT" \
            "4" "🔄 重装 XRK-AGT" \
            "5" "🗑️  卸载 XRK-AGT")

        case "$choice" in
            1) start_service ;;
            2) stop_service ;;
            3) restart_service ;;
            6) start_debug ;;
            4) reinstall_project ;;
            5) uninstall_project ;;
            b) break ;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)   start_service ;;
        stop)    stop_service > /dev/null 2>&1 ;;
        restart)   restart_service ;;
        status)  show_status ;;
        is-installed) is_installed && echo "yes" || echo "no" ;;
        uninstall) uninstall_project ;;
        *)
            echo "用法: manage.sh --auto {start|stop|restart|status|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    xrk_manage
fi
