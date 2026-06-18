#!/bin/bash
# Hamster tmux 帮助 + F9/\\ 备用菜单
INSTALL_DIR="${HAMSTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
MENU="bash ${INSTALL_DIR}/config/tmux/tmux-menu.sh"

case "${1:-}" in
    help)
        tmux display-message -d 10000 \
            "Hamster tmux | 前缀 Alt+Space | F9 或 \\\\ 菜单 | 右键窗格
Alt+hjkl 切窗格 | v/s 分割 | [ y 复制 | Alt+0~5 切窗口 | cs 打开主菜单"
        ;;
    pane)
        tmux display-menu -T '#[align=centre]Hamster · 窗格' -t = -x C -y P \
            '复制模式' '[' 'copy-mode' \
            '左右分割' 'v' 'split-window -h -c "#{pane_current_path}"' \
            '上下分割' 's' 'split-window -v -c "#{pane_current_path}"' \
            '关闭窗格' 'w' 'kill-pane' \
            '帮助' 'h' "run-shell '${MENU} help || true'" \
            '重载' 'r' 'source-file ~/.tmux.conf \; display "配置已重载"' \
            '分离' 'd' 'detach-client' \
            || true
        ;;
    *)
        echo "用法: tmux-menu.sh help|pane" >&2
        exit 1
        ;;
esac
