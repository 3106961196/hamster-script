#!/bin/bash
# Hamster tmux 帮助 + F9/\\ 备用菜单（完整右键菜单见 tmux-menus.conf）

Tmux_菜单脚本路径() {
    local install_dir="${HAMSTER_ROOT:-${INSTALL_DIR:-}}"
    [[ -n "$install_dir" ]] || install_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
    echo "bash ${install_dir}/config/tmux/tmux-menu.sh"
}

Tmux_重载命令() {
    local conf="${HAMSTER_TMUX_CONF:-${HOME}/.tmux/main.conf}"
    echo "source-file ${conf} \\; display \"配置已重载\""
}

MENU="$(Tmux_菜单脚本路径)"
RELOAD="$(Tmux_重载命令)"

case "${1:-}" in
    help)
        tmux display-message -d 10000 \
            "Hamster tmux | 前缀 Alt+Space | F9 或 \\\\ 菜单
右键: 窗格 / 会话(左) / 窗口(中) / 系统(右)
Alt+hjkl 切窗格 | v/s 分割 | cs 打开主菜单"
        ;;
    pane)
        tmux display-menu -T '#[align=centre]Hamster · 窗格' -t = -x C -y P \
            '复制模式' '[' 'copy-mode' \
            '左右分割' 'v' 'split-window -h -c "#{pane_current_path}"' \
            '上下分割' 's' 'split-window -v -c "#{pane_current_path}"' \
            '关闭窗格' 'w' 'kill-pane' \
            '帮助' 'h' "run-shell '${MENU} help || true'" \
            '重载' 'r' "${RELOAD}" \
            '分离' 'd' 'detach-client' \
            || true
        ;;
    *)
        echo "用法: tmux-menu.sh help|pane" >&2
        exit 1
        ;;
esac
