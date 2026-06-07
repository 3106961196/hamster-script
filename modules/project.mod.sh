#!/bin/bash

# ─── 项目常量 ───────────────────────────────────────────────
# 固定项目列表（key => 显示名称）
declare -A PROJECT_NAMES=(
    [xrk-agt]="XRK-AGT"
    [napcat]="NapCat"
)
FIXED_PROJECTS=("xrk-agt" "napcat")

# ─── 工具函数 ───────────────────────────────────────────────

project_display_name() {
    local name="$1"
    echo "${PROJECT_NAMES[$name]:-$name}"
}

project_manage_script() {
    local name="$1"
    echo "${PROJECT_ROOT}/tools/${name}/manage.sh"
}

project_install_script() {
    local name="$1"
    echo "${PROJECT_ROOT}/tools/${name}/install.sh"
}

project_is_installed() {
    local name="$1"
    local script
    script="$(project_manage_script "$name")"
    [[ -f "$script" ]] && bash "$script" --auto is-installed 2>/dev/null | grep -q "yes"
}

# ─── 项目列表（直接作为主菜单入口） ────────────────────────

project_menu() {
    while true; do
        local items=()
        for key in "${FIXED_PROJECTS[@]}"; do
            local display status_text
            display=$(project_display_name "$key")

            if project_is_installed "$key"; then
                local run_status
                run_status=$(bash "$(project_manage_script "$key")" --auto status 2>/dev/null)
                if [[ "$run_status" == "运行中" ]]; then
                    status_text="🟢 运行中"
                else
                    status_text="🔴 已停止"
                fi
            else
                status_text="⚪ 未安装"
            fi

            items+=("$key" "$display  $status_text")
        done

        local selected
        selected=$(ui_select "📁 项目列表" "选择项目:" "${items[@]}")
        [[ -z "$selected" ]] && break

        if project_is_installed "$selected"; then
            ui_clear
            bash "$(project_manage_script "$selected")"
        else
            local display
            display=$(project_display_name "$selected")
            if ui_confirm "⚠️ $display 尚未安装\n\n是否立即安装？"; then
                project_install_fixed "$selected"
            fi
        fi
    done
}

# ─── 安装项目（从项目列表选中未安装项目时调用） ────────────

project_install_fixed() {
    local name="$1"
    local display
    display=$(project_display_name "$name")

    if project_is_installed "$name"; then
        ui_msg "$display 已经安装" "提示"
        return
    fi

    local script
    script=$(project_install_script "$name")
    if [[ -f "$script" ]]; then
        ui_clear
        bash "$script"
    else
        ui_error "$display 暂未提供安装脚本"
    fi
}
