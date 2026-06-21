#!/bin/bash
# XRK-AGT 安装脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
工具引导

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# 检查是否已安装
if [[ -d "$TOOL_INSTALL_DIR" ]]; then
    界面消息 "XRK-AGT 已存在于 $TOOL_INSTALL_DIR\n如需重装请先卸载" "错误"
    exit 1
fi

# 标准安装流程
工具_安装 "xrk-agt"

# 询问是否启动
if 界面确认 "是否现在启动 XRK-AGT？"; then
    if 工具_启动 "xrk-agt"; then
        界面成功 "XRK-AGT 已启动"
    else
        界面消息 "XRK-AGT 启动失败，请检查 Redis 和 MongoDB 是否正常运行" "错误"
    fi
fi

界面信息 "使用 cs 项目管理菜单管理 XRK-AGT"
