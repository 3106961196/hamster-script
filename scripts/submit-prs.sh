#!/bin/bash
# 在 gh auth login 完成后运行此脚本，向 3106961196/hamster-script 提交 8 个 PR
set -euo pipefail

UPSTREAM="3106961196/hamster-script"
FORK_OWNER="$(gh api user -q .login)"

echo "==> Fork 仓库（如已有则跳过）"
gh repo fork "$UPSTREAM" --remote=true --remote-name=fork 2>/dev/null || true

declare -A PR_TITLE PR_BODY
PR_TITLE[fix/tool-bootstrap]="fix: add tool_bootstrap for standalone tool scripts"
PR_BODY[fix/tool-bootstrap]="工具 install/manage 脚本在子 shell 中运行时缺少 log/pkg 等库，导致函数未定义。"

PR_TITLE[fix/config-system]="fix: wire config loading and save_user_config"
PR_BODY[fix/config-system]="支持默认/系统/用户三层配置加载；实现 save_user_config；添加 get_install_dir/get_work_dir。"

PR_TITLE[fix/install-paths]="fix: remove hardcoded /cs install paths"
PR_BODY[fix/install-paths]="tmux、cs 包装脚本和项目安装路径改为从 INSTALL_DIR/配置读取。"

PR_TITLE[fix/git-proxy-and-safe-update]="fix: make GitHub proxy opt-in and confirm before hard reset"
PR_BODY[fix/git-proxy-and-safe-update]="Git 代理需 ENABLE_GITHUB_PROXY=1；setup/update 在 hard reset 前检测本地改动并确认。"

PR_TITLE[fix/tool-start-security]="fix: replace eval in tool_start with bash -c"
PR_BODY[fix/tool-start-security]="用 nohup bash -c 替代 eval 启动工具；统一 xrk-agt 安装后启动流程。"

PR_TITLE[fix/cli-and-docs]="feat: add cs update/version/help CLI aliases"
PR_BODY[fix/cli-and-docs]="支持 cs update/version/help，保留 cs r 别名；同步 README 与 setup 提示。"

PR_TITLE[fix/apt-and-security]="fix: apt mirror for Debian and harden dangerous ops"
PR_BODY[fix/apt-and-security]="Debian 使用 debian 镜像路径；用户删除列表排除 root；移除无效时区；iptables 清空前警告。"

PR_TITLE[chore/remove-dev-artifacts]="chore: remove local dev artifacts from repo"
PR_BODY[chore/remove-dev-artifacts]="删除 fix_pick.ps1、reasonix.toml 并加入 .gitignore。"

BRANCHES=(
    fix/tool-bootstrap
    fix/config-system
    fix/install-paths
    fix/git-proxy-and-safe-update
    fix/tool-start-security
    fix/cli-and-docs
    fix/apt-and-security
    chore/remove-dev-artifacts
)

for branch in "${BRANCHES[@]}"; do
    echo ""
    echo "==> 推送 $branch"
    git push -u fork "$branch"

    if gh pr view --repo "$UPSTREAM" --head "${FORK_OWNER}:${branch}" &>/dev/null; then
        echo "PR 已存在: $branch"
        continue
    fi

    echo "==> 创建 PR: $branch"
    gh pr create \
        --repo "$UPSTREAM" \
        --head "${FORK_OWNER}:${branch}" \
        --base main \
        --title "${PR_TITLE[$branch]}" \
        --body "$(cat <<EOF
## Summary
${PR_BODY[$branch]}

## Test plan
- [ ] \`bash -n\` 语法检查相关脚本
- [ ] 在 Linux 环境运行 \`cs\` 验证对应功能
EOF
)"
done

echo ""
echo "全部 PR 已提交。查看: https://github.com/${UPSTREAM}/pulls"
