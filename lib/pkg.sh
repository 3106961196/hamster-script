#!/bin/bash

# ─── 镜像源配置 ─────────────────────────────────────────────
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
LINUXMIRROR_URL="${LINUXMIRROR_URL:-https://linuxmirrors.cn/main.sh}"

_INSTALL_MAX_RETRIES=3

# ─── 包管理器检测 ─────────────────────────────────────────────

包管理_检测操作系统() {
    if [[ -n "${TERMUX_VERSION:-}" && -n "${PREFIX:-}" ]]; then
        echo "termux"
        return
    fi
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        case "${ID:-}" in
            ubuntu) echo "ubuntu" ;;
            debian) echo "debian" ;;
            arch|archarm|archlinuxarm|manjaro) echo "arch" ;;
            centos|rhel|fedora|rocky|almalinux) echo "centos" ;;
            opensuse*|sles) echo "opensuse" ;;
            alpine) echo "alpine" ;;
            void) echo "void" ;;
            gentoo) echo "gentoo" ;;
            *) echo "${ID:-unknown}" ;;
        esac
    else
        echo "unknown"
    fi
}

包管理_检测架构() {
    local m
    m=$(uname -m)
    case "$m" in
        x86_64|amd64) echo "x64" ;;
        aarch64|arm64) echo "arm64" ;;
        armv7l|armhf) echo "armv7l" ;;
        ppc64le) echo "ppc64le" ;;
        s390x) echo "s390x" ;;
        i386|i686) echo "x86" ;;
        *) echo "$m" ;;
    esac
}

包管理_检测AptDnf() {
    local os
    os=$(包管理_检测操作系统)
    case "$os" in
        debian|ubuntu) echo "apt-get"; return 0 ;;
        centos|rhel|fedora|rocky|almalinux)
            command -v dnf &>/dev/null && echo "dnf" && return 0
            command -v yum &>/dev/null && echo "yum" && return 0
            return 1
            ;;
        *) return 1 ;;
    esac
}

包管理_确保命令() {
    local cmd="$1" pkg="${2:-$1}"
    [[ -z "$cmd" ]] && return 1
    command -v "$cmd" &>/dev/null && return 0
    包管理_安装 "$pkg"
}

包管理_获取系统类型() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu|debian) echo "debian" ;;
            centos|rhel|fedora|rocky|almalinux) echo "rhel" ;;
            arch|manjaro) echo "arch" ;;
            alpine) echo "alpine" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

包管理_获取管理器() {
    local system_type
    system_type=$(包管理_获取系统类型)
    case "$system_type" in
        debian) echo "apt" ;;
        rhel) echo "yum" ;;
        arch) echo "pacman" ;;
        alpine) echo "apk" ;;
        *) echo "unknown" ;;
    esac
}

包管理_获取发行版版本() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${VERSION_CODENAME:-unknown}"
    else
        echo "unknown"
    fi
}

包管理_更新源() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) apt update 2>&1 || return 1 ;;
        yum) yum makecache || return 1 ;;
        pacman) pacman -Sy || return 1 ;;
        apk) apk update || return 1 ;;
        *) return 1 ;;
    esac
    日志信息 "软件源索引已更新，继续后续步骤..."
}

# 交互式更换 Debian/Ubuntu apt 镜像（linuxmirrors.cn）
包管理_Linux换源() {
    local pkg_manager

    [[ $EUID -eq 0 ]] || { 日志错误 "换源需要 root 权限（sudo cs）"; return 1; }

    pkg_manager=$(包管理_获取管理器)
    if [[ "$pkg_manager" != "apt" ]]; then
        日志错误 "linuxmirrors 当前仅支持 apt 系（Debian/Ubuntu）"
        return 1
    fi

    if command -v curl &>/dev/null; then
        bash <(curl -fsSL --connect-timeout 15 --max-time 120 "$LINUXMIRROR_URL")
    elif command -v wget &>/dev/null; then
        bash <(wget -qO- --timeout=15 "$LINUXMIRROR_URL")
    else
        日志错误 "换源需要 curl 或 wget"
        return 1
    fi
}

# npm/pnpm 换国内镜像
包管理_换源Js() {
    包管理_配置Js镜像
    日志成功 "npm/pnpm 已指向 ${NPM_REGISTRY}"
}

