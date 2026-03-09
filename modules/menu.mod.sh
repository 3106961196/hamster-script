#!/bin/bash

main_menu() {
    while true; do
        local choice
        choice=$(ui_menu "🐹 Hamster Script" "请选择功能:" \
            "1" "📦 软件管理" \
            "2" "📁 项目管理" \
            "3" "⚙️ 系统管理" \
            "4" "💾 备份恢复" \
            "5" "📊 系统监控" \
            "6" "🔄 脚本更新" \
            "7" "⚙️ 系统设置" \
            "q" "🚪 退出")
        
        case "$choice" in
            1) package_menu ;;
            2) project_menu ;;
            3) system_menu ;;
            4) backup_menu ;;
            5) monitor_menu ;;
            6) update_menu ;;
            7) settings_menu ;;
            q) 
                ui_clear
                echo "再见！👋"
                exit 0
                ;;
        esac
    done
}
