#!/bin/bash
# NapCat 公共逻辑（install / manage / nt 共用，路径以 tool.conf 为准）

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
    _NAPCAT_CONF_LOADED=1
}

NapCat_加载配置() { _NapCat_加载配置; }

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

NapCat_QQ匹配() {
    echo "qq --no-sandbox"
}

NapCat_QQ是否运行() {
    local qq_num="$1"
    pgrep -f "$(NapCat_QQ匹配) -q ${qq_num}" >/dev/null 2>&1
}

NapCat_是否运行中() {
    pgrep -f "$(NapCat_QQ匹配)" >/dev/null 2>&1
}

NapCat_获取运行中QQ() {
    pgrep -f "$(NapCat_QQ匹配)" 2>/dev/null | while read -r pid; do
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null \
            | grep -oP '\-q \K[0-9]+' 2>/dev/null
    done | sort -u
}

NapCat_确保Bot() {
    _NapCat_加载配置
    if [[ ! -f "$NAPCATBOT_FILE" ]]; then
        mkdir -p "$(dirname "$NAPCATBOT_FILE")"
        echo '[]' > "$NAPCATBOT_FILE"
    fi
}

NapCat_添加或更新QQ() {
    local qq_num="$1"
    local port="$2"
    _NapCat_加载配置
    NapCat_确保Bot

    local tmp="${NAPCATBOT_FILE}.tmp"
    jq --arg qq "$qq_num" --argjson port "$port" \
        'if any(.[]; .qq == $qq) then
            map(if .qq == $qq then .port = $port else . end)
        else
            . + [{"qq": $qq, "port": $port}]
        end' \
        "$NAPCATBOT_FILE" > "$tmp" || { rm -f "$tmp"; return 1; }
    mv "$tmp" "$NAPCATBOT_FILE"
}

NapCat_获取QQ列表() {
    _NapCat_加载配置
    [[ -f "$NAPCATBOT_FILE" ]] && jq -r '.[].qq' "$NAPCATBOT_FILE" 2>/dev/null
}

NapCat_获取QQ端口() {
    local qq_num="$1"
    _NapCat_加载配置
    [[ -f "$NAPCATBOT_FILE" ]] && \
        jq -r --arg qq "$qq_num" '.[] | select(.qq == $qq) | .port' "$NAPCATBOT_FILE" 2>/dev/null
}

NapCat_生成配置() {
    local qq_num="$1"
    local port="$2"
    _NapCat_加载配置
    mkdir -p "$CONFIG_DIR"

    cat > "${CONFIG_DIR}/napcat_${qq_num}.json" << EOF
{
    "fileLog": false,
    "consoleLog": true,
    "fileLogLevel": "debug",
    "consoleLogLevel": "info",
    "packetBackend": "auto",
    "packetServer": ""
}
EOF

    local reverse_ws_url="ws://127.0.0.1:${port}/OneBotv11"
    cat > "${CONFIG_DIR}/onebot11_${qq_num}.json" << EOF
{
  "network": {
    "httpServers": [
      {
        "name": "http-server",
        "enable": false,
        "port": 3000,
        "host": "",
        "enableCors": true,
        "enableWebsocket": true,
        "messagePostFormat": "array",
        "token": "",
        "debug": false
      }
    ],
    "httpClients": [],
    "websocketServers": [
      {
        "name": "websocket-server",
        "enable": false,
        "host": "",
        "port": 3001,
        "messagePostFormat": "array",
        "reportSelfMessage": true,
        "token": "",
        "enableForcePushEvent": true,
        "debug": false,
        "heartInterval": 30000
      }
    ],
    "websocketClients": [
      {
        "name": "websocket-client",
        "enable": true,
        "url": "${reverse_ws_url}",
        "messagePostFormat": "array",
        "reportSelfMessage": true,
        "reconnectInterval": 5000,
        "token": "",
        "debug": false,
        "heartInterval": 30000
      }
    ]
  },
  "musicSignUrl": "",
  "enableLocalFile2Url": true
}
EOF
}

NapCat_启动QQ() {
    local qq_num="$1"
    _NapCat_加载配置

    if [[ ! -f "$NAPCATBOT_FILE" ]] \
        || ! jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        echo "找不到 QQ $qq_num 的配置，请先添加账号" >&2
        return 1
    fi

    local port qq_cmd="${QQ_BIN}"
    port=$(NapCat_获取QQ端口 "$qq_num")
    [[ -z "$port" ]] && port="$NAPCAT_DEFAULT_PORT"

    if ! NapCat_是否就绪; then
        echo "NapCat 未正确安装，请先运行安装脚本" >&2
        return 1
    fi

    NapCat_生成配置 "$qq_num" "$port"
    export DISPLAY="${DISPLAY:-:99}"
    command -v qq &>/dev/null && qq_cmd="qq"

    clear 2>/dev/null || true
    killall dialog 2>/dev/null || true
    echo "正在启动 QQ $qq_num（端口: $port）..."
    exec xvfb-run -a "$qq_cmd" --no-sandbox -q "$qq_num"
}

