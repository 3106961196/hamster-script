#!/bin/bash

UI_TITLE="${UI_TITLE:-Hamster Script}"
UI_BACKTITLE="${UI_BACKTITLE:-${PROJECT_NAME:-Hamster} v${PROJECT_VERSION:-}}"

界面初始化() {
    if ! command -v dialog &>/dev/null; then
        echo "错误: dialog 未安装，菜单功能不可用" >&2
        return 1
    fi
    export DIALOGRC="${DIALOGRC:-}"
    return 0
}

# ─── 内部辅助 ────────────────────────────────────────────────

_界面_终端尺寸() {
    local lines cols
    lines=$(tput lines 2>/dev/null || echo 24)
    cols=$(tput cols 2>/dev/null || echo 80)
    [[ "$lines" -lt 12 ]] && lines=12
    [[ "$cols" -lt 60 ]] && cols=60
    echo "$lines $cols"
}

_界面_计算菜单尺寸() {
    local item_pairs="$1"
    local lines cols box_h box_w menu_h
    read -r lines cols < <(_界面_终端尺寸)

    menu_h=$((item_pairs + 2))
    [[ $menu_h -lt 6 ]] && menu_h=6
    [[ $menu_h -gt 16 ]] && menu_h=16

    box_h=$((menu_h + 7))
    [[ $box_h -gt $((lines - 2)) ]] && box_h=$((lines - 2))
    [[ $box_h -lt 12 ]] && box_h=12

    box_w=74
    [[ $cols -lt 80 ]] && box_w=$((cols - 6))
    [[ $box_w -lt 58 ]] && box_w=58

    echo "$box_h $box_w $menu_h"
}

_界面_转义文本() {
    printf '%b' "$1"
}

# dialog 关闭后恢复终端，避免残留 TUI/安装日志叠在下层菜单上
_界面_重置终端() {
    local tty_out="/dev/tty"
    [[ ! -e "$tty_out" ]] && tty_out="/dev/stdout"

    tput rmcup >"$tty_out" 2>/dev/null || true
    printf '\033[?1049l\033[?25h\033[0m' >"$tty_out" 2>/dev/null || true
    tput cnorm >"$tty_out" 2>/dev/null || true
    tput sgr0 >"$tty_out" 2>/dev/null || true
    tput reset >"$tty_out" 2>/dev/null || true
    clear >"$tty_out" 2>/dev/null || clear 2>/dev/null || true
}

_界面_消息框尺寸() {
    local text="$1"
    local lines cols box_h box_w len
    read -r lines cols < <(_界面_终端尺寸)
    len=$(printf '%b' "$text" | wc -l | tr -d ' ')
    box_h=$((len + 8))
    [[ $box_h -lt 8 ]] && box_h=8
    [[ $box_h -gt $((lines - 2)) ]] && box_h=$((lines - 2))
    box_w=68
    [[ $cols -lt 74 ]] && box_w=$((cols - 6))
    echo "$box_h $box_w"
}

# dialog 统一入口：--clear 绘制前清屏，关闭后再重置
_界面_dialog() {
    local rc=0
    dialog --clear --backtitle "$UI_BACKTITLE" "$@" 2>/dev/tty || rc=$?
    _界面_重置终端
    return "$rc"
}

# ─── 核心菜单函数 ─────────────────────────────────────────

