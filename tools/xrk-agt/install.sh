#!/bin/bash
# XRK-AGT 安装脚本

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"

REPO_URL="https://github.com/sunflowermm/XRK-AGT"
INSTALL_DIR="${INSTALL_DIR:-/root/cs/XRK-AGT}"

echo "=== XRK-AGT 安装 ==="
echo ""

# 检查是否已安装
if [[ -d "$INSTALL_DIR" ]]; then
    echo "错误: XRK-AGT 已存在于 $INSTALL_DIR"
    echo "如需重装请先卸载"
    exit 1
fi

# 检查依赖
for cmd in git node npm; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "正在安装 $cmd..."
        if command -v apt &>/dev/null; then
            apt install -y "$cmd" 2>/dev/null
        elif command -v yum &>/dev/null; then
            yum install -y "$cmd" 2>/dev/null
        else
            echo "错误: 请先手动安装 $cmd"
            exit 1
        fi
    fi
done

# 安装 pnpm（如未安装）
if ! command -v pnpm &>/dev/null; then
    echo "正在安装 pnpm..."
    npm install -g pnpm
fi

# 创建目录
mkdir -p "$(dirname "$INSTALL_DIR")"

# 克隆仓库
echo "正在克隆 XRK-AGT 仓库..."
if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"; then
    echo "错误: 克隆仓库失败"
    exit 1
fi

# 安装依赖
echo "正在安装依赖..."
cd "$INSTALL_DIR"
if [[ -f "pnpm-lock.yaml" ]]; then
    pnpm install
elif [[ -f "yarn.lock" ]]; then
    yarn install
else
    npm install
fi

echo ""
echo "✅ XRK-AGT 安装成功！"
echo "安装目录: $INSTALL_DIR"
echo ""
echo "使用 cs 项目管理菜单启动 XRK-AGT"