包管理_升级() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confold" 2>&1 || return 1 ;;
        yum) yum upgrade -y || return 1 ;;
        pacman) pacman -Syu --noconfirm || return 1 ;;
        apk) apk upgrade || return 1 ;; 
        *) return 1 ;;
    esac
}

# MongoDB 官方源（https://www.mongodb.com/docs/manual/tutorial/install-mongodb-on-ubuntu/）
_包管理_配置MongoDB源() {
    local pkg_manager keyring list_file codename ubuntu_codename

    pkg_manager=$(包管理_获取管理器)
    keyring="/usr/share/keyrings/mongodb-server-7.0.gpg"
    list_file="/etc/apt/sources.list.d/mongodb-org-7.0.list"

    case "$pkg_manager" in
        apt)
            command -v curl &>/dev/null || { 日志错误 "安装 MongoDB 需要 curl"; return 1; }
            codename=$(lsb_release -cs 2>/dev/null || echo jammy)
            case "$codename" in
                noble|oracular|mantic|lunar|kinetic) ubuntu_codename=jammy ;;
                *) ubuntu_codename="$codename" ;;
            esac
            rm -f "$keyring"
            curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
                | gpg --batch --yes --dearmor -o "$keyring" 2>/dev/null || return 1
            echo "deb [ signed-by=${keyring} ] https://repo.mongodb.org/apt/ubuntu ${ubuntu_codename}/mongodb-org/7.0 multiverse" > "$list_file"
            DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || apt update -qq 2>/dev/null || true
            ;;
        yum|dnf)
            cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'YUMEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
YUMEOF
            ;;
        *)
            日志错误 "不支持的包管理器: $pkg_manager"
            return 1
            ;;
    esac
}

包管理_规范化包名() {
    case "$1" in
        chromium-browser) echo chromium ;;
        mongodb|mongod) echo mongodb ;;
        nodejs) echo node ;;
        redis-server) echo redis ;;
        *) echo "$1" ;;
    esac
}

# MongoDB：菜单名 mongodb，实际包 mongodb-org；过渡包 mongodb 不算已安装
包管理_MongoDB已安装() {
    command -v mongod &>/dev/null && return 0
    dpkg -l mongodb-org-server mongodb-org 2>/dev/null | grep -q '^ii' && return 0
    rpm -q mongodb-org-server &>/dev/null && return 0
    return 1
}

包管理_MongoDB版本() {
    local v
    if command -v mongod &>/dev/null; then
        v=$(mongod --version 2>/dev/null | awk '/^db version/ {print $3; exit}')
        [[ -n "$v" ]] && { echo "$v"; return 0; }
    fi
    v=$(dpkg -l mongodb-org-server 2>/dev/null | awk '/^ii/ {print $3; exit}')
    [[ -n "$v" ]] && { echo "$v"; return 0; }
    v=$(rpm -q mongodb-org-server 2>/dev/null | sed 's/mongodb-org-server-//')
    [[ -n "$v" && "$v" != *"not installed"* ]] && { echo "$v"; return 0; }
    return 1
}

包管理_MongoDB显示信息() {
    local info="" svc pkg_info

    if 包管理_MongoDB已安装; then
        info="状态: 已安装"
        v=$(包管理_MongoDB版本 2>/dev/null) && info+="\n版本: $v"
        if command -v systemctl &>/dev/null; then
            svc=$(systemctl is-active mongod 2>/dev/null || echo 未知)
            info+="\n服务 mongod: $svc"
        fi
    else
        info="状态: 未安装\n说明: Ubuntu/Debian 需安装官方 mongodb-org（非过渡包 mongodb）"
    fi

    if command -v apt-cache &>/dev/null; then
        pkg_info=$(apt-cache show mongodb-org 2>/dev/null | head -24)
        [[ -n "$pkg_info" ]] && info+="\n\n--- mongodb-org ---\n${pkg_info}"
    elif command -v yum &>/dev/null; then
        pkg_info=$(yum info mongodb-org 2>/dev/null | head -20)
        [[ -n "$pkg_info" ]] && info+="\n\n--- mongodb-org ---\n${pkg_info}"
    fi

    printf '%b\n' "$info"
}

