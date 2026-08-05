#!/bin/bash
# NapCat 公共逻辑（install / manage / nt 共用，路径以 tool.conf 为准）
# OneBot/WebUI/多框架：tools/napcat/security.sh（对齐 xrk napcat_security.sh）

_NapCat_加载配置() {
    [[ -n "${_NAPCAT_CONF_LOADED:-}" ]] && return 0
    local dir
    dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if declare -F _Conf_加载 &>/dev/null; then
        _Conf_加载 "$dir/tool.conf"
    else
        # shellcheck source=/dev/null
        source <(sed 's/\r$//' "$dir/tool.conf")
    fi
    declare -F _工具_规范化Deps &>/dev/null && _工具_规范化Deps
    if declare -F _工具_解析安装目录 &>/dev/null; then
        _工具_解析安装目录 "napcat"
    elif [[ -z "${TOOL_INSTALL_DIR:-}" ]]; then
        local work=""
        declare -F 获取工作目录 &>/dev/null && work="$(获取工作目录 2>/dev/null || true)"
        TOOL_INSTALL_DIR="${work:-/root/cs}/${TOOL_INSTALL_SUBDIR:-NapCat}"
    fi
    QQ_ROOT="${QQ_ROOT:-/opt/QQ}"
    NAPCAT_LAUNCHER="${NAPCAT_LAUNCHER:-${QQ_ROOT}/resources/app/app_launcher}"
    QQ_PACKAGE_JSON="${QQ_PACKAGE_JSON:-${QQ_ROOT}/resources/app/package.json}"
    LOAD_NAPCAT_JS="${LOAD_NAPCAT_JS:-${QQ_ROOT}/resources/app/loadNapCat.js}"
    QQ_BIN="${QQ_BIN:-${QQ_ROOT}/qq}"
    CONFIG_DIR="${TOOL_INSTALL_DIR}/config"
    NAPCAT_CONFIG_DIR="$CONFIG_DIR"
    export QQ_ROOT NAPCAT_LAUNCHER TOOL_INSTALL_DIR CONFIG_DIR NAPCAT_CONFIG_DIR
    export QQ_PACKAGE_JSON LOAD_NAPCAT_JS QQ_BIN
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$dir/security.sh")
    if [[ -z "${NAPCAT_QQ_DIR:-}" ]]; then
        NAPCAT_QQ_DIR="$(napcat_qq_dir)"
    fi
    export NAPCAT_QQ_DIR
    if [[ -z "${NAPCAT_PREFS_FILE:-}" ]]; then
        NAPCAT_PREFS_FILE="$(napcat_prefs_path)"
    fi
    export NAPCAT_PREFS_FILE
    mkdir -p "$NAPCAT_QQ_DIR" 2>/dev/null || true
    _NAPCAT_CONF_LOADED=1
}

NapCat_加载配置() { _NapCat_加载配置; }

NapCat_QQ配置文件() {
    printf '%s/qq_%s.json' "$(napcat_qq_dir)" "$1"
}

NapCat_是否已安装() {
    _NapCat_加载配置
    [[ -f "${TOOL_INSTALL_DIR}/napcat.mjs" ]] \
        && [[ -f "${LOAD_NAPCAT_JS}" ]] \
        && [[ -d "${TOOL_INSTALL_DIR}" ]]
}

NapCat_是否已注入() {
    _NapCat_加载配置
    [[ -f "$QQ_PACKAGE_JSON" ]] \
        && jq -e '.main == "./loadNapCat.js"' "$QQ_PACKAGE_JSON" &>/dev/null
}

NapCat_是否就绪() {
    NapCat_是否已安装 && NapCat_是否已注入
}

