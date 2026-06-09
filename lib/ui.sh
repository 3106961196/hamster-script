#!/bin/bash

UI_TITLE="🐹 Hamster Script"
FZF_SUPPORTS_BECOME="false"

ui_init() {
    if ! command -v fzf &>/dev/null; then
        echo "错误: fzf 未安装" >&2
        return 1
    fi

    if fzf --help 2>&1 | grep -q "become(.*COMMAND"; then
        FZF_SUPPORTS_BECOME="true"
    else
        FZF_SUPPORTS_BECOME="false"
    fi

    export FZF_DEFAULT_OPTS="
        --height=80%
        --layout=reverse
        --border=rounded
        --prompt='❯ '
        --pointer='▶'
        --marker='✓'
        --header-first
        --color=bg+:#363a4f,bg:#24273a,spinner:#f4dbd6,hl:#ed8796
        --color=fg:#cad3f5,header:#ed8796,info:#c6a0f6,pointer:#f4dbd6
        --color=marker:#f4dbd6,fg+:#cad3f5,prompt:#c6a0f6,hl+:#ed8796
    "
}

ui_bind_right_click() {
    local command="$1"

    if [[ "$FZF_SUPPORTS_BECOME" == "true" ]]; then
        printf -- "--bind=right-click:become(%s)" "$command"
    fi
}

# _ui_fzf_pick: 内核函数，统一处理临时文件创建、awk格式化、fzf调用、结果读取、临时文件清理
# 参数:
#   $1  - header (显示在fzf顶部的标题)
#   $2  - prompt (fzf输入提示符)
#   $3  - right_click_command (右键点击时执行的命令)
#   $4  - extra_line (追加到临时文件末尾的额外行，为空则不追加)
#   $5  - extra_fzf_opts (额外的fzf选项字符串，空格分隔，如 "--multi" 或 "--select-1")
#   $6+ - items数组 (key-value交替的条目列表)
_ui_fzf_pick() {
    local header="$1"
    local prompt="$2"
    local right_click_command="$3"
    local extra_line="$4"
    local extra_fzf_opts="$5"
    shift 5
    local items=("$@")

    local tmp_file
    tmp_file=$(mktemp)

    # 用 printf 逐对写入 key\tvalue，避免 awk 处理特殊字符问题
    local i=0
    while [ $i -lt ${#items[@]} ]; do
        printf '%s\t%s\n' "${items[$i]}" "${items[$((i+1))]}" >> "$tmp_file"
        i=$((i + 2))
    done

    if [[ -n "$extra_line" ]]; then
        printf '%s\n' "$extra_line" >> "$tmp_file"
    fi

    local fzf_opts=(
        --header="$header"
        --prompt="$prompt "
        --with-nth=2..
        --delimiter=$'\t'
        --exit-0
    )

    # 添加额外的fzf选项
    if [[ -n "$extra_fzf_opts" ]]; then
        read -ra extra_opts <<< "$extra_fzf_opts"
        fzf_opts+=("${extra_opts[@]}")
    fi

    local right_click_bind
    right_click_bind=$(ui_bind_right_click "$right_click_command")
    if [[ -n "$right_click_bind" ]]; then
        fzf_opts+=("$right_click_bind")
    fi

    local result
    result=$(fzf "${fzf_opts[@]}" < "$tmp_file" | cut -f1)

    rm -f "$tmp_file"
    echo "$result"
}

ui_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    local select_one="${3:-false}"
    shift 3
    local items=("$@")

    local extra_opts=""
    if [[ "$select_one" == "true" ]]; then
        extra_opts="--select-1"
    fi

    _ui_fzf_pick "$title" "$prompt" 'echo ""' "" "$extra_opts" "${items[@]}"
}

ui_menu() {
    ui_select "$1" "${2:-请选择:}" "true" "${@:3}"
}

ui_submenu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")

    _ui_fzf_pick "$title" "$prompt" 'echo b' 'b	返回' "" "${items[@]}"
}

ui_multi_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")

    _ui_fzf_pick "$title" "$prompt" 'echo ""' "" "--multi" "${items[@]}"
}

ui_msg() {
    local message="$1"
    local title="${2:-提示}"

    echo "$title" | fzf --header="$message" \
        --prompt="按 Enter 继续 " \
        --height=10 \
        --exit-0 >/dev/null 2>&1
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
    result=$(echo "" | fzf --header="$prompt" \
        --prompt="输入: " \
        --print-query \
        --height=10 \
        --exit-0 \
        --query="$default" \
        | head -1)

    echo "$result"
}

ui_confirm() {
    local message="$1"
    local title="${2:-确认}"

    local result
    local fzf_opts=(
        --header="$title: $message"
        --prompt="选择: "
        --with-nth=2..
        --delimiter=$'\t'
        --height=10
        --exit-0
    )

    local right_click_bind
    right_click_bind=$(ui_bind_right_click 'echo n')
    if [[ -n "$right_click_bind" ]]; then
        fzf_opts+=("$right_click_bind")
    fi

    result=$(printf "y\t是\nn\t否\n" | fzf "${fzf_opts[@]}" | cut -f1)

    [[ "$result" == "y" ]]
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

    local content
    content=$(cat "$file")

    echo "$content" | fzf --header="$title" \
        --prompt="按 Enter 返回 " \
        --exit-0 \
        --height=80%
}

ui_text() {
    local content="$1"
    local title="${2:-内容}"

    echo "$content" | fzf --header="$title" \
        --prompt="按 Enter 返回 " \
        --exit-0 \
        --height=80%
}

ui_select_file() {
    local start_dir="${1:-.}"
    local title="${2:-选择文件}"

    local result
    result=$(find "$start_dir" -type f 2>/dev/null | \
        fzf --header="$title" \
            --prompt="选择文件: " \
            --exit-0)

    echo "$result"
}

ui_select_dir() {
    local start_dir="${1:-.}"
    local title="${2:-选择目录}"

    local result
    result=$(find "$start_dir" -type d 2>/dev/null | \
        fzf --header="$title" \
            --prompt="选择目录: " \
            --exit-0)

    echo "$result"
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
    local spin='⣾⣽⣻⢿⡿⣟⣯⣷'
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        i=$(( (i+1) % 8 ))
        printf "\r${spin:$i:1} $message"
        sleep 0.1
    done
    printf "\r"
}

ui_loading() {
    local message="${1:-加载中...}"
    local pid="$2"

    if [[ -n "$pid" ]]; then
        ui_spinner "$pid" "$message"
    else
        echo "$message"
    fi
}

ui_table() {
    local title="$1"
    shift
    local data=("$@")

    printf "%s\n" "${data[@]}" | \
        fzf --header="$title" \
            --prompt="按 Enter 返回 " \
            --exit-0 \
            --height=80%
}

ui_search() {
    local title="$1"
    local prompt="${2:-搜索:}"
    shift 2
    local items=("$@")

    _ui_fzf_pick "$title (输入关键词搜索)" "$prompt" 'echo ""' "" "" "${items[@]}"
}

ui_action() {
    local title="$1"
    shift
    local actions=("$@")

    _ui_fzf_pick "$title" "操作:" 'echo ""' "" "" "${actions[@]}"
}
