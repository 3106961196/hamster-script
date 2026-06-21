#!/bin/bash
# Chromium 安装（xtradeb PPA，镜像测速 + 404 回退，对齐 xrk-projects-scripts）

_CHROMIUM_PPA_FP="82BB6851C64F6880"
_CHROMIUM_PPA_MIRRORS=(launchpad.proxy.ustclug.org ppa.launchpadcontent.net)

包管理_Chromium已安装() {
    command -v chromium &>/dev/null || dpkg -l chromium 2>/dev/null | grep -q '^ii'
}

包管理_Chromium版本() {
    local v

    v=$(dpkg -l chromium 2>/dev/null | awk '/^ii/ {print $3; exit}')
    [[ -n "$v" ]] && { echo "$v"; return 0; }

    command -v chromium &>/dev/null && {
        chromium --version 2>/dev/null | head -1
        return 0
    }

    return 1
}

_包管理_Chromium链接() {
    local bin="/usr/bin/chromium-browser"
    command -v chromium &>/dev/null || return 0
    [[ -e "$bin" ]] && return 0
    ln -sf "$(command -v chromium)" "$bin" 2>/dev/null && 日志信息 "已创建符号链接: chromium-browser"
}

_包管理_Chromium架构() {
    case "$(uname -m)" in
        aarch64|arm64) echo arm64 ;;
        armv7l|armhf) echo armhf ;;
        amd64|x86_64) echo amd64 ;;
        *) 日志错误 "不支持的架构: $(uname -m)"; return 1 ;;
    esac
}

_包管理_Chromium准备Apt() {
    local tool
    DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    for tool in wget curl gnupg ca-certificates apt-transport-https software-properties-common; do
        dpkg -l 2>/dev/null | grep -q "^ii  ${tool} " && continue
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "$tool" 2>/dev/null || true
    done
}

_包管理_Chromium选镜像() {
    local mirror elapsed start end min=999999 pick=""
    for mirror in "${_CHROMIUM_PPA_MIRRORS[@]}"; do
        start=$(date +%s%N 2>/dev/null || echo 0)
        if timeout 5 curl -fsI "https://${mirror}/" >/dev/null 2>&1; then
            end=$(date +%s%N 2>/dev/null || echo 0)
            elapsed=$(( (end - start) / 1000000 ))
            [[ "$elapsed" -lt "$min" ]] && { min=$elapsed; pick=$mirror; }
        fi
    done
    echo "${pick:-ppa.launchpadcontent.net}"
}

_包管理_Chromium导入密钥() {
    local keyring="/usr/share/keyrings/xtradeb-chromium.gpg"
    local server fp="0x${_CHROMIUM_PPA_FP}"

    rm -f "$keyring"
    for server in keyserver.ubuntu.com keys.openpgp.org pgp.mit.edu; do
        if gpg --batch --yes --no-default-keyring --keyring "$keyring" \
            --keyserver "hkp://${server}:80" --recv-keys "$fp" 2>/dev/null; then
            日志信息 "GPG 密钥已导入 (${server})"
            return 0
        fi
    done

    if curl -fsSL "https://keyserver.ubuntu.com/pks/lookup?op=get&search=${fp}" 2>/dev/null \
        | gpg --batch --yes --dearmor -o "$keyring" 2>/dev/null; then
        日志信息 "GPG 密钥已导入 (web)"
        return 0
    fi

    日志错误 "Chromium PPA 密钥导入失败"
    return 1
}

_包管理_Chromium写PPA源() {
    local codename="$1" mirror="$2" list="/etc/apt/sources.list.d/xtradeb-apps.list"
    local url="https://ppa.launchpadcontent.net/xtradeb/apps/ubuntu"

    [[ "$mirror" == "launchpad.proxy.ustclug.org" ]] \
        && url="https://${mirror}/xtradeb/apps/ubuntu"

    echo "deb [signed-by=/usr/share/keyrings/xtradeb-chromium.gpg] ${url} ${codename} main" > "$list"
}

_包管理_ChromiumApt更新() {
    local log="/tmp/hamster-chromium-apt.log"
    DEBIAN_FRONTEND=noninteractive apt-get update 2>&1 | tee "$log" >/dev/null || true

    if grep -qE '404 Not Found|does not have a Release file' "$log" 2>/dev/null; then
        日志警告 "xtradeb 镜像源不可用，改用官方 Launchpad"
        _包管理_Chromium写PPA源 "$1" "ppa.launchpadcontent.net"
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    fi

    if grep -q NO_PUBKEY "$log" 2>/dev/null; then
        local key
        while read -r key; do
            [[ -n "$key" ]] || continue
            gpg --batch --yes --no-default-keyring \
                --keyring /usr/share/keyrings/xtradeb-chromium.gpg \
                --keyserver hkp://keyserver.ubuntu.com:80 --recv-keys "$key" 2>/dev/null || true
        done < <(grep NO_PUBKEY "$log" | awk '{print $NF}' | sort -u)
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
    fi

    rm -f "$log"
}

_包管理_ChromiumApt安装() {
    local codename mirror

    [[ -f /etc/os-release ]] || { 日志错误 "无法检测系统版本"; return 1; }
    # shellcheck source=/dev/null
    source /etc/os-release
    codename="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null)}"
    [[ -n "$codename" ]] || { 日志错误 "无法获取系统代号"; return 1; }

    case "${ID:-}" in
        ubuntu|debian|linuxmint|pop) ;;
        *)
            command -v apt-get &>/dev/null || { 日志错误 "仅支持 Debian/Ubuntu 系"; return 1; }
            日志警告 "未知 Debian 系发行版，尝试 PPA 安装"
            ;;
    esac

    _包管理_Chromium架构 || return 1
    日志信息 "系统: ${PRETTY_NAME:-unknown} (${codename})"
    _包管理_Chromium准备Apt

    mirror="$(_包管理_Chromium选镜像)"
    日志信息 "PPA 镜像: ${mirror}"

    _包管理_Chromium导入密钥 || return 1
    _包管理_Chromium写PPA源 "$codename" "$mirror"
    _包管理_ChromiumApt更新 "$codename"

    if apt-cache search chromium 2>/dev/null | grep -q '^chromium '; then
        :
    elif ! apt-cache policy chromium 2>/dev/null | grep -q xtradeb; then
        日志警告 "PPA 未验证，尝试继续安装"
    fi

    日志信息 "正在通过 PPA 安装 Chromium..."
    if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y chromium 2>&1; then
        _包管理_Chromium链接
        日志成功 "Chromium 安装成功 ($(chromium --version 2>/dev/null | head -1))"
        return 0
    fi

    日志警告 "PPA 安装失败，尝试系统源 chromium-browser"
    DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y chromium-browser 2>/dev/null \
        || DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y chromium 2>/dev/null \
        || return 1
    _包管理_Chromium链接
    return 0
}

包管理_确保Chromium() {
    if 包管理_Chromium已安装; then
        _包管理_Chromium链接
        日志信息 "Chromium 已安装"
        return 0
    fi

    declare -F _包管理_TTY清屏 &>/dev/null && _包管理_TTY清屏

    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            _包管理_ChromiumApt安装
            ;;
        *)
            日志信息 "正在安装 Chromium..."
            _包管理_安装重试 chromium || _包管理_安装重试 chromium-browser
            ;;
    esac
}
