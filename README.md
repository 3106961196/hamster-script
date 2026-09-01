# Hamster Script

Linux 服务器管理脚本，dialog 菜单界面。

## 安装

主仓库为 [Gitee](https://gitee.com/duac/hamster-script)。一键安装即可（按区域自动选镜像：`HAMSTER_REGION` 覆盖 → IP → 时区；只有显式 `REPO_URL` 才固定仓库）：

```bash
cd $HOME   # 不要在 /cs 内执行
bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)
```

可选覆盖：

```bash
REPO_URL=https://github.com/3106961196/hamster-script.git \
  bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)

HAMSTER_REGION=cn bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)
```

区域自测：`bash /cs/scripts/region-selftest.sh`（`TZ=` / `HAMSTER_REGION=` 任意机器可验）。

已装过可直接 `cs update`。目录被删后，再跑上面的一键安装即可恢复。

## 使用

```bash
cs              # 主菜单（脚本设置：更新 / 切换更新源）
cs update       # 更新（只查当前配置源：gitee / gitcode / github）
nt              # NapCat 管理（多 QQ · 多框架 · WebUI）
nt <QQ>         # 启动已配置 QQ
nt --sync-onebot <QQ>  # 仅同步 onebot（需先停 QQ）
nt --webui-apply       # 合并写入 webui.json（需先停 QQ）
hamster-tmux    # tmux 桌面
```

## License

MIT
