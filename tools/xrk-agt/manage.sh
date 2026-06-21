#!/bin/bash
# XRK-AGT 管理

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"

_XRK_运行() {
    local entry="${1:-app.js}"

    工具_是否已安装 "xrk-agt" || {
        界面警告 "XRK-AGT 未安装\n请先安装"
        return 1
    }

    工具_加载配置 "xrk-agt" || return 1
    工具_安装依赖 "xrk-agt" || return 1
    cd "$TOOL_INSTALL_DIR" || return 1
    界面清屏
    exec node "$entry"
}

_XRK_重装项目() {
    工具_是否已安装 "xrk-agt" || {
        界面警告 "XRK-AGT 未安装\n请先安装"
        return 1
    }

    界面确认 "重装 XRK-AGT 将拉取最新代码并重新安装依赖\n\n确定继续？" "重装确认" || return 0
    工具_更新 "xrk-agt"
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
            1) _XRK_运行 app.js ;;
            2) _XRK_运行 debug.js ;;
            3) _XRK_重装项目 ;;
            4) _XRK_卸载项目 && exit 0 ;;
            b|"") exit 0 ;;
        esac
    done
}

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)        _XRK_运行 app.js ;;
        debug)        _XRK_运行 debug.js ;;
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
