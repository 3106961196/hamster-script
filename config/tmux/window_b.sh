#!/bin/bash

# GitHub 代理（可选，需显式启用: ENABLE_GITHUB_PROXY=1）
if [[ "${ENABLE_GITHUB_PROXY:-0}" == "1" ]]; then
    _git_proxy_cfg="url.https://gh-proxy.com/https://github.com/.insteadOf"
    [[ "$(git config --global --get "$_git_proxy_cfg" 2>/dev/null)" != "https://github.com/" ]] && \
        git config --global "$_git_proxy_cfg" "https://github.com/"
    unset _git_proxy_cfg
fi

WORK_DIR="${HAMSTER_WORK_DIR:-/root/cs}"
cd "$WORK_DIR"
exec bash