包管理_Redis已安装() {
    command -v redis-server &>/dev/null && return 0
    dpkg -l redis-server 2>/dev/null | grep -q '^ii' && return 0
    rpm -q redis &>/dev/null
}

# LinuxQQ 仅能通过官方 deb/rpm 安装（对齐 xrk NapCat.sh，不在 apt 源里）
包管理_LinuxQQ已安装() {
    [[ -x /opt/QQ/qq ]] && return 0
    dpkg -l linuxqq 2>/dev/null | grep -q '^ii' && return 0
    rpm -q linuxqq &>/dev/null
}

包管理_安装() {
    local package
    package=$(包管理_规范化包名 "$1")

    if [[ "$package" == "linuxqq" ]]; then
        日志错误 "linuxqq 不在 apt 源中，请通过 NapCat 安装（自动下载腾讯 QQ.deb）"
        return 1
    fi
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)

    # Chromium：走 xtradeb PPA（见 lib/chromium.sh）
    if [[ "$package" == "chromium" ]]; then
        包管理_确保Chromium
        return $?
    fi

    # MongoDB：菜单项 mongodb → 官方 mongodb-org
    if [[ "$package" == "mongodb" ]]; then
        包管理_确保MongoDB
        return $?
    fi

    # Redis
    if [[ "$package" == "redis" ]]; then
        包管理_确保Redis
        return $?
    fi

    # Node.js：官方 tarball + pnpm（见 包管理_确保Node）
    if [[ "$package" == "node" ]]; then
        包管理_确保Node
        return $?
    fi

    # MongoDB：官方 apt/yum 源（mongodb-org 7.0）
    if [[ "$package" == "mongodb-org" ]]; then
        _包管理_配置MongoDB源 || return 1
        case "$pkg_manager" in
            apt)
                DEBIAN_FRONTEND=noninteractive apt-get install -y mongodb-org 2>&1 || return 1
                ;;
            yum|dnf)
                "$pkg_manager" install -y mongodb-org 2>&1 || return 1
                ;;
            *) 日志错误 "不支持的包管理器"; return 1 ;;
        esac
        return 0
    fi

    _包管理_安装重试 "$package"
}

_包管理_TTY清屏() {
    declare -F _界面_重置终端 &>/dev/null && _界面_重置终端
}

_包管理_安装重试() {
    local package="$1"
    local pkg_manager retry=0

    if 包管理_是否已安装 "$package"; then
        日志信息 "$package 已安装"
        return 0
    fi

    _包管理_TTY清屏
    pkg_manager=$(包管理_获取管理器)
    while [[ "$retry" -lt "$_INSTALL_MAX_RETRIES" ]]; do
        日志信息 "正在安装 $package..."
        case "$pkg_manager" in
            apt)
                DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
                    apt-get update -qq 2>/dev/null || true
                if DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a \
                    apt-get install -y "$package" && 包管理_是否已安装 "$package"; then
                    日志成功 "$package 安装成功"
                    return 0
                fi
                ;;
            yum) yum install -y "$package" && { 日志成功 "$package 安装成功"; return 0; } ;;
            pacman) pacman --disable-sandbox -Sy --noconfirm "$package" && { 日志成功 "$package 安装成功"; return 0; } ;;
            apk) apk add --no-cache "$package" && { 日志成功 "$package 安装成功"; return 0; } ;;
            *) 日志错误 "无法识别的包管理器"; return 1 ;;
        esac
        retry=$((retry + 1))
        [[ "$retry" -lt "$_INSTALL_MAX_RETRIES" ]] && 日志警告 "重试安装 $package ($retry/$_INSTALL_MAX_RETRIES)..."
        sleep 1
    done
    日志错误 "$package 安装失败次数达到上限"
    return 1
}

包管理_卸载() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) apt remove -y "$package" 2>&1 || return 1 ;;
        yum) yum remove -y "$package" || return 1 ;;
        pacman) pacman -R --noconfirm "$package" || return 1 ;;
        apk) apk del "$package" || return 1 ;;
        *) return 1 ;;
    esac
}

