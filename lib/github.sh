#!/bin/bash
# GitHub 访问：国内走代理，海外直连（区域见 lib/region.sh）

_HAMSTER_GITHUB_PROXY_CACHED="${_HAMSTER_GITHUB_PROXY_CACHED:-}"

# 按实测稳定性排序；克隆失败时再依次 fallback
_GITHUB_PROXIES=(
    "https://gh-proxy.com"
    "https://ghfast.top"
    "https://mirror.ghproxy.com"
    "https://ghp.ci"
    "https://gitclone.com/github.com"
)

_代理化GitHub地址() {
    local proxy="$1" direct="$2"
    case "$proxy" in
        https://gitclone.com/github.com)
            echo "${proxy}/${direct#https://github.com/}"
            ;;
        *)
            echo "${proxy}/${direct}"
            ;;
    esac
}

_GitHub_代理可用() {
    local proxy="$1"
    [[ -n "$proxy" ]] || return 1
    # 探针失败也允许下载阶段再试（部分镜像首页 403 但 release 仍可下）
    curl -fsS --connect-timeout 3 --max-time 5 -o /dev/null \
        "${proxy}/https://github.com" 2>/dev/null && return 0
    curl -fsS --connect-timeout 3 --max-time 8 -r 0-1024 -o /dev/null \
        "${proxy}/https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip" 2>/dev/null
}

_缓存代理自克隆地址() {
    local url="$1" p
    for p in "${_GITHUB_PROXIES[@]}"; do
        case "$url" in
            "${p}"/*) _HAMSTER_GITHUB_PROXY_CACHED="$p"; return 0 ;;
        esac
    done
    return 1
}

_挑选GitHub代理() {
    local proxy

    [[ -n "$_HAMSTER_GITHUB_PROXY_CACHED" ]] && {
        echo "$_HAMSTER_GITHUB_PROXY_CACHED"
        return 0
    }

    for proxy in "${_GITHUB_PROXIES[@]}"; do
        if _GitHub_代理可用 "$proxy"; then
            _HAMSTER_GITHUB_PROXY_CACHED="$proxy"
            echo "[git] 加速: ${proxy#https://}" >&2
            echo "$proxy"
            return 0
        fi
    done

    echo "[git] 无可用加速，将尝试直连" >&2
    echo ""
}

_GitHub_清理URL() {
    local url="$1"
    url=$(echo "$url" | sed -E '
        s|^https?://[^/]+/https://github\.com|https://github.com|;
        s|^https?://[^/]+/github\.com|https://github.com|;
        s|^https?://gitclone\.com/github\.com/|https://github.com/|;
        s|^https?://gh(proxy)?[.][^/]+/|https://|;
        s|/$||
    ')
    echo "$url"
}

# 用法：getgh url_var | getgh "https://github.com/..."
getgh() {
    local arg="$1" var_name="" original_url proxy="" new_url

    case "$arg" in
        https://github.com/*|https://raw.githubusercontent.com/*)
            original_url="$arg"
            ;;
        http://*|https://*)
            printf '%s\n' "$arg"
            return 0
            ;;
        *)
            var_name="$arg"
            case "$var_name" in
                ''|*'['*|*']'*|*' '*|*'$'*|*'*'*|*'?'*|*'!'*)
                    return 0
                    ;;
            esac
            original_url="${!var_name}"
            case "$original_url" in
                https://github.com/*|https://raw.githubusercontent.com/*) ;;
                *) return 0 ;;
            esac
            ;;
    esac

    new_url="$original_url"
    if 是否国内区域; then
        proxy="$(_挑选GitHub代理)"
        [[ -n "$proxy" ]] && new_url="$(_代理化GitHub地址 "$proxy" "$original_url")"
    fi

    if [[ -n "$var_name" ]]; then
        printf -v "$var_name" '%s' "$new_url"
    else
        printf '%s\n' "$new_url"
    fi
}

_git_克隆一次() {
    local label="$1" url="$2" dest="$3" depth="$4"
    local errf last_line rc git_bin

    git_bin=$(command -v git) || { echo "[git] 未找到 git" >&2; return 1; }
    errf="${TMPDIR:-/tmp}/hamster_git_err_$$_${RANDOM}"
    echo "[git] → ${label}" >&2
    rm -rf "$dest" 2>/dev/null || true

    if command -v timeout &>/dev/null; then
        timeout 90 env GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= \
            "$git_bin" clone --depth="$depth" "$url" "$dest" 2>"$errf"
    else
        GIT_TERMINAL_PROMPT=0 GIT_ASKPASS= \
            "$git_bin" clone --depth="$depth" "$url" "$dest" 2>"$errf"
    fi
    rc=$?

    if [[ "$rc" -eq 0 && -d "$dest/.git" ]]; then
        echo "[git] ✓ ${label}" >&2
        rm -f "$errf"
        return 0
    fi

    last_line=$(tail -n 1 "$errf" 2>/dev/null | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    case "$rc" in
        124) echo "[git] ✗ ${label}（超时 90s）" >&2 ;;
        *)
            if [[ -n "$last_line" ]]; then
                echo "[git] ✗ ${label}: ${last_line}" >&2
            else
                echo "[git] ✗ ${label}" >&2
            fi
            ;;
    esac
    rm -f "$errf"
    rm -rf "$dest" 2>/dev/null || true
    return 1
}

_git_已尝试() {
    local u="$1" x
    for x in "${_GIT_TRIED[@]}"; do
        [[ "$x" = "$u" ]] && return 0
    done
    return 1
}

_git_记录尝试() {
    _GIT_TRIED+=("$1")
}

_git_试克隆() {
    local label="$1" url="$2" dest="$3" depth="$4"
    [[ -z "$url" ]] && return 1
    _git_已尝试 "$url" && return 1
    _git_记录尝试 "$url"
    _git_克隆一次 "$label" "$url" "$dest" "$depth"
}

GitHub_克隆() {
    local url="$1" dest="$2" depth="${3:-1}"
    local direct name region proxy proxied u
    local -a _GIT_TRIED=()

    [[ -z "$url" || -z "$dest" ]] && return 1
    command -v git &>/dev/null || { echo "[git] 未找到 git" >&2; return 1; }

    direct="$(_GitHub_清理URL "$url")"
    name="${direct##*/}"
    region=$(网络_检测区域 2>/dev/null || echo overseas)

    echo "[git] 克隆 ${name} | 区域: ${region} | 目标: ${dest}" >&2

    if [[ -n "$_HAMSTER_GITHUB_PROXY_CACHED" ]]; then
        proxied="$(_代理化GitHub地址 "$_HAMSTER_GITHUB_PROXY_CACHED" "$direct")"
        if _git_试克隆 "缓存代理 ${_HAMSTER_GITHUB_PROXY_CACHED#https://}" "$proxied" "$dest" "$depth"; then
            return 0
        fi
        _HAMSTER_GITHUB_PROXY_CACHED=""
    fi

    if 是否国内区域; then
        proxy="$(_挑选GitHub代理)"
        if [[ -n "$proxy" ]]; then
            proxied="$(_代理化GitHub地址 "$proxy" "$direct")"
            _git_试克隆 "代理 ${proxy#https://}" "$proxied" "$dest" "$depth" \
                && { _缓存代理自克隆地址 "$proxied" || true; return 0; }
        fi
    fi

    _git_试克隆 "直连 GitHub" "$direct" "$dest" "$depth" \
        && { _HAMSTER_GITHUB_PROXY_CACHED=""; return 0; }

    for proxy in "${_GITHUB_PROXIES[@]}"; do
        proxied="$(_代理化GitHub地址 "$proxy" "$direct")"
        _git_试克隆 "代理 ${proxy#https://}" "$proxied" "$dest" "$depth" \
            && { _缓存代理自克隆地址 "$proxied" || true; return 0; }
    done

    echo "[git] 克隆失败（已试 ${#_GIT_TRIED[@]} 种方式）: $direct" >&2
    echo "[git] 提示: export HAMSTER_REGION=cn 后重试，或检查防火墙/DNS" >&2
    return 1
}

