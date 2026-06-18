#!/bin/bash
# 不使用 gh：原生 GitHub API fork + push + 创建 PR
set -euo pipefail

UPSTREAM="3106961196/hamster-script"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_DIR"

TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | awk -F= '/^password=/{print $2}')
if [[ -z "$TOKEN" ]]; then
    echo "错误: 无法获取 GitHub token" >&2
    exit 1
fi

FORK_OWNER=$(curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
echo "GitHub 用户: $FORK_OWNER"

git remote set-url origin "https://github.com/${UPSTREAM}.git"
if git remote get-url fork &>/dev/null; then
    git remote set-url fork "https://github.com/${FORK_OWNER}/hamster-script.git"
else
    git remote add fork "https://github.com/${FORK_OWNER}/hamster-script.git"
fi

HTTP=$(curl -s -o /tmp/hamster-fork.json -w '%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    "https://api.github.com/repos/${UPSTREAM}/forks")
case "$HTTP" in
    200|202|422) echo "Fork 就绪 (HTTP $HTTP)" ;;
    *) echo "Fork 失败 (HTTP $HTTP):"; cat /tmp/hamster-fork.json; exit 1 ;;
esac

json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

create_pr() {
    local branch="$1" title="$2" body="$3"
    local head="${FORK_OWNER}:${branch}"
    local esc_title esc_body payload url http_code resp

    local existing
    existing=$(curl -s -H "Authorization: Bearer $TOKEN" \
        "https://api.github.com/repos/${UPSTREAM}/pulls?head=${head}&state=open" | \
        sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
    if [[ -n "$existing" ]]; then
        echo "PR 已存在: $existing"
        return 0
    fi

    esc_title=$(json_escape "$title")
    esc_body=$(json_escape "$body")
    payload="{\"title\":\"${esc_title}\",\"head\":\"${head}\",\"base\":\"main\",\"body\":\"${esc_body}\"}"

    resp=$(curl -s -w '\n__HTTP__:%{http_code}' -X POST \
        -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" \
        -d "$payload" \
        "https://api.github.com/repos/${UPSTREAM}/pulls")

    http_code="${resp##*__HTTP__:}"
    body_resp="${resp%__HTTP__:*}"
    url=$(echo "$body_resp" | sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

    if [[ "$http_code" == "201" && -n "$url" ]]; then
        echo "PR 已创建: $url"
    else
        echo "PR 创建失败 (HTTP $http_code): $body_resp" >&2
        return 1
    fi
}

BRANCHES=(
    "fix/tool-bootstrap|fix: add tool_bootstrap for standalone tool scripts|工具 install/manage 脚本在子 shell 中运行时缺少 log/pkg 等库，导致函数未定义。"
    "fix/config-system|fix: wire config loading and save_user_config|支持默认/系统/用户三层配置加载；实现 save_user_config；添加 get_install_dir/get_work_dir。"
    "fix/install-paths|fix: remove hardcoded /cs install paths|tmux、cs 包装脚本和项目安装路径改为从 INSTALL_DIR/配置读取。"
    "fix/git-proxy-and-safe-update|fix: make GitHub proxy opt-in and confirm before hard reset|Git 代理需 ENABLE_GITHUB_PROXY=1；setup/update 在 hard reset 前检测本地改动并确认。"
    "fix/tool-start-security|fix: replace eval in tool_start with bash -c|用 nohup bash -c 替代 eval 启动工具；统一 xrk-agt 安装后启动流程。"
    "fix/cli-and-docs|feat: add cs update/version/help CLI aliases|支持 cs update/version/help，保留 cs r 别名；同步 README 与 setup 提示。"
    "fix/apt-and-security|fix: apt mirror for Debian and harden dangerous ops|Debian 使用 debian 镜像路径；用户删除列表排除 root；移除无效时区；iptables 清空前警告。"
    "chore/remove-dev-artifacts|chore: remove local dev artifacts from repo|删除 fix_pick.ps1、reasonix.toml 并加入 .gitignore。"
)

PR_URLS=()
FAILED=0

for entry in "${BRANCHES[@]}"; do
    IFS='|' read -r branch title summary <<< "$entry"
    body="${summary}

## Test plan
- [ ] bash -n 语法检查相关脚本
- [ ] 在 Linux 环境运行 cs 验证对应功能"

    echo ""
    echo "==> $branch"
    git push -u fork "$branch" || { echo "push 失败: $branch" >&2; FAILED=$((FAILED+1)); continue; }

    if create_pr "$branch" "$title" "$body"; then
        url=$(curl -s -H "Authorization: Bearer $TOKEN" \
            "https://api.github.com/repos/${UPSTREAM}/pulls?head=${FORK_OWNER}:${branch}&state=open" | \
            sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
        [[ -n "$url" ]] && PR_URLS+=("$url")
    else
        FAILED=$((FAILED+1))
    fi
done

echo ""
echo "========== PR 列表 =========="
for u in "${PR_URLS[@]}"; do echo "$u"; done
echo "=============================="
echo "https://github.com/${UPSTREAM}/pulls"
exit $FAILED
