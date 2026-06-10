#!/bin/bash

UI_TITLE="Hamster Script"

ui_init() {
    if ! command -v dialog &>/dev/null; then
        echo "错误: dialog 未安装" >&2
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

    local tmp_file
    tmp_file=$(mktemp)

    local height=20
    local width=76
    local menu_height=15

    local cmd=(dialog --stdout --title "$title" --ascii-lines --menu "$prompt" "$height" "$width" "$menu_height")

    if [[ "$mode" == "checklist" ]]; then
        cmd=(dialog --stdout --title "$title" --ascii-lines --checklist "$prompt" "$height" "$width" "$menu_height")
    fi

    # 写入条目 (menu 模式: key label 交替)
    local i=0
    while [ $i -lt ${#items[@]} ]; do
        cmd+=("${items[$i]}" "${items[$((i+1))]}")
        i=$((i + 2))
    done

    # 添加返回项 (menu 模式不需要 off)
    if [[ -n "$extra_key" && -n "$extra_label" ]]; then
        cmd+=("$extra_key" "$extra_label")
    fi

    # dialog 行为:
    #   UI(界面) 输出到 stderr (fd 2)
    #   选择结果到 stdout (fd 1) —— 加了 --stdout 后
    #
    # 需求: UI 在终端显示, 选择结果由 $() 捕获
    # 技巧: fd3->stdout(供 $() 捕获), fd2->tty(UI显示)
    local result
    result=$("${cmd[@]}" 2>/dev/tty 3>&1 1>&3)
    local exit_code=$?

    echo "$result"
    return $exit_code
}

ui_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")

    _ui_dialog_pick "$title" "$prompt" '' '' "menu" "${items[@]}"
}

ui_menu() {
    ui_select "$1" "${2:-请选择:}" "${@:3}"
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

    dialog --title "$title" --msgbox "$message" 10 60 --ascii-lines
}

ui_error() {
    local message="$1"
    echo -e "\033[31m* $message\033[0m" >&2
}

ui_info() {
    local message="$1"
    echo -e "\033[36m$message\033[0m" >&2
}

ui_success() {
    local message="$1"
    echo -e "\033[32m+ $message\033[0m" >&2
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"

    local result
    result=$(dialog --stdout --title "输入" --inputbox "$prompt" 10 60 "$default" 2>/dev/tty)
    echo "$result"
}

ui_confirm() {
    local message="$1"
    local title="${2:-确认}"

    dialog --title "$title" --yesno "$message" 10 60 --ascii-lines
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

    dialog --title "$title" --textbox "$file" 20 76 --ascii-lines
}

ui_text() {
    local content="$1"
    local title="${2:-内容}"

    local tmp_file
    tmp_file=$(mktemp)
    echo "$content" > "$tmp_file"
    dialog --title "$title" --textbox "$tmp_file" 20 76 --ascii-lines
    rm -f "$tmp_file"
}

ui_select_file() {
    local start_dir="${1:-.}"
    local title="${2:-选择文件}"

    dialog --stdout --title "$title" --fselect "$start_dir/" 16 76 --ascii-lines 2>/dev/tty
}

ui_select_dir() {
    local start_dir="${1:-.}"
    local title="${2:-选择目录}"

    dialog --stdout --title "$title" --dselect "$start_dir/" 16 76 --ascii-lines 2>/dev/tty
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
        ui_spinner "$pid" "$message" | dialog --gauge "$message" 6 50 --ascii-lines
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
    dialog --title "$title" --textbox "$tmp_file" 20 76 --ascii-lines
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
