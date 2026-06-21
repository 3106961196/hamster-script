#!/bin/bash
# 工具脚本加载（需先 source lib/core.sh 并 工具引导）

工具_加载() {
    local script_path="$1"
    local tool_dir tool_name

    tool_dir="$(cd "$(dirname "$script_path")" && pwd)"
    tool_name="$(basename "$tool_dir")"
    if [[ -f "$tool_dir/tool.conf" ]]; then
        if declare -F _Conf_加载 &>/dev/null; then
            _Conf_加载 "$tool_dir/tool.conf"
        else
            # shellcheck source=/dev/null
            source <(sed 's/\r$//' "$tool_dir/tool.conf")
        fi
        declare -F _工具_规范化Deps &>/dev/null && _工具_规范化Deps
        declare -F _工具_解析安装目录 &>/dev/null && _工具_解析安装目录 "$tool_name"
    fi
    if [[ -f "$tool_dir/common.sh" ]]; then
        # shellcheck source=/dev/null
        source "$tool_dir/common.sh"
    fi

    TOOL_SCRIPT_DIR="$tool_dir"
    export TOOL_SCRIPT_DIR
}
