#!/bin/bash

# shellcheck source=/dev/null
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"
Tmux_引导 "${BASH_SOURCE[0]}" || exit 1

case "${1:-}" in
    --link-only)
        Tmux_链接配置 "$INSTALL_DIR"
        exit $?
        ;;
esac

Tmux_清理旧配置
Tmux_安装包 || exit 1
Tmux_链接配置 "$INSTALL_DIR" || exit 1
echo "[hamster-tmux] 完成"
