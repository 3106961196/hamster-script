#!/bin/bash

# ─── 项目列表 ───────────────────────────────────────────────
# 格式: key|显示名|type(tool|static)

PROJECT_DEFS=(
    "xrk-agt|XRK-AGT|tool"
    "napcat|NapCat|tool"
    "TRSS-Yunzai|TRSS-Yunzai|static"
)

# ─── 辅助函数 ───────────────────────────────────────────────

项目_解析项() {
    local item="$1"
    _PROJ_KEY="${item%%|*}"
    local rest="${item#*|}"
    _PROJ_NAME="${rest%%|*}"
    _PROJ_TYPE="${rest##*|}"
}

项目_管理脚本路径() {
    echo "${PROJECT_ROOT}/tools/${1}/manage.sh"
}

项目_安装脚本路径() {
    echo "${PROJECT_ROOT}/tools/${1}/install.sh"
}

项目_安装前置依赖() {
    case "$1" in
        TRSS-Yunzai|XRK-Yunzai)
            日志信息 "检查 $1 依赖..."
            包管理_批量安装 git wget jq curl tmux dialog || return 1
            包管理_确保Node || return 1
            包管理_确保Redis || return 1
            包管理_确保Chromium || return 1
            ;;
    esac
}

项目_是否已安装() {
    local name="$1" type="$2"
    case "$type" in
        tool) 工具_是否已安装 "$name" ;;
        static) [[ -d "$(获取工作目录)/${name}" ]] ;;
        *) return 1 ;;
    esac
}

项目_查找() {
    local key="$1" item
    for item in "${PROJECT_DEFS[@]}"; do
        项目_解析项 "$item"
        [[ "$_PROJ_KEY" == "$key" ]] && return 0
    done
    return 1
}

项目_检查状态() {
    local -n _inst="$1"
    local item

    for item in "${PROJECT_DEFS[@]}"; do
        项目_解析项 "$item"
        if 项目_是否已安装 "$_PROJ_KEY" "$_PROJ_TYPE"; then
            _inst["$_PROJ_KEY"]="yes"
        else
            _inst["$_PROJ_KEY"]="no"
        fi
    done
}

# ─── 主菜单 ─────────────────────────────────────────────────

项目_菜单() {
    while true; do
        local -A _installed=()
        项目_检查状态 _installed

        local items=() item idx=1
        local -a keys=()
        for item in "${PROJECT_DEFS[@]}"; do
            项目_解析项 "$item"
            keys+=("$_PROJ_KEY")
            if [[ "${_installed[$_PROJ_KEY]}" == "yes" ]]; then
                items+=("$idx" "$_PROJ_NAME [已安装]")
            else
                items+=("$idx" "$_PROJ_NAME [未安装]")
            fi
            idx=$((idx + 1))
        done

        local selected
        selected=$(界面子菜单 "项目列表" "选择要管理的项目:" "${items[@]}")
        [[ -z "$selected" || "$selected" == "b" ]] && break

        selected="${keys[$((selected - 1))]}"
        [[ -z "$selected" ]] && break

        local display
        项目_查找 "$selected" || continue
        display="$_PROJ_NAME"
        type="$_PROJ_TYPE"

        if [[ "${_installed[$selected]}" == "yes" ]]; then
            if [[ "$type" == "tool" ]]; then
                界面清屏
                bash "$(项目_管理脚本路径 "$selected")"
                界面清屏
            else
                界面消息 "$display 安装目录: $(获取工作目录)/$selected" "提示"
            fi
        elif 界面确认 "$display 尚未安装\n\n是否立即安装？" "安装确认"; then
            项目_执行安装 "$selected" "$type"
        fi
    done
}

项目_执行安装() {
    local name="$1" type="$2" display script rc=1

    项目_查找 "$name" || { 界面错误 "未知项目: $name"; return; }
    display="$_PROJ_NAME"

    if ! 项目_安装前置依赖 "$name"; then
        界面错误 "依赖安装失败，已中止"
        return
    fi

    case "$type" in
        tool)
            if [[ "$name" == "napcat" && $EUID -ne 0 ]]; then
                界面错误 "NapCat 安装需要 root 权限\n请使用 sudo cs"
                return
            fi
            script=$(项目_安装脚本路径 "$name")
            if [[ -f "$script" ]]; then
                if 界面任务 "正在安装 ${display}..." bash "$script"; then
                    rc=0
                fi
            elif 界面任务 "正在安装 ${display}..." 工具_安装 "$name"; then
                rc=0
            fi
            if [[ $rc -eq 0 ]] && 项目_是否已安装 "$name" "$type"; then
                界面成功 "${display} 安装完成"
            elif [[ $rc -eq 0 ]]; then
                界面警告 "${display} 安装步骤已结束\n但检测未通过，请查看终端日志"
            else
                界面错误 "${display} 安装失败"
            fi
            ;;
        static)
            local target="$(获取工作目录)/$name"
            if [[ -d "$target" ]]; then
                界面消息 "$display 已存在\n目录: $target" "提示"
                return
            fi
            界面清屏
            printf '正在安装 %s...\n\n' "$display" >&2
            mkdir -p "$(获取工作目录)"
            if git clone --depth 1 "https://gitee.com/TimeRainStarSky/Yunzai.git" "$target" 2>&1; then
                if [[ -f "$target/package.json" ]]; then
                    界面任务 "正在安装 npm 依赖..." bash -c "cd \"$target\" && 包管理_Npm安装" \
                        || 界面消息 "pnpm/npm 依赖安装可能未完成" "提示"
                fi
                界面成功 "$display 安装成功\n目录: $target"
            else
                界面错误 "$display 安装失败"
            fi
            ;;
    esac
}
