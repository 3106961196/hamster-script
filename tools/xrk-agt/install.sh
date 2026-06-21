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

工具_加载配置 "xrk-agt" || exit 1
工具_安装依赖 "xrk-agt" || exit 1
cd "$TOOL_INSTALL_DIR" || exit 1
界面清屏
exec node app.js
