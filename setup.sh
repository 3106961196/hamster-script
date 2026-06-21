#!/bin/bash

REPO_URL="${REPO_URL:-https://github.com/3106961196/hamster-script.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/cs}"

# GitHub 代理（可选，需显式启用: ENABLE_GITHUB_PROXY=1）
安装_Git代理() {
    if [[ "${ENABLE_GITHUB_PROXY:-0}" != "1" ]]; then
        return 0
    fi
    local _git_proxy_cfg="url.https://gh-proxy.com/https://github.com/.insteadOf"
    git config --global "$_git_proxy_cfg" "https://github.com/"
    echo "已启用 GitHub 代理 (gh-proxy.com)，可通过 git config --global --unset-all url.https://gh-proxy.com/https://github.com/.insteadOf 撤销"
}

TOTAL_STEPS=6
CURRENT_STEP=0

显示进度() {
    local current="$1"
    local total="$2"
    local message="$3"
    local width=40
    local percent=$((current * 100 / total))
    local filled=$((current * width / total))
    local empty=$((width - filled))
    
    printf "\r["
    printf "%${filled}s" | tr ' ' '='
    printf "%${empty}s" | tr ' ' '-'
    printf "] %3d%% %s" "$percent" "$message"
    
    if [[ "$current" -eq "$total" ]]; then
        echo ""
    fi
}

显示步骤() {
    local step_num="$1"
    local message="$2"
    echo ""
    echo "[$step_num/$TOTAL_STEPS] $message"
}

打印横幅() {
    clear
    echo ""
    echo "    (\\_/)"
    echo "    ( •_•)"
    echo "    / >🐹< \\"
    echo "   /     \\"
    echo "  /       \\"
    echo ""
    echo "           Hamster Script Installer"
    echo ""
}

检查Root权限() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 请使用 root 用户运行此脚本"
        exit 1
    fi
}

检查操作系统() {
    if [[ ! -f /etc/os-release ]]; then
        echo "错误: 无法识别系统类型"
        exit 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            PKG_MANAGER="apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            PKG_MANAGER="yum"
            ;;
        arch|manjaro)
            PKG_MANAGER="pacman"
            ;;
        alpine)
            PKG_MANAGER="apk"
            ;;
        *)
            echo "错误: 不支持的系统: $ID"
            exit 1
            ;;
    esac
}

安装依赖() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "安装依赖包..."

    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt update -qq || { echo "错误: apt update 失败"; exit 1; }
            apt install -y -qq git wget curl tar xz-utils jq sudo tmux dialog fonts-wqy* grep || apt install -y git wget curl tar xz-utils jq sudo tmux dialog grep || { echo "错误: 依赖包安装失败"; exit 1; }
            ;;
        yum)
            yum install -y -q git wget curl tar xz jq sudo tmux dialog grep || { echo "错误: 依赖包安装失败"; exit 1; }
            ;;
        pacman)
            pacman -S --noconfirm --quiet git wget curl tar xz jq sudo tmux dialog grep || { echo "错误: 依赖包安装失败"; exit 1; }
            ;;
        apk)
            apk add --quiet git wget curl tar xz jq sudo tmux dialog grep || { echo "错误: 依赖包安装失败"; exit 1; }
            ;;
    esac
}

检查Dialog() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "检查 dialog..."

    if command -v dialog &>/dev/null; then
        echo "dialog 已安装，跳过"
        return 0
    fi

    echo "正在安装 dialog..."
    case "$PKG_MANAGER" in
        apt) apt install -y -qq dialog || { echo "错误: dialog 安装失败"; exit 1; } ;;
        yum) yum install -y dialog || { echo "错误: dialog 安装失败"; exit 1; } ;;
        pacman) pacman -S --noconfirm dialog || { echo "错误: dialog 安装失败"; exit 1; } ;;
        apk) apk add dialog || { echo "错误: dialog 安装失败"; exit 1; } ;;
    esac

    if ! command -v dialog &>/dev/null; then
        echo "错误: dialog 安装失败"
        exit 1
    fi
    echo "dialog 安装成功"
}

