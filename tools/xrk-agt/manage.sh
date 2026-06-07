#!/bin/bash
# XRK-AGT 管理脚本
# 供 project.mod.sh 通过 --auto 接口调用；无参数时进入交互菜单

# 加载项目 UI 库
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"
source "$PROJECT_ROOT/lib/core.sh" 2>/dev/null || true
# 确保 ui 函数可用
if ! type ui_init &>/dev/null; then
    source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null || true
fi
if ! type log_info &>/dev/null; then
    source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null || true
fi

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
        [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && return 0
    fi
    pgrep -f "xrk-agt" > /dev/null 2>&1
}

get_pid() {
    if [[ -f "$PID_FILE" ]]; then
        cat "$PID_FILE" 2>/dev/null
    else
        pgrep -f "xrk-agt" 2>/dev/null | head -1
    fi
}

# ─── 启动 ─────────────────────────────────────────────────────

start_service() {
    if is_running; then
        ui_msg "XRK-AGT 已在运行中\nPID: $(get_pid)" "提示"
        return 0
    fi

    if ! is_installed; then
        ui_msg "XRK-AGT 未安装，请先安装" "错误"
        return 1
    fi

    ensure_log_dir

    cd "$INSTALL_DIR"
    ui_info "正在启动 XRK-AGT..."

    if command -v pm2 &>/dev/null; then
        pm2 start npm --name "xrk-agt" -- start > /dev/null 2>&1
        sleep 2
        local pid
        pid=$(pm2 pid xrk-agt 2>/dev/null)
        [[ -n "$pid" && "$pid" != "0" ]] && echo "$pid" > "$PID_FILE"
    else
        nohup npm start > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        disown $!
    fi

    sleep 3

    if is_running; then
        ui_success "XRK-AGT 已启动 (PID: $(get_pid))"
    else
        ui_error "XRK-AGT 启动失败，请检查日志: $LOG_FILE"
        return 1
    fi
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

    if command -v pm2 &>/dev/null && pm2 describe xrk-agt &>/dev/null; then
        pm2 stop xrk-agt > /dev/null 2>&1
        pm2 delete xrk-agt > /dev/null 2>&1
    fi

    if [[ -f "$PID_FILE" ]]; then
        local pid
        pid=$(cat "$PID_FILE")
        kill "$pid" 2>/dev/null
        rm -f "$PID_FILE"
    fi

    pkill -f "xrk-agt" 2>/dev/null
    sleep 1

    ui_success "XRK-AGT 已停止"
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
        if command -v pm2 &>/dev/null && pm2 describe xrk-agt &>/dev/null; then
            pm2 stop xrk-agt > /dev/null 2>&1
            pm2 delete xrk-agt > /dev/null 2>&1
        fi
        pkill -f "xrk-agt" 2>/dev/null
        sleep 1
        rm -f "$PID_FILE"
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
        if command -v pm2 &>/dev/null && pm2 describe xrk-agt &>/dev/null; then
            pm2 stop xrk-agt > /dev/null 2>&1
            pm2 delete xrk-agt > /dev/null 2>&1
        fi
        pkill -f "xrk-agt" 2>/dev/null
        sleep 1
        rm -f "$PID_FILE"
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
            "3" "🔄 重装 XRK-AGT" \
            "4" "🗑️  卸载 XRK-AGT")

        case "$choice" in
            1) start_service ;;
            2) stop_service ;;
            3) reinstall_project ;;
            4) uninstall_project ;;
            b) break ;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)   start_service > /dev/null 2>&1 ;;
        stop)    stop_service > /dev/null 2>&1 ;;
        restart)
            stop_service > /dev/null 2>&1
            sleep 1
            start_service > /dev/null 2>&1
            ;;
        status)  show_status ;;
        is-installed) is_installed && echo "yes" || echo "no" ;;
        *)
            echo "用法: manage.sh --auto {start|stop|restart|status|is-installed}"
            exit 1
            ;;
    esac
else
    xrk_manage
fi
