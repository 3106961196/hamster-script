#!/bin/bash
# bin/cs、bin/nt 共用引导

仓鼠_bin引导() {
    local script_path="$1"

    if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || "$OSTYPE" == "win32" ]]; then
        echo "错误：此脚本需要在 Linux 环境中运行"
        exit 1
    fi

    local _root_lib=""
    for _p in "$(cd "$(dirname "$script_path")" && pwd)/../lib/root.sh" "/cs/lib/root.sh"; do
        [[ -f "$_p" ]] && { _root_lib="$_p"; break; }
    done
    [[ -z "$_root_lib" ]] && { echo "错误：未找到 Hamster 安装目录（/cs）"; exit 1; }

    # shellcheck source=/dev/null
    source "$_root_lib"
    export PROJECT_ROOT="$(仓鼠_安装根 "$script_path")"
    export HAMSTER_ROOT="$PROJECT_ROOT"
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/lib/core.sh"
}
