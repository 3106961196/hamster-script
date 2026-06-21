#!/bin/bash
# NapCat 安装入口（逻辑在 common.sh）

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"
NapCat_加载配置

_show_help() {
    cat <<'EOF'
用法: install.sh [选项]

  --force           强制重装 LinuxQQ 与 NapCat
  --auto-force      版本不匹配时自动重装（默认）
  --no-auto-force   关闭自动强制重装
  -h, --help        显示帮助
EOF
}

main() {
    local force=n auto_force=y
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --force) force=y; shift ;;
            --auto-force) auto_force=y; shift ;;
            --no-auto-force) auto_force=n; shift ;;
            -h|--help) _show_help; exit 0 ;;
            *) _show_help; exit 1 ;;
        esac
    done
    NapCat_执行安装 "$force" "$auto_force"
}

main "$@"
