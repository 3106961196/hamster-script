#!/bin/bash
# tmux 安装/配置共用逻辑（setup.sh、tmux.sh 引用）

Tmux_引导() {
    local script="${1:-${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}}"
    local root_lib dir

    if [[ -n "${HAMSTER_ROOT:-}" && -f "${HAMSTER_ROOT}/lib/root.sh" ]]; then
        root_lib="${HAMSTER_ROOT}/lib/root.sh"
    elif dir="$(cd "$(dirname "$script")" 2>/dev/null && pwd)" && [[ -f "$dir/../../lib/root.sh" ]]; then
        root_lib="$(cd "$dir/../.." && pwd)/lib/root.sh"
    elif [[ -f /cs/lib/root.sh ]]; then
        root_lib="/cs/lib/root.sh"
    fi

    [[ -n "$root_lib" ]] || { echo "错误：未找到 Hamster 安装目录" >&2; return 1; }

    # shellcheck source=/dev/null
    source "$root_lib"
    INSTALL_DIR="$(仓鼠_安装根 "$script")"
    export HAMSTER_ROOT="$INSTALL_DIR"
    WORK_DIR="$(仓鼠_工作目录 "$INSTALL_DIR")"
    export WORK_DIR
}

Tmux_用户主目录() {
    local dir="${HOME:-}" install_dir="${INSTALL_DIR:-${HAMSTER_ROOT:-/cs}}"

    _Tmux_尝试主目录() {
        local candidate="$1" probe
        [[ -n "$candidate" ]] || return 1
        mkdir -p "${candidate}/.tmux" 2>/dev/null || return 1
        [[ -d "$candidate" && -w "$candidate" ]] || return 1
        probe="${candidate}/.tmux/.hamster-write-test"
        echo test >"$probe" 2>/dev/null || return 1
        rm -f "$probe"
        return 0
    }

    if _Tmux_尝试主目录 "$dir"; then
        echo "$dir"
        return 0
    fi

    dir=$(getent passwd "$(id -un 2>/dev/null || echo root)" 2>/dev/null | cut -d: -f6)
    if _Tmux_尝试主目录 "$dir"; then
        echo "$dir"
        return 0
    fi

    dir="${install_dir}/.tmux-home"
    if _Tmux_尝试主目录 "$dir"; then
        echo "$dir"
        return 0
    fi

    echo "[hamster-tmux] 无法创建配置目录（HOME 不可写，已尝试 ${install_dir}/.tmux-home）" >&2
    return 1
}

Tmux_清理旧配置() {
    local home
    home=$(Tmux_用户主目录 2>/dev/null || echo "${HOME:-}")
    [[ -n "$home" ]] || return 0
    rm -rf "${home}/.tmux/plugins" "${home}/.tmux/resurrect" 2>/dev/null || true
    rm -f "${home}/.tmux/hamster-mouse.conf" "${home}/.tmux/hamster-menu" 2>/dev/null || true
}

Tmux_链接配置() {
    local install_dir="${1:-${INSTALL_DIR:-${HAMSTER_ROOT:-}}}"
    local home tmux_main_conf menus_tpl menus_out entry menu_cmd reload_cmd

    [[ -n "$install_dir" ]] || {
        echo "[hamster-tmux] 缺少安装目录" >&2
        return 1
    }

    home=$(Tmux_用户主目录) || return 1
    tmux_main_conf="${install_dir}/config/tmux/tmux.conf"
    menus_tpl="${install_dir}/config/tmux/tmux-menus.conf"
    entry="${home}/.tmux/main.conf"
    menus_out="${home}/.tmux/hamster-menus.conf"
    menu_cmd="bash ${install_dir}/config/tmux/tmux-menu.sh"
    reload_cmd="source-file ${entry} \\; display \"配置已重载\""

    [[ -f "$tmux_main_conf" && -f "$menus_tpl" ]] || {
        echo "[hamster-tmux] 缺少 config/tmux/tmux.conf 或 tmux-menus.conf" >&2
        return 1
    }

    sed -e "s|@HAMSTER_MENU@|${menu_cmd}|g" \
        -e "s|@HAMSTER_RELOAD@|${reload_cmd}|g" \
        "$menus_tpl" > "$menus_out"
    {
        echo "# Hamster Script tmux（hamster-tmux --setup 生成）"
        sed "s|@HAMSTER_RELOAD@|${reload_cmd}|g" "$tmux_main_conf"
        echo ""
        echo "source-file ${menus_out}"
    } > "$entry"

    ln -sf "$entry" "${home}/.tmux.conf" 2>/dev/null || true
    export HAMSTER_TMUX_CONF="$entry"
    echo "[hamster-tmux] 已写入 $entry"
}

Tmux_安装包() {
    if command -v tmux &>/dev/null; then
        echo "[hamster-tmux] 已安装: $(tmux -V)"
        return 0
    fi

    echo "[hamster-tmux] 安装 tmux…"
    if command -v apt-get &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt-get update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt-get install -y -qq tmux
    elif command -v apt &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt update -qq 2>/dev/null || true
        DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a apt install -y -qq tmux
    elif command -v dnf &>/dev/null; then
        dnf install -y -q tmux
    elif command -v yum &>/dev/null; then
        yum install -y -q tmux
    else
        echo "[hamster-tmux] 请手动安装 tmux（仅自动支持 apt/dnf/yum）" >&2
        return 1
    fi

    command -v tmux &>/dev/null || {
        echo "[hamster-tmux] tmux 安装失败" >&2
        return 1
    }
    echo "[hamster-tmux] 已安装: $(tmux -V)"
}

Tmux_配置就绪() {
    local home="${1:-$(Tmux_用户主目录 2>/dev/null || true)}"
    [[ -n "$home" ]] \
        && [[ -f "${home}/.tmux/main.conf" ]] \
        && grep -q 'Hamster Script tmux' "${home}/.tmux/main.conf" \
        && [[ -f "${home}/.tmux/hamster-menus.conf" ]] \
        && grep -q 'MouseDown3StatusLeft' "${home}/.tmux/hamster-menus.conf" 2>/dev/null
}

Tmux_确保UTF8() {
    case "${LANG:-}" in
        *UTF-8*|*utf8*) return 0 ;;
    esac
    if locale -a 2>/dev/null | grep -qiE 'c\.utf-?8'; then
        export LANG=C.UTF-8 LC_ALL=C.UTF-8
    elif locale -a 2>/dev/null | grep -qi 'zh_cn.utf-8'; then
        export LANG=zh_CN.UTF-8 LC_ALL=zh_CN.UTF-8
    fi
}
