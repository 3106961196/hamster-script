# Hamster Script

Linux 服务器管理脚本，dialog 菜单界面。

## 安装

任选其一（**GitHub 为主仓库**）。注意：Gitee 默认分支是 `master`；GitCode 的网页 raw 会返回 HTML，需走 API。

```bash
# GitHub（主）
bash <(curl -fsSL https://github.com/3106961196/hamster-script/raw/main/setup.sh)

# Gitee（分支 master）
REPO_URL=https://gitee.com/duac/hamster-script.git REPO_BRANCH=master \
  bash <(curl -fsSL https://gitee.com/duac/hamster-script/raw/master/setup.sh)

# GitCode（API raw）
REPO_URL=https://gitcode.com/duac/hamster-script.git REPO_BRANCH=main \
  bash <(curl -fsSL "https://gitcode.com/api/v5/repos/duac/hamster-script/raw/setup.sh?ref=main")
```

已有 `/cs` 时，也可直接改远程再更新（不必重装）：

```bash
cd /cs
# 例：切到 Gitee
git remote set-url origin https://gitee.com/duac/hamster-script.git
git fetch origin
git checkout -B main origin/master   # Gitee 默认 master，本地常用 main
# 或 GitCode：
# git remote set-url origin https://gitcode.com/duac/hamster-script.git
# git fetch origin && git reset --hard origin/main
cs update
```

| 平台 | 仓库地址 | 一键注意 |
|------|----------|----------|
| GitHub（主） | https://github.com/3106961196/hamster-script | `raw/main` |
| Gitee | https://gitee.com/duac/hamster-script | 分支是 `master` |
| GitCode | https://gitcode.com/duac/hamster-script | 用 API raw，勿用网页 `/raw/` |

## 使用

```bash
cs              # 主菜单
cs update       # 更新（新版本会依次试 GitHub/Gitee/GitCode；全失败会提示检查网络）
nt              # NapCat 管理（多 QQ · 多框架 · WebUI）
nt <QQ>         # 启动已配置 QQ
nt --sync-onebot <QQ>  # 仅同步 onebot（需先停 QQ）
nt --webui-apply       # 合并写入 webui.json（需先停 QQ）
hamster-tmux    # tmux 桌面
```

## License

MIT