包管理_搜索() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) apt search "$package" 2>/dev/null | grep -E "^[^/]+/" | sed 's|/[^ ]*||' | head -30 ;;
        yum) yum search "$package" 2>/dev/null | grep -E "^[^ ]+\." | awk '{print $1}' | head -30 ;;
        pacman) pacman -Ss "$package" 2>/dev/null | grep -E "^[^/]+/" | sed 's|/.*||' | head -30 ;;
        apk) apk search "$package" 2>/dev/null | head -30 ;;
        *) return 1 ;;
    esac
}

包管理_已安装列表() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) dpkg -l | awk '/^ii/ {print $2, $3}' ;;
        yum) rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}\n' ;;
        pacman) pacman -Q ;;
        apk) apk info -v | sed 's/-\([0-9].*\)/ \1/' ;;
        *) return 1 ;;
    esac
}

包管理_可升级列表() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            apt list --upgradable 2>/dev/null | tail -n +2 | while read -r line; do
                local name old_ver new_ver
                name=$(echo "$line" | cut -d'/' -f1)
                old_ver=$(echo "$line" | awk -F' ' '{print $2}')
                new_ver=$(echo "$line" | awk -F' ' '{print $3}' | tr -d ']')
                echo "$name $old_ver $new_ver"
            done
            ;;
        yum)
            yum check-update --quiet 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
        pacman)
            pacman -Qu 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
        apk)
            apk version -l '<' 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
        *) return 1 ;;
    esac
}

包管理_是否已安装() {
    local package
    package=$(包管理_规范化包名 "$1")
    local os="${2:-$(包管理_检测操作系统)}"

    if [[ "$package" == "chromium" ]]; then
        declare -F 包管理_Chromium已安装 &>/dev/null && 包管理_Chromium已安装 && return 0
        return 1
    fi

    if [[ "$package" == "mongodb" || "$package" == "mongodb-org" || "$package" == "mongod" ]]; then
        包管理_MongoDB已安装 && return 0
        return 1
    fi

    if [[ "$package" == "redis" ]]; then
        包管理_Redis已安装 && return 0
        return 1
    fi

    if [[ "$package" == "node" ]]; then
        包管理_验证Node环境 && 包管理_Node已满足 && _包管理_Pnpm就绪
        return $?
    fi

    if [[ "$package" == "linuxqq" ]]; then
        包管理_LinuxQQ已安装
        return $?
    fi

    case "$os" in
        termux) pkg list-installed 2>/dev/null | grep -q "^${package}/" ;;
        debian|ubuntu) dpkg -s "$package" >/dev/null 2>&1 ;;
        arch) pacman -Qi "$package" >/dev/null 2>&1 ;;
        centos) rpm -q "$package" >/dev/null 2>&1 ;;
        opensuse) rpm -q "$package" >/dev/null 2>&1 ;;
        alpine) apk info -e "$package" >/dev/null 2>&1 ;;
        void) xbps-query -S "$package" 2>/dev/null | grep -q "^ii" ;;
        gentoo) qlist -I 2>/dev/null | grep -qE "/${package}$" ;;
        *)
            local pkg_manager
            pkg_manager=$(包管理_获取管理器)
            case "$pkg_manager" in
                apt) dpkg -s "$package" >/dev/null 2>&1 ;;
                yum) rpm -q "$package" &>/dev/null ;;
                pacman) pacman -Q "$package" &>/dev/null ;;
                apk) apk info -e "$package" &>/dev/null ;;
                *) return 1 ;;
            esac
            ;;
    esac
}