NapCat_停止QQ() {
    local qq_num="$1"
    if ! NapCat_QQ是否运行 "$qq_num"; then
        return 0
    fi
    pkill -f "$(NapCat_QQ匹配) -q ${qq_num}" 2>/dev/null
    sleep 2
    if NapCat_QQ是否运行 "$qq_num"; then
        pkill -9 -f "$(NapCat_QQ匹配) -q ${qq_num}" 2>/dev/null
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
    NapCat_停止QQ "$qq_num" 2>/dev/null || true

    if [[ -f "$NAPCATBOT_FILE" ]]; then
        local tmp="${NAPCATBOT_FILE}.tmp"
        jq --arg qq "$qq_num" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "$tmp" \
            || { rm -f "$tmp"; return 1; }
        mv "$tmp" "$NAPCATBOT_FILE"
    fi

    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json"
    rm -f "${CONFIG_DIR}/onebot11_${qq_num}.json"
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
    done
    rm -f "$NAPCATBOT_FILE" 2>/dev/null
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

NapCat_下载并解压包() {
    _NapCat_加载配置
    local work_dir="${1:-$(mktemp -d)}"
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
    echo "$work_dir"
}

NapCat_比较版本() {
    local a="$1" b="$2"
    工具_版本比较 "$a" "$b"
    case $? in
        0) echo equal ;;
        1) echo newer ;;
        2) echo older ;;
    esac
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
    local pm arch ver hash build base url pkg_file

    ver=$(jq -r '.linuxVersion' "${work_dir}/NapCat/qqnt.json")
    hash=$(jq -r '.linuxVerHash' "${work_dir}/NapCat/qqnt.json")
    build=${ver##*-}
    [[ -z "$ver" || "$ver" == null || -z "$hash" || "$hash" == null ]] && { 日志错误 "无法读取 QQ 目标版本"; return 1; }

    pm=$(包管理_检测AptDnf) || return 1
    arch=$(NapCat_系统架构) || return 1
    [[ "$auto_force" == y ]] && force=y
    [[ "$force" == y ]] && { NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"; return; }

    if 包管理_LinuxQQ已安装; then
        local installed
        installed=$(包管理_获取版本 linuxqq 2>/dev/null || true)
        if [[ "$(NapCat_比较版本 "$installed" "$ver")" == older ]]; then
            NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
        else
            日志信息 "LinuxQQ 版本已满足: $installed"
            NapCat_更新QQ用户配置 "$ver" "$build"
        fi
    else
        NapCat_安装LinuxQQ包 "$work_dir" "$ver" "$hash" "$build" "$pm" "$arch"
    fi
}

NapCat_安装LinuxQQ包() {
    local work_dir="$1" ver="$2" hash="$3" build="$4" pm="$5" arch="$6"
    local base url pkg_file script_dir="${TOOL_SCRIPT_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

    日志信息 "卸载旧版 LinuxQQ（如有）..."
    if [[ "$pm" == apt-get ]]; then
        apt-get remove -y linuxqq 2>/dev/null || true
    else
        rpm -e linuxqq 2>/dev/null || true
    fi

    base="https://dldir1.qq.com/qqfile/qq/QQNT/${hash}/linuxqq_${ver}"
    if [[ "$arch" == amd64 ]]; then
        [[ "$pm" == apt-get ]] && url="${base}_amd64.deb" || url="${base}_x86_64.rpm"
    else
        [[ "$pm" == apt-get ]] && url="${base}_arm64.deb" || url="${base}_aarch64.rpm"
    fi

    if [[ "$pm" == apt-get ]]; then
        pkg_file="${script_dir}/QQ.deb"
        日志信息 "QQ 下载: ${url}"
        日志信息 "下载 LinuxQQ ${ver}（deb 较大，请耐心等待）..."
        [[ -f "$pkg_file" ]] || 网络_下载 "$url" "$pkg_file" 3 || return 1
        日志信息 "安装 LinuxQQ deb 包..."
        apt-get install -f -y "$pkg_file" || return 1
        apt-get install -y libnss3 libgbm1 2>/dev/null || true
        apt-get install -y libasound2 2>/dev/null || apt-get install -y libasound2t64 2>/dev/null || return 1
        rm -f "$pkg_file"
    else
        pkg_file="${script_dir}/QQ.rpm"
        [[ -f "$pkg_file" ]] || 网络_下载 "$url" "$pkg_file" 3 || return 1
        dnf localinstall -y "$pkg_file" || return 1
        rm -f "$pkg_file"
    fi
    NapCat_链接QQ命令
    NapCat_更新QQ用户配置 "$ver" "$build"
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
            *) 日志信息 "NapCat 已是最新: v${installed}"; return 0 ;;
        esac
    fi

    for dir in /opt/QQ /opt/QQ/resources /opt/QQ/resources/app; do
        [[ -d "$dir" ]] || { 日志错误 "QQ 未正确安装，缺少 $dir"; return 1; }
    done

    mkdir -p "${NAPCAT_LAUNCHER}" "${TOOL_INSTALL_DIR}"
    cp -rf "${work_dir}/NapCat/"* "${TOOL_INSTALL_DIR}/" || return 1
    chmod -R 777 "${TOOL_INSTALL_DIR}/"
    NapCat_注入QQ || return 1
    日志成功 "NapCat 已注入 ${TOOL_INSTALL_DIR}"
}

NapCat_执行安装() {
    local force="${1:-n}" auto_force="${2:-y}" work_dir

    [[ $EUID -ne 0 ]] && { 日志错误 "NapCat 安装需要 root 权限"; return 1; }

    NapCat_安装系统依赖 || return 1
    work_dir=$(NapCat_下载并解压包) || return 1
    NapCat_安装LinuxQQ "$work_dir" "$force" "$auto_force" || return 1
    NapCat_安装Shell "$work_dir" "$force" || return 1
    rm -rf "$work_dir"

    NapCat_链接QQ命令 2>/dev/null || true
    type 安装_后处理 &>/dev/null && 安装_后处理 "$PROJECT_ROOT" 2>/dev/null || true

    日志成功 "NapCat 安装完成"
    日志信息 "WEBUI: ${CONFIG_DIR}/webui.json"
    日志信息 "启动: nt [QQ号] [端口]"
    return 0
}

