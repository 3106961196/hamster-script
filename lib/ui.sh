#!/bin/bash

UI_TITLE="🐹 Hamster Script"

ui_init() {
    if ! command -v fzf &>/dev/null; then
        echo "错误: fzf 未安装" >&2
        return 1
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

ui_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    local select_one="${3:-false}"
    shift 3
    local items=("$@")
    
    local header="$title"
    local tmp_file
    tmp_file=$(mktemp)
    
    printf "%s\n" "${items[@]}" | \
        awk 'NR%2==1{key=$0; getline; print key "\t" $0}' > "$tmp_file"
    
    local fzf_opts=(
        --header="$header"
        --prompt="$prompt "
        --with-nth=2..
        --delimiter=$'\t'
        --exit-0
        --bind='right-click:become(echo "")'
    )
    
    if [[ "$select_one" == "true" ]]; then
        fzf_opts+=(--select-1)
    fi
    
    local result
    result=$(fzf "${fzf_opts[@]}" < "$tmp_file" | cut -f1)
    
    rm -f "$tmp_file"
    echo "$result"
}

ui_menu() {
    ui_select "$1" "${2:-请选择:}" "true" "${@:3}"
}

ui_submenu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")
    
    local header="$title"
    local tmp_file
    tmp_file=$(mktemp)
    
    printf "%s\n" "${items[@]}" | \
        awk 'NR%2==1{key=$0; getline; print key "\t" $0}' > "$tmp_file"
    printf "b\t返回\n" >> "$tmp_file"
    
    local result
    result=$(fzf --header="$header" \
            --prompt="$prompt " \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --exit-0 \
            --bind='right-click:become(echo b)' \
            < "$tmp_file" | cut -f1)
    
    rm -f "$tmp_file"
    echo "$result"
}

ui_multi_select() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")
    
    local header="$title"
    local tmp_file
    tmp_file=$(mktemp)
    
    printf "%s\n" "${items[@]}" | \
        awk 'NR%2==1{key=$0; getline; print key "\t" $0}' > "$tmp_file"
    
    local result
    result=$(fzf --header="$header" \
            --prompt="$prompt " \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --multi \
            --exit-0 \
            --bind='right-click:become(echo "")' \
            < "$tmp_file" | cut -f1)
    
    rm -f "$tmp_file"
    echo "$result"
}

ui_msg() {
    local message="$1"
    local title="${2:-提示}"
    
    echo "$title" | fzf --header="$message" \
        --prompt="按 Enter 继续 " \
        --no-input \
        --height=10 \
        --exit-0
}

ui_info() {
    local message="$1"
    echo -e "\033[36m$message\033[0m"
}

ui_success() {
    local message="$1"
    echo -e "\033[32m✓ $message\033[0m"
}

ui_error() {
    local message="$1"
    echo -e "\033[31m✗ $message\033[0m"
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
        --no-input \
        --query="$default" \
        | head -1)
    
    echo "$result"
}

ui_confirm() {
    local message="$1"
    local title="${2:-确认}"
    
    local result
    result=$(printf "y\t是\nn\t否\n" | \
        fzf --header="$title: $message" \
            --prompt="选择: " \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --height=10 \
            --exit-0 \
            --bind='right-click:become(echo n)' \
        | cut -f1)
    
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
        --no-input \
        --exit-0 \
        --height=80%
}

ui_text() {
    local content="$1"
    local title="${2:-内容}"
    
    echo "$content" | fzf --header="$title" \
        --prompt="按 Enter 返回 " \
        --no-input \
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
            --no-input \
            --exit-0 \
            --height=80%
}

ui_search() {
    local title="$1"
    local prompt="${2:-搜索:}"
    shift 2
    local items=("$@")
    
    local header="$title (输入关键词搜索)"
    local tmp_file
    tmp_file=$(mktemp)
    
    printf "%s\n" "${items[@]}" | \
        awk 'NR%2==1{key=$0; getline; print key "\t" $0}' > "$tmp_file"
    
    local result
    result=$(fzf --header="$header" \
            --prompt="$prompt " \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --exit-0 \
            --bind='right-click:become(echo "")' \
            < "$tmp_file" | cut -f1)
    
    rm -f "$tmp_file"
    echo "$result"
}

ui_action() {
    local title="$1"
    shift
    local actions=("$@")
    
    local header="$title"
    local tmp_file
    tmp_file=$(mktemp)
    
    printf "%s\n" "${actions[@]}" | \
        awk 'NR%2==1{key=$0; getline; print key "\t" $0}' > "$tmp_file"
    
    local result
    result=$(fzf --header="$header" \
            --prompt="操作: " \
            --with-nth=2.. \
            --delimiter=$'\t' \
            --exit-0 \
            --bind='right-click:become(echo "")' \
            < "$tmp_file" | cut -f1)
    
    rm -f "$tmp_file"
    echo "$result"
}
