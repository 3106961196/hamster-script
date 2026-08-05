#!/bin/bash

# 三平台镜像（更新时按可达性自动选用；国内优先 Gitee/GitCode）
_更新_GITHUB_URL="https://github.com/3106961196/hamster-script.git"
_更新_GITEE_URL="https://gitee.com/duac/hamster-script.git"
_更新_GITCODE_URL="https://gitcode.com/duac/hamster-script.git"

# ─── 内部辅助函数 ─────────────────────────────────────────

_更新_分支() {
    git symbolic-ref -q --short HEAD 2>/dev/null || echo main
}

_更新_国内优先() {
    if declare -F _是否国内区域 &>/dev/null; then
        _是否国内区域 && return 0
    fi
    if declare -F _是否国内时区 &>/dev/null; then
        _是否国内时区 && return 0
    fi
    case "${HAMSTER_REGION:-}" in cn) return 0 ;; esac
    return 1
}

# 确保 github / gitee / gitcode 远程存在（不改动 origin）
_更新_注册镜像远程() {
    cd "$PROJECT_ROOT" || return 1
    local name url
    local -a pairs=(
        "github|${_更新_GITHUB_URL}"
        "gitee|${_更新_GITEE_URL}"
        "gitcode|${_更新_GITCODE_URL}"
    )
    for pair in "${pairs[@]}"; do
        name="${pair%%|*}"
        url="${pair#*|}"
        if git remote get-url "$name" >/dev/null 2>&1; then
            git remote set-url "$name" "$url" >/dev/null 2>&1 || true
        else
            git remote add "$name" "$url" >/dev/null 2>&1 || true
        fi
    done
}

# 输出尝试顺序（空格分隔）
_更新_远程顺序() {
    local -a order
    if _更新_国内优先; then
        order=(gitee gitcode github)
    else
        order=(github gitee gitcode)
    fi
    # origin 保留用户自定义地址，优先试一次
    if git remote get-url origin >/dev/null 2>&1; then
        order=(origin "${order[@]}")
    fi
    printf '%s' "${order[*]}"
}

# 拉取各镜像；成功则选提交时间最新的 tip
# 输出: ref|source   失败 return 1
_更新_拉取最佳() {
    cd "$PROJECT_ROOT" || return 1
    _更新_注册镜像远程 || return 1

    local branch name tip ts best_ts=0 best_ref="" best_name="" fetched=0
    branch="$(_更新_分支)"

    for name in $(_更新_远程顺序); do
        git remote get-url "$name" >/dev/null 2>&1 || continue
        if timeout 45 git fetch --depth 1 --prune "$name" \
            "+refs/heads/${branch}:refs/remotes/${name}/${branch}" >/dev/null 2>&1; then
            tip="${name}/${branch}"
            git rev-parse --verify "$tip" >/dev/null 2>&1 || continue
            fetched=1
            ts=$(git log -1 --format=%ct "$tip" 2>/dev/null || echo 0)
            [[ "$ts" =~ ^[0-9]+$ ]] || ts=0
            # 同时间戳保留先成功的（顺序即优先级）
            if [[ -z "$best_ref" || "$ts" -gt "$best_ts" ]]; then
                best_ts=$ts
                best_ref=$tip
                best_name=$name
            fi
        fi
    done

    [[ "$fetched" -eq 1 && -n "$best_ref" ]] || return 1
    printf '%s|%s' "$best_ref" "$best_name"
}

_更新_检查() {
    cd "$PROJECT_ROOT" || return 1

    if [[ ! -d ".git" ]]; then
        return 2
    fi

    local picked ref source current_commit latest_commit behind
    picked=$(_更新_拉取最佳) || return 3
    ref="${picked%%|*}"
    source="${picked#*|}"

    current_commit=$(git rev-parse --short HEAD 2>/dev/null)
    latest_commit=$(git rev-parse --short "$ref" 2>/dev/null)

    if [[ -n "$current_commit" && "$current_commit" == "$latest_commit" ]]; then
        echo "latest|${source}|${ref}"
        return 0
    fi

    behind=$(git rev-list --count HEAD.."$ref" 2>/dev/null || echo "?")
    echo "update|${behind}|${current_commit}|${latest_commit}|${ref}|${source}"
}

_更新_执行() {
    local ref="${1:-}"
    [[ -n "$ref" ]] || return 1

    if git reset --hard "$ref" && git clean -f -d; then
        安装_后处理 "$PROJECT_ROOT"
        return 0
    fi
    return 1
}

# ─── 公开函数 ─────────────────────────────────────────

更新_菜单() {
    更新_执行
}

更新_执行() {
    local result exit_code status rest
    local behind current_commit latest_commit ref source
    local changes diff_summary dirty_msg

    界面清屏
    printf '正在检查更新（GitHub / Gitee / GitCode）...\n\n' >&2
    result=$(_更新_检查)
    exit_code=$?
    界面清屏

    if [[ $exit_code -eq 2 ]]; then
        界面消息 "非 Git 安装，请手动更新" "提示"
        return
    fi

    if [[ $exit_code -eq 3 || -z "$result" ]]; then
        界面错误 "三平台均无法拉取\n请检查网络，或稍后重试"
        return 1
    fi

    status="${result%%|*}"
    rest="${result#*|}"

    if [[ "$status" == "latest" ]]; then
        source="${rest%%|*}"
        ref="${rest#*|}"
        界面消息 "当前已是最新版本\n来源: ${source}" "提示"
        return
    fi

    # update|behind|current|latest|ref|source
    behind="${rest%%|*}"
    rest="${rest#*|}"
    current_commit="${rest%%|*}"
    rest="${rest#*|}"
    latest_commit="${rest%%|*}"
    rest="${rest#*|}"
    ref="${rest%%|*}"
    source="${rest#*|}"

    cd "$PROJECT_ROOT" || return 1

    changes=$(git diff --stat --color=always HEAD "$ref" 2>/dev/null)
    diff_summary=$(git diff --numstat HEAD "$ref" 2>/dev/null | awk '{added+=$1; removed+=$2} END {printf "+%d / -%d", added, removed}')

    dirty_msg=""
    if [[ -n "$(git diff --numstat 2>/dev/null)" || -n "$(git diff --cached --numstat 2>/dev/null)" ]]; then
        dirty_msg="\n\n⚠️ 检测到本地未提交修改，更新将丢失这些改动"
    fi

    if ! 界面确认 "来源: ${source}\n${current_commit} → ${latest_commit}（约 ${behind} 提交）\n\n确定要更新到最新版本吗？${dirty_msg}"; then
        return
    fi

    if 界面任务 "正在从 ${source} 更新..." _更新_执行 "$ref"; then
        界面成功 "脚本更新成功！（${source}）"

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