包管理_获取版本() {
    local package
    package=$(包管理_规范化包名 "$1")
    local pkg_manager v

    if [[ "$package" == "chromium" ]]; then
        if declare -F 包管理_Chromium版本 &>/dev/null; then
            包管理_Chromium版本 || echo "未知"
        else
            echo "未知"
        fi
        return 0
    fi

    if [[ "$package" == "mongodb" || "$package" == "mongodb-org" || "$package" == "mongod" ]]; then
        包管理_MongoDB版本 2>/dev/null || echo "未知"
        return 0
    fi

    if [[ "$package" == "redis" ]]; then
        redis-server --version 2>/dev/null | awk '{print $3}' || echo "未知"
        return 0
    fi

    if [[ "$package" == "node" ]]; then
        if 包管理_验证Node环境; then
            if command -v pnpm &>/dev/null; then
                echo "$(/opt/node/bin/node -v 2>/dev/null) + pnpm $(pnpm -v 2>/dev/null)"
            else
                /opt/node/bin/node -v 2>/dev/null
            fi
        else
            echo "未安装"
        fi
        return 0
    fi

    if [[ "$package" == "linuxqq" ]]; then
        v=$(dpkg -l linuxqq 2>/dev/null | awk '/^ii/ {print $3; exit}')
        [[ -n "$v" ]] && { echo "$v"; return 0; }
        v=$(rpm -q linuxqq 2>/dev/null | awk -F- '{print $2; exit}')
        [[ -n "$v" ]] && { echo "$v"; return 0; }
        echo "未知"
        return 0
    fi

    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) v=$(dpkg -l "$package" 2>/dev/null | awk '/^ii/ {print $3; exit}') ;;
        yum) v=$(rpm -q "$package" 2>/dev/null | awk -F- '{print $2}') ;;
        pacman) v=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}') ;;
        apk) v=$(apk info -v "$package" 2>/dev/null | sed 's/.*-//') ;;
        *) echo "unknown"; return 0 ;;
    esac
    [[ -n "$v" ]] && echo "$v" || echo "未知"
}

包管理_获取可升级版本() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            apt list --upgradable 2>/dev/null | grep "^$package/" | awk -F' ' '{print $3}' | tr -d ']'
            ;;
        yum)
            yum check-update --quiet "$package" 2>/dev/null | awk '{print $2}'
            ;;
        pacman)
            pacman -Qu "$package" 2>/dev/null | awk '{print $2}'
            ;;
        apk)
            apk version -l '<' "$package" 2>/dev/null | awk '{print $2}'
            ;;
        *) echo "" ;;
    esac
}

包管理_获取版本列表() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            apt-cache madison "$package" 2>/dev/null | awk -F'|' '{print $2}' | tr -d ' ' | head -10
            ;;
        yum)
            yum --showduplicates list "$package" 2>/dev/null | awk '{print $2}' | head -10
            ;;
        pacman)
            pacman -Si "$package" 2>/dev/null | grep -E "^Version" | awk '{print $3}'
            ;;
        apk)
            apk policy "$package" 2>/dev/null | grep -E "^[0-9]" | head -10
            ;;
        *) echo "latest" ;;
    esac
}

包管理_显示信息() {
    local package pkg_manager info
    package=$(包管理_规范化包名 "$1")

    case "$package" in
        mongodb|mongodb-org|mongod)
            包管理_MongoDB显示信息
            return 0
            ;;
    esac

    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            info=$(apt-cache show "$package" 2>/dev/null | head -30)
            ;;
        yum)
            info=$(yum info "$package" 2>/dev/null)
            ;;
        pacman)
            info=$(pacman -Si "$package" 2>/dev/null)
            ;;
        apk)
            info=$(apk info -a "$package" 2>/dev/null)
            ;;
        *) info="无法获取软件包信息" ;;
    esac
    [[ -n "$info" ]] && { printf '%s\n' "$info"; return 0; }
    echo "未找到 ${package} 的软件源信息"
}

包管理_自动移除() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) apt autoremove -y 2>&1 || return 1 ;;
        yum) yum autoremove -y || return 1 ;;
        pacman) pacman -Rns --noconfirm "$(pacman -Qdtq)" 2>/dev/null || return 1 ;;
        apk) apk cache clean 2>&1 || return 1 ;;
        *) return 1 ;;
    esac
}

包管理_清理() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) apt autoclean -y 2>&1 || return 1 && apt clean 2>&1 || return 1 ;;
        yum) yum clean all || return 1 ;;
        pacman) pacman -Sc --noconfirm || return 1 ;;
        apk) apk cache clean 2>&1 || return 1 ;;    
        *) return 1 ;;
    esac
}

包管理_批量安装() {
    local packages=("$@")
    local failed=()
    
    for pkg in "${packages[@]}"; do
        if 包管理_是否已安装 "$pkg"; then
            日志信息 "$pkg 已安装"
        elif 包管理_安装 "$pkg"; then
            :
        else
            日志错误 "$pkg 安装失败"
            failed+=("$pkg")
        fi
    done
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        日志错误 "以下软件包安装失败: ${failed[*]}"
        return 1
    fi
    return 0
}

