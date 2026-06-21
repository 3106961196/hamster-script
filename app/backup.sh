#!/bin/bash

备份_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "💾 备份恢复" "请选择功能:" \
            "1" "创建备份" \
            "2" "备份管理")
        
        case "$choice" in
            1) 备份_创建 ;;
            2) 备份_管理 ;;
            b) break ;;
        esac
    done
}

备份_创建() {
    local items=()
    items+=("/home" "用户主目录")
    items+=("/etc" "系统配置")
    items+=("/root" "Root 目录")
    items+=("/var/www" "网站目录")
    items+=("/var/lib" "数据目录")
    items+=("custom" "自定义路径...")
    
    local selected
    selected=$(界面选择 "💾 创建备份" "选择要备份的目录:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    local backup_dir
    if [[ "$selected" == "custom" ]]; then
        backup_dir=$(界面输入 "请输入要备份的目录路径")
        [[ -z "$backup_dir" ]] && return
    else
        backup_dir="$selected"
    fi
    
    if [[ ! -d "$backup_dir" ]]; then
        界面消息 "目录不存在: $backup_dir" "错误"
        return
    fi
    
    local backup_name
    backup_name=$(basename "$backup_dir")
    backup_name="${backup_name}_$(date +%Y%m%d_%H%M%S)"
    
    backup_name=$(界面输入 "备份名称" "$backup_name")
    [[ -z "$backup_name" ]] && return
    
    local backup_path="${CONFIG[backup_dir]}"
    确保目录 "$backup_path"
    
    界面信息 "正在创建备份 $backup_name..."
    
    local temp_log="${CONFIG[temp_dir]}/backup_create.log"
    if tar -czf "$backup_path/${backup_name}.tar.gz" -C "$(dirname "$backup_dir")" "$(basename "$backup_dir")" 2>&1 | tee "$temp_log"; then
        local size
        size=$(du -h "$backup_path/${backup_name}.tar.gz" | cut -f1)
        界面成功 "备份创建成功\n\n文件: $backup_path/${backup_name}.tar.gz\n大小: $size"
    else
        界面错误 "备份创建失败"
    fi
}

备份_管理() {
    local backup_path="${CONFIG[backup_dir]}"
    
    if [[ ! -d "$backup_path" ]]; then
        界面消息 "备份目录不存在" "提示"
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
        界面消息 "暂无备份文件" "提示"
        return
    fi
    
    local selected
    selected=$(界面选择 "💾 备份管理" "选择备份文件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    备份_文件操作 "$selected"
}

备份_文件操作() {
    local file="$1"
    local name size mtime
    name=$(basename "$file")
    size=$(du -h "$file" 2>/dev/null | cut -f1)
    mtime=$(stat -c %y "$file" 2>/dev/null | cut -d. -f1)
    
    local action
    action=$(界面动作 "💾 $name\n大小: $size\n时间: $mtime" \
        "restore" "恢复备份" \
        "view" "查看内容" \
        "delete" "删除备份")
    
    case "$action" in
        restore) 备份_恢复 "$file" ;;
        view) 备份_查看内容 "$file" ;;
        delete) 备份_删除 "$file" ;;
    esac
}

备份_恢复() {
    local file="$1"
    local name
    name=$(basename "$file" .tar.gz)
    
    local restore_dir
    restore_dir=$(界面输入 "请输入恢复目录" "/tmp/restore_${name}")
    
    [[ -z "$restore_dir" ]] && return
    
    if [[ -d "$restore_dir" ]] && [[ "$(ls -A "$restore_dir" 2>/dev/null)" ]]; then
        if ! 界面确认 "目录 $restore_dir 不为空，是否覆盖？"; then
            return
        fi
    fi
    
    确保目录 "$restore_dir"
    
    界面信息 "正在恢复备份..."
    
    if tar -xzf "$file" -C "$restore_dir" 2>&1; then
        界面成功 "备份已恢复到 $restore_dir"
    else
        界面错误 "恢复失败"
    fi
}

备份_查看内容() {
    local file="$1"
    
    界面信息 "正在读取备份内容..."
    
    local content
    content=$(tar -tzf "$file" 2>/dev/null | head -100)
    
    if [[ -z "$content" ]]; then
        界面消息 "无法读取备份内容" "错误"
        return
    fi
    
    界面文本 "$content" "📋 备份内容"
}

备份_删除() {
    local file="$1"
    local name
    name=$(basename "$file")
    
    if 界面确认 "确定要删除备份 $name 吗？\n\n此操作不可恢复！"; then
        rm -f "$file" 2>&1 && 界面成功 "备份已删除" || 界面错误 "删除失败"
    fi
}
