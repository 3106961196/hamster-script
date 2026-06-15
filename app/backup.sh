#!/bin/bash

backup_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "💾 备份恢复" "请选择功能:" \
            "1" "创建备份" \
            "2" "备份管理")
        
        case "$choice" in
            1) backup_create ;;
            2) backup_manage ;;
            b) break ;;
        esac
    done
}

backup_create() {
    local items=()
    items+=("/home" "用户主目录")
    items+=("/etc" "系统配置")
    items+=("/root" "Root 目录")
    items+=("/var/www" "网站目录")
    items+=("/var/lib" "数据目录")
    items+=("custom" "自定义路径...")
    
    local selected
    selected=$(ui_select "💾 创建备份" "选择要备份的目录:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    local backup_dir
    if [[ "$selected" == "custom" ]]; then
        backup_dir=$(ui_input "请输入要备份的目录路径")
        [[ -z "$backup_dir" ]] && return
    else
        backup_dir="$selected"
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        ui_msg "目录不存在: $backup_dir" "错误"
        return
    fi
    
    local backup_name
    backup_name=$(basename "$backup_dir")
    backup_name="${backup_name}_$(date +%Y%m%d_%H%M%S)"
    
    backup_name=$(ui_input "备份名称" "$backup_name")
    [[ -z "$backup_name" ]] && return
    
    local backup_path="${CONFIG[backup_dir]}"
    ensure_dir "$backup_path"
    
    ui_info "正在创建备份 $backup_name..."
    
    local temp_log="${CONFIG[temp_dir]}/backup_create.log"
    if tar -czf "$backup_path/${backup_name}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>&1 | tee "$temp_log"; then
        local size
        size=$(du -h "$backup_path/${backup_name}.tar.gz" | cut -f1)
        ui_success "备份创建成功\n\n文件: $backup_path/${backup_name}.tar.gz\n大小: $size"
    else
        ui_error "备份创建失败"
    fi
}

backup_manage() {
    local backup_path="${CONFIG[backup_dir]}"
    
    if [[ ! -d "$backup_path" ]]; then
        ui_msg "备份目录不存在" "提示"
        return
    fi
    
    local items=()
    
    while IFS= read -r file; do
        if [[ -n "$file" ]] && [[ "$file" == *.tar.gz ]]; then
            local name size mtime
            name=$(basename "$file")
            size=$(du -h "$file" 2>/dev/null | cut -f1)
            mtime=$(stat -c %y "$file" 2>/dev/null | cut -d. -f1)
            items+=("$file" "$size | $mtime")
        fi
    done < <(find "$backup_path" -name "*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "暂无备份文件" "提示"
        return
    fi
    
    local selected
    selected=$(ui_select "💾 备份管理" "选择备份文件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    backup_file_action "$selected"
}

backup_file_action() {
    local file="$1"
    local name size mtime
    name=$(basename "$file")
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    mtime=$(stat -c %y "$file" 2>/dev/null | cut -d. -f1)
    
    local action
    action=$(ui_action "💾 $name\n大小: $size\n时间: $mtime" \
        "restore" "恢复备份" \
        "view" "查看内容" \
        "delete" "删除备份")
    
    case "$action" in
        restore) backup_restore "$file" ;;
        view) backup_view_content "$file" ;;
        delete) backup_delete "$file" ;;
    esac
}

backup_restore() {
    local file="$1"
    local name
    name=$(basename "$file" .tar.gz)
    
    local restore_dir
    restore_dir=$(ui_input "请输入恢复目录" "/tmp/restore_${name}")
    
    [[ -z "$restore_dir" ]] && return
    
    if [[ -d "$restore_dir" ]] && [[ "$(ls -A "$restore_dir" 2>/dev/null)" ]]; then
        if ! ui_confirm "目录 $restore_dir 不为空，是否覆盖？"; then
            return
        fi
    fi
    
    ensure_dir "$restore_dir"
    
    ui_info "正在恢复备份..."
    
    if tar -xzf "$file" -C "$restore_dir" 2>&1; then
        ui_success "备份已恢复到 $restore_dir"
    else
        ui_error "恢复失败"
    fi
}

backup_view_content() {
    local file="$1"
    
    ui_info "正在读取备份内容..."
    
    local content
    content=$(tar -tzf "$file" 2>/dev/null | head -100)
    
    if [[ -z "$content" ]]; then
        ui_msg "无法读取备份内容" "错误"
        return
    fi
    
    ui_text "$content" "📋 备份内容"
}

backup_delete() {
    local file="$1"
    local name
    name=$(basename "$file")
    
    if ui_confirm "确定要删除备份 $name 吗？\n\n此操作不可恢复！"; then
        rm -f "$file" 2>&1 && ui_success "备份已删除" || ui_error "删除失败"
    fi
}
