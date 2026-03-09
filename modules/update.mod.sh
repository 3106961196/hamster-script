#!/bin/bash

update_menu() {
    local current_version latest_version
    current_version="$PROJECT_VERSION"
    
    ui_info "正在检查更新..."
    latest_version=$(update_check_latest 2>/dev/null)
    
    local status
    if [[ -n "$latest_version" ]] && [[ "$latest_version" != "$current_version" ]]; then
        status="⬆️ 有新版本: $latest_version"
    else
        status="✅ 已是最新版本"
    fi
    
    local choice
    choice=$(ui_submenu "🔄 脚本更新" "当前版本: $current_version\n$status" \
        "1" "立即更新" \
        "2" "查看更新日志" \
        "3" "检查更新")
    
    case "$choice" in
        1) update_do ;;
        2) update_changelog ;;
        3) update_check ;;
    esac
}

update_check() {
    ui_info "正在检查更新..."
    
    local latest_version
    latest_version=$(update_check_latest 2>/dev/null)
    
    if [[ -z "$latest_version" ]]; then
        ui_msg "无法检查更新，请检查网络连接" "错误"
        return
    fi
    
    if [[ "$latest_version" == "$PROJECT_VERSION" ]]; then
        ui_msg "当前已是最新版本: $PROJECT_VERSION" "提示"
    else
        ui_msg "发现新版本: $latest_version\n当前版本: $PROJECT_VERSION" "更新可用"
    fi
}

update_do() {
    if ! ui_confirm "确定要更新脚本吗？"; then
        return
    fi
    
    ui_info "正在更新脚本..."
    
    cd "$PROJECT_ROOT"
    
    if [[ -d ".git" ]]; then
        if git fetch origin && git reset --hard origin/main && git clean -f -d; then
            ui_success "脚本更新成功！"
            ui_msg "请重新运行脚本以使用新版本" "提示"
            exit 0
        else
            ui_error "更新失败"
        fi
    else
        ui_msg "非 Git 安装，请手动更新" "提示"
    fi
}

update_changelog() {
    ui_info "正在获取更新日志..."
    
    local changelog
    changelog=$(curl -sL "https://raw.githubusercontent.com/3106961196/hamster-script/main/CHANGELOG.md" 2>/dev/null | head -100)
    
    if [[ -z "$changelog" ]]; then
        ui_msg "无法获取更新日志" "提示"
        return
    fi
    
    ui_text "$changelog" "📋 更新日志"
}

update_check_latest() {
    local version
    version=$(curl -sL "https://raw.githubusercontent.com/3106961196/hamster-script/main/lib/core.sh" 2>/dev/null | grep "PROJECT_VERSION=" | head -1 | cut -d'"' -f2)
    echo "$version"
}
