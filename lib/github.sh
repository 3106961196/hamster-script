#!/bin/bash
# GitHub 访问：国内走代理，海外直连（HAMSTER_REGION=cn|overseas 可覆盖）

_HAMSTER_GITHUB_PROXY_CACHED="${_HAMSTER_GITHUB_PROXY_CACHED:-}"

# 按实测稳定性排序；克隆失败时再依次 fallback
_GITHUB_PROXIES=(
    "https://gh-proxy.com"
    "https://ghfast.top"
    "https://mirror.ghproxy.com"
    "https://ghp.ci"
    "https://gitclone.com/github.com"
)

_是否国内区域() {
    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn) return 0 ;;
        overseas) return 1 ;;
    esac
    case "${XRK_SOURCE:-}" in
        3|cn) return 0 ;;
    esac
    [[ "$(网络_检测区域 2>/dev/null || echo overseas)" = "cn" ]]
}

_是否国内时区() {
    local tz="${TZ:-$(cat /etc/timezone 2>/dev/null)}"
    case "$tz" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|Asia/Kashgar \
            |Asia/Hong_Kong|Asia/Macau|Asia/Taipei) return 0 ;;
    esac
    [[ -L /etc/localtime ]] && readlink /etc/localtime 2>/dev/null \
        | grep -qE 'Asia/(Shanghai|Chongqing|Harbin|Urumqi|Kashgar|Hong_Kong|Macau|Taipei)'
}

网络_检测区域() {
    local json country

    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn|overseas) echo "${HAMSTER_REGION:-$XRK_REGION}"; return 0 ;;
    esac

    if 命令存在 curl; then
        json=$(curl -s --connect-timeout 4 --max-time 8 "http://ip-api.com/json" 2>/dev/null || true)
        country=$(printf '%s' "$json" | grep -oE '"countryCode":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$country" ]]; then
            [[ "$country" = "CN" ]] && { echo "cn"; return 0; }
            echo "overseas"
            return 0
        fi
        # countryCode 解析失败时，尝试 country 字段
        case "$json" in
            *'"country":"China"'*) echo "cn"; return 0 ;;
        esac
    fi

    _是否国内时区 && { echo "cn"; return 0; }
    echo "overseas"
}

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
    if _是否国内区域; then
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

    if _是否国内区域; then
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

# GitHub 下载 URL 候选（国内：公共加速镜像 → 直连）
GitHub_下载候选() {
    local url="$1" direct proxy proxied u
    local -A _seen=()
    local -a urls=() out=()

    case "$url" in
        https://github.com/*|https://raw.githubusercontent.com/*) ;;
        *) printf '%s\n' "$url"; return 0 ;;
    esac

    direct="$(_GitHub_清理URL "$url")"
    [[ -z "$direct" ]] && return 1

    if _是否国内区域; then
        proxy="$(_挑选GitHub代理)"
        [[ -n "$proxy" ]] && urls+=("$(_代理化GitHub地址 "$proxy" "$direct")")
        for proxy in "${_GITHUB_PROXIES[@]}"; do
            urls+=("$(_代理化GitHub地址 "$proxy" "$direct")")
        done
    fi
    urls+=("$direct")

    for u in "${urls[@]}"; do
        [[ -n "$u" && -z "${_seen[$u]:-}" ]] && { _seen[$u]=1; out+=("$u"); }
    done
    printf '%s\n' "${out[@]}"
}
