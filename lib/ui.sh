#!/bin/bash

UI_TITLE="🐹 Hamster Script"

ui_init() {
    if ! command -v dialog &>/dev/null; then
        echo "错误: dialog 未安装" >&2
        return 1
    fi
}

# ─── 核心菜单函数 ─────────────────────────────────────────

# _ui_dialog_pick: 内核函数，统一处理 dialog --menu 交互
# 参数:
#   $1  - title (显示在 dialog 顶部的标题)
#   $2  - prompt (菜单提示文本)
#   $3  - extra_key (返回键的 key，如 'b'，为空则不添加)
#   $4  - extra_label (返回键的显示文本，如 '返回')
#   $5  - mode (menu|checklist，默认 menu)
#   $6+ - items数组 (key-value交替的条目列表)
_ui_dialog_pick() {
    local title="$1"
    local prompt="$2"
    local extra_key="$3"
    local extra_label="$4"
    local mode="${5:-menu}"
    shift 5
    local items=("$@")

    local dialog_args=()
    dialog_args+=(--title "$title" --menu "$prompt" 20 76 15)

    if [[ "$mode" == "checklist" ]]; then
        dialog_args[2]="--checklist"
    fi

    # 写入条目
    local i=0
    while [ $i -lt ${#items[@]} ]; do
        dialog_args+=("${items[$i]}" "${items[$((i+1))]}" off)
        i=$((i + 2))
    done

    # 添加返回项
    if [[ -n "$extra_key" && -n "$extra_label" ]]; then
        dialog_args+=("$extra_key" "$extra_label" off)
    fi

    local tmp_file
    tmp_file=$(mktemp)

    local result
    result=$(dialog --stdout "${dialog_args[@]}" 2>"$tmp_file")
    local exit_code=$?

    # checklist 模式：读取所有选中项
    if [[ "$mode" == "checklist" ]]; then
        cat "$tmp_file" 2>/dev/null
        rm -f "$tmp_file"
        return $exit_code
    fi

    # menu 模式：直接返回选中 key
    echo "$result"
    rm -f "$tmp_file"
    return $exit_code
}

ui_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    local select_one="${3:-false}"
    shift 3
    local items=("$@")

    _ui_dialog_pick "$title" "$prompt" '' '' "menu" "${items[@]}"
}

ui_menu() {
    ui_select "$1" "${2:-请选择:}" "true" "${@:3}"
}

ui_submenu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")

    _ui_dialog_pick "$title" "$prompt" 'b' '返回' "menu" "${items[@]}"
}

ui_multi_select() {
    local title="$1"
    local prompt="${2:-请选择 (空格选中, Enter确认):}"
    shift 2
    local items=("$@")

    _ui_dialog_pick "$title" "$prompt" '' '' "checklist" "${items[@]}"
}

ui_msg() {
    local message="$1"
    local title="${2:-提示}"

    dialog --title "$title" --msgbox "$message" 10 60
}

ui_error() {
    local message="$1"
    echo -e "\033[31m✗ $message\033[0m" >&2
}

ui_info() {
    local message="$1"
    echo -e "\033[36m$message\033[0m" >&2
}

ui_success() {
    local message="$1"
    echo -e "\033[32m✓ $message\033[0m" >&2
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"

    local result
    result=$(dialog --title "输入" --inputbox "$prompt" 10 60 "$default" 2>&1 >/dev/tty)
    echo "$result"
}

ui_confirm() {
    local message="$1"
    local title="${2:-确认}"

    dialog --title "$title" --yesno "$message" 10 60
}

ui_yesno() {
    ui_confirm "$@"
}

ui_textbox() {
    local file="$1"
    local title="${2:-内容}"

    if [[ ! -f "$file" ]]; then
        ui_error "文件不存在: $file"
        return 1
    fi

    dialog --title "$title" --textbox "$file" 20 76
}

ui_text() {
    local content="$1"
    local title="${2:-内容}"

    local tmp_file
    tmp_file=$(mktemp)
    echo "$content" > "$tmp_file"
    dialog --title "$title" --textbox "$tmp_file" 20 76
    rm -f "$tmp_file"
}

ui_select_file() {
    local start_dir="${1:-.}"
    local title="${2:-选择文件}"

    dialog --title "$title" --fselect "$start_dir/" 16 76 2>&1 >/dev/tty
}

ui_select_dir() {
    local start_dir="${1:-.}"
    local title="${2:-选择目录}"

    dialog --title "$title" --dselect "$start_dir/" 16 76 2>&1 >/dev/tty
}

ui_pause() {
    local message="${1:-按 Enter 继续...}"
    read -r -p "$message" -n 1 -s
    echo ""
}

ui_clear() {
    clear
}

ui_spinner() {
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

ui_loading() {
    local message="${1:-加载中...}"
    local pid="$2"

    if [[ -n "$pid" ]]; then
        ui_spinner "$pid" "$message" | dialog --gauge "$message" 6 50
    else
        echo "$message"
    fi
}

ui_table() {
    local title="$1"
    shift
    local data=("$@")

    local tmp_file
    tmp_file=$(mktemp)
    printf "%s\n" "${data[@]}" > "$tmp_file"
    dialog --title "$title" --textbox "$tmp_file" 20 76
    rm -f "$tmp_file"
}

ui_search() {
    local title="$1"
    local prompt="${2:-搜索:}"
    shift 2
    local items=("$@")

    _ui_dialog_pick "$title (输入关键词搜索)" "$prompt" '' '' "menu" "${items[@]}"
}

ui_action() {
    local title="$1"
    shift
    local actions=("$@")

    _ui_dialog_pick "$title" "操作:" '' '' "menu" "${actions[@]}"
}
