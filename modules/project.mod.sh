#!/bin/bash

PROJECTS_CONFIG="${CONFIG[config_dir]}/projects.yaml"
PROJECTS_DEFAULT="$PROJECT_ROOT/config/projects.yaml"
PROJECTS_DATA="${CONFIG[data_dir]}/projects"

project_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "项目管理" "请选择功能:" \
            "1" "安装项目" \
            "2" "项目列表" \
            "3" "删除项目" \
            "4" "项目配置")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) project_install ;;
            2) project_list ;;
            3) project_delete ;;
            4) project_config ;;
        esac
    done
}

project_install() {
    if ! command_exists yq; then
        ui_info "正在安装 yq..."
        local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
        if command_exists wget; then
            wget -q "$yq_url" -O /usr/local/bin/yq && chmod +x /usr/local/bin/yq
        elif command_exists curl; then
            curl -sL "$yq_url" -o /usr/local/bin/yq && chmod +x /usr/local/bin/yq
        fi
        
        if ! command_exists yq; then
            ui_msg "yq 安装失败" "错误"
            return 1
        fi
    fi
    
    if [[ ! -f "$PROJECTS_CONFIG" ]]; then
        if [[ -f "$PROJECTS_DEFAULT" ]]; then
            cp "$PROJECTS_DEFAULT" "$PROJECTS_CONFIG"
        else
            ui_msg "项目配置文件不存在" "错误"
            return 1
        fi
    fi
    
    local project_count
    project_count=$(yq '.projects | length' "$PROJECTS_CONFIG" 2>/dev/null || echo "0")
    
    if [[ "$project_count" -eq 0 ]]; then
        ui_msg "没有可安装的项目"
        return 0
    fi
    
    local items=()
    local i=1
    while [[ $i -le $project_count ]]; do
        local name
        name=$(yq ".projects[$((i-1))].name" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
        if [[ -n "$name" && "$name" != "null" ]]; then
            items+=("$i" "$name")
        fi
        ((i++))
    done
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可安装的项目"
        return 0
    fi
    
    local choice
    choice=$(ui_submenu "安装项目" "请选择要安装的项目:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return 0
    fi
    
    local idx=$((choice - 1))
    local name url target pre post
    
    name=$(yq ".projects[$idx].name" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
    url=$(yq ".projects[$idx].url" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
    target=$(yq ".projects[$idx].target" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
    pre=$(yq ".projects[$idx].pre" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
    post=$(yq ".projects[$idx].post" "$PROJECTS_CONFIG" 2>/dev/null | sed 's/^"//;s/"$//')
    
    local project_dir="$target/$name"
    
    if [[ -d "$project_dir" ]]; then
        if ! ui_confirm "项目 $name 已存在，是否重新安装？"; then
            return 0
        fi
    else
        if ! ui_confirm "确定要安装项目 $name 吗？"; then
            return 0
        fi
    fi
    
    ui_clear
    
    log_section "安装项目"
    log_info "项目名称: $name"
    log_info "下载地址: $url"
    log_info "安装目录: $target"
    echo ""
    
    if [[ -n "$pre" && "$pre" != "null" ]]; then
        log_info "检查依赖..."
        IFS=',' read -ra deps <<< "$pre"
        for dep in "${deps[@]}"; do
            dep=$(trim "$dep")
            if [[ -n "$dep" ]]; then
                if ! command_exists "$dep"; then
                    log_info "安装依赖: $dep"
                    pkg_ensure_installed "$dep"
                fi
            fi
        done
    fi
    
    log_info "下载项目..."
    ensure_dir "$target"
    
    if [[ "$url" == git@* ]] || [[ "$url" == https://*git* ]]; then
        if [[ -d "$project_dir" ]]; then
            rm -rf "$project_dir"
        fi
        
        if git clone --depth 1 "$url" "$project_dir" 2>&1; then
            log_success "下载完成"
        else
            log_error "下载失败"
            ui_pause "按任意键返回..."
            return 1
        fi
    else
        source "$UTILS_DIR/download.sh"
        if ! download "$url" "$target" "$name"; then
            log_error "下载失败"
            ui_pause "按任意键返回..."
            return 1
        fi
    fi
    
    if [[ -n "$post" && "$post" != "null" ]]; then
        log_info "执行安装后命令..."
        echo ""
        
        IFS=';' read -ra cmds <<< "$post"
        for cmd in "${cmds[@]}"; do
            cmd=$(trim "$cmd")
            if [[ -n "$cmd" ]]; then
                log_info "执行: $cmd"
                (cd "$project_dir" && eval "$cmd")
            fi
        done
    fi
    
    ensure_dir "$PROJECTS_DATA"
    cat > "$PROJECTS_DATA/$name.json" << EOF
{
    "name": "$name",
    "url": "$url",
    "target_dir": "$target",
    "installed_at": "$(date +"%Y-%m-%d %H:%M:%S")",
    "status": "installed"
}
EOF
    
    echo ""
    log_section "安装完成"
    log_success "项目 $name 安装成功"
    echo ""
    ui_pause "按任意键返回..."
}

project_list() {
    local temp_log="${CONFIG[temp_dir]}/project_list.log"
    
    {
        echo "已安装项目:"
        echo ""
        
        if [[ -d "$PROJECTS_DATA" ]]; then
            local count=0
            for file in "$PROJECTS_DATA"/*.json; do
                if [[ -f "$file" ]]; then
                    local name target time
                    name=$(grep '"name"' "$file" | cut -d'"' -f4)
                    target=$(grep '"target_dir"' "$file" | cut -d'"' -f4)
                    time=$(grep '"installed_at"' "$file" | cut -d'"' -f4)
                    
                    echo "$name"
                    echo "  目录: $target"
                    echo "  时间: $time"
                    echo ""
                    ((count++))
                fi
            done
            
            if [[ $count -eq 0 ]]; then
                echo "没有已安装的项目"
            else
                echo "共 $count 个项目"
            fi
        else
            echo "没有已安装的项目"
        fi
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "项目列表"
}

project_delete() {
    if [[ ! -d "$PROJECTS_DATA" ]]; then
        ui_msg "没有已安装的项目"
        return
    fi
    
    local items=()
    for file in "$PROJECTS_DATA"/*.json; do
        if [[ -f "$file" ]]; then
            local name
            name=$(grep '"name"' "$file" | cut -d'"' -f4)
            items+=("$name" "已安装项目")
        fi
    done
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "没有可删除的项目"
        return
    fi
    
    local choice
    choice=$(ui_submenu "删除项目" "请选择要删除的项目:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    if ui_confirm "确定要删除项目 $choice 吗？\n\n这将删除项目目录和配置！"; then
        local config_file="$PROJECTS_DATA/$choice.json"
        local target_dir
        
        if [[ -f "$config_file" ]]; then
            target_dir=$(grep '"target_dir"' "$config_file" | cut -d'"' -f4)
            local project_dir="$target_dir/$choice"
            
            if [[ -d "$project_dir" ]]; then
                rm -rf "$project_dir"
            fi
            rm -f "$config_file"
        fi
        
        ui_msg "项目 $choice 已删除"
    fi
}

project_config() {
    if [[ ! -f "$PROJECTS_CONFIG" ]]; then
        ui_msg "项目配置文件不存在"
        return
    fi
    
    ui_textbox "$PROJECTS_CONFIG" "项目配置"
}
