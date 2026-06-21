# 🐹 Hamster Script

一个功能完善的 Linux 服务器管理脚本集，提供友好的 dialog 菜单界面。  
**v2.0.0** · 函数命名已统一为中文，便于阅读与二次开发。

## 功能特性

- **软件管理**: 安装、卸载、搜索、列表、更新软件源、升级所有软件
- **项目管理**: 安装项目、项目列表、删除项目、项目配置
- **系统管理**: 系统信息、更新、优化、安全加固、时间管理、用户管理、进程管理、磁盘分析
- **服务管理**: 位于「系统管理 → 服务管理」子菜单
- **备份恢复**: 创建备份、恢复备份、备份列表、删除备份
- **系统监控**: CPU / 内存 / 磁盘 / 网络 / 实时监控
- **Tmux 桌面**: SSH 登录自动进入多窗格工作区

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
├── bin/cs                 # 主命令入口
├── lib/                   # 核心库（中文函数 API）
│   ├── core.sh            # 路径、加载、初始化
│   ├── config.sh          # 配置管理
│   ├── log.sh             # 日志
│   ├── ui.sh              # dialog 封装
│   ├── pkg.sh             # 包管理
│   ├── sys.sh             # 系统信息
│   ├── service.sh         # systemd 服务
│   ├── firewall.sh        # 防火墙
│   ├── net.sh             # 网络与下载
│   └── tool.sh            # 工具框架
├── app/                   # 菜单应用模块
├── tools/                 # 可安装工具（napcat、xrk-agt 等）
├── config/
│   ├── config.yaml        # 默认配置
│   └── tmux/              # tmux 桌面
├── scripts/               # 开发辅助（PR 提交、函数重命名）
└── setup.sh               # 一键安装
```

## 支持的系统

- Ubuntu / Debian
- CentOS / RHEL / Rocky / AlmaLinux
- Arch Linux / Manjaro
- Alpine Linux

## 配置文件

配置按优先级加载：**默认 → 系统 → 用户**（后者覆盖前者）。

| 路径 | 说明 |
|------|------|
| `config/config.yaml` | 仓库内置默认值 |
| `/etc/hamster-scripts/config.yaml` | 系统级覆盖 |
| `~/.config/hamster-scripts/config.yaml` | 用户级覆盖 |

```yaml
log_dir: /var/log/hamster-scripts
backup_dir: /var/backups/hamster-scripts
work_dir: /root/cs
install_dir: /cs
```

可在「系统设置」菜单中快捷修改路径类配置。

## 菜单结构

```
主菜单
├── 软件管理
├── 项目管理
├── 系统管理
│   ├── 系统信息 / 更新 / 优化
│   ├── 安全加固 / 时间管理 / 用户管理
│   ├── 进程管理 / 磁盘分析
│   └── 服务管理（列表 / 启停 / 状态）
├── 备份恢复
├── 系统监控
├── 系统设置
├── 更新脚本
└── 退出
```

## 项目审计（2026-06）

### 已修复

| 项 | 说明 |
|----|------|
| 缺失 `config/config.yaml` | 已补全默认配置，避免 `config_load` 仅靠 fallback |
| 函数命名不统一 | 全项目 ~276 个 Bash 函数已改为中文命名 |
| 更新页颜色变量缺失 | `lib/log.sh` 补充 `COLOR_PURPLE/GREEN/RESET` |
| tmux 架构 | 已对齐 xrk-projects-scripts（setup + conf + menu） |

### 已知限制

| 项 | 说明 |
|----|------|
| 路径硬编码 | `tools/*/tool.conf` 与 setup 中仍有 `/cs`、`/root/cs`，建议后续统一走 `获取工作目录` |
| XRK-AGT 启动 | `manage.sh` 前台 `node` 与 `工具_启动` 后台方式不一致 |
| NapCat 安装 | 自定义流程，未走标准 `工具_安装`（zip 分发） |
| Git 更新策略 | `更新_执行` 强制 `reset --hard origin/main`，本地改动会丢失 |
| 未使用函数 | `随机字符串`、`config_save`、`工具_版本比较` 等暂未调用，保留供扩展 |
| 开发脚本 | `scripts/submit-prs-api.sh` 为批量 PR 工具，非运行时组件 |

### 命名约定

- **公开函数**: 中文动词短语，如 `加载配置`、`主菜单`
- **模块前缀**: `包管理_`、`系统_`、`工具_`、`软件包_` 等
- **内部函数**: `_` 前缀，如 `_更新_检查`、`_NapCat_主流程`
- **入口函数**: `程序入口`（`bin/cs`、`setup.sh`）
- **钩子函数**: `工具钩子_安装LinuxQQ`（供 `declare -F` 检测）

## 开发指南

### 模块开发

在 `app/` 下新增菜单模块，遵循现有命名：

```bash
#!/bin/bash

我的模块_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "模块名称" "请选择:" \
            "1" "功能1" \
            "2" "功能2")

        case "$choice" in
            1) 我的模块_功能1 ;;
            2) 我的模块_功能2 ;;
            b|'') break ;;
        esac
    done
}
```

在 `app/menu.sh` 的 `主菜单` 中注册入口即可。

### 工具开发

```
tools/my-tool/
├── tool.conf      # TOOL_NAME、TOOL_REPO、TOOL_DEPS 等
├── install.sh     # 头部调用 工具引导，再 工具_安装 或自定义流程
└── manage.sh      # 工具引导 + 管理菜单
```

自定义依赖 hook 示例（NapCat LinuxQQ）：

```bash
工具钩子_安装LinuxQQ() { ... }
```

框架会在 `工具_安装依赖` 中通过 `declare -F 工具钩子_安装LinuxQQ` 调用。

### 核心 API（中文函数）

#### 初始化

| 函数 | 说明 |
|------|------|
| `初始化核心` | 加载全部库 + 配置 + 日志 + UI |
| `工具引导` | 工具脚本独立运行时的轻量初始化 |
| `加载模块` | 按需加载 `app/*.sh` |

#### 日志

| 函数 | 说明 |
|------|------|
| `写日志` / `日志信息` / `日志成功` / `日志警告` / `日志错误` | 分级输出 |
| `初始化日志` | 创建日志目录与文件 |

#### 界面

| 函数 | 说明 |
|------|------|
| `界面菜单` / `界面子菜单` | 菜单选择 |
| `界面消息` / `界面确认` / `界面输入` | 对话框 |
| `界面信息` / `界面成功` / `界面错误` | 提示框 |

#### 包管理

| 函数 | 说明 |
|------|------|
| `包管理_安装` / `包管理_卸载` / `包管理_搜索` | 系统包 |
| `包管理_确保Node` / `包管理_确保Redis` / `包管理_确保MongoDB` | 依赖检测安装 |

#### 工具框架

| 函数 | 说明 |
|------|------|
| `工具_安装` / `工具_启动` / `工具_停止` / `工具_状态` | 标准生命周期 |
| `工具_加载配置` | 读取 `tools/*/tool.conf` |

#### 配置

| 函数 | 说明 |
|------|------|
| `加载配置` | 三层 YAML 加载 |
| `获取配置` | 读取 `CONFIG` 关联数组 |
| `保存用户配置` | 写入 `~/.config/hamster-scripts/config.yaml` |

完整映射见 `scripts/rename-functions-zh.py`。

### 提交 PR

```bash
git checkout -b fix/my-feature
# ... 修改并 commit ...
bash scripts/push-one-pr.sh fix/my-feature "fix: 描述" "详细说明"
```

## License

MIT
