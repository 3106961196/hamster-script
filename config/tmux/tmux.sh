#!/bin/bash
# Hamster tmux 桌面入口（对齐 xrk-projects-scripts/body/tmux.sh）

INSTALL_DIR="${HAMSTER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
SESSION_NAME="${HAMSTER_TMUX_SESSION:-🐹 Hamster Script}"
TMUX_CONF="${HOME}/.tmux.conf"
read -ra HAMSTER_TMUX_WINDOWS <<< "${HAMSTER_TMUX_WINDOW_NAMES:-甲 乙}"

_hamster_work_dir() {
    if [[ -n "${HAMSTER_WORK_DIR:-}" ]]; then
        echo "$HAMSTER_WORK_DIR"
        return
    fi
    if [[ -f /etc/hamster-scripts/config.yaml ]]; then
        local wd
        wd=$(grep -E '^work_dir:' /etc/hamster-scripts/config.yaml 2>/dev/null | awk '{print $2}')
        if [[ -n "$wd" ]]; then
            echo "$wd"
            return
        fi
    fi
    echo "/root/cs"
}

WORK_DIR="$(_hamster_work_dir)"
mkdir -p "$WORK_DIR"

_tmux_usage() {
    cat <<EOF
用法: hamster-tmux [选项]
  (无参数)  进入或创建「${SESSION_NAME}」
  --setup   安装 tmux 并写入配置
  --status  检查环境
  -h        本帮助
EOF
}

_tmux_ensure_utf8() {
    case "${LANG:-}" in
        *UTF-8*|*utf8*) ;;
        *) export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8 ;;
    esac
}

_tmux_conf_ok() {
    [[ -f "$TMUX_CONF" ]] && grep -q 'Hamster Script tmux' "$TMUX_CONF" \
        && [[ -f "$HOME/.tmux/hamster-menus.conf" ]]
}

_tmux_reload_config() {
    [[ -f "$TMUX_CONF" ]] || return 1
    tmux info &>/dev/null || tmux -f "$TMUX_CONF" start-server 2>/dev/null || return 1
    tmux source-file "$TMUX_CONF" 2>/dev/null || return 1
}

_tmux_repair_config() {
    [[ -f "$INSTALL_DIR/config/tmux/setup.sh" ]] \
        && bash "$INSTALL_DIR/config/tmux/setup.sh" --link-only
}

_tmux_apply_window_names() {
    local session="$1" i
    tmux has-session -t "$session" 2>/dev/null || return 0
    for i in "${!HAMSTER_TMUX_WINDOWS[@]}"; do
        tmux rename-window -t "$session:$i" "${HAMSTER_TMUX_WINDOWS[$i]}" 2>/dev/null || true
    done
}

_tmux_session_usable() {
    local s="$1" n
    tmux has-session -t "$s" 2>/dev/null || return 1
    n=$(tmux list-windows -t "$s" 2>/dev/null | wc -l)
    [[ "${n:-0}" -ge 2 ]]
}

_tmux_status() {
    echo "tmux: $(command -v tmux >/dev/null && tmux -V || echo 未安装)"
    echo "配置: $TMUX_CONF $(_tmux_conf_ok && echo OK || echo 未就绪)"
    echo "工作目录: $WORK_DIR"
    tmux has-session -t "$SESSION_NAME" 2>/dev/null \
        && echo "会话: $SESSION_NAME 已存在" || echo "会话: 未创建"
}

_tmux_ensure_env() {
    command -v tmux &>/dev/null || {
        echo "[hamster-tmux] 未安装，请运行 hamster-tmux --setup" >&2
        return 1
    }
    _tmux_conf_ok || _tmux_repair_config || {
        echo "[hamster-tmux] 配置未就绪，请运行 hamster-tmux --setup" >&2
        return 1
    }
}

_tmux_create_layout() {
    local s="$SESSION_NAME"
    if _tmux_session_usable "$s"; then
        _tmux_apply_window_names "$s"
        return 0
    fi
    tmux has-session -t "$s" 2>/dev/null && tmux kill-session -t "$s" 2>/dev/null || true

    tmux new-session -d -s "$s" -n "${HAMSTER_TMUX_WINDOWS[0]}" -c "$WORK_DIR" \
        "printf '\033[1;32m使用 cs 命令打开脚本主菜单\033[0m\n'; exec bash"
    tmux split-window -v -t "$s:0" -c "$WORK_DIR" "exec bash"
    tmux new-window -t "$s:1" -n "${HAMSTER_TMUX_WINDOWS[1]:-乙}" -c "$WORK_DIR" "exec bash"
    tmux split-window -v -t "$s:1" -c "$WORK_DIR" "exec bash"
    tmux select-window -t "$s:0"
    _tmux_apply_window_names "$s"
}

_tmux_enter() {
    local cur
    _tmux_ensure_utf8
    _tmux_ensure_env || exit 1
    _tmux_reload_config || true
    _tmux_create_layout || exit 1
    _tmux_reload_config || true

    if [[ -n "$TMUX" ]]; then
        cur=$(tmux display-message -p '#S' 2>/dev/null || true)
        _tmux_apply_window_names "$SESSION_NAME"
        tmux display-message "配置已刷新" 2>/dev/null || true
        [[ "$cur" == "$SESSION_NAME" ]] && {
            echo "[hamster-tmux] 已在 $SESSION_NAME，配置已刷新"
            return 0
        }
        tmux switch-client -t "$SESSION_NAME"
        return 0
    fi

    echo "[hamster-tmux] 进入 $SESSION_NAME …"
    exec tmux attach-session -t "$SESSION_NAME"
}

case "${1:-}" in
    -h|--help)  _tmux_usage; exit 0 ;;
    --status)   _tmux_status; exit 0 ;;
    --setup)    bash "$INSTALL_DIR/config/tmux/setup.sh"; exit $? ;;
esac

_tmux_enter
