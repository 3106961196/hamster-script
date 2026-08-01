# Hamster Script

Linux 服务器管理脚本，dialog 菜单界面。

## 拉取代码

任选其一（浅克隆；**GitHub 为主仓库**）：

```bash
# GitHub（主）
git clone --depth=1 https://github.com/3106961196/hamster-script.git

# Gitee
git clone --depth=1 https://gitee.com/duac/hamster-script.git

# GitCode
git clone --depth=1 https://gitcode.com/duac/hamster-script.git
```

| 平台 | 仓库地址 |
|------|----------|
| GitHub（主） | https://github.com/3106961196/hamster-script |
| Gitee | https://gitee.com/duac/hamster-script |
| GitCode | https://gitcode.com/duac/hamster-script |

## 安装

一键（GitHub raw）：

```bash
bash <(curl -sL https://github.com/3106961196/hamster-script/raw/main/setup.sh)
```

或 clone 后本地安装：

```bash
cd hamster-script
sudo ./setup.sh
```

## 使用

```bash
cs              # 主菜单
cs update       # 更新
nt              # NapCat 管理（多 QQ · 多框架 · WebUI）
nt <QQ>         # 启动已配置 QQ
nt --sync-onebot <QQ>  # 仅同步 onebot（需先停 QQ）
nt --webui-apply       # 合并写入 webui.json（需先停 QQ）
hamster-tmux    # tmux 桌面
```

## License

MIT
