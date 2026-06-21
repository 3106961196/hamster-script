#!/bin/bash

# ─── 镜像源配置（不影响系统配置） ─────────────────────────────
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
APT_MIRROR="${APT_MIRROR:-https://mirrors.aliyun.com}"
GITHUB_PROXY="${GITHUB_PROXY:-https://gh-proxy.com/}"

# ─── 内部辅助函数 ─────────────────────────────────────────────

# 带镜像源的 apt 安装
_Apt安装() {
    local packages=("$@")
    local temp_conf
    temp_conf=$(mktemp)
    local distro_id codename mirror_path
    
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        distro_id="${ID:-ubuntu}"
        codename="${VERSION_CODENAME:-$(lsb_release -cs 2>/dev/null)}"
    else
        distro_id="ubuntu"
        codename="$(lsb_release -cs 2>/dev/null || echo jammy)"
    fi
    
    case "$distro_id" in
        debian) mirror_path="debian" ;;
        *) mirror_path="ubuntu" ;;
    esac
    
    cat > "$temp_conf" << EOF
deb ${APT_MIRROR}/${mirror_path}/ ${codename} main restricted
deb ${APT_MIRROR}/${mirror_path}/ ${codename}-updates main restricted
EOF
    
    apt -o Dir::Etc::SourceList="$temp_conf" install -y "${packages[@]}"
    rm -f "$temp_conf"
}

# ─── 包管理器检测 ─────────────────────────────────────────────

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

包管理_安装() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)

    # Node.js 特殊处理：apt 中包名是 nodejs，且版本极老
    if [[ "$package" == "node" || "$package" == "nodejs" ]]; then
        if command -v node &>/dev/null; then
            local major
            major=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
            if [[ "$major" -ge 18 ]] 2>/dev/null; then
                日志信息 "Node.js $(node -v) 已满足要求"
                return 0
            fi
        fi

        # 优先尝试 nvm
        if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
            source "$HOME/.nvm/nvm.sh"
            nvm install 20
            return $?
        fi

        # 尝试 NodeSource
        if command -v curl &>/dev/null; then
            日志信息 "正在通过 NodeSource 安装 Node.js 20..."
            case "$pkg_manager" in
                apt)
                    curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 && \
                    apt install -y nodejs 2>&1 || return 1
                    ;;
                yum)
                    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash - 2>&1 && \
                    yum install -y nodejs 2>&1 || return 1
                    ;;
                *) 日志错误 "不支持的包管理器"; return 1 ;;
            esac
            return $?
        fi

        # 兜底：直接安装 nodejs（版本可能较老）
        日志警告 "无法使用 NodeSource，将通过系统包管理器安装 nodejs（版本可能较老）"
        package="nodejs"
    fi

    # MongoDB 特殊处理：需要通过官方源安装
    if [[ "$package" == "mongodb-org" ]]; then
        case "$pkg_manager" in
            apt)
                if command -v curl &>/dev/null; then
                    curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc | \
                        gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg 2>/dev/null || true
                    local codename
                    codename=$(lsb_release -cs 2>/dev/null || echo jammy)
                    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] https://repo.mongodb.org/apt/ubuntu ${codename}/mongodb-org/7.0 multiverse" > /etc/apt/sources.list.d/mongodb-org-7.0.list 2>/dev/null || true
                    apt update 2>&1 | tail -1
                fi
                apt install -y mongodb-org 2>&1 || return 1
                return $?
                ;;
            yum)
                cat > /etc/yum.repos.d/mongodb-org-7.0.repo <<'YUMEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/redhat/$releasever/mongodb-org/7.0/$basearch/
gpgcheck=1
enabled=1
gpgkey=https://www.mongodb.org/static/pgp/server-7.0.asc
YUMEOF
                yum install -y mongodb-org 2>&1 || return 1
                return $?
                ;;
            *) 日志错误 "不支持的包管理器"; return 1 ;;
        esac
    fi

    case "$pkg_manager" in
        apt) _Apt安装 "$package" ;;
        yum) yum install -y "$package" ;;
        pacman) pacman -S --noconfirm "$package" ;;
        apk) apk add "$package" ;;
        *) return 1 ;;
    esac
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
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) dpkg -l | grep -q "^ii  $package " ;;
        yum) rpm -q "$package" &>/dev/null ;;
        pacman) pacman -Q "$package" &>/dev/null ;;
        apk) apk info -e "$package" &>/dev/null ;;
        *) return 1 ;;
    esac
}

