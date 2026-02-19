#!/bin/bash

DIALOG_BACKTITLE="🐹 Hamster Script v${PROJECT_VERSION}"
DIALOG_WIDTH="${CONFIG[dialog_width]:-60}"
DIALOG_HEIGHT="${CONFIG[dialog_height]:-15}"

ui_init() {
    if ! command_exists dialog; then
        echo "Error: dialog is not installed" >&2
        return 1
    fi
    export DIALOGRC="${CONFIG[config_dir]}/dialogrc"
}

ui_menu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "返回" \
           --menu "$prompt" \
           $((DIALOG_HEIGHT + 2)) $DIALOG_WIDTH $DIALOG_HEIGHT \
           "${items[@]}" 2>&1 >/dev/tty
}

ui_submenu() {
    local title="$1"
    local prompt="${2:-请选择:}"
    shift 2
    local items=("$@")
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "返回" \
           --menu "$prompt" \
           $((DIALOG_HEIGHT + 2)) $DIALOG_WIDTH $DIALOG_HEIGHT \
           "${items[@]}" "b" "返回" 2>&1 >/dev/tty
}

ui_msg() {
    local message="$1"
    local title="${2:-提示}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --msgbox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

ui_info() {
    local message="$1"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --infobox "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

ui_input() {
    local prompt="$1"
    local default="${2:-}"
    local title="${3:-输入}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "取消" \
           --inputbox "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH "$default" 2>&1 >/dev/tty
}

ui_password() {
    local prompt="$1"
    local title="${2:-输入密码}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "取消" \
           --passwordbox "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH 2>&1 >/dev/tty
}

ui_confirm() {
    local message="$1"
    local title="${2:-确认}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --yes-label "确定" \
           --no-label "取消" \
           --yesno "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

ui_yesno() {
    local message="$1"
    local title="${2:-确认}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --yesno "$message" $DIALOG_HEIGHT $DIALOG_WIDTH
}

ui_textbox() {
    local file="$1"
    local title="${2:-内容}"
    
    if [[ ! -f "$file" ]]; then
        ui_msg "文件不存在: $file" "错误"
        return 1
    fi
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --textbox "$file" 20 70
}

ui_tailbox() {
    local file="$1"
    local title="${2:-日志}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --tailbox "$file" 20 70
}

ui_checklist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "取消" \
           --checklist "$prompt" \
           $((DIALOG_HEIGHT + 4)) $DIALOG_WIDTH $DIALOG_HEIGHT \
           "${items[@]}" 2>&1 >/dev/tty
}

ui_radiolist() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --ok-label "确定" \
           --cancel-label "取消" \
           --radiolist "$prompt" \
           $((DIALOG_HEIGHT + 4)) $DIALOG_WIDTH $DIALOG_HEIGHT \
           "${items[@]}" 2>&1 >/dev/tty
}

ui_form() {
    local title="$1"
    local prompt="$2"
    shift 2
    local items=("$@")
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --form "$prompt" \
           $((DIALOG_HEIGHT + 6)) $DIALOG_WIDTH $DIALOG_HEIGHT \
           "${items[@]}" 2>&1 >/dev/tty
}

ui_gauge() {
    local title="$1"
    local prompt="$2"
    local percent="$3"
    
    echo "$percent" | dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --gauge "$prompt" $DIALOG_HEIGHT $DIALOG_WIDTH 0
}

ui_pause() {
    local message="${1:-按任意键继续...}"
    read -r -p "$message" -n 1 -s
    echo ""
}

ui_wait() {
    local message="${1:-请稍候...}"
    local pid="$2"
    
    (
        while kill -0 "$pid" 2>/dev/null; do
            echo "XXX"
            echo "$message"
            echo "XXX"
            sleep 1
        done
    ) | dialog --backtitle "$DIALOG_BACKTITLE" \
               --title "请稍候" \
               --gauge "$message" $DIALOG_HEIGHT $DIALOG_WIDTH 0
}

ui_select_file() {
    local start_dir="${1:-/}"
    local title="${2:-选择文件}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --fselect "$start_dir" 15 60 2>&1 >/dev/tty
}

ui_select_dir() {
    local start_dir="${1:-/}"
    local title="${2:-选择目录}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --dselect "$start_dir" 15 60 2>&1 >/dev/tty
}

ui_calendar() {
    local title="${1:-选择日期}"
    local default_date="${2:-$(date +%Y-%m-%d)}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --calendar "选择日期" 0 0 \
           ${default_date//-/ } 2>&1 >/dev/tty
}

ui_timebox() {
    local title="${1:-选择时间}"
    local default_time="${2:-$(date +%H:%M:%S)}"
    
    dialog --backtitle "$DIALOG_BACKTITLE" \
           --title "$title" \
           --timebox "选择时间" 0 0 \
           ${default_time//:/ } 2>&1 >/dev/tty
}

ui_clear() {
    clear
}
