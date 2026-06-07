#!/bin/bash

# ─── 项目列表 ───────────────────────────────────────────────
# 每一项的格式：key|显示名称|类型
# 类型 tool = 有 tools/<key>/manage.sh 和 install.sh
# 类型 static = 内嵌安装逻辑（git clone）

PROJECT_DEFS=(
    "xrk-agt|XRK-AGT|tool"
    "napcat|NapCat|tool"
    "TRSS-Yunzai|TRSS-Yunzai|static"
)

# ─── 辅助函数 ───────────────────────────────────────────────

project_manage_script() {
    echo "${PROJECT_ROOT}/tools/${1}/manage.sh"
}
project_install_script() {
    echo "${PROJECT_ROOT}/tools/${1}/install.sh"
}

# ─── 检测安装状态 ───────────────────────────────────────────
# 一次性填好 _installed 和 _run_status 关联数组

project_check_status() {
    local -n _inst="$1"
    local -n _run="$2"
    local item key type

    for item in "${PROJECT_DEFS[@]}"; do
        key="${item%%|*}"
        type="${item##*|}"

        if [[ "$type" == "tool" ]]; then
            local script
            script=$(project_manage_script "$key")
            if [[ ! -f "$script" ]]; then
                _inst["$key"]="no"
                _run["$key"]=""
                continue
            fi

            local result
            result=$(bash "$script" --auto is-installed 2>/dev/null | tr -d '\n')
            if [[ "$result" == "yes" ]]; then
                _inst["$key"]="yes"
                _run["$key"]=$(bash "$script" --auto status 2>/dev/null | tr -d '\n')
            else
                _inst["$key"]="no"
                _run["$key"]=""
            fi
        else
            # static 项目：检测目录是否存在
            if [[ -d "/root/cs/$key" ]]; then
                _inst["$key"]="yes"
                _run["$key"]=""
            else
                _inst["$key"]="no"
                _run["$key"]=""
            fi
        fi
    done
}

project_display_name() {
    local key="$1"
    local item
    for item in "${PROJECT_DEFS[@]}"; do
        local k="${item%%|*}"
        if [[ "$k" == "$key" ]]; then
            local rest="${item#*|}"
            echo "${rest%|*}"
            return
        fi
    done
    echo "$key"
}

project_type() {
    local key="$1"
    local item
    for item in "${PROJECT_DEFS[@]}"; do
        local k="${item%%|*}"
        if [[ "$k" == "$key" ]]; then
            echo "${item##*|}"
            return
        fi
    done
    echo ""
}

# ─── 主菜单 ─────────────────────────────────────────────────

project_menu() {
    while true; do
        # 一次性检测所有项目状态
        local -A _installed=()
        local -A _run_status=()
        project_check_status _installed _run_status

        # 构建菜单项
        local items=()
        local item key type display
        for item in "${PROJECT_DEFS[@]}"; do
            key="${item%%|*}"
            type="${item##*|}"
            display=$(project_display_name "$key")

            local status_text
            if [[ "${_installed[$key]}" == "yes" ]]; then
                if [[ "$type" == "tool" ]] && [[ "${_run_status[$key]}" == "运行中" ]]; then
                    status_text="✅ 已安装 🟢 运行中"
                else
                    status_text="✅ 已安装"
                fi
            else
                status_text="⚪ 未安装"
            fi
            items+=("$key" "$display  $status_text")
        done

        local selected
        selected=$(ui_submenu "📁 项目列表" "选择项目:" "${items[@]}")
        [[ -z "$selected" || "$selected" == "b" ]] && break

        local display type
        display=$(project_display_name "$selected")
        type=$(project_type "$selected")

        if [[ "${_installed[$selected]}" == "yes" ]]; then
            # 已安装 → 工具项目直接进管理界面，static 提示路径
            if [[ "$type" == "tool" ]]; then
                ui_clear
                bash "$(project_manage_script "$selected")"
            else
                ui_msg "$display 安装目录: /root/cs/$selected" "提示"
            fi
        else
            if ui_confirm "⚠️ $display 尚未安装\n\n是否立即安装？"; then
                project_do_install "$selected" "$type"
            fi
        fi
    done
}


project_do_install() {
    local name="$1"
    local type="$2"

    case "$type" in
        tool)
            local script
            script=$(project_install_script "$name")
            if [[ -f "$script" ]]; then
                ui_clear
                bash "$script"
            else
                ui_error "$name 暂未提供安装脚本"
            fi
            ;;
        static)
            # TRSS-Yunzai：从 Gitee 克隆
            local target="/root/cs/$name"
            if [[ -d "$target" ]]; then
                ui_msg "$name 已存在" "提示"
                return
            fi
            ui_info "正在安装 $name ..."
            mkdir -p /root/cs
            if git clone --depth 1 "https://gitee.com/TimeRainStarSky/Yunzai.git" "$target" 2>&1; then
                ui_success "$name 安装成功"
                ui_info "安装目录: $target"
            else
                ui_error "$name 安装失败"
            fi
            ;;
    esac
}


