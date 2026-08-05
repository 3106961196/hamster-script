#!/bin/bash

# 主仓库 Gitee。未设 REPO_URL 时按区域自动选镜像；显式 REPO_URL 才固定。
# 区域逻辑与 lib/region.sh 一致（clone 前自包含）：覆盖 → IP → 时区
INSTALL_DIR="${INSTALL_DIR:-/cs}"
_SETUP_GITEE_URL="https://gitee.com/duac/hamster-script.git"
_SETUP_GITCODE_URL="https://gitcode.com/duac/hamster-script.git"
_SETUP_GITHUB_URL="https://github.com/3106961196/hamster-script.git"
HAMSTER_DETECT_METHOD=""

系统_检测时区() {
    local tz="${TZ:-}"
    [[ -n "$tz" ]] && { printf '%s\n' "$tz"; return 0; }
    tz=$(timedatectl show -p Timezone --value 2>/dev/null) && [[ -n "$tz" ]] && { printf '%s\n' "$tz"; return 0; }
    [[ -f /etc/timezone ]] && { cat /etc/timezone; return 0; }
    readlink -f /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p'
}

系统_是否国内时区() {
    case "$(系统_检测时区)" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|Asia/Kashgar|PRC \
        |Asia/Hong_Kong|Asia/Macau|Asia/Taipei) return 0 ;;
    esac
    return 1
}

网络_检测区域() {
    local json country
    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn|overseas)
            HAMSTER_DETECT_METHOD="override"
            printf '%s\n' "${HAMSTER_REGION:-$XRK_REGION}"
            return 0
            ;;
    esac
    if command -v curl &>/dev/null; then
        json=$(curl -s --connect-timeout 3 --max-time 5 "http://ip-api.com/json" 2>/dev/null || true)
        country=$(printf '%s' "$json" | grep -oE '"countryCode":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$country" ]]; then
            HAMSTER_DETECT_METHOD="ip"
            [[ "$country" == "CN" ]] && { echo cn; return 0; }
            echo overseas
            return 0
        fi
        case "$json" in
            *'"country":"China"'*) HAMSTER_DETECT_METHOD="ip"; echo cn; return 0 ;;
        esac
    fi
    if 系统_是否国内时区; then
        HAMSTER_DETECT_METHOD="timezone"
        echo cn
        return 0
    fi
    HAMSTER_DETECT_METHOD="default"
    echo overseas
}

是否国内区域() { [[ "$(网络_检测区域)" == "cn" ]]; }

_仓库默认分支() {
    case "$1" in
        *gitee.com*) echo master ;;
        *) echo main ;;
    esac
}

# 输出候选：每行 url|branch（指定 REPO_URL 时仅一行）
_克隆候选列表() {
    local url branch
    if [[ -n "${REPO_URL:-}" ]]; then
        url="$REPO_URL"
        branch="${REPO_BRANCH:-$(_仓库默认分支 "$url")}"
        printf '%s|%s\n' "$url" "$branch"
        return 0
    fi
    if 是否国内区域; then
        printf '%s|%s\n' "$_SETUP_GITEE_URL" master
        printf '%s|%s\n' "$_SETUP_GITCODE_URL" main
        printf '%s|%s\n' "$_SETUP_GITHUB_URL" main
    else
        printf '%s|%s\n' "$_SETUP_GITHUB_URL" main
        printf '%s|%s\n' "$_SETUP_GITCODE_URL" main
        printf '%s|%s\n' "$_SETUP_GITEE_URL" master
    fi
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
    local cand url branch branch_now
    # 重建安装目录前离开该路径，避免 getcwd / No such file or directory
    if ! { cd . && [[ -d . ]]; } 2>/dev/null; then
        cd / || cd "$HOME" || true
    fi
    case "$(pwd -P 2>/dev/null || true)/" in
        "${INSTALL_DIR}/"*) cd / || cd "$HOME" || true ;;
    esac

    if [[ -d "$INSTALL_DIR/lib" && -f "$INSTALL_DIR/lib/core.sh" ]]; then
        cd "$INSTALL_DIR" || return 1
        # git reset 会往 stdout 打印 "HEAD is now at ..."，不能污染 $() 捕获的路径
        branch_now=$(git symbolic-ref -q --short HEAD 2>/dev/null || true)
        git fetch origin >/dev/null 2>&1 || true
        if [[ -n "$branch_now" ]]; then
            git reset --hard "origin/${branch_now}" >/dev/null 2>&1 || true
        else
            git reset --hard @{u} >/dev/null 2>&1 || true
        fi
        git clean -f -d >/dev/null 2>/dev/null || true
        echo "$INSTALL_DIR"
        return 0
    fi

    rm -rf "$INSTALL_DIR"

    if 是否国内区域; then
        echo "[setup] 国内环境（${HAMSTER_DETECT_METHOD}），优先 Gitee…" >&2
    else
        echo "[setup] 海外环境（${HAMSTER_DETECT_METHOD}），优先 GitHub…" >&2
    fi
    [[ -n "${REPO_URL:-}" ]] && echo "[setup] 使用指定仓库: $REPO_URL" >&2

    while IFS= read -r cand; do
        [[ -z "$cand" ]] && continue
        url="${cand%%|*}"
        branch="${cand#*|}"
        echo "[setup] 尝试克隆: $url ($branch)" >&2
        if timeout 120 git clone --depth 1 -b "$branch" "$url" "$INSTALL_DIR" 2>/dev/null; then
            echo "[setup] ✓ 克隆成功: $url" >&2
            echo "$INSTALL_DIR"
            return 0
        fi
        rm -rf "$INSTALL_DIR"
    done < <(_克隆候选列表)

    echo "[setup] ✗ 克隆失败（已按区域尝试可用镜像）" >&2
    echo "[setup] 建议：检查网络，或指定仓库：" >&2
    echo "  REPO_URL=https://gitee.com/duac/hamster-script.git bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)" >&2
    return 1
}

