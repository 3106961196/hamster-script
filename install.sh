#!/bin/bash

REPO_URL="https://github.com/3106961196/hamster-script.git"
INSTALL_DIR="${INSTALL_DIR:-/cs}"

TOTAL_STEPS=6
CURRENT_STEP=0

show_progress() {
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

print_banner() {
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

install_dependencies() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "安装依赖包..."
    
    local packages="git wget curl tar dialog xz-utils jq sudo tmux"
    
    case "$PKG_MANAGER" in
        apt)
            export DEBIAN_FRONTEND=noninteractive
            apt update -qq 2>/dev/null
            apt install -y -qq $packages fonts-wqy* 2>/dev/null || apt install -y $packages >/dev/null 2>&1
            ;;
        yum)
            yum install -y -q git wget curl tar dialog xz jq sudo tmux >/dev/null 2>&1
            ;;
        pacman)
            pacman -S --noconfirm --quiet git wget curl tar dialog xz jq sudo tmux >/dev/null 2>&1
            ;;
        apk)
            apk add --quiet git wget curl tar dialog xz jq sudo tmux >/dev/null 2>&1
            ;;
    esac
}

ask_backup() {
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

download_scripts() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    
    if [[ -d "$INSTALL_DIR" ]]; then
        if [[ -d "$INSTALL_DIR/.git" ]]; then
            local current_url
            current_url=$(cd "$INSTALL_DIR" && git config --get remote.origin.url 2>/dev/null)
            
            if [[ "$current_url" == "$REPO_URL" ]]; then
                show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "更新现有安装..."
                cd "$INSTALL_DIR"
                git fetch origin >/dev/null 2>&1
                git reset --hard origin/main >/dev/null 2>&1
                git clean -f -d >/dev/null 2>&1
            else
                if ask_backup "$INSTALL_DIR"; then
                    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "克隆仓库..."
                    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
                else
                    exit 0
                fi
            fi
        else
            if ask_backup "$INSTALL_DIR"; then
                show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "克隆仓库..."
                git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
            else
                exit 0
            fi
        fi
    else
        show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "克隆仓库..."
        git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" >/dev/null 2>&1
    fi
    
    find "$INSTALL_DIR" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null
}

create_command() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "创建 cs 命令..."
    
    cat > /usr/local/bin/cs << 'EOF'
#!/bin/bash
bash /cs/bin/cs "$@"
EOF
    chmod +x /usr/local/bin/cs
}

create_directories() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "创建配置目录..."
    
    mkdir -p /var/log/hamster-scripts
    mkdir -p /var/backups/hamster-scripts
    mkdir -p /etc/hamster-scripts
    mkdir -p /var/lib/hamster-scripts
    mkdir -p /root/cs
    
    if [[ -f "$INSTALL_DIR/config/dialogrc" ]]; then
        cp "$INSTALL_DIR/config/dialogrc" /etc/hamster-scripts/
    fi
}

setup_tmux() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "配置 Tmux..."
    
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
    fi
}

print_success() {
    CURRENT_STEP=$((CURRENT_STEP + 1))
    show_progress "$CURRENT_STEP" "$TOTAL_STEPS" "安装完成!"
    
    echo ""
    echo "========================================"
    echo "          🎉 安装完成!"
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

sync_timezone() {
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
    
    sync_timezone
    
    if [[ -n "$SSH_CONNECTION" && -z "$TMUX" ]]; then
        echo "正在启动 Tmux..."
        bash "$INSTALL_DIR/packages/tmux.sh"
    fi
}

main "$@"
