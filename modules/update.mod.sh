#!/bin/bash

update_menu() {
    cd "$PROJECT_ROOT"
    
    if [[ ! -d ".git" ]]; then
        ui_msg "非 Git 安装，无法检查更新" "提示"
        return
    fi
    
    ui_info "正在检查更新..."
    git fetch origin 2>/dev/null
    
    local current_commit latest_commit
    current_commit=$(git rev-parse --short HEAD 2>/dev/null)
    latest_commit=$(git rev-parse --short origin/main 2>/dev/null)
    
    local status
    if [[ "$current_commit" != "$latest_commit" ]]; then
        status="⬆️ 有新版本: $latest_commit"
    else
        status="✅ 已是最新版本"
    fi
    
    local choice
    choice=$(ui_submenu "🔄 脚本更新" "当前版本: $PROJECT_VERSION ($current_commit)\n$status" \
        "1" "立即更新" \
        "2" "查看更新日志" \
        "3" "查看远程变更")
    
    case "$choice" in
        1) update_do ;;
        2) update_changelog ;;
        3) update_show_changes ;;
    esac
}

update_show_changes() {
    cd "$PROJECT_ROOT"
    
    if [[ ! -d ".git" ]]; then
        ui_msg "非 Git 安装" "提示"
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
    
    ui_msg "按 Enter 返回" "查看完成"
}

update_check() {
    cd "$PROJECT_ROOT"
    
    if [[ ! -d ".git" ]]; then
        ui_msg "非 Git 安装，无法检查更新" "提示"
        return
    fi
    
    ui_info "正在检查更新..."
    git fetch origin 2>/dev/null
    
    local current_commit latest_commit
    current_commit=$(git rev-parse HEAD 2>/dev/null)
    latest_commit=$(git rev-parse origin/main 2>/dev/null)
    
    if [[ "$current_commit" == "$latest_commit" ]]; then
        ui_msg "当前已是最新版本" "提示"
    else
        local behind
        behind=$(git rev-list --count HEAD..origin/main 2>/dev/null)
        ui_msg "发现新版本，落后 $behind 个提交\n当前: ${current_commit:0:7}\n最新: ${latest_commit:0:7}" "更新可用"
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
