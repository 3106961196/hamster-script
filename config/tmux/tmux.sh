#!/bin/bash

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
Tmux_引导 "${BASH_SOURCE[0]}" || exit 1

SESSION_NAME="${HAMSTER_TMUX_SESSION:-🐹 Hamster Script}"
TMUX_HOME="$(Tmux_用户主目录)" || exit 1
TMUX_CONF="${TMUX_HOME}/.tmux.conf"
read -ra HAMSTER_TMUX_WINDOWS <<< "${HAMSTER_TMUX_WINDOW_NAMES:-甲 乙}"

mkdir -p "$WORK_DIR"

_Tmux启动服务() {
    [[ -f "$TMUX_CONF" ]] || return 1
    tmux info &>/dev/null || tmux -f "$TMUX_CONF" start-server 2>/dev/null || return 1
    tmux source-file "$TMUX_CONF" 2>/dev/null || return 1
}

_Tmux应用窗口名() {
    local session="$1" i
    tmux has-session -t "$session" 2>/dev/null || return 0
    for i in "${!HAMSTER_TMUX_WINDOWS[@]}"; do
        tmux rename-window -t "$session:$i" "${HAMSTER_TMUX_WINDOWS[$i]}" 2>/dev/null || true
    done
}

_Tmux确保会话() {
    local s="$SESSION_NAME"
    if tmux has-session -t "$s" 2>/dev/null; then
        _Tmux应用窗口名 "$s"
        return 0
    fi

    tmux new-session -d -s "$s" -n "${HAMSTER_TMUX_WINDOWS[0]}" -c "$WORK_DIR" \
        "printf '\033[1;32m使用 cs 命令打开脚本主菜单\033[0m\n'; exec bash"
    tmux split-window -v -t "$s:0" -c "$WORK_DIR"
    tmux new-window -t "$s:1" -n "${HAMSTER_TMUX_WINDOWS[1]:-乙}" -c "$WORK_DIR"
    tmux split-window -v -t "$s:1" -c "$WORK_DIR"
    tmux select-window -t "$s:0"
    _Tmux应用窗口名 "$s"
}

_Tmux进入() {
    Tmux_确保UTF8
    command -v tmux &>/dev/null || {
        echo "[hamster-tmux] 未安装，请运行 hamster-tmux --setup" >&2
        exit 1
    }
    Tmux_配置就绪 "$TMUX_HOME" || Tmux_链接配置 || {
        echo "[hamster-tmux] 配置未就绪，请运行 hamster-tmux --setup" >&2
        exit 1
    }
    _Tmux启动服务 || true
    _Tmux确保会话 || exit 1

    if [[ -n "$TMUX" ]]; then
        [[ "$(tmux display-message -p '#S' 2>/dev/null)" == "$SESSION_NAME" ]] \
            && echo "[hamster-tmux] 已在 $SESSION_NAME" \
            || tmux switch-client -t "$SESSION_NAME"
        return 0
    fi

    echo "[hamster-tmux] 进入 $SESSION_NAME …"
    exec tmux attach-session -t "$SESSION_NAME"
}

case "${1:-}" in
    -h|--help)
        cat <<EOF
用法: hamster-tmux [选项]
  (无参数)  进入或创建「${SESSION_NAME}」
  --setup   安装 tmux 并写入配置
  --status  检查环境
  -h        本帮助
EOF
        exit 0
        ;;
    --status)
        echo "tmux: $(command -v tmux >/dev/null && tmux -V || echo 未安装)"
        echo "配置: $TMUX_CONF $(Tmux_配置就绪 "$TMUX_HOME" && echo OK || echo 未就绪)"
        echo "工作目录: $WORK_DIR"
        if tmux has-session -t "$SESSION_NAME" 2>/dev/null; then
            echo "会话: $SESSION_NAME 已存在（$(tmux list-windows -t "$SESSION_NAME" 2>/dev/null | wc -l) 个窗口）"
        else
            echo "会话: 未创建"
        fi
        exit 0
        ;;
    --setup)
        exec bash "$INSTALL_DIR/config/tmux/setup.sh"
        ;;
esac

_Tmux进入
