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
bash <(curl -sL https://github.com/3106961196/hamster-script/raw/main/setup.sh)
```

## 使用方法

```bash
cs              # 启动主菜单
cs update       # 更新脚本（别名: cs r）
cs version      # 显示版本
cs help         # 查看帮助
hamster-tmux    # 进入 tmux 桌面（SSH 登录自动进入）
cs tmux         # 同上（未安装 wrapper 时可用）
```

## 目录结构

```
hamster-script/
├── bin/                    # 入口脚本
│   └── cs                 # 主命令入口
├── lib/                    # 核心库
│   ├── core.sh            # 极简核心（路径 + 加载函数）
│   ├── config.sh          # 配置管理（CONFIG + YAML）
│   ├── log.sh             # 日志模块
│   ├── ui.sh              # dialog 封装
│   ├── pkg.sh             # 包管理 + 镜像源
│   ├── sys.sh             # 系统信息 + 清理
│   ├── service.sh         # 服务管理
│   ├── firewall.sh        # 防火墙管理
│   ├── net.sh             # 网络 + 下载
│   └── tool.sh            # 工具通用框架
├── app/                    # 应用模块
│   ├── menu.sh            # 主菜单
│   ├── package.sh         # 软件管理
│   ├── project.sh         # 项目管理
│   ├── system.sh          # 系统管理
│   ├── backup.sh          # 备份恢复
│   ├── monitor.sh         # 系统监控
│   ├── settings.sh        # 系统设置
│   └── update.sh          # 脚本更新
├── tools/                  # 工具实例
│   ├── _template/         # 工具模板
│   ├── napcat/            # NapCat 工具
│   │   ├── tool.conf      # 工具配置
│   │   ├── install.sh     # 安装脚本
│   │   └── manage.sh      # 管理脚本
│   └── xrk-agt/           # XRK-AGT 工具
│       ├── tool.conf      # 工具配置
│       ├── install.sh     # 安装脚本
│       └── manage.sh      # 管理脚本
├── config/                 # 配置文件
│   ├── config.yaml        # 主配置
│   └── tmux/              # tmux 桌面（对齐 xrk 模式）
│       ├── tmux.sh        # 桌面入口
│       ├── setup.sh       # 安装并写入 ~/.tmux.conf
│       ├── tmux.conf      # 主配置模板
│       ├── tmux-menus.conf
│       └── tmux-menu.sh
└── setup.sh               # 项目安装脚本
```

## 支持的系统

- Ubuntu / Debian
- CentOS / RHEL / Rocky / AlmaLinux
- Arch Linux / Manjaro
- Alpine Linux

## 配置文件

主配置文件位于 `config/config.yaml`，可自定义：

```yaml
log_dir: /var/log/hamster-scripts
backup_dir: /var/backups/hamster-scripts
work_dir: /root/cs
install_dir: /cs
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

每个功能模块位于 `app/` 目录：

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

### 工具开发

在 `tools/` 目录创建新工具：

```bash
tools/
└── my-tool/
    ├── tool.conf      # 工具配置
    ├── install.sh     # 安装脚本
    └── manage.sh      # 管理脚本
```

### 核心函数

- `log_info/log_success/log_warn/log_error` - 日志输出
- `ui_menu/ui_msg/ui_input/ui_confirm` - 对话框封装
- `pkg_install/pkg_remove/pkg_search` - 包管理
- `pkg_ensure_node/pkg_ensure_redis/pkg_ensure_mongodb` - 依赖检测安装
- `tool_install/tool_start/tool_stop/tool_status` - 工具管理


## License

MIT
