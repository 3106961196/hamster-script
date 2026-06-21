#!/bin/bash
# 安装 tmux 并写入 ~/.tmux.conf（对齐 xrk-projects-scripts 模式）
set -euo pipefail

INSTALL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

链接Tmux配置() {
    local 主配置文件 menus_tpl menus_out entry menu_cmd
    主配置文件="${INSTALL_DIR}/config/tmux/tmux.conf"
    menus_tpl="${INSTALL_DIR}/config/tmux/tmux-menus.conf"
    entry="$HOME/.tmux.conf"
    menus_out="$HOME/.tmux/hamster-menus.conf"
    menu_cmd="bash ${INSTALL_DIR}/config/tmux/tmux-menu.sh"

    [[ -f "$主配置文件" && -f "$menus_tpl" ]] || {
        echo "[hamster-tmux] 缺少 config/tmux/tmux.conf 或 tmux-menus.conf" >&2
        return 1
    }

    mkdir -p "$HOME/.tmux"
    sed "s|@HAMSTER_MENU@|${menu_cmd}|g" "$menus_tpl" > "$menus_out"
    {
        echo "# Hamster Script tmux（hamster-tmux --setup 生成）"
        cat "$主配置文件"
        echo ""
        echo "source-file ${menus_out}"
    } > "$entry"
    echo "[hamster-tmux] 已写入 $entry"
}

安装Tmux包() {
    command -v tmux &>/dev/null && {
        echo "[hamster-tmux] 已安装: $(tmux -V)"
        return 0
    }
    echo "[hamster-tmux] 安装 tmux…"
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
    elif command -v dnf &>/dev/null; then
        dnf install -y -q tmux
    elif command -v yum &>/dev/null; then
        yum install -y -q tmux
    elif command -v pacman &>/dev/null; then
        pacman -S --noconfirm tmux
    elif command -v apk &>/dev/null; then
        apk add tmux
    else
        echo "[hamster-tmux] 请手动安装 tmux" >&2
        return 1
    fi
    echo "[hamster-tmux] 已安装: $(tmux -V)"
}

创建Tmux包装命令() {
    cat > /usr/local/bin/hamster-tmux << EOF
#!/bin/bash
export HAMSTER_ROOT="${INSTALL_DIR}"
bash "${INSTALL_DIR}/config/tmux/tmux.sh" "\$@"
EOF
    chmod +x /usr/local/bin/hamster-tmux
}

case "${1:-}" in
    --link-only)
        链接Tmux配置
        exit 0
        ;;
esac

安装Tmux包
链接Tmux配置
创建Tmux包装命令
echo "[hamster-tmux] 完成"
