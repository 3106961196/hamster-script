#!/usr/bin/env python3
"""将项目内 Bash 函数名批量替换为中文命名。"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# 英文函数名 -> 中文函数名（按模块分组，便于维护）
RENAME_MAP: dict[str, str] = {
    # bin / setup / scripts
    "_show_help": "_显示帮助",
    "main": "程序入口",
    "setup_git_proxy": "安装_Git代理",
    "show_progress": "显示进度",
    "show_step": "显示步骤",
    "print_banner": "打印横幅",
    "check_root": "检查Root权限",
    "check_os": "检查操作系统",
    "install_dependencies": "安装依赖",
    "check_dialog": "检查Dialog",
    "ask_backup": "询问备份",
    "download_scripts": "下载脚本",
    "create_command": "创建命令",
    "create_directories": "创建目录",
    "setup_tmux": "安装Tmux",
    "print_success": "打印成功信息",
    "sync_timezone": "同步时区",
    "json_escape": "Json转义",
    "create_pr": "创建PR",
    # lib/core
    "get_project_root": "获取项目根目录",
    "load_lib": "加载库",
    "load_module": "加载模块",
    "load_all_libs": "加载全部库",
    "init_core": "初始化核心",
    "tool_bootstrap": "工具引导",
    "command_exists": "命令存在",
    "file_exists": "文件存在",
    "dir_exists": "目录存在",
    "ensure_dir": "确保目录",
    "is_root": "是否Root",
    "trim": "去空白",
    "random_string": "随机字符串",
    "cleanup_temp": "清理临时目录",
    "trap_add": "添加退出陷阱",
    # lib/config
    "parse_yaml": "解析YAML",
    "config_load": "加载配置",
    "config_get": "获取配置",
    "get_install_dir": "获取安装目录",
    "get_work_dir": "获取工作目录",
    "config_set": "设置配置",
    "save_user_config": "保存用户配置",
    "config_save": "保存配置",
    # lib/log
    "_get_log_priority": "_获取日志优先级",
    "_should_log": "_是否应记录日志",
    "_format_message": "_格式化日志消息",
    "_write_to_file": "_写入日志文件",
    "log_section": "日志分节",
    "log_success": "日志成功",
    "log_debug": "日志调试",
    "log_error": "日志错误",
    "log_warn": "日志警告",
    "log_info": "日志信息",
    "init_logging": "初始化日志",
    "set_log_level": "设置日志级别",
    "log": "写日志",
    # lib/ui
    "_ui_dialog_pick": "_界面选择对话框",
    "ui_multi_select": "界面多选",
    "ui_select_file": "界面选择文件",
    "ui_submenu": "界面子菜单",
    "ui_confirm": "界面确认",
    "ui_success": "界面成功",
    "ui_spinner": "界面加载动画",
    "ui_action": "界面动作",
    "ui_select": "界面选择",
    "ui_input": "界面输入",
    "ui_pause": "界面暂停",
    "ui_clear": "界面清屏",
    "ui_error": "界面错误",
    "ui_yesno": "界面是否",
    "ui_init": "界面初始化",
    "ui_menu": "界面菜单",
    "ui_text": "界面文本",
    "ui_info": "界面信息",
    "ui_msg": "界面消息",
    # lib/pkg
    "_apt_install": "_Apt安装",
    "pkg_get_system_type": "包管理_获取系统类型",
    "pkg_get_distro_version": "包管理_获取发行版版本",
    "pkg_get_upgradable_version": "包管理_获取可升级版本",
    "pkg_list_upgradable": "包管理_可升级列表",
    "pkg_list_installed": "包管理_已安装列表",
    "pkg_install_packages": "包管理_批量安装",
    "pkg_ensure_installed": "包管理_确保已安装",
    "pkg_ensure_chromium": "包管理_确保Chromium",
    "pkg_ensure_mongodb": "包管理_确保MongoDB",
    "pkg_get_manager": "包管理_获取管理器",
    "pkg_get_versions": "包管理_获取版本列表",
    "pkg_download_file": "包管理_下载文件",
    "pkg_ensure_redis": "包管理_确保Redis",
    "pkg_ensure_pnpm": "包管理_确保Pnpm",
    "pkg_show_info": "包管理_显示信息",
    "pkg_upgrade_all": "包管理_全部升级",
    "pkg_autoremove": "包管理_自动移除",
    "pkg_ensure_node": "包管理_确保Node",
    "pkg_git_clone": "包管理_Git克隆",
    "pkg_npm_install": "包管理_Npm安装",
    "pkg_is_installed": "包管理_是否已安装",
    "pkg_get_version": "包管理_获取版本",
    "pkg_install": "包管理_安装",
    "pkg_remove": "包管理_卸载",
    "pkg_search": "包管理_搜索",
    "pkg_update": "包管理_更新源",
    "pkg_upgrade": "包管理_升级",
    "pkg_clean": "包管理_清理",
    # lib/sys
    "sys_get_timezone_from_api": "系统_从API获取时区",
    "sys_get_memory_usage": "系统_获取内存使用",
    "sys_get_disk_usage": "系统_获取磁盘使用",
    "sys_get_cpu_usage": "系统_获取CPU使用",
    "sys_set_timezone": "系统_设置时区",
    "sys_get_timezone": "系统_获取时区",
    "sys_clean_journal": "系统_清理日志",
    "sys_clean_temp": "系统_清理临时",
    "sys_sync_time": "系统_同步时间",
    "sys_get_info": "系统_获取信息",
    # lib/service
    "sys_service_is_running": "服务_是否运行中",
    "sys_service_restart": "服务_重启",
    "sys_service_status": "服务_状态",
    "sys_service_start": "服务_启动",
    "sys_service_stop": "服务_停止",
    "sys_service_list": "服务_列表",
    "sys_is_systemd": "服务_是否Systemd",
    # lib/firewall
    "sys_get_firewall_type": "防火墙_获取类型",
    "sys_firewall_open_port": "防火墙_开放端口",
    "sys_firewall_close_port": "防火墙_关闭端口",
    "sys_firewall_disable": "防火墙_禁用",
    "sys_firewall_enable": "防火墙_启用",
    "sys_firewall_status": "防火墙_状态",
    # lib/net
    "sys_parse_process_list": "网络_解析进程列表",
    "sys_get_top_processes": "网络_获取Top进程",
    "sys_get_public_ip": "网络_获取公网IP",
    "sys_get_local_ip": "网络_获取本地IP",
    "sys_get_open_ports": "网络_获取开放端口",
    "sys_kill_process": "网络_结束进程",
    "sys_check_port": "网络_检查端口",
    "download_extract": "下载并解压",
    "download_file": "下载文件",
    "download_git": "下载Git仓库",
    "download": "下载",
    # lib/tool
    "tool_hook_install_linuxqq": "工具钩子_安装LinuxQQ",
    "tool_version_compare": "工具_版本比较",
    "tool_install_deps": "工具_安装依赖",
    "tool_is_installed": "工具_是否已安装",
    "tool_clone_repo": "工具_克隆仓库",
    "tool_install_npm": "工具_安装Npm依赖",
    "tool_uninstall": "工具_卸载",
    "tool_install": "工具_安装",
    "tool_restart": "工具_重启",
    "tool_status": "工具_状态",
    "tool_start": "工具_启动",
    "tool_stop": "工具_停止",
    "tool_update": "工具_更新",
    "tool_load": "工具_加载配置",
    # app
    "main_menu": "主菜单",
    "package_install_package": "软件包_安装指定包",
    "package_installed_list": "软件包_已安装列表",
    "package_package_action": "软件包_包操作",
    "package_update_sources": "软件包_更新软件源",
    "package_install": "软件包_安装",
    "package_menu": "软件包_菜单",
    "project_manage_script": "项目_管理脚本路径",
    "project_install_script": "项目_安装脚本路径",
    "project_check_status": "项目_检查状态",
    "project_display_name": "项目_显示名称",
    "project_do_install": "项目_执行安装",
    "project_menu": "项目_菜单",
    "project_type": "项目_类型",
    "system_optimize_custom": "系统管理_自定义优化",
    "system_optimize_menu": "系统管理_优化菜单",
    "system_service_action": "系统管理_服务操作",
    "system_service_menu": "系统管理_服务菜单",
    "system_security_check": "系统管理_安全检查",
    "system_security_menu": "系统管理_安全菜单",
    "system_firewall_status": "系统管理_防火墙状态",
    "system_firewall_enable": "系统管理_防火墙启用",
    "system_firewall_disable": "系统管理_防火墙禁用",
    "system_firewall_open_port": "系统管理_防火墙开放端口",
    "system_time_set_timezone": "系统管理_设置时区",
    "system_process_action": "系统管理_进程操作",
    "system_process_search": "系统管理_搜索进程",
    "system_process_list": "系统管理_进程列表",
    "system_process_menu": "系统管理_进程菜单",
    "system_disk_find_large": "系统管理_查找大文件",
    "system_disk_dir_size": "系统管理_目录大小",
    "system_disk_usage": "系统管理_磁盘使用",
    "system_disk_menu": "系统管理_磁盘菜单",
    "system_user_password": "系统管理_用户改密",
    "system_user_delete": "系统管理_删除用户",
    "system_user_list": "系统管理_用户列表",
    "system_user_menu": "系统管理_用户菜单",
    "system_user_add": "系统管理_添加用户",
    "system_time_show": "系统管理_显示时间",
    "system_time_menu": "系统管理_时间菜单",
    "system_time_sync": "系统管理_同步时间",
    "system_optimize_all": "系统管理_全部优化",
    "system_update": "系统管理_系统更新",
    "system_reboot": "系统管理_重启",
    "system_info": "系统管理_信息",
    "system_menu": "系统管理_菜单",
    "backup_view_content": "备份_查看内容",
    "backup_file_action": "备份_文件操作",
    "backup_restore": "备份_恢复",
    "backup_create": "备份_创建",
    "backup_delete": "备份_删除",
    "backup_manage": "备份_管理",
    "backup_menu": "备份_菜单",
    "monitor_network_interfaces": "监控_网络接口",
    "monitor_network_connections": "监控_网络连接",
    "monitor_network_ports": "监控_网络端口",
    "monitor_network_test": "监控_网络测试",
    "monitor_realtime": "监控_实时",
    "monitor_processes": "监控_进程",
    "monitor_overview": "监控_概览",
    "monitor_resources": "监控_资源",
    "monitor_network": "监控_网络",
    "monitor_memory": "监控_内存",
    "monitor_menu": "监控_菜单",
    "monitor_disk": "监控_磁盘",
    "monitor_cpu": "监控_CPU",
    "settings_set_path": "设置_设置路径",
    "settings_reset": "设置_重置",
    "settings_quick": "设置_快捷",
    "settings_edit": "设置_编辑",
    "settings_show": "设置_显示",
    "settings_menu": "设置_菜单",
    "_update_execute": "_更新_执行",
    "_update_check": "_更新_检查",
    "update_menu": "更新_菜单",
    "update_do": "更新_执行",
    # config/tmux
    "_hamster_work_dir": "_仓鼠工作目录",
    "_tmux_apply_window_names": "_Tmux应用窗口名",
    "_tmux_repair_config": "_Tmux修复配置",
    "_tmux_reload_config": "_Tmux重载配置",
    "_tmux_session_usable": "_Tmux会话可用",
    "_tmux_create_layout": "_Tmux创建布局",
    "_tmux_ensure_utf8": "_Tmux确保UTF8",
    "_tmux_ensure_env": "_Tmux确保环境",
    "_tmux_status": "_Tmux状态",
    "_tmux_enter": "_Tmux进入",
    "_tmux_usage": "_Tmux用法",
    "_tmux_conf_ok": "_Tmux配置正常",
    "install_tmux_pkg": "安装Tmux包",
    "create_wrapper": "创建Tmux包装命令",
    "link_conf": "链接Tmux配置",
    # tools/napcat
    "_nc_install_linuxqq_from_hook": "_NapCat_从钩子安装LinuxQQ",
    "_nc_modify_qq_interactive": "_NapCat_交互修改QQ",
    "_nc_delete_qq_interactive": "_NapCat_交互删除QQ",
    "_nc_add_qq_interactive": "_NapCat_交互添加QQ",
    "_nc_start_qq_interactive": "_NapCat_交互启动QQ",
    "_nc_reinstall_project": "_NapCat_重装项目",
    "_nc_uninstall_project": "_NapCat_卸载项目",
    "_nc_generate_configs": "_NapCat_生成配置",
    "_nc_ensure_napcatbot": "_NapCat_确保Bot",
    "_nc_get_running_qqs": "_NapCat_获取运行中QQ",
    "_nc_compare_versions": "_NapCat_比较版本",
    "_nc_install_dependency": "_NapCat_安装依赖",
    "_nc_update_qq_config": "_NapCat_更新QQ配置",
    "_nc_get_system_arch": "_NapCat_获取系统架构",
    "_nc_download_napcat": "_NapCat_下载NapCat",
    "_nc_install_linuxqq": "_NapCat_安装LinuxQQ",
    "_nc_install_napcat": "_NapCat_安装NapCat",
    "_nc_show_all_status": "_NapCat_显示全部状态",
    "_nc_is_qq_running": "_NapCat_QQ是否运行",
    "_nc_add_update_qq": "_NapCat_添加或更新QQ",
    "_nc_get_qq_list": "_NapCat_获取QQ列表",
    "_nc_get_qq_port": "_NapCat_获取QQ端口",
    "_nc_remove_qq": "_NapCat_移除QQ",
    "_nc_start_qq": "_NapCat_启动QQ",
    "_nc_stop_qq": "_NapCat_停止QQ",
    "_nc_is_installed": "_NapCat_是否已安装",
    "_nc_is_running": "_NapCat_是否运行中",
    "_nc_pick_qq": "_NapCat_选择QQ",
    "_nc_manage": "_NapCat_管理",
    "_nc_main": "_NapCat_主流程",
    # tools/xrk-agt
    "_xrk_check_dependencies": "_XRK_检查依赖",
    "_xrk_reinstall_project": "_XRK_重装项目",
    "_xrk_uninstall_project": "_XRK_卸载项目",
    "_xrk_is_installed": "_XRK_是否已安装",
    "_xrk_start_service": "_XRK_启动服务",
    "_xrk_start_debug": "_XRK_启动调试",
    "xrk_manage": "XRK_管理",
}

PROTECT_TOKENS = [
    ("origin/main", "___ORIGIN_MAIN___"),
    ("origin/master", "___ORIGIN_MASTER___"),
    ("origin main", "___ORIGIN_MAIN_REF___"),
    ("origin master", "___ORIGIN_MASTER_REF___"),
    ("git pull origin main", "___GIT_PULL_MAIN___"),
    ("git pull origin master", "___GIT_PULL_MASTER___"),
]


def collect_files() -> list[Path]:
    files: list[Path] = []
    for pattern in ("**/*.sh", "bin/cs"):
        files.extend(ROOT.glob(pattern))
    return sorted(set(files))


def protect(text: str) -> str:
    for src, token in PROTECT_TOKENS:
        text = text.replace(src, token)
    return text


def unprotect(text: str) -> str:
    for src, token in PROTECT_TOKENS:
        text = text.replace(token, src)
    return text


def rename_functions(text: str) -> str:
    text = protect(text)
    for old in sorted(RENAME_MAP, key=len, reverse=True):
        new = RENAME_MAP[old]
        pattern = rf"(?<![A-Za-z0-9_]){re.escape(old)}(?![A-Za-z0-9_])"
        text = re.sub(pattern, new, text)
    return unprotect(text)


def main() -> None:
    changed = 0
    for path in collect_files():
        if "rename-functions-zh.py" in str(path):
            continue
        original = path.read_text(encoding="utf-8")
        updated = rename_functions(original)
        if updated != original:
            path.write_text(updated, encoding="utf-8", newline="\n")
            changed += 1
            print(f"updated: {path.relative_to(ROOT)}")
    print(f"done, {changed} files changed")


if __name__ == "__main__":
    main()