_配置时区() {
    local tz
    tz=$(系统_检测时区)
    系统_是否国内时区 && return 0
    是否国内区域 || return 0
    echo "[setup] 系统时区为 ${tz:-未知}，设置为 Asia/Shanghai…"
    if timedatectl set-timezone Asia/Shanghai 2>/dev/null; then
        echo "[setup] ✓ 系统时区已设为 Asia/Shanghai"
        return 0
    fi
    if [[ -f /usr/share/zoneinfo/Asia/Shanghai ]]; then
        ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        echo Asia/Shanghai > /etc/timezone
        echo "[setup] ✓ 系统时区已设为 Asia/Shanghai"
    fi
}

_安装前引导() {
    local pkg_manager

    _配置时区

    pkg_manager=$(包管理_获取管理器 2>/dev/null || echo unknown)
    [[ "$pkg_manager" != "apt" ]] && return 0

    if 是否国内区域; then
        echo ""
        echo "检测到国内服务器（${HAMSTER_DETECT_METHOD}），自动优化 apt 源..."
        if _自动换源_apt; then
            echo "✓ apt 源已优化"
        else
            echo "⚠ 自动换源失败，继续安装..."
        fi
    fi
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

    # 进程替换 / 目录被删时 cwd 会失效；先落到安全目录
    if ! { cd . && [[ -d . ]]; } 2>/dev/null; then
        cd / 2>/dev/null || cd "$HOME" 2>/dev/null || true
    fi
    # 避免在即将重建的安装目录内执行（rm -rf 后 cwd 失效）
    case "$(pwd -P 2>/dev/null || true)/" in
        "${INSTALL_DIR}/"*) cd / || cd "$HOME" || true ;;
    esac

    repo_root="$(_仓库根路径)"
    if [[ -z "$repo_root" ]]; then
        repo_root="$(_拉取仓库)" || { echo "拉取仓库失败"; exit 1; }
    fi

    if [[ ! -f "$repo_root/lib/core.sh" ]]; then
        echo "仓库路径无效（缺少 lib/core.sh）: $repo_root" >&2
        exit 1
    fi

    export PROJECT_ROOT="$repo_root" HAMSTER_ROOT="$repo_root"
    cd "$repo_root" 2>/dev/null || cd / || true

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

    # 自动进入 tmux 桌面（先 cd 到有效目录，避免 getcwd 报错）
    if command -v hamster-tmux &>/dev/null; then
        echo "正在进入 tmux 桌面..."
        cd "$repo_root" 2>/dev/null || cd / || cd "$HOME" || true
        exec hamster-tmux
    else
        echo "运行: cs"
    fi
}

程序入口 "$@"
