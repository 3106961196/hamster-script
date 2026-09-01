#!/bin/bash

# 三平台镜像（由 update_source 指定其一；不再同时探测多个）
_UPDATE_GITHUB_URL="https://github.com/3106961196/hamster-script.git"
_UPDATE_GITEE_URL="https://gitee.com/duac/hamster-script.git"
_UPDATE_GITCODE_URL="https://gitcode.com/duac/hamster-script.git"

# ─── 更新源 ─────────────────────────────────────────

_更新_源URL() {
    case "$1" in
        github) printf '%s' "$_UPDATE_GITHUB_URL" ;;
        gitee) printf '%s' "$_UPDATE_GITEE_URL" ;;
        gitcode) printf '%s' "$_UPDATE_GITCODE_URL" ;;
        *) return 1 ;;
    esac
}

_更新_源显示名() {
    case "$1" in
        github) echo "GitHub" ;;
        gitee) echo "Gitee" ;;
        gitcode) echo "GitCode" ;;
        *) echo "$1" ;;
    esac
}

# 解析当前更新源：显式配置 > 区域默认（国内 Gitee，海外 GitHub）
_更新_当前源() {
    local src
    src="$(获取配置 "update_source" "")"
    case "$src" in
        github|gitee|gitcode) printf '%s' "$src"; return 0 ;;
    esac
    if _更新_国内优先; then
        printf '%s' "gitee"
    else
        printf '%s' "github"
    fi
}

_更新_分支() {
    git symbolic-ref -q --short HEAD 2>/dev/null || echo main
}

_更新_国内优先() {
    if declare -F 是否国内区域 &>/dev/null; then
        是否国内区域 && return 0
        return 1
    fi
    case "${HAMSTER_REGION:-}" in cn) return 0 ;; esac
    return 1
}

# 注册/校正指定远程，并把 origin 指到同一地址（单源更新）
_更新_注册远程() {
    local name="$1"
    local url
    url="$(_更新_源URL "$name")" || return 1
    cd "$PROJECT_ROOT" || return 1

    if git remote get-url "$name" >/dev/null 2>&1; then
        git remote set-url "$name" "$url" >/dev/null 2>&1 || true
    else
        git remote add "$name" "$url" >/dev/null 2>&1 || true
    fi

    if git remote get-url origin >/dev/null 2>&1; then
        git remote set-url origin "$url" >/dev/null 2>&1 || true
    else
        git remote add origin "$url" >/dev/null 2>&1 || true
    fi
}

# 某远程上尝试的分支名（Gitee 默认 master，其余多为 main）
_更新_远程分支候选() {
    local name="$1" local_branch="$2"
    case "$name" in
        gitee) printf '%s' "master main ${local_branch}" ;;
        *) printf '%s' "${local_branch} main master" ;;
    esac
}

# 仅拉取当前配置源；成功输出: ref|source
_更新_拉取最佳() {
    cd "$PROJECT_ROOT" || return 1

    local name local_branch remote_branch tip
    name="$(_更新_当前源)"
    _更新_注册远程 "$name" || return 1

    local_branch="$(_更新_分支)"

    for remote_branch in $(_更新_远程分支候选 "$name" "$local_branch"); do
        if timeout 45 git fetch --depth 1 --prune "$name" \
            "+refs/heads/${remote_branch}:refs/remotes/${name}/${remote_branch}" >/dev/null 2>&1; then
            tip="${name}/${remote_branch}"
            git rev-parse --verify "$tip" >/dev/null 2>&1 || continue
            printf '%s|%s' "$tip" "$name"
            return 0
        fi
    done
    return 1
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

# ─── 菜单 ─────────────────────────────────────────

脚本设置_菜单() {
    while true; do
        local choice src label
        src="$(_更新_当前源)"
        label="$(_更新_源显示名 "$src")"
        choice=$(界面子菜单 "脚本设置" "当前更新源: ${label}" \
            "1" "检查并更新脚本" \
            "2" "切换脚本更新源")

        case "$choice" in
            1) 更新_执行 ;;
            2) 更新_切换源 ;;
            b|"") break ;;
        esac
    done
}

更新_菜单() {
    脚本设置_菜单
}

更新_切换源() {
    local current choice name url label
    current="$(_更新_当前源)"

    choice=$(界面子菜单 "切换脚本更新源" "当前: $(_更新_源显示名 "$current")（只查所选仓库）" \
        "1" "Gitee$([ "$current" = gitee ] && echo ' *')" \
        "2" "GitCode$([ "$current" = gitcode ] && echo ' *')" \
        "3" "GitHub$([ "$current" = github ] && echo ' *')")

    case "$choice" in
        1) name=gitee ;;
        2) name=gitcode ;;
        3) name=github ;;
        *) return ;;
    esac

    if [[ "$name" == "$current" ]] && [[ "$(获取配置 "update_source" "")" == "$name" ]]; then
        界面消息 "已是 $(_更新_源显示名 "$name")" "提示"
        return
    fi

    CONFIG[update_source]="$name"
    保存用户配置

    url="$(_更新_源URL "$name")"
    if [[ -d "$PROJECT_ROOT/.git" ]]; then
        _更新_注册远程 "$name" || true
    fi

    label="$(_更新_源显示名 "$name")"
    界面成功 "更新源已切换为: ${label}\n${url}"
}

更新_执行() {
    local result exit_code status rest
    local behind current_commit latest_commit ref source
    local changes diff_summary dirty_msg
    local src_label

    src_label="$(_更新_源显示名 "$(_更新_当前源)")"

    界面清屏
    printf '正在检查更新（%s）...\n\n' "$src_label" >&2
    result=$(_更新_检查)
    exit_code=$?
    界面清屏

    if [[ $exit_code -eq 2 ]]; then
        界面消息 "非 Git 安装，请手动更新" "提示"
        return
    fi

    if [[ $exit_code -eq 3 || -z "$result" ]]; then
        界面错误 "无法从 ${src_label} 拉取\n请检查网络，或在「脚本设置」中换源后重试"
        return 1
    fi

    status="${result%%|*}"
    rest="${result#*|}"

    if [[ "$status" == "latest" ]]; then
        source="${rest%%|*}"
        ref="${rest#*|}"
        界面消息 "当前已是最新版本\n来源: $(_更新_源显示名 "$source")" "提示"
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

    if ! 界面确认 "来源: $(_更新_源显示名 "$source")\n${current_commit} → ${latest_commit}（约 ${behind} 提交）\n\n确定要更新到最新版本吗？${dirty_msg}"; then
        return
    fi

    if 界面任务 "正在从 $(_更新_源显示名 "$source") 更新..." _更新_执行 "$ref"; then
        界面成功 "脚本更新成功！（$(_更新_源显示名 "$source")）"

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