_界面选择对话框() {
    local title="$1"
    local prompt="$2"
    local extra_key="$3"
    local extra_label="$4"
    local mode="${5:-menu}"
    shift 5
    local items=("$@")

    local pair_count=$(( ${#items[@]} / 2 ))
    [[ -n "$extra_key" && -n "$extra_label" ]] && pair_count=$((pair_count + 1))

    local box_h box_w menu_h
    read -r box_h box_w menu_h < <(_界面_计算菜单尺寸 "$pair_count")

    local box_type="--menu"
    [[ "$mode" == "checklist" ]] && box_type="--checklist"

    local cmd=(dialog --clear --stdout --backtitle "$UI_BACKTITLE" --title "$title"
        "$box_type" "$prompt" "$box_h" "$box_w" "$menu_h")

    local i=0
    while [[ $i -lt ${#items[@]} ]]; do
        cmd+=("${items[$i]}" "${items[$((i + 1))]}")
        i=$((i + 2))
    done

    if [[ -n "$extra_key" && -n "$extra_label" ]]; then
        cmd+=("$extra_key" "$extra_label")
    fi

    local result rc=0
    _界面_重置终端
    result=$("${cmd[@]}" 2>/dev/tty) || rc=$?
    # dialog 底部 Cancel / Esc：映射为 extra_key（如 b / cancel）
    if [[ -z "$result" && $rc -ne 0 && -n "$extra_key" ]]; then
        result="$extra_key"
    fi
    _界面_重置终端
    printf '%s' "$result"
    [[ -n "$result" ]]
}

界面有选择() {
    [[ -n "${1:-}" ]]
}

界面选择() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    _界面选择对话框 "$title" "$prompt" '' '' "menu" "$@"
}

界面菜单() {
    界面选择 "$1" "${2:-请选择:}" "${@:3}"
}

界面子菜单() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    _界面选择对话框 "$title" "$prompt" 'b' '← 返回上级' "menu" "$@"
}

界面多选() {
    local title="$1"
    local prompt="${2:-请选择 (空格选中, Enter 确认):}"
    shift 2
    _界面选择对话框 "$title" "$prompt" '' '' "checklist" "$@"
}

# ─── 消息 / 输入（全部走 dialog，避免与菜单 TUI 冲突） ─────

界面提示() {
    local message="$1"
    local title="${2:-提示}"
    local box_h box_w
    read -r box_h box_w < <(_界面_消息框尺寸 "$message")
    _界面_dialog --title "$title" --msgbox "$(_界面_转义文本 "$message")" "$box_h" "$box_w"
}

界面警告() {
    界面提示 "$1" "${2:-⚠ 提示}"
}

界面完成() {
    界面提示 "$1" "${2:-✓ 完成}"
}

界面消息() {
    界面提示 "$@"
}

界面错误() {
    if command -v dialog &>/dev/null && [[ -e /dev/tty ]]; then
        界面警告 "$1" "✗ 错误"
    else
        echo -e "\033[31m✗ $1\033[0m" >&2
    fi
}

界面信息() {
    if [[ "${1:-}" == 正在* ]]; then
        declare -F _界面_重置终端 &>/dev/null && _界面_重置终端
        printf '%b\n' "$(_界面_转义文本 "$1")" >&2
        return 0
    fi
    if command -v dialog &>/dev/null && [[ -e /dev/tty ]]; then
        界面提示 "$1" "ℹ 信息"
    else
        echo -e "\033[36m$1\033[0m" >&2
    fi
}

界面成功() {
    if command -v dialog &>/dev/null && [[ -e /dev/tty ]]; then
        界面完成 "$1"
    else
        echo -e "\033[32m✓ $1\033[0m" >&2
    fi
}

界面输入() {
    local prompt="$1"
    local default="${2:-}"
    local result

    _界面_重置终端
    result=$(dialog --clear --stdout --backtitle "$UI_BACKTITLE" --title "输入" \
        --inputbox "$(_界面_转义文本 "$prompt")" 10 62 "$default" 2>/dev/tty) || true
    _界面_重置终端
    printf '%s' "$result"
}

界面确认() {
    local message="$1"
    local title="${2:-确认}"
    _界面_dialog --title "$title" --yesno "$(_界面_转义文本 "$message")" 12 62
}

界面是否() {
    界面确认 "$@"
}

界面文本() {
    local content="$1"
    local title="${2:-内容}"
    local tmp_file box_h box_w lines

    tmp_file=$(mktemp)
    _界面_转义文本 "$content" > "$tmp_file"
    lines=$(wc -l < "$tmp_file" | tr -d ' ')
    box_h=$((lines + 6))
    read -r _lines cols < <(_界面_终端尺寸)
    [[ $box_h -lt 12 ]] && box_h=12
    [[ $box_h -gt $((_lines - 2)) ]] && box_h=$((_lines - 2))
    box_w=76
    [[ $cols -lt 82 ]] && box_w=$((cols - 6))

    _界面_dialog --title "$title" --textbox "$tmp_file" "$box_h" "$box_w"
    rm -f "$tmp_file"
}

界面选择文件() {
    local start_dir="${1:-.}"
    local title="${2:-选择文件}"
    local result

    _界面_重置终端
    result=$(dialog --clear --stdout --backtitle "$UI_BACKTITLE" --title "$title" \
        --fselect "$start_dir/" 16 76 2>/dev/tty) || true
    _界面_重置终端
    printf '%s' "$result"
}

界面暂停() {
    local message="${1:-按 Enter 继续...}"
    if command -v dialog &>/dev/null; then
        _界面_dialog --title " " --msgbox "$(_界面_转义文本 "$message")" 6 52
    else
        read -r -p "$message" -s
        echo ""
    fi
}

界面清屏() {
    _界面_重置终端
}

# 清屏后执行命令（安装/查询等），结束后再次清屏，避免日志残留在菜单下层
界面任务() {
    local hint="${1:-}"
    shift
    _界面_重置终端
    export HAMSTER_UI_TASK=1
    HAMSTER_LAST_ERROR=""
    [[ -n "$hint" ]] && printf '%b\n\n' "$hint" >&2
    local rc=0
    if [[ $# -gt 0 ]]; then
        "$@" || rc=$?
    fi
    unset HAMSTER_UI_TASK
    _界面_重置终端
    return "$rc"
}

界面加载动画() {
    local pid="$1"
    local message="${2:-处理中...}"
    local pct=0

    while kill -0 "$pid" 2>/dev/null; do
        pct=$(( (pct + 1) % 100 ))
        echo "XXX"
        echo "$message"
        echo "XXX"
        echo "$pct"
        sleep 0.2
    done
    echo "XXX"
    echo "完成"
    echo "XXX"
    echo "100"
}

界面已取消() {
    case "${1:-}" in cancel|b|'') return 0 ;; esac
    return 1
}

界面动作() {
    local title="$1"
    shift
    _界面选择对话框 "$title" "操作:" 'cancel' '← 取消' "menu" "$@"
}
