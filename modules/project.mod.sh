#!/bin/bash

PROJECTS_CONFIG="${CONFIG[config_dir]}/projects.yaml"
PROJECTS_DATA="${CONFIG[data_dir]}/projects.json"

project_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "📁 项目管理" "请选择功能:" \
            "1" "安装项目" \
            "2" "已装项目")
        
        case "$choice" in
            1) project_install ;;
            2) project_list ;;
            b) break ;;
        esac
    done
}

project_install() {
    local items=()
    
    items+=("preset" "📦 预置项目")
    items+=("git" "📥 Git 仓库")
    items+=("archive" "📦 压缩包 URL")
    
    local install_type
    install_type=$(ui_select "📁 安装项目" "选择安装方式:" "${items[@]}")
    
    case "$install_type" in
        preset) project_install_preset ;;
        git) project_install_git ;;
        archive) project_install_archive ;;
    esac
}

project_install_preset() {
    local items=()
    
    if [[ -f "$PROJECTS_CONFIG" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*name:[[:space:]]*(.*) ]]; then
                local name="${BASH_REMATCH[1]}"
                name=$(echo "$name" | tr -d '"' | tr -d "'")
                items+=("$name" "预置项目")
            fi
        done < "$PROJECTS_CONFIG"
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        items+=("napcat" "QQ机器人框架")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可用的预置项目" "提示"
        return
    fi
    
    local selected
    selected=$(ui_select "📦 预置项目" "选择要安装的项目:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    if project_is_installed "$selected"; then
        ui_msg "$selected 已经安装" "提示"
        return
    fi
    
    project_do_install "$selected" "preset"
}

project_install_git() {
    local repo_url
    repo_url=$(ui_input "Git 仓库地址" "https://github.com/user/repo.git")
    
    [[ -z "$repo_url" ]] && return
    
    local project_name
    project_name=$(basename "$repo_url" .git)
    
    project_name=$(ui_input "项目名称" "$project_name")
    [[ -z "$project_name" ]] && return
    
    if project_is_installed "$project_name"; then
        ui_msg "$project_name 已经安装" "提示"
        return
    fi
    
    project_do_install "$project_name" "git" "$repo_url"
}

project_install_archive() {
    local archive_url
    archive_url=$(ui_input "压缩包 URL" "")
    
    [[ -z "$archive_url" ]] && return
    
    local project_name
    project_name=$(basename "$archive_url" | sed 's/\.[^.]*$//' | sed 's/\.[^.]*$//')
    
    project_name=$(ui_input "项目名称" "$project_name")
    [[ -z "$project_name" ]] && return
    
    if project_is_installed "$project_name"; then
        ui_msg "$project_name 已经安装" "提示"
        return
    fi
    
    project_do_install "$project_name" "archive" "$archive_url"
}

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
        preset)
            project_install_preset_project "$name" "$install_dir"
            ;;
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
    
    project_save_info "$name" "$install_dir" "$type"
    
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

project_install_preset_project() {
    local name="$1"
    local install_dir="$2"
    
    case "$name" in
        napcat)
            if [[ -f "${PROJECT_ROOT}/tools/napcat/install.sh" ]]; then
                bash "${PROJECT_ROOT}/tools/napcat/install.sh" "$install_dir"
            else
                ui_error "NapCat 安装脚本不存在"
                return 1
            fi
            ;;
        *)
            ui_error "未知项目: $name"
            return 1
            ;;
    esac
}

project_list() {
    local items=()
    
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local name dir status
            name=$(echo "$line" | cut -d'|' -f1)
            dir=$(echo "$line" | cut -d'|' -f2)
            
            if project_is_running "$name"; then
                status="🟢 运行中"
            else
                status="🔴 已停止"
            fi
            
            items+=("$name" "$status")
        fi
    done < <(project_get_all)
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "暂无已安装的项目" "提示"
        return
    fi
    
    local selected
    selected=$(ui_select "📁 已装项目" "选择项目:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    project_action "$selected"
}

project_action() {
    local name="$1"
    local info
    info=$(project_get_info "$name")
    
    local dir type installed
    dir=$(echo "$info" | grep "^dir:" | cut -d' ' -f2-)
    type=$(echo "$info" | grep "^type:" | cut -d' ' -f2-)
    installed=$(echo "$info" | grep "^installed:" | cut -d' ' -f2-)
    
    local is_running
    is_running=$(project_is_running "$name" && echo "true" || echo "false")
    
    local status_text
    if [[ "$is_running" == "true" ]]; then
        status_text="🟢 运行中"
    else
        status_text="🔴 已停止"
    fi
    
    local actions
    if [[ "$is_running" == "true" ]]; then
        actions=(
            "stop" "停止"
            "restart" "重启"
            "logs" "查看日志"
            "info" "项目信息"
            "update" "更新"
            "uninstall" "卸载"
        )
    else
        actions=(
            "start" "启动"
            "info" "项目信息"
            "update" "更新"
            "uninstall" "卸载"
        )
    fi
    
    local action
    action=$(ui_action "📁 $name ($status_text)" "${actions[@]}")
    
    case "$action" in
        start) project_start "$name" ;;
        stop) project_stop "$name" ;;
        restart) project_restart "$name" ;;
        logs) project_logs "$name" ;;
        info) project_show_info "$name" ;;
        update) project_update "$name" ;;
        uninstall) project_uninstall "$name" ;;
    esac
}