NapCat_确保依赖() {
    _NapCat_加载配置
    if type 包管理_确保命令 &>/dev/null; then
        包管理_确保命令 jq jq || return 1
        包管理_确保命令 curl curl 2>/dev/null || true
        command -v xvfb-run &>/dev/null || 包管理_安装 xvfb 2>/dev/null || true
    else
        for pkg in jq curl; do
            command -v "$pkg" &>/dev/null || { echo "缺少 $pkg"; return 1; }
        done
        command -v xvfb-run &>/dev/null || { echo "缺少 xvfb-run"; return 1; }
    fi
}

# [q]q 避免 pgrep 匹配自身命令行（对齐 xrk nt_napcat_running）
NapCat_QQ匹配() {
    echo '[q]q --no-sandbox'
}

# 精确匹配 -q <QQ>，避免 -q 123 误伤 -q 12345
NapCat_QQ进程模式() {
    local qq_num="$1"
    printf '%s -q %s( |$)' "$(NapCat_QQ匹配)" "$qq_num"
}

NapCat_QQ是否运行() {
    local qq_num="$1"
    [[ -n "$qq_num" ]] || return 1
    pgrep -f "$(NapCat_QQ进程模式 "$qq_num")" >/dev/null 2>&1
}

NapCat_是否运行中() {
    pgrep -f "$(NapCat_QQ匹配)" >/dev/null 2>&1
}

NapCat_获取运行中QQ() {
    local pid cmdline
    while IFS= read -r pid; do
        [[ -z "$pid" ]] && continue
        cmdline="$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null || true)"
        # 取 -q 后完整账号，避免短号截断
        if [[ "$cmdline" =~ -q[[:space:]]+([0-9]+) ]]; then
            printf '%s\n' "${BASH_REMATCH[1]}"
        fi
    done < <(pgrep -f "$(NapCat_QQ匹配)" 2>/dev/null) | sort -u
}

NapCat_确保Bot() {
    _NapCat_加载配置
    mkdir -p "$(napcat_qq_dir)"
}

NapCat_保存QQ配置() {
    local qq="$1" links="$2" ob_token="${3:-}" old_qq="${4:-}"
    local qf
    _NapCat_加载配置
    mkdir -p "$(napcat_qq_dir)"
    links="$(napcat_json_or "$links" '[]')"
    qf="$(NapCat_QQ配置文件 "$qq")"
    jq -n --arg qq "$qq" --arg ob "$ob_token" --argjson links "$links" \
        '{qq:$qq,ob_token:$ob,links:$links,console_log:true,file_log:false}' > "$qf" || {
        NAPCAT_LAST_ERR="写入 QQ 配置失败: $qf"
        return 1
    }
    if [[ -n "$old_qq" && "$old_qq" != "$qq" ]]; then
        rm -f "$(NapCat_QQ配置文件 "$old_qq")"
        rm -f "${CONFIG_DIR}/napcat_${old_qq}.json" "${CONFIG_DIR}/onebot11_${old_qq}.json"
    fi
}

NapCat_获取QQ列表() {
    _NapCat_加载配置
    NapCat_确保Bot
    local qq_dir qf
    qq_dir="$(napcat_qq_dir)"
    shopt -s nullglob
    for qf in "${qq_dir}"/qq_*.json; do
        basename "$qf" | sed 's/^qq_//;s/\.json$//'
    done | sort -n
    shopt -u nullglob
}

NapCat_准备运行时() {
    local qq_num="$1"
    local qf
    _NapCat_加载配置
    qf="$(NapCat_QQ配置文件 "$qq_num")"
    [[ -f "$qf" ]] || { NAPCAT_LAST_ERR="无配置: $qf"; return 1; }
    napcat_prepare_runtime "$qq_num" "$qf"
}

