#!/bin/bash

# ─── 内部辅助函数 ─────────────────────────────────────────

_更新_检查() {
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

_更新_执行() {
    if git reset --hard origin/main && git clean -f -d; then
        # 恢复文件权限
        find "$PROJECT_ROOT" -type f \( -name "*.sh" -o -name "cs" \) -exec chmod +x {} \; 2>/dev/null
        return 0
    fi
    return 1
}

# ─── 公开函数 ─────────────────────────────────────────

更新_菜单() {
    更新_执行
}

更新_执行() {
    界面信息 "正在检查更新..."

    local result
    result=$(_更新_检查)
    local exit_code=$?

    if [[ $exit_code -eq 2 ]]; then
        界面消息 "非 Git 安装，请手动更新" "提示"
        return
    fi

    if [[ "$result" == "latest" ]]; then
        界面消息 "当前已是最新版本" "提示"
        return
    fi

    cd "$PROJECT_ROOT"

    # 在更新前保存变更内容（带颜色）
    local changes diff_summary
    changes=$(git diff --stat --color=always HEAD origin/main 2>/dev/null)
    diff_summary=$(git diff --numstat HEAD origin/main 2>/dev/null | awk '{added+=$1; removed+=$2} END {printf "+%d / -%d", added, removed}')

    界面信息 "正在更新脚本..."

    local dirty_msg=""
    if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
        dirty_msg="\n\n⚠️ 检测到本地未提交修改，更新将丢失这些改动"
    fi

    if ! 界面确认 "确定要更新到最新版本吗？${dirty_msg}"; then
        return
    fi

    if _更新_执行; then
        界面成功 "脚本更新成功！"

        echo ""
        echo -e "${COLOR_PURPLE}========== 代码变更统计 ==========${COLOR_RESET}"
        echo -e "${changes}"
        echo -e "${COLOR_PURPLE}==================================${COLOR_RESET}"
        echo -e "变更概览: ${COLOR_GREEN}${diff_summary}${COLOR_RESET} 行"

        echo ""
        for i in 3 2 1; do
            echo "${i}秒后自动重启..."
            sleep 1
        done
        echo "正在重启..."

        exec "$PROJECT_ROOT/bin/cs"
    else
        界面错误 "更新失败"
    fi
}
