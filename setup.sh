#!/bin/bash

REPO_URL="${REPO_URL:-https://github.com/3106961196/hamster-script.git}"
REPO_BRANCH="${REPO_BRANCH:-main}"
INSTALL_DIR="${INSTALL_DIR:-/cs}"

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
    if [[ -d "$INSTALL_DIR/lib" && -f "$INSTALL_DIR/lib/core.sh" ]]; then
        cd "$INSTALL_DIR" || return 1
        # git reset 会往 stdout 打印 "HEAD is now at ..."，不能污染 $() 捕获的路径
        git fetch origin >/dev/null 2>&1 || true
        git reset --hard "origin/${REPO_BRANCH}" >/dev/null 2>&1 || true
        git clean -f -d >/dev/null 2>&1 || true
        echo "$INSTALL_DIR"
        return 0
    fi

    rm -rf "$INSTALL_DIR"
    git clone --depth 1 -b "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR" || return 1
    echo "$INSTALL_DIR"
}

_安装前引导() {
    local choice pkg_manager

    pkg_manager=$(包管理_获取管理器 2>/dev/null || echo unknown)
    [[ "$pkg_manager" != "apt" ]] && return 0

    echo ""
    echo "安装前可选步骤："
    echo "  1) 使用 linuxmirrors 换源"
    echo "  2) 跳过，直接安装"
    read -rp "请选择 [1/2]: " choice
    case "$choice" in
        1)
            echo "正在启动 linuxmirrors..."
            包管理_Linux换源 || echo "换源未完成" >&2
            ;;
    esac
}

程序入口() {
    local repo_root

    [[ $EUID -ne 0 ]] && { echo "请使用 root 运行 setup.sh"; exit 1; }

    repo_root="$(_仓库根路径)"
    if [[ -z "$repo_root" ]]; then
        repo_root="$(_拉取仓库)" || { echo "拉取仓库失败"; exit 1; }
    fi

    if [[ ! -f "$repo_root/lib/core.sh" ]]; then
        echo "仓库路径无效（缺少 lib/core.sh）: $repo_root" >&2
        exit 1
    fi

    export PROJECT_ROOT="$repo_root" HAMSTER_ROOT="$repo_root"

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
    echo "安装完成。运行: cs"
}

程序入口 "$@"
