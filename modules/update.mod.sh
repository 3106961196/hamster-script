#!/bin/bash

# ─── 内部辅助函数 ─────────────────────────────────────────

_update_check() {
    cd "$PROJECT_ROOT" || return 1

    if [[ ! -d ".git" ]]; then
        return 2
    fi

    git fetch origin 2>/dev/null

    local current_commit latest_commit
    current_commit=$(git rev-parse --short HEAD 2>/dev/null)
    latest_commit=$(git rev-parse --short origin/main 2>/dev/null)

    if [[ "$current_commit" == "$latest_commit" ]]; then
        echo "latest"
    else
        local behind
        behind=$(git rev-list --count HEAD..origin/main 2>/dev/null)
        echo "update:$behind:$current_commit:$latest_commit"
    fi
}

_update_show_changes() {
    echo ""
    echo "========== 代码变更统计 =========="
    git diff --stat HEAD origin/main 2>/dev/null
    echo "=================================="
    echo ""

    local diff_summary
    diff_summary=$(git diff --numstat HEAD origin/main 2>/dev/null | awk '{added+=$1; removed+=$2} END {printf "+%d / -%d", added, removed}')
    echo "变更概览: $diff_summary 行"
    echo ""
}

_update_execute() {
    if git reset --hard origin/main && git clean -f -d; then
        # 恢复文件权限
        find "$PROJECT_ROOT" -type f \( -name "*.sh" -o -name "cs" \) -exec chmod +x {} \; 2>/dev/null
        return 0
    fi
    return 1
}

# ─── 公开函数 ─────────────────────────────────────────

update_menu() {
    local result
    result=$(_update_check)
    local exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        ui_msg "非 Git 安装，无法检查更新" "提示"
        return
    fi

    local status current_commit latest_commit
    if [[ "$result" == "latest" ]]; then
        status="已是最新版本"
    else
        local behind
        behind=$(echo "$result" | cut -d: -f2)
        current_commit=$(echo "$result" | cut -d: -f3)
        latest_commit=$(echo "$result" | cut -d: -f4)
        status="有新版本 (落后 $behind 个提交)"
    fi

    local choice
    choice=$(ui_submenu "脚本更新" "当前版本: $PROJECT_VERSION ($current_commit)\n状态: $status" \
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
    local result
    result=$(_update_check)
    local exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        ui_msg "非 Git 安装" "提示"
        return
    fi

    if [[ "$result" == "latest" ]]; then
        ui_msg "当前已是最新版本" "提示"
        return
    fi

    cd "$PROJECT_ROOT"
    _update_show_changes
    ui_msg "按 Enter 返回" "查看完成"
}

update_do() {
    ui_info "正在检查更新..."

    local result
    result=$(_update_check)
    local exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        ui_msg "非 Git 安装，请手动更新" "提示"
        return
    fi

    if [[ "$result" == "latest" ]]; then
        ui_msg "当前已是最新版本" "提示"
        return
    fi

    cd "$PROJECT_ROOT"
    _update_show_changes

    if ! ui_confirm "确定要更新脚本吗？"; then
        return
    fi

    ui_info "正在更新脚本..."

    if _update_execute; then
        ui_success "脚本更新成功！"

        echo ""
        for i in 3 2 1; do
            echo "${i}秒后自动重启..."
            sleep 1
        done
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

    ui_text "$changelog" "更新日志"
}
