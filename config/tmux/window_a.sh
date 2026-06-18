#!/bin/bash

# GitHub 代理（仅 tmux 内生效）
_git_proxy_cfg="url.https://gh-proxy.com/https://github.com/.insteadOf"
[[ "$(git config --global --get "$_git_proxy_cfg" 2>/dev/null)" != "https://github.com/" ]] && \
    git config --global "$_git_proxy_cfg" "https://github.com/"
unset _git_proxy_cfg

WORK_DIR="${HAMSTER_WORK_DIR:-/root/cs}"
cd "$WORK_DIR"
echo -e "\033[1;32m使用\"cs\"命令打开脚本主菜单\033[0m"
exec bash
