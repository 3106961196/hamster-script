#!/bin/bash

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
Tmux_引导 "${BASH_SOURCE[0]}" || exit 1

SESSION_NAME="${HAMSTER_TMUX_SESSION:-🐹 Hamster Script}"
TMUX_HOME="$(Tmux_用户主目录)" || exit 1
TMUX_CONF="${TMUX_HOME}/.tmux/main.conf"
export HAMSTER_TMUX_CONF="$TMUX_CONF"
read -ra HAMSTER_TMUX_WINDOWS <<< "${HAMSTER_TMUX_WINDOW_NAMES:-甲 乙}"

mkdir -p "$WORK_DIR"

_Tmux重载配置() {
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

_Tmux会话可用() {
    local s="$1" n
    tmux has-session -t "$s" 2>/dev/null || return 1
    n=$(tmux list-windows -t "$s" 2>/dev/null | wc -l)
    [[ "${n:-0}" -ge 2 ]]
}

_Tmux创建布局() {
    local s="$SESSION_NAME"
    if _Tmux会话可用 "$s"; then
        _Tmux应用窗口名 "$s"
        return 0
    fi
    tmux has-session -t "$s" 2>/dev/null && tmux kill-session -t "$s" 2>/dev/null || true

    tmux new-session -d -s "$s" -n "${HAMSTER_TMUX_WINDOWS[0]}" -c "$WORK_DIR" \
        "printf '\033[1;32m使用 cs 命令打开脚本主菜单\033[0m\n'; exec bash"
    tmux split-window -v -t "$s:0" -c "$WORK_DIR" "exec bash"
    tmux new-window -t "$s:1" -n "${HAMSTER_TMUX_WINDOWS[1]:-乙}" -c "$WORK_DIR" "exec bash"
    tmux split-window -v -t "$s:1" -c "$WORK_DIR" "exec bash"
    tmux select-window -t "$s:0"
    _Tmux应用窗口名 "$s"
}

_Tmux进入() {
    local cur
    Tmux_确保UTF8
    command -v tmux &>/dev/null || {
        echo "[hamster-tmux] 未安装，请运行 hamster-tmux --setup" >&2
        exit 1
    }
    Tmux_配置就绪 "$TMUX_HOME" || Tmux_链接配置 || {
        echo "[hamster-tmux] 配置未就绪，请运行 hamster-tmux --setup" >&2
        exit 1
    }
    _Tmux重载配置 || true
    _Tmux创建布局 || exit 1
    _Tmux重载配置 || true

    if [[ -n "$TMUX" ]]; then
        cur=$(tmux display-message -p '#S' 2>/dev/null || true)
        _Tmux应用窗口名 "$SESSION_NAME"
        tmux display-message "配置已刷新" 2>/dev/null || true
        [[ "$cur" == "$SESSION_NAME" ]] && exit 0
        tmux switch-client -t "$SESSION_NAME"
        exit 0
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
        tmux has-session -t "$SESSION_NAME" 2>/dev/null \
            && echo "会话: $SESSION_NAME 已存在" || echo "会话: 未创建"
        exit 0
        ;;
    --setup)
        exec bash "$INSTALL_DIR/config/tmux/setup.sh"
        ;;
esac

_Tmux进入
