#!/bin/bash
# 本地快速自检（WSL / Linux）
set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== 1. 版本 ==="
bash bin/cs version

echo ""
echo "=== 2. 语法检查 ==="
for f in lib/*.sh app/*.sh bin/cs config/tmux/*.sh tools/*/*.sh; do
    bash -n "$f"
done
echo "全部通过"

echo ""
echo "=== 3. 初始化与配置 ==="
source lib/core.sh
初始化核心
echo "log_dir=$(获取配置 log_dir)"
echo "work_dir=$(获取工作目录)"

echo ""
echo "=== 4. 系统信息（前 5 行）==="
系统_获取信息 | head -5

echo ""
echo "=== 5. tmux 状态 ==="
bash config/tmux/tmux.sh --status 2>&1 | head -8

echo ""
echo "自检完成。交互菜单请运行: bash bin/cs"
