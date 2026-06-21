#!/bin/bash
# XRK-AGT 安装

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"

if 工具_是否已安装 "xrk-agt"; then
    界面错误 "XRK-AGT 已存在于 $TOOL_INSTALL_DIR\n如需重装请先卸载"
    exit 1
fi

if ! 界面任务 "" 工具_安装 "xrk-agt"; then
    exit 1
fi

if 界面确认 "是否现在启动 XRK-AGT？"; then
    if 工具_启动 "xrk-agt"; then
        界面成功 "XRK-AGT 已启动"
    else
        界面警告 "XRK-AGT 启动失败\n请检查 Redis/MongoDB 是否在运行\n或在管理菜单中前台启动查看日志"
    fi
fi
