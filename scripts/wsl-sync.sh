#!/bin/bash
# WSL 开发同步：Windows 仓库内容 → /cs（不是 /cs/hamster-script）
#
# 用法（WSL root）:
#   sudo bash /mnt/c/Users/sunflowerss/Desktop/XRKshop/hamster-script/scripts/wsl-sync.sh
#
# 或指定路径:
#   HAMSTER_SOURCE=/mnt/c/.../hamster-script HAMSTER_INSTALL_DIR=/cs sudo bash scripts/wsl-sync.sh

set -euo pipefail

SOURCE="${HAMSTER_SOURCE:-/mnt/c/Users/sunflowerss/Desktop/XRKshop/hamster-script}"
TARGET="${HAMSTER_INSTALL_DIR:-/cs}"

if [[ $EUID -ne 0 ]]; then
    echo "请用 root 运行: sudo bash $0" >&2
    exit 1
fi

if [[ ! -f "$SOURCE/lib/core.sh" ]]; then
    echo "源目录无效（缺少 lib/core.sh）: $SOURCE" >&2
    exit 1
fi

echo "[sync] $SOURCE → $TARGET/"

mkdir -p "$TARGET"

if command -v rsync &>/dev/null; then
    rsync -a --delete \
        --exclude '.git/' \
        --exclude '.tmux-home/' \
        "$SOURCE/" "$TARGET/"
else
    find "$TARGET" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
    cp -a "$SOURCE/." "$TARGET/"
fi

find "$TARGET" -type f \( -name '*.sh' -o -path '*/bin/*' -o -name '*.conf' \) \
    -exec sed -i 's/\r$//' {} + 2>/dev/null || true
find "$TARGET" -type f \( -name '*.sh' -o -path '*/bin/*' \) \
    -exec chmod +x {} + 2>/dev/null || true

# shellcheck source=/dev/null
source "$TARGET/lib/core.sh"
初始化核心
安装_后处理 "$TARGET"
安装_系统目录 "$TARGET"

echo "[sync] 完成。验证: head -5 $TARGET/lib/pkg.sh"
head -5 "$TARGET/lib/pkg.sh"
echo "[sync] 运行: cs"
