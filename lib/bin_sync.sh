#!/bin/bash

_命令同步_复制() {
    local dest="$1" src="$2"
    rm -f "$dest"
    sed 's/\r$//' "$src" > "$dest" && chmod 755 "$dest"
}

_命令同步_包装() {
    local dest="$1" script="$2"
    rm -f "$dest"
    printf '#!/bin/bash\nexec bash %q "$@"\n' "$script" > "$dest" && chmod 755 "$dest"
}

命令同步() {
    local install_dir="${1:-${PROJECT_ROOT:-${HAMSTER_ROOT:-}}}"
    local bin_dir="${HAMSTER_BIN:-/usr/local/bin}"
    local name dest src script n=0
    local -a missing=()

    declare -A copy_cmds=( [cs]=bin/cs [nt]=bin/nt )
    declare -A wrap_cmds=( [hamster-tmux]=config/tmux/tmux.sh )

    mkdir -p "$bin_dir" 2>/dev/null || true

    for name in "${!copy_cmds[@]}"; do
        dest="${bin_dir}/${name}"
        src="${install_dir}/${copy_cmds[$name]}"
        if [[ ! -f "$src" ]]; then
            missing+=("$name")
            continue
        fi
        _命令同步_复制 "$dest" "$src" && n=$((n + 1))
    done

    for name in "${!wrap_cmds[@]}"; do
        dest="${bin_dir}/${name}"
        script="${install_dir}/${wrap_cmds[$name]}"
        if [[ ! -f "$script" ]]; then
            missing+=("$name")
            continue
        fi
        _命令同步_包装 "$dest" "$script" && n=$((n + 1))
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
