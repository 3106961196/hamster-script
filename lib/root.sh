#!/bin/bash

仓鼠_安装根() {
    local script_path="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
    local script_dir install_dir

    if [[ -n "$script_path" ]]; then
        script_dir="$(cd "$(dirname "$script_path")" 2>/dev/null && pwd)" || script_dir=""
        if [[ -n "$script_dir" && -f "$script_dir/../lib/core.sh" ]]; then
            cd "$script_dir/.." && pwd
            return 0
        fi
    fi

    if [[ -n "${HAMSTER_ROOT:-}" && -f "${HAMSTER_ROOT}/lib/core.sh" ]]; then
        echo "$HAMSTER_ROOT"
        return 0
    fi

    if [[ -f /etc/hamster-scripts/config.yaml ]]; then
        install_dir=$(grep -E '^[[:space:]]*install_dir:' /etc/hamster-scripts/config.yaml 2>/dev/null | head -1 | sed -E 's/^[^:]*:[[:space:]]*//; s/^["'\'' ]+//; s/["'\'' ]+$//')
        if [[ -n "$install_dir" && -f "$install_dir/lib/core.sh" ]]; then
            echo "$install_dir"
            return 0
        fi
    fi

    if [[ -f /cs/lib/core.sh ]]; then
        echo "/cs"
        return 0
    fi

    echo "${INSTALL_DIR:-/cs}"
}
