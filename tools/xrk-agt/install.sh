#!/bin/bash
# XRK-AGT 安装（克隆依赖后 pnpm build，再启动 dist/app.js）

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
cd "$TOOL_INSTALL_DIR" || exit 1

日志信息 "正在构建 XRK-AGT（pnpm build）..."
if ! pnpm build; then
    界面错误 "构建失败\n请检查 pnpm build 输出"
    exit 1
fi
if [[ ! -f "dist/app.js" ]]; then
    界面错误 "构建后仍缺少 dist/app.js"
    exit 1
fi

界面清屏
exec node --expose-gc --no-warnings dist/app.js
