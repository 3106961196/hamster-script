# 在 gh auth login 完成后运行，向 3106961196/hamster-script 提交 8 个 PR
$ErrorActionPreference = "Stop"
$gh = "${env:ProgramFiles}\GitHub CLI\gh.exe"
if (-not (Test-Path $gh)) { $gh = "gh" }

& $gh auth status | Out-Null

$upstream = "3106961196/hamster-script"
$forkOwner = & $gh api user -q .login

Write-Host "==> Fork 仓库"
& $gh repo fork $upstream --remote=true --remote-name=fork 2>$null

$prs = [ordered]@{
    "fix/tool-bootstrap"              = @{ title = "fix: add tool_bootstrap for standalone tool scripts"; body = "工具 install/manage 脚本在子 shell 中运行时缺少 log/pkg 等库。" }
    "fix/config-system"               = @{ title = "fix: wire config loading and save_user_config"; body = "三层配置加载 + save_user_config + 路径 helper。" }
    "fix/install-paths"               = @{ title = "fix: remove hardcoded /cs install paths"; body = "消除 /cs 硬编码，改用 INSTALL_DIR/配置。" }
    "fix/git-proxy-and-safe-update"   = @{ title = "fix: make GitHub proxy opt-in and confirm before hard reset"; body = "Git 代理可选；更新前确认本地改动。" }
    "fix/tool-start-security"         = @{ title = "fix: replace eval in tool_start with bash -c"; body = "移除 eval，统一工具启动。" }
    "fix/cli-and-docs"                = @{ title = "feat: add cs update/version/help CLI aliases"; body = "CLI 与 README 对齐。" }
    "fix/apt-and-security"            = @{ title = "fix: apt mirror for Debian and harden dangerous ops"; body = "Debian 镜像 + 危险操作加固。" }
    "chore/remove-dev-artifacts"      = @{ title = "chore: remove local dev artifacts from repo"; body = "清理开发临时文件。" }
}

foreach ($branch in $prs.Keys) {
    Write-Host "`n==> 推送 $branch"
    git push -u fork $branch

    $existing = & $gh pr list --repo $upstream --head "${forkOwner}:$branch" --json number -q ".[0].number" 2>$null
    if ($existing) {
        Write-Host "PR 已存在 #$existing"
        continue
    }

    $info = $prs[$branch]
    $body = @"
## Summary
$($info.body)

## Test plan
- [ ] bash -n 语法检查
- [ ] Linux 环境运行 cs 验证
"@
    Write-Host "==> 创建 PR"
    & $gh pr create --repo $upstream --head "${forkOwner}:$branch" --base main --title $info.title --body $body
}

Write-Host "`n完成: https://github.com/$upstream/pulls"
