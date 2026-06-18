#!/bin/bash
# XRK-AGT 安装脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
tool_bootstrap

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# 检查是否已安装
if [[ -d "$TOOL_INSTALL_DIR" ]]; then
    ui_msg "XRK-AGT 已存在于 $TOOL_INSTALL_DIR\n如需重装请先卸载" "错误"
    exit 1
fi

# 标准安装流程
tool_install "xrk-agt"

# 询问是否启动
if ui_confirm "是否现在启动 XRK-AGT？"; then
    if tool_start "xrk-agt"; then
        ui_success "XRK-AGT 已启动"
    else
        ui_msg "XRK-AGT 启动失败，请检查 Redis 和 MongoDB 是否正常运行" "错误"
    fi
fi

ui_info "使用 cs 项目管理菜单管理 XRK-AGT"
