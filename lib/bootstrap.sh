#!/bin/bash

安装_规范化脚本() {
    local root="${1:-$PROJECT_ROOT}"
    [[ -z "$root" || ! -d "$root" ]] && return 1

    find "$root" -type f \( -name '*.sh' -o -path '*/bin/*' -o -name '*.conf' \) \
        -exec sed -i 's/\r$//' {} + 2>/dev/null || true
    find "$root" -type f \( -name '*.sh' -o -path '*/bin/*' \) \
        -exec chmod +x {} \; 2>/dev/null || true
}

安装_同步命令() {
    local root="${1:-$PROJECT_ROOT}"
    [[ -f "$root/lib/bin_sync.sh" ]] || return 1
    # shellcheck source=/dev/null
    source "$root/lib/bin_sync.sh"
    命令同步 "$root"
}

安装_链接Tmux() {
    local root="${1:-$PROJECT_ROOT}"
    [[ -f "$root/config/tmux/setup.sh" ]] || return 0
    bash "$root/config/tmux/setup.sh" --link-only 2>/dev/null || true
}

# SSH 登录时自动进 tmux（写入 /etc/profile.d，login shell 生效）
安装_注册Shell钩子() {
    local root="${1:-$PROJECT_ROOT}"
    local hook="/etc/profile.d/hamster-init.sh"
    local install_dir="$root"

    [[ -f "$root/.init.sh" ]] || return 0

    if [[ -f /etc/hamster-scripts/config.yaml ]]; then
        install_dir=$(grep -E '^[[:space:]]*install_dir:' /etc/hamster-scripts/config.yaml 2>/dev/null | head -1 \
            | sed -E 's/^[^:]*:[[:space:]]*//; s/^["'\'' ]+//; s/["'\'' ]+$//')
    fi
    [[ -n "$install_dir" && -f "${install_dir}/.init.sh" ]] || install_dir="$root"

    cat > "$hook" <<EOF
# Hamster Script: SSH 登录 shell 自动进入 tmux
# 删除本文件，或 export HAMSTER_NO_TMUX=1 可关闭
if [ -f "${install_dir}/.init.sh" ]; then
    . "${install_dir}/.init.sh"
fi
EOF
    chmod 644 "$hook" 2>/dev/null || true
}

安装_后处理() {
    local root="${1:-$PROJECT_ROOT}"
    安装_规范化脚本 "$root"
    安装_同步命令 "$root"
    安装_链接Tmux "$root"
    安装_注册Shell钩子 "$root"
}

安装_系统目录() {
    local root="${1:-$PROJECT_ROOT}"
    mkdir -p /var/log/hamster-scripts /var/backups/hamster-scripts \
        /etc/hamster-scripts /var/lib/hamster-scripts 2>/dev/null || true
    if [[ -f "$root/config/config.yaml" ]]; then
        cp "$root/config/config.yaml" /etc/hamster-scripts/ 2>/dev/null || true
    fi
}
