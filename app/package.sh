#!/bin/bash

软件包_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "📦 软件管理" "请选择功能:" \
            "1" "安装软件" \
            "2" "已装列表" \
            "3" "更新软件源")
        
        case "$choice" in
            1) 软件包_安装 ;;
            2) 软件包_已安装列表 ;;
            3) 软件包_更新软件源 ;;
            b) break ;;
        esac
    done
}

软件包_安装() {
    local search_term
    search_term=$(界面输入 "🔍 搜索软件 (留空显示常用软件)")
    
    local items=()
    
    if [[ -n "$search_term" ]]; then
        界面信息 "正在搜索: $search_term ..."
        local search_results
        search_results=$(包管理_搜索 "$search_term" 2>/dev/null | head -20)
        
        if [[ -n "$search_results" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    local pkg_name pkg_desc
                    pkg_name=$(echo "$line" | awk '{print $1}')
                    pkg_desc=$(echo "$line" | cut -d' ' -f2- | xargs)
                    [[ -n "$pkg_name" ]] && items+=("$pkg_name" "$pkg_desc")
                fi
            done <<< "$search_results"
        fi
    fi
    
    # 常用软件列表：优先读取配置文件，否则使用默认值
    local common_file="${SCRIPT_DIR:-.}/common_packages.conf"
    local common_packages=()
    if [[ -f "$common_file" ]]; then
        while IFS='|' read -r name desc _rest; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            common_packages+=("$name" "${desc:-}")
        done < "$common_file"
    fi
    
    if [[ ${#common_packages[@]} -eq 0 ]]; then
        common_packages=("git" "版本控制" "vim" "编辑器" "htop" "系统监控"
            "curl" "网络工具" "wget" "下载工具" "tmux" "终端复用"
            "jq" "JSON处理" "tree" "目录树" "ncdu" "磁盘分析"
            "net-tools" "网络工具集" "dialog" "对话框" "ripgrep" "快速搜索")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        items=("${common_packages[@]}")
    else
        界面消息 "未找到 \"${search_term}\" 相关结果，显示常用软件" "提示"
        items+=("" "" "── 常用软件 ──" "")
        items+=("${common_packages[@]}")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        界面消息 "未找到相关软件" "提示"
        return
    fi
    
    local selected
    selected=$(界面选择 "📦 安装软件" "选择要安装的软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    软件包_安装指定包 "$selected"
}

软件包_安装指定包() {
    local pkg_name="$1"
    
    if 包管理_是否已安装 "$pkg_name"; then
        local current_version
        current_version=$(包管理_获取版本 "$pkg_name" 2>/dev/null)
        界面消息 "$pkg_name 已安装\n当前版本: $current_version" "提示"
        return
    fi
    
    local versions
    versions=$(包管理_获取版本列表 "$pkg_name" 2>/dev/null)
    
    local version_items=()
    if [[ -n "$versions" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                version_items+=("$line" "")
            fi
        done <<< "$versions"
    fi
    
    local selected_version
    if [[ ${#version_items[@]} -gt 2 ]]; then
        selected_version=$(界面选择 "📦 $pkg_name - 选择版本" "选择版本:" "${version_items[@]}")
        [[ -z "$selected_version" ]] && return
    else
        selected_version="latest"
    fi
    
    local action
    action=$(界面动作 "📦 $pkg_name" \
        "install" "安装" \
        "info" "查看详情" \
        "cancel" "取消")
    
    case "$action" in
        install)
            界面信息 "正在安装 $pkg_name..."
            if 包管理_安装 "$pkg_name" 2>&1; then
                界面成功 "$pkg_name 安装成功"
            else
                界面错误 "$pkg_name 安装失败"
            fi
            ;;
        info)
            local info
            info=$(包管理_显示信息 "$pkg_name" 2>/dev/null)
            界面文本 "$info" "📦 $pkg_name 详情"
            ;;
        cancel)
            return
            ;;
    esac
}

软件包_已安装列表() {
    界面信息 "正在获取已安装软件列表..."
    
    local temp_file="${CONFIG[temp_dir]}/installed_packages.txt"
    包管理_已安装列表 > "$temp_file" 2>/dev/null
    
    local upgrade_file="${CONFIG[temp_dir]}/upgradable_packages.txt"
    包管理_可升级列表 > "$upgrade_file" 2>/dev/null &
    local check_pid=$!
    
    local items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pkg_name pkg_version
            pkg_name=$(echo "$line" | awk '{print $1}')
            pkg_version=$(echo "$line" | awk '{print $2}')
            [[ -n "$pkg_name" ]] && items+=("$pkg_name" "$pkg_version")
        fi
    done < "$temp_file"
    
    if [[ ${#items[@]} -eq 0 ]]; then
        界面消息 "无法获取已安装软件列表" "错误"
        return
    fi
    
    local upgradable_count=0
    local upgrade_items=()
    
    界面加载动画 "$check_pid" "正在检查软件更新..."
    wait "$check_pid" 2>/dev/null
    
    if [[ -f "$upgrade_file" ]] && [[ -s "$upgrade_file" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local upg_name upg_old upg_new
                upg_name=$(echo "$line" | awk '{print $1}')
                upg_old=$(echo "$line" | awk '{print $2}')
                upg_new=$(echo "$line" | awk '{print $3}')
                
                for i in "${!items[@]}"; do
                    if [[ $((i % 2)) -eq 0 ]] && [[ "${items[$i]}" == "$upg_name" ]]; then
                        items[$((i+1))]="${upg_old} ⬆️ ${upg_new}"
                        break
                    fi
                done
                
                upgradable_count=$((upgradable_count + 1))
            fi
        done < "$upgrade_file"
    fi
    
    local selected
    selected=$(界面选择 "📦 已装列表 (${upgradable_count}个可更新)" "选择软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    软件包_包操作 "$selected"
}

软件包_包操作() {
    local pkg_name="$1"
    local current_version new_version
    
    current_version=$(包管理_获取版本 "$pkg_name" 2>/dev/null)
    new_version=$(包管理_获取可升级版本 "$pkg_name" 2>/dev/null)
    
    local actions
    if [[ -n "$new_version" ]] && [[ "$new_version" != "$current_version" ]]; then
        actions=(
            "upgrade" "升级到 $new_version"
            "info" "查看详情"
            "uninstall" "卸载"
            "cancel" "返回"
        )
    else
        actions=(
            "info" "查看详情"
            "uninstall" "卸载"
            "cancel" "返回"
        )
    fi
    
    local action
    action=$(界面动作 "📦 $pkg_name ($current_version)" "${actions[@]}")
    
    case "$action" in
        upgrade)
            if 界面确认 "确定要升级 $pkg_name 吗？"; then
                界面信息 "正在升级 $pkg_name..."
                if 包管理_升级 "$pkg_name" 2>&1; then
                    界面成功 "$pkg_name 升级成功"
                else
                    界面错误 "$pkg_name 升级失败"
                fi
            fi
            ;;
        info)
            local info
            info=$(包管理_显示信息 "$pkg_name" 2>/dev/null)
            界面文本 "$info" "📦 $pkg_name 详情"
            软件包_包操作 "$pkg_name"
            ;;
        uninstall)
            if 界面确认 "确定要卸载 $pkg_name 吗？"; then
                界面信息 "正在卸载 $pkg_name..."
                if 包管理_卸载 "$pkg_name" 2>&1; then
                    界面成功 "$pkg_name 卸载成功"
                else
                    界面错误 "$pkg_name 卸载失败"
                fi
            fi
            ;;
        cancel)
            return
            ;;
    esac
}

软件包_更新软件源() {
    界面信息 "正在更新软件源..."
    
    if 包管理_更新源 2>&1; then
        界面成功 "软件源更新成功"
    else
        界面错误 "软件源更新失败"
    fi
}
