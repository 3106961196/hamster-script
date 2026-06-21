#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BRANCH="${1:-refactor/tmux-xrk-style}"
TITLE="${2:-refactor: consolidate tmux stack like xrk-projects-scripts}"
BODY="${3:-学习 xrk-projects-scripts 的 tmux 架构，删除底层冗余。}"

TOKEN=$(printf 'protocol=https\nhost=github.com\n\n' | git credential fill | awk -F= '/^password=/{print $2}')
FORK_OWNER=$(curl -s -H "Authorization: Bearer $TOKEN" https://api.github.com/user | sed -n 's/.*"login"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

git push -u fork "$BRANCH"

Json转义() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    printf '%s' "$s"
}

full_body="${BODY}

## Test plan
- [ ] hamster-tmux --setup
- [ ] hamster-tmux --status
- [ ] SSH 登录自动进入桌面
- [ ] cs tmux 手动进入"

payload="{\"title\":\"$(Json转义 "$TITLE")\",\"head\":\"${FORK_OWNER}:${BRANCH}\",\"base\":\"main\",\"body\":\"$(Json转义 "$full_body")\"}"

resp=$(curl -s -w '\n__HTTP__:%{http_code}' -X POST \
    -H "Authorization: Bearer $TOKEN" \
    -H "Accept: application/vnd.github+json" \
    -d "$payload" \
    "https://api.github.com/repos/3106961196/hamster-script/pulls")

http_code="${resp##*__HTTP__:}"
body_resp="${resp%__HTTP__:*}"
url=$(echo "$body_resp" | sed -n 's/.*"html_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')

if [[ "$http_code" == "201" && -n "$url" ]]; then
    echo "PR 已创建: $url"
else
    echo "失败 HTTP $http_code: $body_resp" >&2
    exit 1
fi
