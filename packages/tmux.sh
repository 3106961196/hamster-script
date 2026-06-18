#!/bin/bash

# 配置变量
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
SESSION_NAME="🐹 Hamster Script"
TMUX_CONF="${INSTALL_DIR}/config/tmux/.tmux.conf"
WINDOW_A="${INSTALL_DIR}/config/tmux/window_a.sh"
WINDOW_B="${INSTALL_DIR}/config/tmux/window_b.sh"

# 创建桌面端布局
create_desktop_layout() {
    tmux new-session -d -s "$SESSION_NAME" -n "甲" "bash ${WINDOW_A}; exec bash"
    tmux split-window -v -t "$SESSION_NAME":甲 "bash ${WINDOW_B}; exec bash"
    tmux new-window -t "$SESSION_NAME" -n "乙" "bash ${WINDOW_B}; exec bash"
    tmux split-window -v -t "$SESSION_NAME":乙 "bash ${WINDOW_B}; exec bash"
    tmux select-window -t "$SESSION_NAME":0
}

# 错误处理函数
handle_error() {
    echo "错误: $1" >&2
    exit 1
}

# 检查依赖
check_dependencies() {
    command -v tmux >/dev/null 2>&1 || handle_error "未安装 tmux"
    [ -f "$TMUX_CONF" ] || handle_error "配置文件不存在: $TMUX_CONF"
    [ -f "$WINDOW_A" ] || handle_error "window_a.sh 不存在"
    [ -f "$WINDOW_B" ] || handle_error "window_b.sh 不存在"
}

# 主函数
main() {
    check_dependencies

    if [ -n "$TMUX" ]; then
        tmux source-file "$TMUX_CONF"
        return
    fi

    if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
        if ! tmux list-windows -t "$SESSION_NAME" | grep -q "甲" || ! tmux list-windows -t "$SESSION_NAME" | grep -q "乙"; then
            tmux kill-session -t "$SESSION_NAME"
            create_desktop_layout
        fi
    else
        create_desktop_layout
    fi

    tmux source-file "$TMUX_CONF"
    tmux attach-session -t "$SESSION_NAME"
}

main
