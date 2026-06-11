#!/bin/bash

# 配置变量
SESSION_NAME="🐹 Hamster Script"
TMUX_CONF="/cs/config/tmux/.tmux.conf"

# 创建桌面端布局
create_desktop_layout() {
    tmux new-session -d -s "$SESSION_NAME" -n "甲" "bash /cs/config/tmux/window_a.sh; exec bash"
    tmux split-window -v -t "$SESSION_NAME":甲 "bash /cs/config/tmux/window_b.sh; exec bash"
    tmux new-window -t "$SESSION_NAME" -n "乙" "bash /cs/config/tmux/window_b.sh; exec bash"
    tmux split-window -v -t "$SESSION_NAME":乙 "bash /cs/config/tmux/window_b.sh; exec bash"
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
    [ -f "/cs/config/tmux/window_a.sh" ] || handle_error "window_a.sh 不存在"
    [ -f "/cs/config/tmux/window_b.sh" ] || handle_error "window_b.sh 不存在"
}

TPM_DIR="/cs/config/tmux/plugins/tpm"

# 安装/更新 TPM
setup_tpm() {
    if [ ! -d "$TPM_DIR" ]; then
        echo "正在安装 TPM..."
        mkdir -p "$(dirname "$TPM_DIR")"
        git clone --depth 1 https://github.com/tmux-plugins/tpm "$TPM_DIR" || {
            echo "警告: TPM 克隆失败，插件功能将不可用"
            return 1
        }
        echo "TPM 安装完成"
    fi
}

# 在 tmux 会话内安装插件
install_plugins_in_session() {
    # 检查是否有插件已安装
    local plugin_count
    plugin_count=$(find "$TPM_DIR/../" -mindepth 1 -maxdepth 1 -type d ! -name "tpm" 2>/dev/null | wc -l)
    if [ "$plugin_count" -eq 0 ]; then
        echo "正在安装 tmux 插件（首次可能需要几分钟）..."
        # 先重载配置，让 @plugin 变量生效
        tmux source-file "$TMUX_CONF"
        sleep 1
        # 在 tmux 内运行安装脚本
        tmux run-shell "$TPM_DIR/bin/install_plugins"
        # 等待安装完成
        sleep 3
        echo "插件安装完成"
    fi
}

# 主函数
main() {
    check_dependencies
    setup_tpm

    if [ -n "$TMUX" ]; then
        tmux source-file "$TMUX_CONF"
        install_plugins_in_session
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
    install_plugins_in_session
    tmux attach-session -t "$SESSION_NAME"
}

main
