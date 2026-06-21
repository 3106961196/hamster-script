#!/bin/bash
# 将 Windows 工作区脚本复制到 Ubuntu 原生目录（避免 /mnt/c 权限与换行问题）
set -euo pipefail

SRC="${1:-/mnt/c/Users/sunflowerss/Desktop/XRKshop/hamster-script}"
DEST="${2:-$HOME/hamster-script}"

if [[ ! -d "$SRC" ]]; then
    echo "错误: 源目录不存在: $SRC" >&2
    exit 1
fi

echo "=== 复制脚本 ==="
echo "  源: $SRC"
echo "  目标: $DEST"

rm -rf "$DEST"
mkdir -p "$DEST"

# rsync 优先；无 rsync 时用 cp
if command -v rsync &>/dev/null; then
    rsync -a --delete \
        --exclude '.git/' \
        --exclude '__pycache__/' \
        "$SRC/" "$DEST/"
else
    cp -a "$SRC/." "$DEST/"
    rm -rf "$DEST/.git" 2>/dev/null || true
fi

echo "=== 修正换行与权限 ==="
find "$DEST" -type f \( -name '*.sh' -o -path '*/bin/cs' \) -exec sed -i 's/\r$//' {} +
find "$DEST" -type f \( -name '*.sh' -o -path '*/bin/cs' \) -exec chmod +x {} +

echo "=== WSL 本地测试配置（非 root 友好）==="
mkdir -p "$HOME/.config/hamster-scripts"
cat > "$HOME/.config/hamster-scripts/config.yaml" << EOF
# WSL 本地从零测试配置（setup.sh 安装前可先用此路径跑菜单）
log_dir: $HOME/.local/log/hamster-scripts
backup_dir: $HOME/.local/backups/hamster-scripts
temp_dir: $HOME/.local/tmp/hamster-scripts
work_dir: $HOME/cs-work
install_dir: $HOME/hamster-script
EOF
mkdir -p "$HOME/.local/log/hamster-scripts" "$HOME/.local/backups/hamster-scripts" \
    "$HOME/.local/tmp/hamster-scripts" "$HOME/cs-work"

echo ""
echo "=== 复制完成 ==="
echo "  目录: $DEST"
echo "  文件数: $(find "$DEST" -type f | wc -l)"
echo ""
echo "快速验证:"
echo "  cd $DEST && bash bin/cs version"
echo ""
echo "启动主菜单（无需 root）:"
echo "  cd $DEST && bash bin/cs"
echo ""
echo "完整安装测试（需 root，模拟生产环境）:"
echo "  cd $DEST && sudo bash setup.sh"
