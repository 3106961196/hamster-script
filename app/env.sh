#!/bin/bash

环境_tmux() {
    local sub
    sub=$(界面子菜单 "tmux" "请选择:" \
        "1" "安装/配置 tmux" \
        "2" "进入 tmux 桌面")
    case "$sub" in
        1)
            if 界面任务 "正在配置 tmux..." bash "$PROJECT_ROOT/config/tmux/setup.sh"; then
                界面成功 "tmux 已就绪"
            else
                界面错误 "tmux 配置失败"
            fi
            ;;
        2)
            界面清屏
            exec bash "$PROJECT_ROOT/config/tmux/tmux.sh"
            ;;
        b|'') ;;
    esac
}

环境_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "🔧 环境与工具" "请选择:" \
            "1" "tmux 安装/进入" \
            "2" "同步命令到 bin" \
            "b" "返回")

        case "$choice" in
            1) 环境_tmux ;;
            2)
                if 界面任务 "正在同步命令..." 安装_同步命令 "$PROJECT_ROOT"; then
                    界面成功 "命令已同步到 /usr/local/bin"
                else
                    界面错误 "同步失败"
                fi
                ;;
            b|'') break ;;
        esac
    done
}
