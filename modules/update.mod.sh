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
    ui_info "正在检查更新..."
    
    cd "$PROJECT_ROOT"
    
    if [[ ! -d ".git" ]]; then
        ui_msg "非 Git 安装，请手动更新" "提示"
        return
    fi
    
    git fetch origin 2>/dev/null
    
    local current_commit latest_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)
    latest_commit=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$current_commit" == "$latest_commit" ]]; then
        ui_msg "当前已是最新版本" "提示"
        return
    fi
    
    echo ""
    echo "========== 代码变更统计 =========="
    git diff --stat HEAD origin/main 2>/dev/null
    echo "=================================="
    echo ""
    
    local diff_summary
    diff_summary=$(git diff --numstat HEAD origin/main 2>/dev/null | awk '{added+=$1; removed+=$2} END {printf "+%d / -%d", added, removed}')
    echo "变更概览: $diff_summary 行"
    echo ""
    
    if ! ui_confirm "确定要更新脚本吗？"; then
        return
    fi
    
    ui_info "正在更新脚本..."
    
    if git reset --hard origin/main && git clean -f -d; then
        ui_success "脚本更新成功！"
        echo ""
        echo "3秒后自动重启..."
        sleep 1
        echo "2秒后自动重启..."
        sleep 1
        echo "1秒后自动重启..."
        sleep 1
        echo "正在重启..."
        exec "$PROJECT_ROOT/bin/cs"
    else
        ui_error "更新失败"
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
