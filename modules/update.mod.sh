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
    update_do
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

    # 保存更新前的变更内容
    local changes diff_summary
    changes=$(git diff --stat HEAD origin/main 2>/dev/null)
    diff_summary=$(git diff --numstat HEAD origin/main 2>/dev/null | awk '{added+=$1; removed+=$2} END {printf "+%d / -%d", added, removed}')

    ui_info "正在更新脚本..."

    if _update_execute; then
        ui_success "脚本更新成功！"

        # 显示更新内容
        local content
        content=$(cat <<CHANGELOG

========== 代码变更统计 ==========
${changes}
==================================

变更概览: ${diff_summary} 行
CHANGELOG
        )
        ui_text "$content" "更新内容"

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