NapCat_启动QQ() {
    local qq_num="$1"
    local qf qq_cmd="${QQ_BIN}" line url
    _NapCat_加载配置

    qf="$(NapCat_QQ配置文件 "$qq_num")"
    if [[ ! -f "$qf" ]]; then
        echo "找不到 QQ $qq_num 的配置，请先添加账号" >&2
        return 1
    fi

    if ! NapCat_是否就绪; then
        echo "NapCat 未正确安装，请先运行安装脚本" >&2
        return 1
    fi

    if NapCat_QQ是否运行 "$qq_num"; then
        echo "QQ $qq_num 已在运行。先停止：nt 菜单「停止 QQ」" >&2
        return 1
    fi

    # 其它 QQ 在跑时仍可启动本号；WebUI 可能写失败，prepare 会降级只同步 OneBot
    NapCat_准备运行时 "$qq_num" || {
        echo "启动前同步失败: ${NAPCAT_LAST_ERR:-未知错误}" >&2
        echo "请先停止所有 QQ（修改 WebUI/onebot 需进程已退出），或: nt --sync-onebot $qq_num" >&2
        return 1
    }

    export DISPLAY="${DISPLAY:-:99}"
    command -v qq &>/dev/null && qq_cmd="qq"

    clear 2>/dev/null || true
    killall dialog 2>/dev/null || true
    echo "┌─ NapCat 启动 ─────────────────"
    echo "│ QQ: $qq_num"
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        echo "│ → $line"
    done < <(napcat_format_connection_lines "$qf")
    if url="$(napcat_webui_url 2>/dev/null)"; then
        echo "│ WebUI（全局）: $url"
    else
        echo "│ WebUI: 关闭"
    fi
    echo "└──────────────────────────────"
    exec xvfb-run -a "$qq_cmd" --no-sandbox -q "$qq_num"
}

NapCat_停止QQ() {
    local qq_num="$1"
    [[ -n "$qq_num" ]] || return 1
    if ! NapCat_QQ是否运行 "$qq_num"; then
        return 0
    fi
    pkill -f "$(NapCat_QQ进程模式 "$qq_num")" 2>/dev/null
    sleep 2
    if NapCat_QQ是否运行 "$qq_num"; then
        pkill -9 -f "$(NapCat_QQ进程模式 "$qq_num")" 2>/dev/null
        sleep 1
    fi
    ! NapCat_QQ是否运行 "$qq_num"
}

NapCat_停止全部() {
    pkill -f "$(NapCat_QQ匹配)" 2>/dev/null
    sleep 2
    pkill -9 -f "$(NapCat_QQ匹配)" 2>/dev/null
    sleep 1
}

NapCat_移除QQ() {
    local qq_num="$1"
    _NapCat_加载配置
    [[ -n "$qq_num" ]] || {
        NAPCAT_LAST_ERR="QQ 号为空"
        return 1
    }
    if ! [[ "$qq_num" =~ ^[0-9]{5,15}$ ]]; then
        NAPCAT_LAST_ERR="QQ 号无效: $qq_num"
        return 1
    fi

    if NapCat_QQ是否运行 "$qq_num"; then
        NapCat_停止QQ "$qq_num" 2>/dev/null || true
        if NapCat_QQ是否运行 "$qq_num"; then
            NAPCAT_LAST_ERR="无法停止 QQ ${qq_num}，请先手动停止再删除"
            return 1
        fi
    fi

    rm -f "$(NapCat_QQ配置文件 "$qq_num")"
    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json" \
        "${CONFIG_DIR}/onebot11_${qq_num}.json" \
        "${NAPCAT_CONFIG_DIR}/napcat_${qq_num}.json" \
        "${NAPCAT_CONFIG_DIR}/onebot11_${qq_num}.json"
    return 0
}

NapCat_备份QQ配置() {
    _NapCat_加载配置
    [[ -f "$QQ_PACKAGE_JSON" && ! -f "${QQ_PACKAGE_JSON}.bak" ]] \
        && cp "$QQ_PACKAGE_JSON" "${QQ_PACKAGE_JSON}.bak"
}

NapCat_注入QQ() {
    _NapCat_加载配置
    NapCat_备份QQ配置
    echo "(async () => {await import('file://${TOOL_INSTALL_DIR}/napcat.mjs');})();" > "$LOAD_NAPCAT_JS"
    jq '.main = "./loadNapCat.js"' "$QQ_PACKAGE_JSON" > "${QQ_PACKAGE_JSON}.tmp" \
        && mv "${QQ_PACKAGE_JSON}.tmp" "$QQ_PACKAGE_JSON"
}

