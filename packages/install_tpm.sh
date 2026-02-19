#!/bin/bash

TPM_DIR="/cs/config/tmux/plugins/tpm"
TPM_REPO="https://github.com/tmux-plugins/tpm"

echo "正在安装 Tmux Plugin Manager (TPM)..."

if [ -d "$TPM_DIR" ]; then
    echo "TPM 已存在于 $TPM_DIR"
    echo "正在更新 TPM..."
    cd "$TPM_DIR" && git pull
else
    echo "正在克隆 TPM 仓库..."
    mkdir -p "$(dirname "$TPM_DIR")"
    git clone "$TPM_REPO" "$TPM_DIR"
fi

if [ $? -eq 0 ]; then
    echo "TPM 安装成功！"
    echo "请按以下步骤操作："
    echo "1. 重新加载 tmux 配置: tmux source-file /cs/config/tmux/.tmux.conf"
    echo "2. 安装插件: 按 Ctrl+b 然后按 I (大写 i)"
else
    echo "TPM 安装失败！"
    exit 1
fi
