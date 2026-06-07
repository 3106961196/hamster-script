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
        nohup node app.js > "$LOG_FILE" 2>&1 &
        echo $! > "$PID_FILE"
        disown $!
    fi

    sleep 3

    if is_running; then
        ui_success "XRK-AGT 已启动 (PID: $(get_pid))"
        if ui_confirm "是否进入控制台？"; then console_menu; fi
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

# ─── 控制台功能 ──────────────────────────────────────────────

console_logs() {
    local log_content
    if command -v pm2 &>/dev/null && pm2 describe xrk-agt &>/dev/null 2>&1; then
        log_content=$(pm2 logs xrk-agt --lines 100 --nostream --raw 2>/dev/null)
    elif [[ -f "$LOG_FILE" ]]; then
        log_content=$(tail -100 "$LOG_FILE" 2>/dev/null)
    else
        ui_msg "未找到日志文件" "提示"; return
    fi
    [ -z "$log_content" ] && log_content="暂无日志"
    ui_text "$log_content" "📋 XRK-AGT 日志（最近100行）"
}

console_tail() {
    local log_source="$LOG_FILE"
    if command -v pm2 &>/dev/null && pm2 describe xrk-agt &>/dev/null 2>&1; then
        log_source=$(pm2 info xrk-agt 2>/dev/null | grep "out log path" | awk "{print \$NF}")
        [ -z "$log_source" ] && log_source="$LOG_FILE"
    fi
    if [[ ! -f "$log_source" ]]; then
        ui_msg "未找到日志文件" "提示"; return
    fi
    ui_info "进入实时日志模式（按 Ctrl+C 返回）..."
    clear; tail -f "$log_source"
}

console_send() {
    if ! is_running; then
        ui_msg "XRK-AGT 未在运行，请先启动" "提示"; return
    fi
    local pid; pid=$(get_pid)
    [ -z "$pid" ] && { ui_msg "无法获取进程 PID" "错误"; return; }
    local cmd; cmd=$(ui_input "输入要发送的命令" "")
    [ -z "$cmd" ] && return
    echo "$cmd" > /proc/$pid/fd/0 2>/dev/null &&
        ui_success "命令已发送: $cmd" ||
        ui_error "命令发送失败（进程可能不支持标准输入）"
}

console_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "💻 XRK-AGT 控制台" "请选择操作:" \
            "1" "📋 查看日志" \
            "2" "📡 实时日志" \
            "3" "⌨️  发送命令")
        case "$choice" in
            1) console_logs ;;
            2) console_tail ;;
            3) console_send ;;
            b) break ;;
        esac
    done
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
            "3" "💻 控制台" \
            "4" "🔄 重装 XRK-AGT" \
            "5" "🗑️  卸载 XRK-AGT")

        case "$choice" in
            1) start_service ;;
            2) stop_service ;;
            3) console_menu ;;
            4) reinstall_project ;;
            5) uninstall_project ;;
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
