# 🐹 Hamster Script

一个功能完善的 Linux 服务器管理脚本集，提供友好的 dialog 菜单界面。

## 功能特性

- **软件管理**: 安装、卸载、搜索、列表、更新软件源、升级所有软件
- **项目管理**: 安装项目、项目列表、删除项目、项目配置
- **系统管理**: 系统信息、更新、优化、安全加固、时间管理、用户管理、进程管理、磁盘分析
- **服务管理**: 服务列表、启动、停止、重启、状态查看
- **备份恢复**: 创建备份、恢复备份、备份列表、删除备份
- **系统监控**: CPU监控、内存监控、磁盘监控、网络监控、实时监控

## 安装

```bash
bash <(curl -sL https://gitee.com/duac/hamster-script/raw/main/install.sh)
```

## 使用方法

```bash
cs              # 启动主菜单
cs update       # 更新脚本
cs version      # 显示版本
cs help         # 查看帮助
```

## 目录结构

```
hamster-script/
├── bin/                    # 入口脚本
│   └── cs                 # 主命令入口
├── lib/                    # 核心库
│   ├── core.sh            # 核心加载器、配置管理
│   ├── log.sh             # 日志模块
│   ├── ui.sh              # dialog 封装
│   ├── pkg.sh             # 包管理
│   └── sys.sh             # 系统函数
├── modules/                # 功能模块
│   ├── menu.mod.sh        # 主菜单
│   ├── package.mod.sh     # 软件管理
│   ├── system.mod.sh      # 系统管理
│   ├── service.mod.sh     # 服务管理
│   ├── backup.mod.sh      # 备份恢复
│   ├── monitor.mod.sh     # 系统监控
│   ├── project.mod.sh     # 项目管理
│   └── update.mod.sh      # 更新模块
├── utils/                  # 工具脚本
│   ├── deps.sh            # 依赖检查
│   └── download.sh        # 下载工具
├── config/                 # 配置文件
│   ├── main.conf          # 主配置
│   ├── projects.yaml      # 项目配置
│   └── tmux/              # tmux 配置
├── packages/               # 安装脚本
└── install.sh             # 安装脚本
```

## 支持的系统

- Ubuntu / Debian
- CentOS / RHEL / Rocky / AlmaLinux
- Arch Linux / Manjaro
- Alpine Linux

## 配置文件

主配置文件位于 `/etc/hamster-scripts/main.conf`，可自定义：

```conf
log_dir=/var/log/hamster-scripts
backup_dir=/var/backups/hamster-scripts
dialog_width=60
dialog_height=15
```

## 菜单功能

```
主菜单
├── 软件管理
│   ├── 安装软件
│   ├── 搜索软件
│   ├── 已装列表
│   ├── 卸载软件
│   ├── 更新软件源
│   └── 升级所有软件
├── 项目管理
│   ├── 安装项目
│   ├── 项目列表
│   ├── 删除项目
│   └── 项目配置
├── 系统管理
│   ├── 系统信息
│   ├── 系统更新
│   ├── 系统优化
│   ├── 安全加固
│   ├── 时间管理
│   ├── 用户管理
│   ├── 进程管理
│   ├── 磁盘分析
│   └── 重启系统
├── 服务管理
│   ├── 服务列表
│   ├── 启动服务
│   ├── 停止服务
│   ├── 重启服务
│   └── 服务状态
├── 备份恢复
│   ├── 创建备份
│   ├── 恢复备份
│   ├── 备份列表
│   └── 删除备份
├── 系统监控
│   ├── CPU 监控
│   ├── 内存监控
│   ├── 磁盘监控
│   ├── 网络监控
│   └── 实时监控
├── 更新脚本
└── 退出
```

## 开发

### 模块开发

每个功能模块位于 `modules/` 目录，使用 `.mod.sh` 后缀：

```bash
#!/bin/bash

module_name_menu() {
    while true; do
        local choice
        choice=$(ui_submenu "模块名称" "请选择:" \
            "1" "功能1" \
            "2" "功能2")
        
        case "$choice" in
            1) function_1 ;;
            2) function_2 ;;
        esac
    done
}
```

### 核心函数

- `log_info/log_success/log_warn/log_error` - 日志输出
- `ui_menu/ui_msg/ui_input/ui_confirm` - 对话框封装
- `pkg_install/pkg_remove/pkg_search` - 包管理
- `sys_get_info/sys_service_*` - 系统函数

## 版本历史

- v2.0.0 - 重构版本，全新架构
- v1.0.0 - 初始版本

## License

MIT
