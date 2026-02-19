#!/bin/bash

show_main_menu() {
    while true; do
        local choice
        choice=$(ui_menu "主菜单" "请选择功能:" \
            "1" "软件管理" \
            "2" "项目管理" \
            "3" "系统管理" \
            "4" "服务管理" \
            "5" "备份恢复" \
            "6" "系统监控" \
            "r" "更新脚本" \
            "q" "退出")
        
        local exit_code=$?
        
        if [[ $exit_code -ne 0 ]] || [[ "$choice" == "q" ]]; then
            ui_clear
            exit 0
        fi
        
        case "$choice" in
            1)
                load_module "package"
                package_menu
                ;;
            2)
                load_module "project"
                project_menu
                ;;
            3)
                load_module "system"
                system_menu
                ;;
            4)
                load_module "service"
                service_menu
                ;;
            5)
                load_module "backup"
                backup_menu
                ;;
            6)
                load_module "monitor"
                monitor_menu
                ;;
            r)
                load_module "update"
                module_update
                ;;
        esac
    done
}
