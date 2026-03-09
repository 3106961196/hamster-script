#!/bin/bash

package_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "📦 软件管理" "请选择功能:" \
            "1" "安装软件" \
            "2" "已装列表" \
            "3" "更新软件源")
        
        case "$choice" in
            1) package_install ;;
            2) package_installed_list ;;
            3) package_update_sources ;;
            b) break ;;
        esac
    done
}

package_install() {
    local search_term
    search_term=$(ui_input "🔍 搜索软件 (留空显示常用软件)")
    
    local items=()
    
    if [[ -n "$search_term" ]]; then
        ui_info "正在搜索: $search_term ..."
        local search_results
        search_results=$(pkg_search "$search_term" 2>/dev/null | head -20)
        
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
    
    local common_packages=("git" "版本控制" "vim" "编辑器" "htop" "系统监控" 
        "curl" "网络工具" "wget" "下载工具" "tmux" "终端复用"
        "jq" "JSON处理" "tree" "目录树" "ncdu" "磁盘分析"
        "net-tools" "网络工具集" "fzf" "模糊搜索" "ripgrep" "快速搜索")
    
    if [[ ${#items[@]} -eq 0 ]]; then
        items=("${common_packages[@]}")
    else
        items+=("" "" "── 常用软件 ──" "")
        items+=("${common_packages[@]}")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        ui_msg "未找到相关软件" "提示"
        return
    fi
    
    local selected
    selected=$(ui_select "📦 安装软件" "选择要安装的软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    package_install_package "$selected"
}

package_install_package() {
    local pkg_name="$1"
    
    if pkg_is_installed "$pkg_name"; then
        local current_version
        current_version=$(pkg_get_version "$pkg_name" 2>/dev/null)
        ui_msg "$pkg_name 已安装\n当前版本: $current_version" "提示"
        return
    fi
    
    local versions
    versions=$(pkg_get_versions "$pkg_name" 2>/dev/null)
    
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
        selected_version=$(ui_select "📦 $pkg_name - 选择版本" "选择版本:" "${version_items[@]}")
        [[ -z "$selected_version" ]] && return
    else
        selected_version="latest"
    fi
    
    local action
    action=$(ui_action "📦 $pkg_name" \
        "install" "安装" \
        "info" "查看详情" \
        "cancel" "取消")
    
    case "$action" in
        install)
            ui_info "正在安装 $pkg_name..."
            if pkg_install "$pkg_name" 2>&1; then
                ui_success "$pkg_name 安装成功"
            else
                ui_error "$pkg_name 安装失败"
            fi
            ;;
        info)
            local info
            info=$(pkg_show_info "$pkg_name" 2>/dev/null)
            ui_text "$info" "📦 $pkg_name 详情"
            ;;
        cancel)
            return
            ;;
    esac
}

package_installed_list() {
    ui_info "正在获取已安装软件列表..."
    
    local temp_file="${CONFIG[temp_dir]}/installed_packages.txt"
    pkg_list_installed > "$temp_file" 2>/dev/null
    
    local upgrade_file="${CONFIG[temp_dir]}/upgradable_packages.txt"
    pkg_list_upgradable > "$upgrade_file" 2>/dev/null &
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
        ui_msg "无法获取已安装软件列表" "错误"
        return
    fi
    
    local upgradable_count=0
    local upgrade_items=()
    
    ui_spinner "$check_pid" "正在检查软件更新..."
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
    selected=$(ui_select "📦 已装列表 (${upgradable_count}个可更新)" "选择软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    package_package_action "$selected"
}

package_package_action() {
    local pkg_name="$1"
    local current_version new_version
    
    current_version=$(pkg_get_version "$pkg_name" 2>/dev/null)
    new_version=$(pkg_get_upgradable_version "$pkg_name" 2>/dev/null)
    
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
    action=$(ui_action "📦 $pkg_name ($current_version)" "${actions[@]}")
    
    case "$action" in
        upgrade)
            if ui_confirm "确定要升级 $pkg_name 吗？"; then
                ui_info "正在升级 $pkg_name..."
                if pkg_upgrade "$pkg_name" 2>&1; then
                    ui_success "$pkg_name 升级成功"
                else
                    ui_error "$pkg_name 升级失败"
                fi
            fi
            ;;
        info)
            local info
            info=$(pkg_show_info "$pkg_name" 2>/dev/null)
            ui_text "$info" "📦 $pkg_name 详情"
            package_package_action "$pkg_name"
            ;;
        uninstall)
            if ui_confirm "确定要卸载 $pkg_name 吗？"; then
                ui_info "正在卸载 $pkg_name..."
                if pkg_remove "$pkg_name" 2>&1; then
                    ui_success "$pkg_name 卸载成功"
                else
                    ui_error "$pkg_name 卸载失败"
                fi
            fi
            ;;
        cancel)
            return
            ;;
    esac
}

package_update_sources() {
    ui_info "正在更新软件源..."
    
    if pkg_update 2>&1; then
        ui_success "软件源更新成功"
    else
        ui_error "软件源更新失败"
    fi
}
