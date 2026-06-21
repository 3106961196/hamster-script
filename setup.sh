#!/bin/bash

REPO_URL="${REPO_URL:-https://github.com/3106961196/hamster-script.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/cs}"

# GitHub 代理列表（国内加速）
_GITHUB_PROXIES=(
    "https://gh-proxy.com"
    "https://ghfast.top"
    "https://mirror.ghproxy.com"
    "https://ghp.ci"
    "https://gitclone.com/github.com"
)

# 检测是否国内（时区判断，不依赖网络）
_是否国内() {
    local tz="${TZ:-}"
    [[ -z "$tz" ]] && tz=$(cat /etc/timezone 2>/dev/null || echo "")
    case "$tz" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|Asia/Kashgar \
        |Asia/Hong_Kong|Asia/Macau|Asia/Taipei) return 0 ;;
    esac
    [[ -L /etc/localtime ]] && readlink /etc/localtime 2>/dev/null \
        | grep -qE 'Asia/(Shanghai|Chongqing|Harbin|Urumqi|Kashgar|Hong_Kong|Macau|Taipei)'
}

# 代理化 GitHub URL
_代理化GitHub() {
    local proxy="$1" url="$2"
    case "$proxy" in
        https://gitclone.com/github.com)
            echo "${proxy}/${url#https://github.com/}"
            ;;
        *)
            echo "${proxy}/${url}"
            ;;
    esac
}

# 尝试用代理克隆
_代理克隆() {
    local url="$1" dest="$2" proxy
    echo "[setup] 检测到国内网络，尝试 GitHub 代理..."
    for proxy in "${_GITHUB_PROXIES[@]}"; do
        local proxied="$(_代理化GitHub "$proxy" "$url")"
        echo "[setup] 尝试: ${proxy#https://}"
        if timeout 60 git clone --depth 1 -b "$REPO_BRANCH" "$proxied" "$dest" 2>/dev/null; then
            echo "[setup] ✓ 代理克隆成功: ${proxy#https://}"
            return 0
        fi
    done
    return 1
}

_仓库根路径() {
    local script_path="${BASH_SOURCE[0]:-$0}"
    local dir=""

    if [[ -n "$script_path" && "$script_path" != "bash" && "$script_path" != "-" ]]; then
        dir="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)" || dir=""
        [[ -n "$dir" && -f "$dir/lib/core.sh" ]] && { echo "$dir"; return 0; }
    fi
    echo ""
}

_拉取仓库() {
    if [[ -d "$INSTALL_DIR/lib" && -f "$INSTALL_DIR/lib/core.sh" ]]; then
        cd "$INSTALL_DIR" || return 1
        # git reset 会往 stdout 打印 "HEAD is now at ..."，不能污染 $() 捕获的路径
        git fetch origin >/dev/null 2>&1 || true
        git reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1 || true
        git clean -f -d >/dev/null 2>/dev/null || true
        echo "$INSTALL_DIR"
        return 0
    fi

    rm -rf "$INSTALL_DIR"
    
    # 国内环境优先使用代理
    if _是否国内; then
        echo "[setup] 检测到国内环境，使用 GitHub 代理加速..."
        if _代理克隆 "$REPO_URL" "$INSTALL_DIR"; then
            echo "$INSTALL_DIR"
            return 0
        fi
        echo "[setup] 代理克隆失败，尝试直连 GitHub..."
    fi
    
    # 直连或代理失败后回退
    if timeout 120 git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" 2>&1; then
        echo "$INSTALL_DIR"
        return 0
    fi
    
    echo "[setup] ✗ 克隆失败"
    echo "[setup] 建议："
    echo "  1. 检查网络连接"
    echo "  2. 手动设置代理: export https_proxy=http://your-proxy:port"
    echo "  3. 或手动克隆后运行: git clone $REPO_URL $INSTALL_DIR && cd $INSTALL_DIR && sudo ./setup.sh"
    return 1
}

_安装前引导() {
    local pkg_manager
    
    pkg_manager=$(包管理_获取管理器 2>/dev/null || echo unknown)
    [[ "$pkg_manager" != "apt" ]] && return 0
    
    # 自动检测是否在国内服务器
    if _是否国内服务器; then
        echo ""
        echo "检测到国内服务器，自动优化 apt 源..."
        if _自动换源_apt; then
            echo "✓ apt 源已优化"
        else
            echo "⚠ 自动换源失败，继续安装..."
        fi
    fi
}