包管理_确保已安装() {
    local package="$1"
    
    if 包管理_是否已安装 "$package"; then
        return 0
    fi
    
    日志信息 "正在安装 $package..."
    包管理_安装 "$package"
}

包管理_全部升级() {
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confold" 2>&1 || return 1 ;;
        yum) yum upgrade -y || return 1 ;;
        pacman) pacman -Syu --noconfirm || return 1 ;;
        apk) apk upgrade || return 1 ;;
        *) return 1 ;;
    esac
}

# ─── npm/pnpm 安装（带镜像源） ─────────────────────────────────

包管理_Npm安装() {
    if command -v pnpm &>/dev/null; then
        pnpm i --registry="$NPM_REGISTRY" "$@"
    else
        npm install --registry="$NPM_REGISTRY" "$@"
    fi
}

# ─── 下载文件（带 GitHub 代理） ────────────────────────────────

包管理_下载文件() {
    local url="$1"
    local target="$2"
    if type 网络_下载 &>/dev/null; then
        网络_下载 "$url" "$target" 3
    else
        type getgh &>/dev/null && url=$(getgh "$url" 2>/dev/null || echo "$url")
        if command -v wget &>/dev/null; then
            wget -q --show-progress -O "$target" "$url" 2>&1
        elif command -v curl &>/dev/null; then
            curl -fsSL -o "$target" "$url" 2>&1
        else
            日志错误 "需要 wget 或 curl"
            return 1
        fi
    fi
}

# ─── Git 克隆（带 GitHub 代理） ────────────────────────────────

包管理_Git克隆() {
    local url="$1"
    local target="$2"

    if type GitHub_克隆 &>/dev/null; then
        GitHub_克隆 "$url" "$target" 1
        return $?
    fi

    type getgh &>/dev/null && url=$(getgh "$url" 2>/dev/null || echo "$url")
    git clone --depth 1 "$url" "$target"
}

# ─── Node.js + pnpm（对齐 xrk project-install/software/node + pnpm） ───

NODE_MIN_MAJOR="${HAMSTER_NODE_MIN_MAJOR:-26}"
NODE_FALLBACK_VERSION="${NODE_FALLBACK_VERSION:-v26.3.1}"
PNPM_VERSION="${PNPM_VERSION:-v10.29.3}"

_包管理_清理版本号() {
    local v="$1"
    v="${v//$'\r'/}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    [[ -n "$v" && "$v" != v* ]] && v="v${v}"
    printf '%s' "$v"
}

# 只取数字主版本，避免配置脏值（如 /root/cs）污染比较
_包管理_NodeMinMajor() {
    local raw="${1:-}" n
    if [[ -z "$raw" ]] && declare -F 获取配置 &>/dev/null; then
        raw="$(获取配置 node_min_major "$NODE_MIN_MAJOR")"
    fi
    raw="${raw:-$NODE_MIN_MAJOR}"
    raw="${raw//$'\r'/}"
    n=$(printf '%s' "$raw" | grep -oE '[0-9]+' | head -1)
    [[ -n "$n" ]] && echo "$n" || echo "$NODE_MIN_MAJOR"
}

_包管理_导出Node路径() {
    export PATH="/opt/node/bin:/usr/local/bin:${PATH}"
    hash -r 2>/dev/null || true
}

_包管理_NodeMajor() {
    包管理_验证Node环境 || return 1
    /opt/node/bin/node -v 2>/dev/null | sed 's/^v//' | cut -d. -f1
}

包管理_验证Node环境() {
    _包管理_导出Node路径
    [[ -x /opt/node/bin/node && -x /opt/node/bin/npm ]] || return 1
    /opt/node/bin/node -v &>/dev/null && /opt/node/bin/npm -v &>/dev/null
}

包管理_Node已满足() {
    local min major
    min="$(_包管理_NodeMinMajor "${1:-}")"
    major=$(_包管理_NodeMajor) || return 1
    [[ "$major" -ge "$min" ]] 2>/dev/null
}

_包管理_Pnpm就绪() {
    _包管理_导出Node路径
    [[ -x /usr/local/bin/pnpm ]] && return 0
    command -v pnpm &>/dev/null
}

