# Hamster Script

Linux 服务器管理脚本，dialog 菜单界面。

## 安装

默认仓库为 [GitHub](https://github.com/3106961196/hamster-script)。国内优先用 Gitee；GitCode 建议先下载再执行（勿直接 `bash <(curl …)`）。

**GitHub（默认）**

```bash
cd $HOME   # 不要在 /cs 内执行
bash <(curl -fsSL https://raw.githubusercontent.com/3106961196/hamster-script/main/setup.sh)
```

**Gitee（国内推荐）**

```bash
cd $HOME
bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)
```

**GitCode（先下载再装）**

```bash
cd $HOME
curl -fsSL -o setup.sh https://gitcode.com/duac/hamster-script/raw/main/setup.sh
bash setup.sh
rm -f setup.sh
```

已装过可直接 `cs update`。目录被删后，再跑上面的一键安装即可恢复。

## 使用

```bash
cs                     # 主菜单（脚本设置：更新 / 切换更新源）
cs r                   # 更新（只查当前配置源：gitee / gitcode / github）
nt                     # NapCat 管理（多 QQ · 多框架 · WebUI）
nt <QQ>                # 启动已配置 QQ
nt --sync-onebot <QQ>  # 仅同步 onebot（需先停 QQ）
nt --webui-apply       # 合并写入 webui.json（需先停 QQ）
hamster-tmux           # tmux 桌面
```

## License

MIT
