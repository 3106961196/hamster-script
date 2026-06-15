#!/bin/bash

# GitHub 代理（仅 tmux 内生效）
_git_proxy_cfg="url.https://gh-proxy.com/https://github.com/.insteadOf"
[[ "$(git config --global --get "$_git_proxy_cfg" 2>/dev/null)" != "https://github.com/" ]] && \
    git config --global "$_git_proxy_cfg" "https://github.com/"
unset _git_proxy_cfg

cd /root/cs
exec bash
