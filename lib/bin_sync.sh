#!/bin/bash

命令同步() {
    local install_dir="${1:-${PROJECT_ROOT:-${HAMSTER_ROOT:-}}}"
    local bin_dir="${HAMSTER_BIN:-/usr/local/bin}"
    local dest src n=0
    local -a missing=()

    declare -A files=(
        ["${bin_dir}/cs"]="${install_dir}/bin/cs"
        ["${bin_dir}/nt"]="${install_dir}/bin/nt"
        ["${bin_dir}/hamster-tmux"]="${install_dir}/config/tmux/tmux.sh"
        ["${bin_dir}/hamster-tmux-setup"]="${install_dir}/config/tmux/setup.sh"
    )

    mkdir -p "$bin_dir" 2>/dev/null || true

    for dest in "${!files[@]}"; do
        src="${files[$dest]}"
        if [[ ! -f "$src" ]]; then
            missing+=("$(basename "$dest")")
            continue
        fi
        rm -f "$dest"
        sed 's/\r$//' "$src" > "$dest" && chmod 755 "$dest" && n=$((n + 1))
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "[hamster] 命令同步跳过（源缺失）: ${missing[*]}" >&2
    fi

    if [[ "$n" -gt 0 ]]; then
        echo "[hamster] 已同步 $n 个命令 → $bin_dir"
        return 0
    fi

    echo "[hamster] 命令同步失败：无可用源文件" >&2
    return 1
}
