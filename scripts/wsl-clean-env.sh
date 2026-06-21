#!/bin/bash
# 清理 WSL/Ubuntu 中的 Hamster 测试环境（从零测试前执行）
set -euo pipefail

echo "=== 停止 tmux 测试会话 ==="
tmux kill-session -t hamster-test 2>/dev/null || true

echo "=== 移除命令与安装目录 ==="
sudo rm -f /usr/local/bin/cs /usr/local/bin/hamster-tmux 2>/dev/null || true
sudo rm -rf /cs 2>/dev/null || true

echo "=== 移除配置与数据 ==="
rm -rf "$HOME/.config/hamster-scripts" 2>/dev/null || true
sudo rm -rf /etc/hamster-scripts 2>/dev/null || true
sudo rm -rf /var/log/hamster-scripts /var/backups/hamster-scripts /var/lib/hamster-scripts 2>/dev/null || true
sudo rm -rf /tmp/hamster-scripts 2>/dev/null || true

echo "=== 清理 bashrc 中的 hamster 条目 ==="
if [[ -f "$HOME/.bashrc" ]]; then
    sed -i '/# Hamster Script/,+1d' "$HOME/.bashrc" 2>/dev/null || true
    sed -i '/\.init\.sh/d' "$HOME/.bashrc" 2>/dev/null || true
    sed -i '/hamster-tmux/d' "$HOME/.bashrc" 2>/dev/null || true
fi

echo "=== 清理 tmux 配置（仅 hamster 相关）==="
if [[ -f "$HOME/.tmux.conf" ]] && grep -q 'Hamster Script tmux' "$HOME/.tmux.conf" 2>/dev/null; then
    rm -f "$HOME/.tmux.conf"
    rm -rf "$HOME/.tmux/hamster-menus.conf" 2>/dev/null || true
fi

echo "=== 移除旧的本机副本 ==="
rm -rf "$HOME/hamster-script" 2>/dev/null || true

echo "=== 清理完成 ==="
echo "  cs:           $(command -v cs 2>/dev/null || echo '未安装')"
echo "  hamster-tmux: $(command -v hamster-tmux 2>/dev/null || echo '未安装')"
echo "  /cs:          $([ -d /cs ] && echo '存在' || echo '不存在')"
echo "  ~/hamster-script: $([ -d ~/hamster-script ] && echo '存在' || echo '不存在')"