_是否国内服务器() {
    # 方式 1：时区判断
    local tz="${TZ:-}"
    [[ -z "$tz" ]] && tz=$(cat /etc/timezone 2>/dev/null || timedatectl show 2>/dev/null | grep -oP 'Timezone=\K.*' || echo "")
    [[ "$tz" == *"Shanghai"* || "$tz" == *"Chongqing"* || "$tz" == *"Asia"* ]] && return 0
    
    # 方式 2：IP 判断（备用）
    if command -v curl &>/dev/null; then
        local country
        country=$(curl -fsSL --connect-timeout 3 --max-time 5 https://ipinfo.io/country 2>/dev/null || echo "")
        [[ "$country" == "CN" ]] && return 0
    fi
    
    return 1
}

_自动换源_apt() {
    local mirrors=(
        "mirrors.aliyun.com"
        "mirrors.tuna.tsinghua.edu.cn"
        "mirrors.ustc.edu.cn"
        "mirrors.huaweicloud.com"
    )
    local best_mirror="" min_ms=999999
    
    # 测速选最快镜像
    for mirror in "${mirrors[@]}"; do
        local start end elapsed
        start=$(date +%s%N 2>/dev/null || echo 0)
        if timeout 3 curl -fsI "https://${mirror}/" >/dev/null 2>&1; then
            end=$(date +%s%N 2>/dev/null || echo 0)
            elapsed=$(( (end - start) / 1000000 ))
            if [[ "$elapsed" -lt "$min_ms" ]]; then
                min_ms=$elapsed
                best_mirror=$mirror
            fi
        fi
    done
    
    [[ -z "$best_mirror" ]] && return 1
    
    # 获取发行版信息
    local codename dist_id
    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        codename="${VERSION_CODENAME:-}"
        dist_id="${ID:-}"
    fi
    [[ -z "$codename" ]] && return 1
    
    # 根据发行版选择正确的源路径
    local repo_path
    case "$dist_id" in
        ubuntu) repo_path="ubuntu" ;;
        debian) repo_path="debian" ;;
        *) return 1 ;;
    esac
    
    # 备份原 sources.list
    local sources_file="/etc/apt/sources.list"
    if [[ -f "$sources_file" ]]; then
        cp "$sources_file" "${sources_file}.bak.$(date +%s)" 2>/dev/null || true
    fi
    
    # 写入新源
    cat > "$sources_file" <<EOF
deb https://${best_mirror}/${repo_path}/ ${codename} main restricted universe multiverse
deb https://${best_mirror}/${repo_path}/ ${codename}-updates main restricted universe multiverse
deb https://${best_mirror}/${repo_path}/ ${codename}-backports main restricted universe multiverse
deb https://${best_mirror}/${repo_path}/ ${codename}-security main restricted universe multiverse
EOF
    
    # 更新源索引
    apt-get update -qq 2>/dev/null || true
    return 0
}

程序入口() {
    local repo_root

    [[ $EUID -ne 0 ]] && { echo "请使用 root 运行 setup.sh"; exit 1; }

    repo_root="$(_仓库根路径)"
    if [[ -z "$repo_root" ]]; then
        repo_root="$(_拉取仓库)" || { echo "拉取仓库失败"; exit 1; }
    fi

    if [[ ! -f "$repo_root/lib/core.sh" ]]; then
        echo "仓库路径无效（缺少 lib/core.sh）: $repo_root" >&2
        exit 1
    fi

    export PROJECT_ROOT="$repo_root" HAMSTER_ROOT="$repo_root"

    # shellcheck source=/dev/null
    source "$repo_root/lib/core.sh"
    工具引导
    _安装前引导

    if ! 包管理_批量安装 git wget curl tar xz-utils jq sudo tmux dialog; then
        echo ""
        echo "警告: 部分依赖未安装成功。可重新运行 setup.sh 并选择 1 换源后再试" >&2
    fi
    安装_系统目录 "$repo_root"
    安装_后处理 "$repo_root"

    echo ""
    echo "安装完成。"
    echo ""

    # 自动进入 tmux 桌面
    if command -v hamster-tmux &>/dev/null; then
        echo "正在进入 tmux 桌面..."
        exec hamster-tmux
    else
        echo "运行: cs"
    fi
}

程序入口 "$@"
