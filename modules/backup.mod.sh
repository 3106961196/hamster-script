#!/bin/bash

backup_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "备份恢复" "请选择功能:" \
            "1" "创建备份" \
            "2" "恢复备份" \
            "3" "备份列表" \
            "4" "删除备份")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) backup_create ;;
            2) backup_restore ;;
            3) backup_list ;;
            4) backup_delete ;;
        esac
    done
}

backup_create() {
    local backup_name
    backup_name=$(ui_input "请输入备份名称" "backup_$(date +%Y%m%d_%H%M%S)")
    
    if [[ -z "$backup_name" ]]; then
        return
    fi
    
    local backup_dir
    backup_dir=$(ui_input "请输入要备份的目录" "/home")
    
    if [[ -z "$backup_dir" ]]; then
        return
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        ui_msg "目录不存在: $backup_dir" "错误"
        return
    fi
    
    local backup_path="${CONFIG[backup_dir]}"
    ensure_dir "$backup_path"
    
    ui_info "正在创建备份 $backup_name..."
    
    local temp_log="${CONFIG[temp_dir]}/backup_create.log"
    if tar -czf "$backup_path/${backup_name}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>&1 | tee "$temp_log"; then
        local size
        size=$(du -h "$backup_path/${backup_name}.tar.gz" | cut -f1)
        ui_msg "备份创建成功\n\n文件: $backup_path/${backup_name}.tar.gz\n大小: $size"
    else
        ui_msg "备份创建失败" "错误"
    fi
}

backup_restore() {
    local backup_path="${CONFIG[backup_dir]}"
    
    if [[ ! -d "$backup_path" ]]; then
        ui_msg "备份目录不存在" "错误"
        return
    fi
    
    local backups=()
    for file in "$backup_path"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local name
            name=$(basename "$file" .tar.gz)
            backups+=("$name")
        fi
    done
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        ui_msg "没有可用的备份"
        return
    fi
    
    local items=()
    for backup in "${backups[@]}"; do
        items+=("$backup" "备份文件")
    done
    
    local choice
    choice=$(ui_submenu "选择备份" "请选择要恢复的备份:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    local restore_dir
    restore_dir=$(ui_input "请输入恢复目录" "/tmp/restore")
    
    if [[ -z "$restore_dir" ]]; then
        return
    fi
    
    if ui_confirm "确定要将备份 $choice 恢复到 $restore_dir 吗？"; then
        ensure_dir "$restore_dir"
        
        ui_info "正在恢复备份..."
        
        local temp_log="${CONFIG[temp_dir]}/backup_restore.log"
        if tar -xzf "$backup_path/${choice}.tar.gz" -C "$restore_dir" 2>&1 | tee "$temp_log"; then
            ui_msg "备份恢复成功\n\n恢复位置: $restore_dir"
        else
            ui_msg "备份恢复失败" "错误"
        fi
    fi
}

backup_list() {
    local backup_path="${CONFIG[backup_dir]}"
    
    if [[ ! -d "$backup_path" ]]; then
        ui_msg "备份目录不存在"
        return
    fi
    
    local temp_log="${CONFIG[temp_dir]}/backup_list.log"
    
    {
        echo "备份列表:"
        echo ""
        
        local count=0
        for file in "$backup_path"/*.tar.gz; do
            if [[ -f "$file" ]]; then
                local name
                name=$(basename "$file" .tar.gz)
                local size
                size=$(du -h "$file" | cut -f1)
                local time
                time=$(stat -c %y "$file" 2>/dev/null | cut -d. -f1)
                echo "$name"
                echo "  大小: $size"
                echo "  时间: $time"
                echo ""
                ((count++))
            fi
        done
        
        if [[ $count -eq 0 ]]; then
            echo "没有备份文件"
        else
            echo "共 $count 个备份"
        fi
    } > "$temp_log" 2>&1
    
    ui_textbox "$temp_log" "备份列表"
}

backup_delete() {
    local backup_path="${CONFIG[backup_dir]}"
    
    if [[ ! -d "$backup_path" ]]; then
        ui_msg "备份目录不存在" "错误"
        return
    fi
    
    local backups=()
    for file in "$backup_path"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            local name
            name=$(basename "$file" .tar.gz)
            backups+=("$name")
        fi
    done
    
    if [[ ${#backups[@]} -eq 0 ]]; then
        ui_msg "没有可删除的备份"
        return
    fi
    
    local items=()
    for backup in "${backups[@]}"; do
        items+=("$backup" "备份文件")
    done
    
    local choice
    choice=$(ui_submenu "删除备份" "请选择要删除的备份:" "${items[@]}")
    
    if [[ -z "$choice" ]] || [[ "$choice" == "b" ]]; then
        return
    fi
    
    if ui_confirm "确定要删除备份 $choice 吗？\n\n此操作不可恢复！"; then
        if rm -f "$backup_path/${choice}.tar.gz" 2>&1; then
            ui_msg "备份 $choice 已删除"
        else
            ui_msg "删除失败" "错误"
        fi
    fi
}