询问备份() {
    local dir="$1"
    local backup_dir="${dir}.bak.$(date +%Y%m%d%H%M%S)"
    
    echo ""
    echo "检测到 $dir 已存在"
    if [[ -d "$dir/.git" ]]; then
        local current_url
        current_url=$(cd "$dir" && git config --get remote.origin.url 2>/dev/null)
        if [[ -n "$current_url" ]]; then
            echo "当前仓库: $current_url"
        fi
    else
        echo "该目录不是 git 仓库"
    fi
    echo ""
    
    read -p "是否备份并清理？(Y/n): " choice
    choice=${choice:-y}
    
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "正在备份到 $backup_dir ..."
        mv "$dir" "$backup_dir"
        return 0
    else
        echo "取消安装"
        return 1
    fi
}

下载脚本() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "下载脚本..."
    
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -d "$INSTALL_DIR/.git" ]]; then
            local current_url
            current_url=$(cd "$INSTALL_DIR" && git config --get remote.origin.url 2>/dev/null)
            
            if [[ "$current_url" == "$REPO_URL" ]]; then
                echo "更新现有安装..."
                cd "$INSTALL_DIR"
                git fetch origin >/dev/null 2>&1
                if ! git diff --quiet 2>/dev/null || ! git diff --cached --quiet 2>/dev/null; then
                    echo ""
                    echo "警告: 检测到本地未提交的修改，强制更新将丢失这些改动"
                    read -p "是否继续强制更新？(y/N): " force_update
                    if [[ ! "$force_update" =~ ^[Yy]$ ]]; then
                        echo "已取消更新"
                        return 0
                    fi
                fi
                git reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1
                git clean -f -d >/dev/null 2>&1
            else
                if 询问备份 "$INSTALL_DIR"; then
                    echo "克隆仓库..."
                    git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
                else
                    exit 0
                fi
            fi
        else
            if 询问备份 "$INSTALL_DIR"; then
                echo "克隆仓库..."
                git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
            else
                exit 0
            fi
        fi
    else
        echo "克隆仓库..."
        git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
    fi
    
    find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
}

创建命令() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "创建 cs 命令..."
    
    cat > /usr/local/bin/cs << EOF
#!/bin/bash
bash ${INSTALL_DIR}/bin/cs "\$@"
EOF
    chmod +x /usr/local/bin/cs
}

创建目录() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "创建配置目录..."
    
    mkdir -p /var/log/hamster-scripts
    mkdir -p /var/backups/hamster-scripts
    mkdir -p /etc/hamster-scripts
    mkdir -p /var/lib/hamster-scripts
    mkdir -p /root/cs
    mkdir -p "$INSTALL_DIR/app"
    
    if [[ -f "$INSTALL_DIR/config/config.yaml" ]]; then
        cp "$INSTALL_DIR/config/config.yaml" /etc/hamster-scripts/ 2>/dev/null
        echo "install_dir: $INSTALL_DIR" >> /etc/hamster-scripts/config.yaml
    fi
}

安装Tmux() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "配置 Tmux..."

    export HAMSTER_ROOT="$INSTALL_DIR"
    bash "$INSTALL_DIR/config/tmux/setup.sh"

    echo '[[ -f /cs/.init.sh ]] && source /cs/.init.sh' >> "$HOME/.bashrc"
}

打印成功信息() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    显示步骤 "$CURRENT_STEP" "安装完成!"
    
    echo ""
    echo "========================================"
    echo "          🎉 安装完成!"
    echo "========================================"
    echo ""
    echo "使用方法:"
    echo "  cs          - 启动主菜单"
    echo "  cs update   - 更新脚本（别名: cs r）"
    echo "  cs version  - 显示版本"
    echo "  cs help     - 查看帮助"
    echo "  hamster-tmux - 进入 tmux 桌面"
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo ""
}

同步时区() {
    if command -v timedatectl &>/dev/null; then
        timedatectl set-ntp true 2>/dev/null || true
        local timezone
        if command -v curl &>/dev/null; then
            timezone=$(curl -s --connect-timeout 3 http://ip-api.com/json 2>/dev/null | grep -oP '"timezone":"\K[^"]+' || echo "")
        fi
        if [[ -n "$timezone" ]]; then
            timedatectl set-timezone "$timezone" 2>/dev/null || true
        fi
    fi
}

程序入口() {
    打印横幅
    检查Root权限
    检查操作系统
    安装_Git代理
    安装依赖
    检查Dialog
    下载脚本
    创建命令
    创建目录
    安装Tmux
    打印成功信息
    
    同步时区
    
    if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
        echo "正在启动 Tmux..."
        hamster-tmux 2>/dev/null || bash "$INSTALL_DIR/config/tmux/tmux.sh"
    fi
}

程序入口 "$@"