包管理_配置Js镜像() {
    command -v npm &>/dev/null && npm config set registry "$NPM_REGISTRY" 2>/dev/null || true
    command -v pnpm &>/dev/null && pnpm config set registry "$NPM_REGISTRY" 2>/dev/null || true
}

_包管理_解析Node版本() {
    local min="$(_包管理_NodeMinMajor "${1:-}")" ver json
    ver="$(_包管理_清理版本号 "${NODE_VERSION:-${HAMSTER_NODE_VERSION:-}}")"
    [[ -n "$ver" ]] && { echo "$ver"; return 0; }

    包管理_确保命令 curl curl || return 1
    for json in \
        "$(curl -fsSL --connect-timeout 10 --max-time 30 https://npmmirror.com/mirrors/node/index.json 2>/dev/null)" \
        "$(curl -fsSL --connect-timeout 10 --max-time 30 https://nodejs.org/dist/index.json 2>/dev/null)"; do
        [[ -z "$json" || "$json" != \[* ]] && continue
        if command -v jq &>/dev/null; then
            ver=$(printf '%s' "$json" | jq -r --arg m "$min" \
                '.[] | select(.version | startswith("v\($m).")) | .version' 2>/dev/null | head -1)
        elif command -v python3 &>/dev/null; then
            ver=$(printf '%s' "$json" | python3 -c "
import json, re, sys
m = sys.argv[1]
for item in json.load(sys.stdin):
    v = item.get('version', '')
    if re.match(rf'^v{m}\\.', v):
        print(v); break
" "$min" 2>/dev/null)
        fi
        ver="$(_包管理_清理版本号 "$ver")"
        [[ -n "$ver" ]] && { echo "$ver"; return 0; }
    done

    ver="$(_包管理_清理版本号 "$NODE_FALLBACK_VERSION")"
    日志警告 "无法解析 Node v${min} 最新版，使用 ${ver}"
    echo "$ver"
}

_包管理_安装NodeTarball() {
    local version="$(_包管理_清理版本号 "$1")" arch base url tmp tdir tb ext
    [[ -n "$version" ]] || return 1

    arch=$(包管理_检测架构)
    case "$arch" in
        x64|arm64|ppc64le|s390x) ;;
        *) 日志错误 "不支持的 Node 架构: $(uname -m)"; return 1 ;;
    esac

    包管理_确保命令 tar tar || return 1
    包管理_确保命令 xz xz-utils || 包管理_安装 xz-utils

    tmp=$(mktemp -d)
    tb="${tmp}/node-${version}-linux-${arch}.tar.xz"
    ext="${tmp}/node-${version}-linux-${arch}"

    for base in "${NODE_DIST_MIRROR:-https://npmmirror.com/mirrors/node}" "https://nodejs.org/dist"; do
        [[ -z "$base" ]] && continue
        url="${base%/}/${version}/node-${version}-linux-${arch}.tar.xz"
        日志信息 "→ ${url}"
        if 包管理_下载文件 "$url" "$tb"; then
            break
        fi
        tb="${tmp}/node-${version}-linux-${arch}.tar.xz"
    done
    [[ -s "$tb" ]] || { 日志错误 "Node 下载失败"; rm -rf "$tmp"; return 1; }

    tar -xf "$tb" -C "$tmp" || { rm -rf "$tmp"; return 1; }
    mkdir -p /opt/node && rm -rf /opt/node/*
    mv "${ext}"/* /opt/node/ || { rm -rf "$tmp"; return 1; }
    ln -sf /opt/node/bin/node /usr/local/bin/node
    ln -sf /opt/node/bin/npm /usr/local/bin/npm
    ln -sf /opt/node/bin/npx /usr/local/bin/npx
    _包管理_导出Node路径
    grep -q '/opt/node/bin' "${HOME}/.bashrc" 2>/dev/null || \
        echo 'export PATH=$PATH:/opt/node/bin' >> "${HOME}/.bashrc"
    rm -rf "$tmp"
    包管理_验证Node环境
}

_包管理_安装Pnpm() {
    local raw bin url tmp
    _包管理_导出Node路径
    _包管理_Pnpm就绪 && return 0

    raw=$(uname -m)
    case "$raw" in
        x86_64|amd64) bin="pnpm-linux-x64" ;;
        aarch64|arm64) bin="pnpm-linux-arm64" ;;
        *) 日志错误 "pnpm 不支持架构: $raw"; return 1 ;;
    esac

    url="https://github.com/pnpm/pnpm/releases/download/${PNPM_VERSION}/${bin}"
    tmp=$(mktemp)
    日志信息 "安装 pnpm ${PNPM_VERSION}..."
    包管理_下载文件 "$url" "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" /usr/local/bin/pnpm && chmod 755 /usr/local/bin/pnpm
    _包管理_Pnpm就绪
}

包管理_确保Node() {
    local min="$(_包管理_NodeMinMajor "${1:-}")" ver
    _包管理_导出Node路径

    if 包管理_验证Node环境 && 包管理_Node已满足 "$min" && _包管理_Pnpm就绪; then
        包管理_配置Js镜像
        return 0
    fi

    [[ $EUID -eq 0 || -w /usr/local/bin ]] || {
        日志错误 "安装 Node.js 需要 root 权限（sudo）"
        return 1
    }

    if ! 包管理_验证Node环境 || ! 包管理_Node已满足 "$min"; then
        ver=$(_包管理_解析Node版本 "$min") || return 1
        日志信息 "正在安装 Node.js ${ver}..."
        _包管理_安装NodeTarball "$ver" || return 1
    fi

    _包管理_安装Pnpm || return 1
    包管理_配置Js镜像
    日志成功 "Node.js $(/opt/node/bin/node -v 2>/dev/null)  pnpm $(pnpm -v 2>/dev/null || /usr/local/bin/pnpm -v 2>/dev/null)"
    return 0
}

包管理_确保Pnpm() { 包管理_确保Node; }

# 确保 Redis 已安装并启动
包管理_Redis运行中() {
    command -v redis-cli &>/dev/null && redis-cli ping 2>/dev/null | grep -q PONG
}

包管理_确保Redis() {
    if 包管理_Redis已安装; then
        日志信息 "Redis 已安装"
    else
        日志信息 "正在安装 Redis..."
        包管理_安装 "redis" || 包管理_安装 "redis-server"
    fi

    if 包管理_Redis运行中; then
        return 0
    fi

    if declare -F 服务_是否Systemd &>/dev/null && 服务_是否Systemd; then
        systemctl enable redis-server 2>/dev/null || true
        服务_启动 redis-server 2>/dev/null || 服务_启动 redis 2>/dev/null || true
    elif command -v service &>/dev/null; then
        service redis-server start 2>/dev/null || service redis start 2>/dev/null || true
    fi

    if ! 包管理_Redis运行中 && command -v redis-server &>/dev/null; then
        redis-server --daemonize yes 2>/dev/null || true
    fi

    包管理_Redis运行中
}

# 确保 MongoDB 已安装并启动（官方 mongodb-org）
包管理_MongoDB运行中() {
    command -v mongosh &>/dev/null && mongosh --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1 \
        || { command -v mongo &>/dev/null && mongo --quiet --eval 'db.runCommand({ ping: 1 }).ok' 2>/dev/null | grep -q 1; }
}

包管理_确保MongoDB() {
    if 包管理_MongoDB已安装; then
        日志信息 "MongoDB 已安装"
    else
        日志信息 "正在安装 MongoDB（官方 mongodb-org）..."
        包管理_安装 "mongodb-org" || return 1
    fi

    if 包管理_MongoDB运行中; then
        return 0
    fi

    if declare -F 服务_是否Systemd &>/dev/null && 服务_是否Systemd; then
        systemctl enable mongod 2>/dev/null || true
        服务_启动 mongod 2>/dev/null || true
    elif command -v service &>/dev/null; then
        service mongod start 2>/dev/null || true
    fi

    if ! 包管理_MongoDB运行中 && command -v mongod &>/dev/null; then
        local log_dir="${HAMSTER_LOG_DIR:-/var/log/hamster-scripts}"
        mkdir -p "$log_dir" 2>/dev/null || log_dir="/tmp"
        mongod --fork --logpath "$log_dir/mongod.log" --dbpath /var/lib/mongodb 2>/dev/null \
            || mongod --fork --logpath "$log_dir/mongod.log" --dbpath /data/db 2>/dev/null \
            || true
    fi

    包管理_MongoDB运行中
}