包管理_获取版本() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt) dpkg -l "$package" 2>/dev/null | awk '/^ii/ {print $3}' ;;
        yum) rpm -q "$package" 2>/dev/null | awk -F- '{print $2}' ;;
        pacman) pacman -Q "$package" 2>/dev/null | awk '{print $2}' ;;
        apk) apk info -v "$package" 2>/dev/null | sed 's/.*-//' ;;
        *) echo "unknown" ;;
    esac
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
    local package="$1"
    local pkg_manager
    pkg_manager=$(包管理_获取管理器)
    case "$pkg_manager" in
        apt)
            apt-cache show "$package" 2>/dev/null | head -30
            ;;
        yum)
            yum info "$package" 2>/dev/null
            ;;
        pacman)
            pacman -Si "$package" 2>/dev/null
            ;;
        apk)
            apk info -a "$package" 2>/dev/null
            ;;
        *) echo "无法获取软件包信息" ;;
    esac
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
        else
            日志信息 "正在安装 $pkg..."
            if 包管理_安装 "$pkg"; then
                日志成功 "$pkg 安装成功"
            else
                日志错误 "$pkg 安装失败"
                failed+=("$pkg")
            fi
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

    # 自动添加 GitHub 代理
    if [[ "$url" == *"github.com"* && -n "${GITHUB_PROXY:-}" ]]; then
        url="${GITHUB_PROXY}${url}"
    fi

    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$target" "$url" 2>&1
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$target" "$url" 2>&1
    else
        日志错误 "需要 wget 或 curl"
        return 1
    fi
}

# ─── Git 克隆（带 GitHub 代理） ────────────────────────────────

包管理_Git克隆() {
    local url="$1"
    local target="$2"
    
    # 自动添加 GitHub 代理
    if [[ "$url" == *"github.com"* && -n "$GITHUB_PROXY" ]]; then
        url="${GITHUB_PROXY}${url}"
    fi
    
    git clone --depth 1 "$url" "$target"
}

# ─── 高级安装函数 ──────────────────────────────────────────────

# 确保 Node.js 18+ 已安装
包管理_确保Node() {
    local min_ver="${1:-18}"
    
    if command -v node &>/dev/null; then
        local major
        major=$(node -v 2>/dev/null | sed 's/v//' | cut -d. -f1)
        if [[ "$major" -ge "$min_ver" ]] 2>/dev/null; then
            日志信息 "Node.js $(node -v) 已满足要求"
            return 0
        fi
    fi
    
    日志信息 "正在安装 Node.js ${min_ver}..."
    包管理_安装 "node"
}

# 确保 pnpm 已安装
包管理_确保Pnpm() {
    if command -v pnpm &>/dev/null; then
        日志信息 "pnpm $(pnpm -v) 已安装"
        return 0
    fi
    
    日志信息 "正在安装 pnpm..."
    npm install -g pnpm --registry="$NPM_REGISTRY"
}

# 确保 Redis 已安装并启动
包管理_确保Redis() {
    if command -v redis-server &>/dev/null; then
        日志信息 "Redis 已安装"
    else
        日志信息 "正在安装 Redis..."
        包管理_安装 "redis" || 包管理_安装 "redis-server"
    fi
    
    # 启动服务
    if command -v systemctl &>/dev/null; then
        systemctl enable redis-server 2>/dev/null || true
        systemctl start redis-server 2>/dev/null || true
    elif command -v rc-service &>/dev/null; then
        rc-service redis start 2>/dev/null || true
    fi
}

# 确保 MongoDB 已安装并启动
包管理_确保MongoDB() {
    if command -v mongod &>/dev/null; then
        日志信息 "MongoDB 已安装"
    else
        日志信息 "正在安装 MongoDB..."
        包管理_安装 "mongodb-org" || 包管理_安装 "mongodb"
    fi
    
    # 启动服务
    if command -v systemctl &>/dev/null; then
        systemctl enable mongod 2>/dev/null || true
        systemctl start mongod 2>/dev/null || true
    elif command -v rc-service &>/dev/null; then
        rc-service mongod start 2>/dev/null || true
    fi
}

# 确保 Chromium 已安装
包管理_确保Chromium() {
    if command -v chromium-browser &>/dev/null || command -v chromium &>/dev/null; then
        日志信息 "Chromium 已安装"
        return 0
    fi
    
    日志信息 "正在安装 Chromium..."
    包管理_安装 "chromium-browser" || 包管理_安装 "chromium"
}