NapCat_恢复QQ配置() {
    _NapCat_加载配置
    if [[ -f "${QQ_PACKAGE_JSON}.bak" ]]; then
        cp "${QQ_PACKAGE_JSON}.bak" "$QQ_PACKAGE_JSON"
    elif [[ -f "$QQ_PACKAGE_JSON" ]]; then
        jq --arg main "$QQ_MAIN_ORIGINAL" '.main = $main' "$QQ_PACKAGE_JSON" > "${QQ_PACKAGE_JSON}.tmp" \
            && mv "${QQ_PACKAGE_JSON}.tmp" "$QQ_PACKAGE_JSON"
    fi
}

NapCat_链接QQ命令() {
    _NapCat_加载配置
    [[ -f "$QQ_BIN" ]] && ln -sf "$QQ_BIN" /usr/local/bin/qq
}

NapCat_卸载文件() {
    _NapCat_加载配置
    NapCat_停止全部
    rm -rf "$TOOL_INSTALL_DIR" 2>/dev/null
    rm -f "$LOAD_NAPCAT_JS"
    NapCat_恢复QQ配置
    local qq
    for qq in $(NapCat_获取QQ列表); do
        rm -f "${CONFIG_DIR}/napcat_${qq}.json"
        rm -f "${CONFIG_DIR}/onebot11_${qq}.json"
        rm -f "${NAPCAT_CONFIG_DIR}/napcat_${qq}.json"
        rm -f "${NAPCAT_CONFIG_DIR}/onebot11_${qq}.json"
    done
}

# 仅卸 LinuxQQ 客户端（保留 NapCat 目录与 QQ 绑定）
NapCat_卸载LinuxQQ() {
    _NapCat_加载配置
    local pm
    NapCat_停止全部
    NapCat_恢复QQ配置
    rm -f "$LOAD_NAPCAT_JS" 2>/dev/null || true
    pm=$(包管理_检测AptDnf 2>/dev/null || true)
    if [[ "$pm" == apt-get ]]; then
        apt-get remove -y linuxqq 2>/dev/null || true
    elif [[ "$pm" == dnf ]]; then
        rpm -e linuxqq 2>/dev/null || true
    fi
    日志成功 "LinuxQQ 已卸载（NapCat 目录与账号绑定仍保留）"
}

# 仅更新/重装 NapCat Shell（force=y 强制覆盖）
NapCat_执行仅Shell() {
    local force="${1:-n}" work_dir
    [[ $EUID -ne 0 ]] && { 日志错误 "需要 root 权限"; return 1; }
    _NapCat_加载配置
    work_dir=$(mktemp -d) || { 日志错误 "无法创建临时目录"; return 1; }
    if ! NapCat_下载并解压包 "$work_dir"; then
        rm -rf "$work_dir"
        return 1
    fi
    if ! NapCat_安装Shell "$work_dir" "$force"; then
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$work_dir"
    type 安装_后处理 &>/dev/null && 安装_后处理 "$PROJECT_ROOT" 2>/dev/null || true
    日志成功 "NapCat Shell 完成 → ${TOOL_INSTALL_DIR}"
}

# 仅更新/重装 LinuxQQ（force=y 强制；auto_force=y 版本过旧才升）
NapCat_执行仅LinuxQQ() {
    local force="${1:-n}" auto_force="${2:-y}" work_dir
    [[ $EUID -ne 0 ]] && { 日志错误 "需要 root 权限"; return 1; }
    _NapCat_加载配置
    work_dir=$(mktemp -d) || { 日志错误 "无法创建临时目录"; return 1; }
    if ! NapCat_下载并解压包 "$work_dir"; then
        rm -rf "$work_dir"
        return 1
    fi
    if ! NapCat_安装LinuxQQ "$work_dir" "$force" "$auto_force"; then
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$work_dir"
    NapCat_链接QQ命令 2>/dev/null || true
    if NapCat_是否已安装; then
        NapCat_注入QQ || return 1
    fi
    日志成功 "LinuxQQ 完成 → ${QQ_ROOT}"
}