# 本机/环境是否配置了本地代理（如 mihomo 127.0.0.1:7890）
_GitHub_有本地代理() {
    case "${https_proxy:-}${HTTPS_PROXY:-}${http_proxy:-}${HTTP_PROXY:-}${ALL_PROXY:-}${all_proxy:-}" in
        *127.0.0.1*|*localhost*) return 0 ;;
    esac
    return 1
}

# dialog/非登录壳常不读 /etc/environment：本机 7890 在听则自动补代理
_GitHub_补本地代理环境() {
    _GitHub_有本地代理 && return 0
    if command -v ss &>/dev/null; then
        ss -lntp 2>/dev/null | grep -qE '127\.0\.0\.1:7890\b' || return 1
    elif command -v curl &>/dev/null; then
        curl -fsS --connect-timeout 1 --max-time 2 -o /dev/null http://127.0.0.1:7890 2>/dev/null || return 1
    else
        return 1
    fi
    export http_proxy="${http_proxy:-http://127.0.0.1:7890}"
    export https_proxy="${https_proxy:-http://127.0.0.1:7890}"
    export HTTP_PROXY="${HTTP_PROXY:-$http_proxy}"
    export HTTPS_PROXY="${HTTPS_PROXY:-$https_proxy}"
    export ALL_PROXY="${ALL_PROXY:-socks5h://127.0.0.1:7890}"
    export all_proxy="${all_proxy:-$ALL_PROXY}"
    export NO_PROXY="${NO_PROXY:-127.0.0.1,localhost,::1}"
    export no_proxy="${no_proxy:-$NO_PROXY}"
    echo "[git] 已启用本机代理 127.0.0.1:7890" >&2
}

# GitHub 下载 URL 候选
# - 有本地代理：直连优先（走系统代理），镜像兜底
# - 国内无本地代理：公共加速镜像 → 直连
# - 海外：直连 → 镜像兜底（避免机房误判/直连挂死时无退路）
GitHub_下载候选() {
    local url="$1" direct proxy u
    local -A _seen=()
    local -a urls=() out=() mirrors=()

    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*) ;;
        *) printf '%s\n' "$url"; return 0 ;;
    esac

    _GitHub_补本地代理环境 || true

    direct="$(_GitHub_清理URL "$url")"
    [[ -z "$direct" ]] && return 1

    # 有本地代理时不预探公共镜像（每个探针数秒，易拖死安装）
    if ! _GitHub_有本地代理; then
        proxy="$(_挑选GitHub代理 2>/dev/null)" || true
        [[ -n "$proxy" ]] && mirrors+=("$(_代理化GitHub地址 "$proxy" "$direct")")
    fi
    for proxy in "${_GITHUB_PROXIES[@]}"; do
        mirrors+=("$(_代理化GitHub地址 "$proxy" "$direct")")
    done

    if _GitHub_有本地代理; then
        urls+=("$direct")
        urls+=("${mirrors[@]}")
    elif 是否国内区域; then
        urls+=("${mirrors[@]}")
        urls+=("$direct")
    else
        urls+=("$direct")
        urls+=("${mirrors[@]}")
    fi

    for u in "${urls[@]}"; do
        [[ -n "$u" && -z "${_seen[$u]:-}" ]] && { _seen[$u]=1; out+=("$u"); }
    done
    printf '%s\n' "${out[@]}"
}
