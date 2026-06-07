#!/bin/bash

# ─── 项目常量 ───────────────────────────────────────────────
# 有 tools/<name>/ 自定义管理脚本的"工具项目"
declare -A TOOL_PROJECT_NAMES=(
    [xrk-agt]="XRK-AGT"
    [napcat]="NapCat"
)
TOOL_PROJECTS=("xrk-agt" "napcat")

# ─── 工具函数 ───────────────────────────────────────────────

project_display_name() {
    local name="$1"
    echo "${TOOL_PROJECT_NAMES[$name]:-$name}"
}

project_manage_script() {
    local name="$1"
    echo "${PROJECT_ROOT}/tools/${name}/manage.sh"
}

project_install_script() {
    local name="$1"
    echo "${PROJECT_ROOT}/tools/${name}/install.sh"
}

# ─── 加载 config/projects.yaml ──────────────────────────────
# 读取通用项目配置（url / target / pre / post）

declare -a YAML_PROJECTS=()
declare -A YAML_URL=()
declare -A YAML_TARGET=()

project_load_yaml() {
    local yaml_file="${PROJECT_ROOT}/config/projects.yaml"
    [[ ! -f "$yaml_file" ]] && return

    YAML_PROJECTS=()

    local in_projects=false
    local current_name=""
    local current_url=""
    local current_target="/root/cs"

    while IFS= read -r line || [[ -n "$line" ]]; do
        # 去掉行首空白
        local trimmed
        trimmed=$(echo "$line" | sed 's/^[[:space:]]*//')

        if [[ "$trimmed" == "projects:" ]]; then
            in_projects=true
            continue
        fi

        if ! $in_projects; then
            continue
        fi

        if [[ "$trimmed" =~ ^-\ *name:\ (.*)$ ]]; then
            # 保存上一个项目
            if [[ -n "$current_name" ]]; then
                YAML_PROJECTS+=("$current_name")
                YAML_URL["$current_name"]="$current_url"
                YAML_TARGET["$current_name"]="$current_target"
            fi
            current_name="${BASH_REMATCH[1]}"
            current_url=""
            current_target="/root/cs"
        elif [[ -n "$current_name" ]] && [[ "$trimmed" =~ ^url:\ (.*)$ ]]; then
            current_url="${BASH_REMATCH[1]}"
        elif [[ -n "$current_name" ]] && [[ "$trimmed" =~ ^target:\ (.*)$ ]]; then
            current_target="${BASH_REMATCH[1]}"
        fi
    done < "$yaml_file"

    # 保存最后一个项目
    if [[ -n "$current_name" ]]; then
        YAML_PROJECTS+=("$current_name")
        YAML_URL["$current_name"]="$current_url"
        YAML_TARGET["$current_name"]="$current_target"
    fi
}

# ─── 构建完整项目列表（工具项目 + YAML 项目，去重） ──────
# 结果写入两个全局数组：ALL_PROJECTS[] 和 ALL_SOURCES[] (值为 "tool" | "yaml")

declare -a ALL_PROJECTS=()
declare -A ALL_SOURCES=()

project_build_full_list() {
    ALL_PROJECTS=()
    ALL_SOURCES=()

    # 1. 工具项目
    for key in "${TOOL_PROJECTS[@]}"; do
        ALL_PROJECTS+=("$key")
        ALL_SOURCES["$key"]="tool"
    done

    # 2. YAML 项目（去重 — 同名时工具项目优先）
    project_load_yaml
    for yaml_name in "${YAML_PROJECTS[@]}"; do
        local duplicate=false
        for existing in "${ALL_PROJECTS[@]}"; do
            if [[ "$existing" == "$yaml_name" ]]; then
                duplicate=true
                break
            fi
        done
        if ! $duplicate; then
            ALL_PROJECTS+=("$yaml_name")
            ALL_SOURCES["$yaml_name"]="yaml"
        fi
    done
}

# ─── 工具项目：安装检测 ＋ 运行状态（一次 fork） ──────────
# 结果写入传入的关联数组引用
project_tool_status() {
    local key="$1"
    local -n _inst="$2"   # 写入选定数组 ["$key"]="yes|no"
    local -n _stat="$3"   # 写入 ["$key"]="运行中|已停止|"

    local script
    script="$(project_manage_script "$key")"
    if [[ ! -f "$script" ]]; then
        _inst["$key"]="no"
        _stat["$key"]=""
        return
    fi

    local result
    result=$(bash "$script" --auto is-installed 2>/dev/null | tr -d '\n')
    if [[ "$result" == "yes" ]]; then
        _inst["$key"]="yes"
        local run_status
        run_status=$(bash "$script" --auto status 2>/dev/null | tr -d '\n')
        _stat["$key"]="$run_status"
    else
        _inst["$key"]="no"
        _stat["$key"]=""
    fi
}