# ─── 安装流程（install.sh 调用） ─────────────────────────────

NapCat_系统架构() {
    case "$(包管理_检测架构)" in
        x64) echo amd64 ;;
        arm64) echo arm64 ;;
        *) 日志错误 "无法识别的系统架构"; return 1 ;;
    esac
}

NapCat_安装系统依赖() {
    _NapCat_加载配置
    local pm pkg
    # 对齐 xrk NapCat.sh install_dependency：固定 apt 包列表，勿把 linuxqq 当 apt 包
    local -a apt_deps=(zip unzip jq curl xvfb screen xauth procps)
    local -a dnf_deps=(zip unzip jq curl xorg-x11-server-Xvfb screen procps-ng)

    pm=$(包管理_检测AptDnf) || { 日志错误 "仅支持 apt-get/dnf"; return 1; }
    日志信息 "安装 NapCat 系统依赖..."
    日志信息 "更新软件源（完成后会继续安装依赖，请稍候）..."
    包管理_更新源 || 日志警告 "软件源更新失败，尝试继续..."
    if [[ "$pm" == apt-get ]]; then
        for pkg in "${apt_deps[@]}"; do
            包管理_是否已安装 "$pkg" && continue
            日志信息 "安装依赖: $pkg"
            包管理_安装 "$pkg" || 日志警告 "$pkg 安装失败，尝试继续..."
        done
    else
        dnf install -y epel-release 2>/dev/null || true
        for pkg in "${dnf_deps[@]}"; do
            包管理_是否已安装 "$pkg" && continue
            日志信息 "安装依赖: $pkg"
            包管理_安装 "$pkg" || 日志警告 "$pkg 安装失败，尝试继续..."
        done
    fi
}

# 解压到指定临时目录（勿用 stdout 回传路径，避免日志污染 $()）
NapCat_下载并解压包() {
    _NapCat_加载配置
    local work_dir="${1:?NapCat_下载并解压包 需要 work_dir}"
    local zip_file="${work_dir}/NapCat.Shell.zip"
    local url="${NAPCAT_ZIP_URL}"

    mkdir -p "${work_dir}/NapCat"
    if [[ ! -f "$zip_file" ]]; then
        日志信息 "下载 NapCat 安装包（GitHub，国内自动走加速镜像）..."
        日志信息 "→ ${url}"
        网络_下载 "$url" "$zip_file" 3 || return 1
    else
        日志信息 "使用已缓存的 NapCat.Shell.zip"
    fi
    unzip -t "$zip_file" >/dev/null 2>&1 || { 日志错误 "安装包校验失败"; return 1; }
    unzip -q -o -d "${work_dir}/NapCat" "$zip_file" || { 日志错误 "解压失败"; return 1; }
    return 0
}

# 支持 4.7.43 / 3.2.19-39038 / 1:3.2.19-39038（先比 X.Y.Z，再比 build）
NapCat_比较版本() {
    local a="$1" b="$2"
    local a_base b_base a_build=0 b_build=0 rc

    a="${a##*:}"
    b="${b##*:}"
    a="${a//[$'\r\n']/}"
    b="${b//[$'\r\n']/}"
    [[ -n "$a" && -n "$b" ]] || { echo older; return 0; }

    a_base="${a%%-*}"
    b_base="${b%%-*}"
    if [[ "$a" == *-* ]]; then
        a_build="${a#*-}"
        a_build="${a_build%%[^0-9]*}"
        [[ "$a_build" =~ ^[0-9]+$ ]] || a_build=0
    fi
    if [[ "$b" == *-* ]]; then
        b_build="${b#*-}"
        b_build="${b_build%%[^0-9]*}"
        [[ "$b_build" =~ ^[0-9]+$ ]] || b_build=0
    fi

    工具_版本比较 "$a_base" "$b_base"
    rc=$?
    case $rc in
        1) echo newer; return 0 ;;
        2) echo older; return 0 ;;
    esac

    if (( a_build > b_build )); then
        echo newer
    elif (( a_build < b_build )); then
        echo older
    else
        echo equal
    fi
}

