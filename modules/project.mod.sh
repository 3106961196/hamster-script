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

# ─── 主菜单 ─────────────────────────────────────────────────

project_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "📁 项目管理" "请选择功能:" \
            "1" "项目列表" \
            "2" "安装项目")

        case "$choice" in
            1) project_list ;;
            2) project_install ;;
            b) break ;;
        esac
    done
}

# ─── 项目列表（固定显示 XRK-AGT + NapCat） ─────────────────

project_list() {
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
    [[ -z "$selected" ]] && return

    if project_is_installed "$selected"; then
        # 已安装 → 进入该项目的交互管理菜单
        ui_clear
        bash "$(project_manage_script "$selected")"
    else
        # 未安装 → 询问是否安装
        local display
        display=$(project_display_name "$selected")
        if ui_confirm "⚠️ $display 尚未安装\n\n是否立即安装？"; then
            project_install_fixed "$selected"
        fi
    fi
}

# ─── 安装项目 ───────────────────────────────────────────────

project_install() {
    local items=()
    items+=("xrk-agt" "📦 XRK-AGT")
    items+=("napcat" "📦 NapCat")
    items+=("git" "📥 Git 仓库")
    items+=("archive" "📦 压缩包 URL")

    local selected
    selected=$(ui_select "📁 安装项目" "选择安装方式:" "${items[@]}")
    [[ -z "$selected" ]] && return

    case "$selected" in
        xrk-agt|napcat) project_install_fixed "$selected" ;;
        git)            project_install_git ;;
        archive)        project_install_archive ;;
    esac
}

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

# ─── 自定义 Git 安装 ────────────────────────────────────────

project_install_git() {
    local repo_url
    repo_url=$(ui_input "Git 仓库地址" "https://github.com/user/repo.git")

    [[ -z "$repo_url" ]] && return

    local project_name
    project_name=$(basename "$repo_url" .git)

    project_name=$(ui_input "项目名称" "$project_name")
    [[ -z "$project_name" ]] && return

    project_do_install "$project_name" "git" "$repo_url"
}

# ─── 自定义压缩包安装 ──────────────────────────────────────

project_install_archive() {
    local archive_url
    archive_url=$(ui_input "压缩包 URL" "")

    [[ -z "$archive_url" ]] && return

    local project_name
    project_name=$(basename "$archive_url" | sed 's/\.[^.]*$//' | sed 's/\.[^.]*$//')

    project_name=$(ui_input "项目名称" "$project_name")
    [[ -z "$project_name" ]] && return

    project_do_install "$project_name" "archive" "$archive_url"
}

# ─── 通用安装执行 ──────────────────────────────────────────

project_do_install() {
    local name="$1"
    local type="$2"
    local url="$3"

    local install_dir="${CONFIG[install_dir]}/app/$name"

    if [[ -d "$install_dir" ]]; then
        if ! ui_confirm "目录 $install_dir 已存在，是否覆盖？"; then
            return
        fi
        rm -rf "$install_dir"
    fi

    mkdir -p "$install_dir"

    ui_info "正在安装 $name..."

    case "$type" in
        git)
            if ! git clone --depth 1 "$url" "$install_dir" 2>&1; then
                ui_error "克隆仓库失败"
                rm -rf "$install_dir"
                return 1
            fi
            ;;
        archive)
            local temp_file="${CONFIG[temp_dir]}/${name}.tar.gz"
            if ! wget -q "$url" -O "$temp_file" 2>&1 && ! curl -sL "$url" -o "$temp_file" 2>&1; then
                ui_error "下载失败"
                rm -rf "$install_dir" "$temp_file"
                return 1
            fi
            if ! tar -xzf "$temp_file" -C "$install_dir" --strip-components=1 2>&1; then
                ui_error "解压失败"
                rm -rf "$install_dir" "$temp_file"
                return 1
            fi
            rm -f "$temp_file"
            ;;
    esac

    if [[ -f "$install_dir/package.json" ]]; then
        if ui_confirm "检测到 Node.js 项目，是否安装依赖？"; then
            ui_info "正在安装依赖..."
            (cd "$install_dir" && npm install 2>&1) || \
            (cd "$install_dir" && pnpm install 2>&1) || \
            (cd "$install_dir" && yarn install 2>&1)
        fi
    fi

    ui_success "$name 安装成功"
}
