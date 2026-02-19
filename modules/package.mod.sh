#!/bin/bash

package_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "软件管理" "请选择功能:" \
            "1" "安装软件" \
            "2" "搜索软件" \
            "3" "已装列表" \
            "4" "卸载软件" \
            "5" "更新软件源" \
            "6" "升级所有软件")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "b" ]]; then
            break
        fi
        
        case "$choice" in
            1) package_install ;;
            2) package_search ;;
            3) package_list ;;
            4) package_remove ;;
            5) package_update_sources ;;
            6) package_upgrade_all ;;
        esac
    done
}

package_install() {
    local package_name
    package_name=$(ui_input "请输入要安装的软件包名称:")
    
    if [[ -z "$package_name" ]]; then
        return
    fi
    
    if pkg_is_installed "$package_name"; then
        ui_msg "$package_name 已经安装"
        return
    fi
    
    ui_info "正在安装 $package_name..."
    
    local temp_log="${CONFIG[temp_dir]}/package_install.log"
    if pkg_install "$package_name" 2>&1 | tee "$temp_log"; then
        ui_msg "$package_name 安装成功"
    else
        ui_msg "$package_name 安装失败，请查看日志:\n$temp_log" "错误"
    fi
}

package_search() {
    local keyword
    keyword=$(ui_input "请输入搜索关键词:")
    
    if [[ -z "$keyword" ]]; then
        return
    fi
    
    local temp_log="${CONFIG[temp_dir]}/package_search.log"
    pkg_search "$keyword" > "$temp_log" 2>&1
    
    if [[ -s "$temp_log" ]]; then
        ui_textbox "$temp_log" "搜索结果"
    else
        ui_msg "未找到匹配的软件包"
    fi
}

package_list() {
    local temp_log="${CONFIG[temp_dir]}/package_list.log"
    pkg_list_installed > "$temp_log" 2>&1
    
    if [[ -s "$temp_log" ]]; then
        ui_textbox "$temp_log" "已安装软件"
    else
        ui_msg "无法获取软件列表"
    fi
}

package_remove() {
    local package_name
    package_name=$(ui_input "请输入要卸载的软件包名称:")
    
    if [[ -z "$package_name" ]]; then
        return
    fi
    
    if ! pkg_is_installed "$package_name"; then
        ui_msg "$package_name 未安装"
        return
    fi
    
    if ui_confirm "确定要卸载 $package_name 吗？"; then
        ui_info "正在卸载 $package_name..."
        
        local temp_log="${CONFIG[temp_dir]}/package_remove.log"
        if pkg_remove "$package_name" 2>&1 | tee "$temp_log"; then
            ui_msg "$package_name 卸载成功"
        else
            ui_msg "$package_name 卸载失败" "错误"
        fi
    fi
}

package_update_sources() {
    ui_info "正在更新软件源..."
    
    local temp_log="${CONFIG[temp_dir]}/package_update.log"
    if pkg_update 2>&1 | tee "$temp_log"; then
        ui_msg "软件源更新成功"
    else
        ui_msg "软件源更新失败" "错误"
    fi
}

package_upgrade_all() {
    if ui_confirm "确定要升级所有软件包吗？"; then
        ui_info "正在升级软件包..."
        
        local temp_log="${CONFIG[temp_dir]}/package_upgrade.log"
        if pkg_upgrade 2>&1 | tee "$temp_log"; then
            ui_msg "软件包升级成功"
        else
            ui_msg "软件包升级失败，请查看日志" "错误"
        fi
    fi
}
