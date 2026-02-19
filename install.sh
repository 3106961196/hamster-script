#!/bin/bash
set -e

REPO_URL="https://gitee.com/duac/hamster-script.git"
INSTALL_DIR="${INSTALL_DIR:-/cs}"

print_banner() {
    echo ""
    echo "  _    _           _                   _   _          _   _       _     _   "
    echo " | |  | |         | |                 | \ | |        | | | |     | |   | |  "
    echo " | |__| |_   _ ___| |_ ___ _ __       |  \| | ___  __| | | | ___ | | __| |  "
    echo " |  __  | | | / __| __/ _ \ '__|      | . \` |/ _ \/ _\` | | |/ _ \| |/ _\` |  "
    echo " | |  | | |_| \__ \ ||  __/ |         | |\  |  __/ (_| | | | (_) | | (_| |  "
    echo " |_|  |_|\__, |___/\__\___|_|         |_| \_|\___|\__,_| |_|\___/|_|\__,_|  "
    echo "          __/ |                                                              "
    echo "         |___/                                                               "
    echo ""
    echo "                    Hamster Script Installer v2.0"
    echo ""
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "错误: 请使用 root 用户运行此脚本"
        exit 1
    fi
}

check_os() {
    if [[ ! -f /etc/os-release ]]; then
        echo "错误: 无法识别系统类型"
        exit 1
    fi
    
    source /etc/os-release
    
    case "$ID" in
        ubuntu|debian)
            echo "检测到系统: $PRETTY_NAME"
            PKG_MANAGER="apt"
            ;;
        centos|rhel|fedora|rocky|almalinux)
            echo "检测到系统: $PRETTY_NAME"
            PKG_MANAGER="yum"
            ;;
        arch|manjaro)
            echo "检测到系统: $PRETTY_NAME"
            PKG_MANAGER="pacman"
            ;;
        alpine)
            echo "检测到系统: $PRETTY_NAME"
            PKG_MANAGER="apk"
            ;;
        *)
            echo "错误: 不支持的系统: $ID"
            exit 1
            ;;
    esac
}

install_dependencies() {
    echo ""
    echo "=== 安装依赖 ==="
    
    local packages="git wget curl tar dialog xz-utils jq sudo tmux"
    
    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt update -qq
            apt install -y -qq $packages fonts-wqy* 2>/dev/null || apt install -y $packages
            ;;
        yum)
            yum install -y -q git wget curl tar dialog xz jq sudo tmux
            ;;
        pacman)
            pacman -S --noconfirm --quiet git wget curl tar dialog xz jq sudo tmux
            ;;
        apk)
            apk add --quiet git wget curl tar dialog xz jq sudo tmux
            ;;
    esac
    
    echo "依赖安装完成"
}

download_scripts() {
    echo ""
    echo "=== 下载脚本 ==="
    
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -d "$INSTALL_DIR/.git" ]]; then
            local current_url
            current_url=$(cd "$INSTALL_DIR" && git config --get remote.origin.url 2>/dev/null)
            
            if [[ "$current_url" != "$REPO_URL" ]]; then
                echo "错误: $INSTALL_DIR 不是指定的仓库"
                exit 1
            fi
            
            echo "更新现有安装..."
            cd "$INSTALL_DIR"
            git fetch origin
            git reset --hard origin/main
            git clean -f -d
        else
            echo "错误: $INSTALL_DIR 已存在但不是 git 仓库"
            exit 1
        fi
    else
        echo "克隆仓库到 $INSTALL_DIR ..."
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
    fi
    
    find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \;
    
    echo "脚本下载完成"
}

create_command() {
    echo ""
    echo "=== 创建命令 ==="
    
    cat > /usr/local/bin/cs << 'EOF'
#!/bin/bash
bash /cs/bin/cs "$@"
EOF
    chmod +x /usr/local/bin/cs
    
    echo "cs 命令创建成功"
}

create_directories() {
    echo ""
    echo "=== 创建目录 ==="
    
    mkdir -p /var/log/hamster-scripts
    mkdir -p /var/backups/hamster-scripts
    mkdir -p /etc/hamster-scripts
    mkdir -p /var/lib/hamster-scripts
    mkdir -p /root/cs
    
    echo "目录创建完成"
}

setup_tmux() {
    echo ""
    echo "=== 配置 Tmux ==="
    
    local bashrc="$HOME/.bashrc"
    local auto_tmux='# Hamster Script Auto Tmux
if [ -n "$SSH_CONNECTION" ] && [ -z "$TMUX" ] && [ -n "$PS1" ] && command -v tmux >/dev/null 2>&1; then
    SESSION="🐹 Hamster Script"
    if tmux has-session -t "$SESSION" 2>/dev/null; then
        tmux attach-session -t "$SESSION"
    else
        bash /cs/packages/tmux.sh
    fi
fi'
    
    if ! grep -q "Hamster Script Auto Tmux" "$bashrc" 2>/dev/null; then
        echo "" >> "$bashrc"
        echo "$auto_tmux" >> "$bashrc"
        echo "Tmux 自动启动已配置"
    else
        echo "Tmux 已配置"
    fi
}

print_success() {
    echo ""
    echo "========================================"
    echo "          安装完成!"
    echo "========================================"
    echo ""
    echo "使用方法:"
    echo "  cs          - 启动主菜单"
    echo "  cs update   - 更新脚本"
    echo "  cs help     - 查看帮助"
    echo ""
    echo "安装目录: $INSTALL_DIR"
    echo ""
}

main() {
    print_banner
    check_root
    check_os
    install_dependencies
    download_scripts
    create_command
    create_directories
    setup_tmux
    print_success
    
    if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
        echo "正在启动 Tmux..."
        bash "$INSTALL_DIR/packages/tmux.sh"
    fi
}

main "$@"