NapCat_更新QQ用户配置() {
    local ver="$1" build="$2" conf
    local confs
    confs=$(find /home -name "config.json" -path "*/.config/QQ/versions/*" 2>/dev/null)
    [[ -f /root/.config/QQ/versions/config.json ]] && confs="/root/.config/QQ/versions/config.json ${confs}"
    for conf in $confs; do
        jq --arg targetVer "$ver" --arg buildId "$build" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' \
            "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf" || return 1
    done
}

NapCat_安装LinuxQQ() {
    _NapCat_加载配置
    local work_dir="$1" force="${2:-n}" auto_force="${3:-y}"
    local pm arch ver hash build installed

    ver=$(jq -r '.linuxVersion' "${work_dir}/NapCat/qqnt.json")
    hash=$(jq -r '.linuxVerHash' "${work_dir}/NapCat/qqnt.json")
    ver="${ver##*:}"
    build=${ver##*-}
    [[ -z "$ver" || "$ver" == null || -z "$hash" || "$hash" == null ]] && { 日志错误 "无法读取 QQ 目标版本"; return 1; }

    pm=$(包管理_检测AptDnf) || return 1
    arch=$(NapCat_系统架构) || return 1

    # --force：始终重装；--auto-force（默认）：仅版本过旧时重装；--no-auto-force：过旧则跳过
    if [[ "$force" == y ]]; then
        NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
        return
    fi

    if ! 包管理_LinuxQQ已安装; then
        NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
        return
    fi

    installed=$(包管理_获取版本 linuxqq 2>/dev/null || true)
    if [[ -z "$installed" || "$installed" == "未知" ]]; then
        NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
        return
    fi

    if [[ "$(NapCat_比较版本 "$installed" "$ver")" == older ]]; then
        if [[ "$auto_force" == y ]]; then
            日志信息 "LinuxQQ 版本过旧: $installed < $ver，自动重装"
            NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
        else
            日志警告 "LinuxQQ 版本过旧: $installed < $ver（已跳过重装；需要升级请加 --force）"
            NapCat_更新QQ用户配置 "$ver" "$build" || true
        fi
    else
        日志信息 "LinuxQQ 版本已满足: $installed（目标 $ver）"
        NapCat_更新QQ用户配置 "$ver" "$build"
    fi
}

# 拉取 GitHub API（国内自动走加速代理）
_NapCat_拉取GitHubAPI() {
    local url="$1" body proxy=""
    body=$(curl -fsSL --connect-timeout 10 --max-time 30 -H "User-Agent: hamster-napcat" "$url" 2>/dev/null) || true
    [[ -n "$body" ]] && { printf '%s' "$body"; return 0; }
    if type _挑选GitHub代理 &>/dev/null; then
        proxy="$(_挑选GitHub代理 2>/dev/null)" || true
    fi
    if [[ -n "$proxy" && "$proxy" != "https://gitclone.com/github.com" ]]; then
        body=$(curl -fsSL --connect-timeout 10 --max-time 30 -H "User-Agent: hamster-napcat" \
            "$(_代理化GitHub地址 "$proxy" "$url")" 2>/dev/null) || true
        [[ -n "$body" ]] && { printf '%s' "$body"; return 0; }
    fi
    return 1
}

# 按 NapCat 最低版本从 zydou/QQ-Linux 解析可用包（腾讯 CDN 旧包已 404）
# 优先同主版本 X.Y.Z，否则取更新的发行版；结果写入全局 napcat_qq_url
NapCat_解析LinuxQQ下载地址() {
    local ver="$1" pm="$2" arch="$3"
    local required_base selected_tag tag tag_base pkg_ext json
    local -a tags=()

    napcat_qq_url=""
    required_base="${ver%%-*}"
    case "$pm" in
        apt-get) pkg_ext="deb" ;;
        dnf|yum) pkg_ext="rpm" ;;
        *) return 1 ;;
    esac
    case "$arch" in
        amd64|arm64) ;;
        *) return 1 ;;
    esac

    日志信息 "正在从镜像源解析 LinuxQQ 版本（最低 ${ver}）..."
    json="$(_NapCat_拉取GitHubAPI "https://api.github.com/repos/zydou/QQ-Linux/releases?per_page=50")" || {
        日志错误 "无法获取 QQ 镜像版本列表"
        return 1
    }

    mapfile -t tags < <(printf '%s' "$json" | jq -r '.[].tag_name | select(test("^[0-9]+\\.[0-9]+\\.[0-9]+-[0-9]+$"))')
    [[ ${#tags[@]} -eq 0 ]] && { 日志错误 "镜像源未返回有效版本标签"; return 1; }

    for tag in "${tags[@]}"; do
        tag_base="${tag%%-*}"
        if [[ "$tag_base" == "$required_base" ]]; then
            selected_tag="$tag"
            break
        fi
    done

    if [[ -z "${selected_tag:-}" ]]; then
        for tag in "${tags[@]}"; do
            tag_base="${tag%%-*}"
            case "$(NapCat_比较版本 "$tag_base" "$required_base")" in
                equal|newer)
                    selected_tag="$tag"
                    break
                    ;;
            esac
        done
    fi

    [[ -z "${selected_tag:-}" ]] && { 日志错误 "未找到满足最低版本 ${required_base} 的镜像包"; return 1; }

    日志信息 "已选择镜像版本: ${selected_tag}"
    napcat_qq_url="https://github.com/zydou/QQ-Linux/releases/download/${selected_tag}/QQ-${selected_tag}-${arch}.${pkg_ext}"
}

NapCat_安装LinuxQQ包() {
    local work_dir="$1" ver="$2" hash="$3" build="$4" pm="$5" arch="$6"
    local url pkg_file installed installed_build keep_pkg=0
    local script_dir="${TOOL_SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}"
    local local_deb="${script_dir}/QQ.deb" local_rpm="${script_dir}/QQ.rpm"

    日志信息 "卸载旧版 LinuxQQ（如有）..."
    if [[ "$pm" == apt-get ]]; then
        apt-get remove -y linuxqq 2>/dev/null || true
    else
        rpm -e linuxqq 2>/dev/null || true
    fi

    # 本地包保留复用；在线下载落到 work_dir，装完再删
    if [[ "$pm" == apt-get ]]; then
        if [[ -f "$local_deb" ]]; then
            pkg_file="$local_deb"
            keep_pkg=1
        else
            pkg_file="${work_dir}/QQ.deb"
        fi
    else
        if [[ -f "$local_rpm" ]]; then
            pkg_file="$local_rpm"
            keep_pkg=1
        else
            pkg_file="${work_dir}/QQ.rpm"
        fi
    fi

    if [[ "$keep_pkg" -eq 1 ]]; then
        日志信息 "使用本地 QQ 安装包: ${pkg_file}"
    else
        NapCat_解析LinuxQQ下载地址 "$ver" "$pm" "$arch" || return 1
        url="$napcat_qq_url"
        日志信息 "QQ 下载: ${url}"
        日志信息 "下载 LinuxQQ（包较大，请耐心等待）..."
        网络_下载 "$url" "$pkg_file" 3 || return 1
    fi

    if [[ "$pm" == apt-get ]]; then
        日志信息 "安装 LinuxQQ deb 包..."
        apt-get install -f -y "$pkg_file" || return 1
        apt-get install -y libnss3 libgbm1 2>/dev/null || true
        apt-get install -y libasound2 2>/dev/null || apt-get install -y libasound2t64 2>/dev/null || return 1
    else
        dnf localinstall -y "$pkg_file" || return 1
    fi
    [[ "$keep_pkg" -eq 0 ]] && rm -f "$pkg_file"

    installed=$(包管理_获取版本 linuxqq 2>/dev/null || echo "$ver")
    [[ "$installed" == "未知" ]] && installed="$ver"
    installed="${installed##*:}"
    installed_build=${installed##*-}
    NapCat_链接QQ命令
    NapCat_更新QQ用户配置 "$installed" "$installed_build"
    日志成功 "LinuxQQ 安装完成"
}

NapCat_安装Shell() {
    _NapCat_加载配置
    local work_dir="$1" force="${2:-n}"
    local target_ver installed

    target_ver=$(jq -r '.version' "${work_dir}/NapCat/package.json")
    [[ -z "$target_ver" || "$target_ver" == null ]] && { 日志错误 "无法读取 NapCat 版本"; return 1; }

    if [[ "$force" != y && -f "${TOOL_INSTALL_DIR}/package.json" ]]; then
        installed=$(jq -r '.version' "${TOOL_INSTALL_DIR}/package.json")
        case "$(NapCat_比较版本 "$installed" "$target_ver")" in
            older) ;;
            *) 日志信息 "NapCat 已是最新: v${installed}"; NapCat_注入QQ || return 1; return 0 ;;
        esac
    fi

    for dir in "${QQ_ROOT}" "${QQ_ROOT}/resources" "${QQ_ROOT}/resources/app"; do
        [[ -d "$dir" ]] || { 日志错误 "QQ 未正确安装，缺少 $dir"; return 1; }
    done

    mkdir -p "$(dirname "$LOAD_NAPCAT_JS")" "${TOOL_INSTALL_DIR}/config"
    cp -rf "${work_dir}/NapCat/"* "${TOOL_INSTALL_DIR}/" || return 1
    chmod -R 777 "${TOOL_INSTALL_DIR}/"
    NapCat_注入QQ || return 1
    日志成功 "NapCat 已安装到 ${TOOL_INSTALL_DIR}"
}

