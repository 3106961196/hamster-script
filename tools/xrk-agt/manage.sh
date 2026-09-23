#!/bin/bash
# XRK-AGT 管理（TypeScript dist 入口：pnpm build → node dist/app.js）

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"

# 构建 dist（tsc + copy-runtime-assets）；失败则不可启动
_XRK_构建() {
    cd "$TOOL_INSTALL_DIR" || return 1
    if [[ ! -f "package.json" ]]; then
        界面错误 "未找到 package.json"
        return 1
    fi
    日志信息 "正在构建 XRK-AGT（pnpm build）..."
    if ! pnpm build; then
        界面错误 "构建失败\n请检查 pnpm build 输出"
        return 1
    fi
    if [[ ! -f "dist/app.js" ]]; then
        界面错误 "构建后仍缺少 dist/app.js"
        return 1
    fi
    return 0
}

# $1 = dist 相对入口，如 dist/app.js / dist/debug.js
_XRK_运行() {
    local entry="${1:-dist/app.js}"

    工具_是否已安装 "xrk-agt" || {
        界面警告 "XRK-AGT 未安装\n请先安装"
        return 1
    }

    工具_加载配置 "xrk-agt" || return 1
    工具_安装依赖 "xrk-agt" || return 1
    工具_安装Npm依赖 "xrk-agt" || return 1
    _XRK_构建 || return 1

    cd "$TOOL_INSTALL_DIR" || return 1
    if [[ ! -f "$entry" ]]; then
        界面错误 "入口不存在: $entry"
        return 1
    fi

    界面清屏
    # 与线上习惯一致：暴露 GC、抑制实验告警
    exec node --expose-gc --no-warnings "$entry"
}

_XRK_重装项目() {
    工具_是否已安装 "xrk-agt" || {
        界面警告 "XRK-AGT 未安装\n请先安装"
        return 1
    }

    界面确认 "重装 XRK-AGT 将拉取最新代码并重新安装依赖\n\n确定继续？" "重装确认" || return 0
    工具_更新 "xrk-agt"
    工具_加载配置 "xrk-agt" || return 1
    _XRK_构建 || return 1
    界面完成 "XRK-AGT 重装完成"
}

_XRK_卸载项目() {
    工具_是否已安装 "xrk-agt" || {
        界面消息 "XRK-AGT 未安装" "提示"
        return 0
    }

    界面确认 "卸载 XRK-AGT 将会删除安装目录\n\n确定继续？" || return 0
    工具_卸载 "xrk-agt"
}

XRK_管理() {
    UI_BACKTITLE="XRK-AGT · ${UI_BACKTITLE:-Hamster Script}"
    while true; do
        local choice
        choice=$(界面子菜单 "XRK-AGT 管理" "请选择操作:" \
            "1" "启动" \
            "2" "Debug 启动" \
            "3" "重装项目" \
            "4" "卸载项目")

        case "$choice" in
            1) _XRK_运行 dist/app.js ;;
            2) _XRK_运行 dist/debug.js ;;
            3) _XRK_重装项目 ;;
            4) _XRK_卸载项目 && exit 0 ;;
            b|"") exit 0 ;;
        esac
    done
}

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)        _XRK_运行 dist/app.js ;;
        debug)        _XRK_运行 dist/debug.js ;;
        reinstall)    _XRK_重装项目 ;;
        is-installed) 工具_是否已安装 "xrk-agt" && echo "yes" || echo "no" ;;
        uninstall)    _XRK_卸载项目 ;;
        *)
            echo "用法: manage.sh --auto {start|debug|reinstall|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    XRK_管理
fi
