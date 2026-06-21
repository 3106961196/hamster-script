#!/bin/bash

加载模块 "package"
加载模块 "project"
加载模块 "system"
加载模块 "backup"
加载模块 "monitor"
加载模块 "update"
加载模块 "settings"

主菜单() {
    while true; do
        local choice
        choice=$(界面菜单 "🐹 Hamster Script" "请选择功能:" \
            "1" "📦 软件管理" \
            "2" "📁 项目列表" \
            "3" "⚙️ 系统管理" \
            "4" "💾 备份恢复" \
            "5" "📊 系统监控" \
            "6" "🔄 脚本更新" \
            "7" "⚙️ 系统设置" \
            "q" "🚪 退出")
        
        case "$choice" in
            1) 软件包_菜单 ;;
            2) 项目_菜单 ;;
            3) 系统管理_菜单 ;;
            4) 备份_菜单 ;;
            5) 监控_菜单 ;;
            6) 更新_菜单 ;;
            7) 设置_菜单 ;;
            q) 
                界面清屏
                echo "再见！👋"
                exit 0
                ;;
        esac
    done
}