NapCat_执行安装() {
    local force="${1:-n}" auto_force="${2:-y}" work_dir

    [[ $EUID -ne 0 ]] && { 日志错误 "NapCat 安装需要 root 权限"; return 1; }

    NapCat_安装系统依赖 || return 1
    work_dir=$(mktemp -d) || { 日志错误 "无法创建临时目录"; return 1; }
    if ! NapCat_下载并解压包 "$work_dir"; then
        rm -rf "$work_dir"
        return 1
    fi
    if ! NapCat_安装LinuxQQ "$work_dir" "$force" "$auto_force"; then
        rm -rf "$work_dir"
        return 1
    fi
    if ! NapCat_安装Shell "$work_dir" "$force"; then
        rm -rf "$work_dir"
        return 1
    fi
    rm -rf "$work_dir"

    NapCat_链接QQ命令 2>/dev/null || true
    type 安装_后处理 &>/dev/null && 安装_后处理 "$PROJECT_ROOT" 2>/dev/null || true

    mkdir -p "$(napcat_qq_dir)" 2>/dev/null || true
    napcat_refresh_frameworks >/dev/null 2>&1 || true
    if ! NapCat_是否运行中; then
        napcat_apply_webui 2>/dev/null || true
    fi

    日志成功 "NapCat 安装完成"
    日志信息 "NapCat: ${TOOL_INSTALL_DIR}"
    日志信息 "LinuxQQ: ${QQ_ROOT}"
    日志信息 "WEBUI: $(napcat_webui_file) （默认 http://127.0.0.1:4071/webui）"
    日志信息 "QQ 绑定: $(napcat_qq_dir)/qq_<QQ>.json"
    日志信息 "启动: nt <QQ号>   管理: nt"
    return 0
}

