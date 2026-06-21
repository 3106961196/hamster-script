#!/bin/bash

# ─── 项目列表 ───────────────────────────────────────────────
# 使用 tool.sh 框架统一管理工具项目

PROJECT_DEFS=(
    "xrk-agt|XRK-AGT|tool"
    "napcat|NapCat|tool"
    "TRSS-Yunzai|TRSS-Yunzai|static"
)

# ─── 辅助函数 ───────────────────────────────────────────────

项目_管理脚本路径() {
    echo "${PROJECT_ROOT}/tools/${1}/manage.sh"
}

项目_安装脚本路径() {
    echo "${PROJECT_ROOT}/tools/${1}/install.sh"
}

# 使用 tool.sh 的 工具_是否已安装 函数
项目_检查状态() {
    local -n _inst="$1"
    local item key type

    for item in "${PROJECT_DEFS[@]}"; do
        key="${item%%|*}"
        type="${item##*|}"

        if [[ "$type" == "tool" ]]; then
            if 工具_是否已安装 "$key"; then
                _inst["$key"]="yes"
            else
                _inst["$key"]="no"
            fi
        else
            if [[ -d "$(获取工作目录)/$key" ]]; then
                _inst["$key"]="yes"
            else
                _inst["$key"]="no"
            fi
        fi
    done
}

项目_显示名称() {
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

项目_类型() {
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

项目_菜单() {
    while true; do
        # 一次性检测所有项目状态
        local -A _installed=()
        项目_检查状态 _installed

        # 构建菜单项
        local items=()
        local item key type display idx=1
        local -a keys=()
        for item in "${PROJECT_DEFS[@]}"; do
            key="${item%%|*}"
            type="${item##*|}"
            display=$(项目_显示名称 "$key")
            keys+=("$key")

            local status_text
            if [[ "${_installed[$key]}" == "yes" ]]; then
                status_text="[已安装]"
            else
                status_text="[未安装]"
            fi
            items+=("$idx" "$display $status_text")
            idx=$((idx + 1))
        done

        local selected
        selected=$(界面子菜单 "📁 项目列表" "选择项目:" "${items[@]}")
        [[ -z "$selected" || "$selected" == "b" ]] && break

        # 数字序号 → 项目 key
        selected="${keys[$((selected - 1))]}"
        [[ -z "$selected" ]] && break

        local display type
        display=$(项目_显示名称 "$selected")
        type=$(项目_类型 "$selected")

        if [[ "${_installed[$selected]}" == "yes" ]]; then
            # 已安装 → 工具项目直接进管理界面，static 提示路径
            if [[ "$type" == "tool" ]]; then
                界面清屏
                bash "$(项目_管理脚本路径 "$selected")"
                界面清屏
            else
                界面消息 "$display 安装目录: $(获取工作目录)/$selected" "提示"
            fi
        else
            if 界面确认 "⚠️ $display 尚未安装\n\n是否立即安装？"; then
                项目_执行安装 "$selected" "$type"
            fi
        fi
    done
}

# 使用 tool.sh 的 工具_安装 函数
项目_执行安装() {
    local name="$1"
    local type="$2"

    case "$type" in
        tool)
            local script
            script=$(项目_安装脚本路径 "$name")
            if [[ -f "$script" ]]; then
                界面清屏
                bash "$script"
                界面清屏
                界面暂停 "按 Enter 返回菜单"
            else
                # 使用 tool.sh 的标准安装流程
                界面信息 "使用标准安装流程..."
                if 工具_安装 "$name"; then
                    界面成功 "$name 安装完成"
                else
                    界面错误 "$name 安装失败"
                fi
                界面暂停 "按 Enter 返回菜单"
            fi
            ;;
        static)
            # TRSS-Yunzai：从 Gitee 克隆
            local target="$(获取工作目录)/$name"
            if [[ -d "$target" ]]; then
                界面消息 "$name 已存在" "提示"
                return
            fi
            界面信息 "正在安装 $name ..."
            mkdir -p "$(获取工作目录)"
            if git clone --depth 1 "https://gitee.com/TimeRainStarSky/Yunzai.git" "$target" 2>&1; then
                界面成功 "$name 安装成功"
                界面信息 "安装目录: $target"
            else
                界面错误 "$name 安装失败"
            fi
            界面暂停 "按 Enter 返回菜单"
            ;;
    esac
}