project_start() {
    local name="$1"
    local info dir
    info=$(project_get_info "$name")
    dir=$(echo "$info" | grep "^dir:" | cut -d' ' -f2-)
    
    ui_info "正在启动 $name..."
    
    if [[ -f "$dir/package.json" ]]; then
        cd "$dir"
        if command -v pm2 &>/dev/null; then
            pm2 start npm --name "$name" 2>&1
        else
            nohup npm start > "${CONFIG[log_dir]}/${name}.log" 2>&1 &
        fi
        ui_success "$name 已启动"
    else
        ui_error "无法确定如何启动此项目"
    fi
}

project_stop() {
    local name="$1"
    
    ui_info "正在停止 $name..."
    
    if command -v pm2 &>/dev/null; then
        pm2 stop "$name" 2>&1
    else
        pkill -f "$name" 2>&1 || true
    fi
    
    ui_success "$name 已停止"
}

project_restart() {
    local name="$1"
    
    ui_info "正在重启 $name..."
    
    if command -v pm2 &>/dev/null; then
        pm2 restart "$name" 2>&1
    else
        project_stop "$name"
        sleep 1
        project_start "$name"
    fi
    
    ui_success "$name 已重启"
}

project_logs() {
    local name="$1"
    local log_file="${CONFIG[log_dir]}/${name}.log"
    
    if [[ -f "$log_file" ]]; then
        tail -100 "$log_file" | ui_text "📋 $name 日志"
    elif command -v pm2 &>/dev/null; then
        pm2 logs "$name" --lines 100 --nostream 2>&1 | ui_text "📋 $name 日志"
    else
        ui_msg "未找到日志文件" "提示"
    fi
}

project_show_info() {
    local name="$1"
    local info
    info=$(project_get_info "$name")
    
    local dir type installed
    dir=$(echo "$info" | grep "^dir:" | cut -d' ' -f2-)
    type=$(echo "$info" | grep "^type:" | cut -d' ' -f2-)
    installed=$(echo "$info" | grep "^installed:" | cut -d' ' -f2-)
    
    local status
    if project_is_running "$name"; then
        status="🟢 运行中"
    else
        status="🔴 已停止"
    fi
    
    local content
    content="项目名称: $name
状态: $status
类型: $type
目录: $dir
安装时间: $installed"
    
    ui_text "$content" "📁 项目信息"
}

project_update() {
    local name="$1"
    local info dir type
    info=$(project_get_info "$name")
    dir=$(echo "$info" | grep "^dir:" | cut -d' ' -f2-)
    type=$(echo "$info" | grep "^type:" | cut -d' ' -f2-)
    
    if [[ "$type" == "git" ]] && [[ -d "$dir/.git" ]]; then
        ui_info "正在更新 $name..."
        cd "$dir"
        git pull 2>&1
        ui_success "$name 更新完成"
    else
        ui_msg "此项目不支持自动更新" "提示"
    fi
}

project_uninstall() {
    local name="$1"
    
    if ! ui_confirm "确定要卸载 $name 吗？\n这将删除项目目录和所有数据"; then
        return
    fi
    
    local info dir
    info=$(project_get_info "$name")
    dir=$(echo "$info" | grep "^dir:" | cut -d' ' -f2-)
    
    project_stop "$name" 2>/dev/null || true
    
    rm -rf "$dir"
    project_remove_info "$name"
    
    ui_success "$name 已卸载"
}

project_is_installed() {
    local name="$1"
    [[ -f "${CONFIG[data_dir]}/projects/${name}.info" ]]
}

project_is_running() {
    local name="$1"
    
    if command -v pm2 &>/dev/null; then
        pm2 describe "$name" &>/dev/null
    else
        pgrep -f "$name" &>/dev/null
    fi
}

project_save_info() {
    local name="$1"
    local dir="$2"
    local type="$3"
    
    local info_dir="${CONFIG[data_dir]}/projects"
    mkdir -p "$info_dir"
    
    cat > "${info_dir}/${name}.info" << EOF
name: $name
dir: $dir
type: $type
installed: $(date '+%Y-%m-%d %H:%M:%S')
EOF
}

project_get_info() {
    local name="$1"
    local info_file="${CONFIG[data_dir]}/projects/${name}.info"
    
    if [[ -f "$info_file" ]]; then
        cat "$info_file"
    else
        echo "name: $name"
        echo "dir: ${CONFIG[install_dir]}/app/$name"
        echo "type: unknown"
        echo "installed: unknown"
    fi
}

project_remove_info() {
    local name="$1"
    rm -f "${CONFIG[data_dir]}/projects/${name}.info"
}

project_get_all() {
    local info_dir="${CONFIG[data_dir]}/projects"
    
    if [[ -d "$info_dir" ]]; then
        for file in "$info_dir"/*.info; do
            if [[ -f "$file" ]]; then
                local name dir
                name=$(grep "^name:" "$file" | cut -d' ' -f2-)
                dir=$(grep "^dir:" "$file" | cut -d' ' -f2-)
                echo "$name|$dir"
            fi
        done
    fi
}