# ─── YAML 项目：安装检测 ────────────────────────────────────
project_yaml_is_installed() {
    local name="$1"
    local target="${YAML_TARGET[$name]:-/root/cs}"
    [[ -d "$target/$name" ]]
}

# ─── 项目列表（主入口） ────────────────────────────────────

project_menu() {
    # 首次构建列表
    project_build_full_list

    while true; do
        # ── 缓存本次循环的状态结果（fix 4） ──
        local -A _installed=()
        local -A _run_status=()

        # ── 构建菜单项 ──
        local items=()
        for key in "${ALL_PROJECTS[@]}"; do
            local display source
            display=$(project_display_name "$key")
            source="${ALL_SOURCES[$key]}"

            local status_text
            if [[ "$source" == "tool" ]]; then
                project_tool_status "$key" _installed _run_status
                if [[ "${_installed[$key]}" == "yes" ]]; then
                    if [[ "${_run_status[$key]}" == "运行中" ]]; then
                        status_text="✅ 已安装 🟢 运行中"
                    else
                        status_text="✅ 已安装 🔴 已停止"
                    fi
                else
                    status_text="⚪ 未安装"
                fi
            else
                # YAML 项目
                if project_yaml_is_installed "$key"; then
                    _installed["$key"]="yes"
                    status_text="✅ 已安装"
                else
                    _installed["$key"]="no"
                    status_text="⚪ 未安装"
                fi
            fi

            items+=("$key" "$display  $status_text")
        done

        # ── 菜单展示（fix 1 & 6: ui_submenu 带返回项，无 --select-1） ──
        local selected
        selected=$(ui_submenu "📁 项目列表" "选择项目:" "${items[@]}")
        [[ -z "$selected" || "$selected" == "b" ]] && break

        # ── 处理选中项目 ──
        local display source
        display=$(project_display_name "$selected")
        source="${ALL_SOURCES[$selected]}"

        if [[ "${_installed[$selected]}" == "yes" ]]; then
            project_installed_actions "$selected" "$source"
        else
            # 未安装 → 确认后安装
            if ui_confirm "⚠️ $display 尚未安装\n\n是否立即安装？"; then
                if [[ "$source" == "tool" ]]; then
                    project_install_fixed "$selected"
                else
                    project_yaml_install "$selected"
                fi
            fi
        fi
    done
}

# ─── 已安装项目 → 统一操作菜单（fix 5） ────────────────────

project_installed_actions() {
    local name="$1"
    local source="$2"
    local display
    display=$(project_display_name "$name")

    local action
    action=$(ui_action "📁 $display（已安装）" \
        "manage" "📋 管理" \
        "uninstall" "🗑️  卸载" \
        "back" "⬅️  返回")

    case "$action" in
        manage)
            if [[ "$source" == "tool" ]]; then
                ui_clear
                bash "$(project_manage_script "$name")"
            else
                ui_msg "$display 没有独立的管理界面\n请在项目目录中手动操作" "提示"
                ui_info "安装目录: ${YAML_TARGET[$name]:-/root/cs}/$name"
            fi
            ;;
        uninstall)
            if ui_confirm "⚠️  确定要卸载 $display 吗？\n此操作不可恢复！"; then
                if [[ "$source" == "tool" ]]; then
                    ui_info "正在卸载 $display ..."
                    bash "$(project_manage_script "$name")" --auto uninstall 2>&1
                    ui_success "$display 卸载完成"
                else
                    project_yaml_uninstall "$name"
                fi
            fi
            ;;
    esac
}

# ─── 安装工具项目（已被 project_menu 调用） ─────────────────

project_install_fixed() {
    local name="$1"
    local display
    display=$(project_display_name "$name")

    local script
    script=$(project_install_script "$name")
    if [[ -f "$script" ]]; then
        ui_clear
        bash "$script"
    else
        ui_error "$display 暂未提供安装脚本"
    fi
}

# ─── YAML 项目：安装 ───────────────────────────────────────

project_yaml_install() {
    local name="$1"
    local url="${YAML_URL[$name]}"
    local target="${YAML_TARGET[$name]:-/root/cs}"

    if [[ -z "$url" ]]; then
        ui_error "$name 缺少下载地址（url）"
        return 1
    fi

    ui_info "正在安装 $name ..."
    # 依赖下载工具
    source "${PROJECT_ROOT}/utils/download.sh"

    # 下载 / 克隆
    if download "$url" "$target" "$name"; then
        ui_success "$name 安装成功"
        ui_info "安装目录: $target/$name"
    else
        ui_error "$name 安装失败"
    fi
}

# ─── YAML 项目：卸载 ───────────────────────────────────────

project_yaml_uninstall() {
    local name="$1"
    local target="${YAML_TARGET[$name]:-/root/cs}"
    local dir="$target/$name"

    if [[ -d "$dir" ]]; then
        ui_info "正在删除 $dir ..."
        rm -rf "$dir"
        ui_success "$name 已卸载"
    else
        ui_msg "$name 未安装" "提示"
    fi
}
