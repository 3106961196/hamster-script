# Hamster Script

Linux 服务器管理脚本，dialog 菜单界面。

## 安装

任选其一（**GitHub 为主仓库**）：

```bash
# GitHub（主）
bash <(curl -sL https://github.com/3106961196/hamster-script/raw/main/setup.sh)

# Gitee
bash <(curl -sL https://gitee.com/duac/hamster-script/raw/main/setup.sh)

# GitCode
bash <(curl -sL https://gitcode.com/duac/hamster-script/raw/main/setup.sh)
```

| 平台 | 仓库地址 |
|------|----------|
| GitHub（主） | https://github.com/3106961196/hamster-script |
| Gitee | https://gitee.com/duac/hamster-script |
| GitCode | https://gitcode.com/duac/hamster-script |

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
