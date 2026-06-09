#!/bin/bash
# NapCat 安装脚本
# 基于 NapCat.sh 核心逻辑改写，适配 hamster-script 框架

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

INSTALL_DIR="/root/cs/Napcat"
CONFIG_DIR="/root/cs/Napcat/config"
NAPCATBOT_FILE="/root/cs/Napcat/Napcatbot"
NAPCAT_CLI="/usr/local/bin/napcat"
NT_CLI="/usr/local/bin/nt"
_NC_WORK_DIR=""

# ─── 颜色 ───────────────────────────────────────────────────
_NC_RED='\033[0;31m'
_NC_GREEN='\033[0;32m'
_NC_YELLOW='\033[1;33m'
_NC_CYAN='\033[0;36m'
_NC_NC='\033[0m'

_nc_log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"无法连接"*|*"不存在"*) echo -e "${_NC_RED}${msg}${_NC_NC}" ;;
        *"成功"*) echo -e "${_NC_GREEN}${msg}${_NC_NC}" ;;
        *"忽略"*|*"跳过"*) echo -e "${_NC_YELLOW}${msg}${_NC_NC}" ;;
        *) echo -e "${_NC_CYAN}${msg}${_NC_NC}" ;;
    esac
}

_nc_run_cmd() {
    _nc_log "$2中..."
    if ! bash -c "$1"; then
        _nc_log "$2失败"
        exit 1
    fi
    _nc_log "$2成功"
}

# ─── 架构检测 ───────────────────────────────────────────────

_nc_get_system_arch() {
    _nc_system_arch=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
    [ -z "$_nc_system_arch" ] && { _nc_log "无法识别的系统架构"; exit 1; }
    _nc_log "当前系统架构: ${_nc_system_arch}"
}

# ─── 包管理器检测 ───────────────────────────────────────────

_nc_set_package_tool() {
    if command -v apt-get &>/dev/null; then
        _nc_package_manager="apt-get"; _nc_package_installer="dpkg"
    elif command -v dnf &>/dev/null; then
        _nc_package_manager="dnf"; _nc_package_installer="rpm"
    elif command -v yum &>/dev/null; then
        _nc_package_manager="yum"; _nc_package_installer="rpm"
    else
        _nc_log "未找到 apt-get/dnf/yum"
        exit 1
    fi
    _nc_log "当前包管理器: ${_nc_package_manager}"
}

# ─── 安装依赖 ───────────────────────────────────────────────

_nc_install_dependency() {
    _nc_log "开始更新依赖..."
    _nc_set_package_tool

    if [ "$_nc_package_manager" = "apt-get" ]; then
        apt-get update -y -qq 2>/dev/null || true
        for p in zip unzip jq curl xvfb screen xauth procps; do
            _nc_log "安装 $p..."
            apt-get install -y -qq "$p" 2>/dev/null || true
        done
    elif [ "$_nc_package_manager" = "dnf" ] || [ "$_nc_package_manager" = "yum" ]; then
        [ "$_nc_package_manager" = "dnf" ] && dnf install -y epel-release 2>/dev/null || true
        for p in zip unzip jq curl xorg-x11-server-Xvfb screen procps-ng; do
            _nc_log "安装 $p..."
            $_nc_package_manager install -y "$p" 2>/dev/null || true
        done
    fi
    _nc_log "更新依赖成功"
}

# ─── 下载 NapCat ────────────────────────────────────────────

_nc_download_napcat() {
    _NC_WORK_DIR=$(mktemp -d)
    _nc_log "使用临时目录: ${_NC_WORK_DIR}"

    local default_file="${_NC_WORK_DIR}/NapCat.Shell.zip"
    mkdir -p "${_NC_WORK_DIR}/NapCat"

    _nc_log "开始下载NapCat安装包,请稍等..."
    napcat_download_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"

    if command -v wget &>/dev/null; then
        wget -q "$napcat_download_url" -O "$default_file" || {
            wget -q "https://gh-proxy.com/${napcat_download_url}" -O "$default_file" || {
                _nc_log "文件下载失败"; rm -rf "${_NC_WORK_DIR}"; exit 1
            }
        }
    elif command -v curl &>/dev/null; then
        curl -sL "$napcat_download_url" -o "$default_file" || {
            curl -sL "https://gh-proxy.com/${napcat_download_url}" -o "$default_file" || {
                _nc_log "文件下载失败"; rm -rf "${_NC_WORK_DIR}"; exit 1
            }
        }
    else
        _nc_log "需要 wget 或 curl"; rm -rf "${_NC_WORK_DIR}"; exit 1
    fi
    _nc_log "NapCat.Shell.zip 成功下载"

    _nc_log "正在验证 ${default_file}..."
    unzip -t "${default_file}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        _nc_log "文件验证失败"
        rm -rf "${_NC_WORK_DIR}"
        exit 1
    fi

    _nc_log "正在解压 ${default_file}..."
    unzip -q -o -d "${_NC_WORK_DIR}/NapCat" "$default_file" || {
        _nc_log "文件解压失败"
        rm -rf "${_NC_WORK_DIR}"
        exit 1
    }
}

# ─── 版本比较（来自上游 NapCat.sh）──────────────────────────

_nc_compare_versions() {
    local ver1="$1"
    local ver2="$2"
    IFS='.-' read -r -a v1_parts <<< "$ver1"
    IFS='.-' read -r -a v2_parts <<< "$ver2"
    local length=${#v1_parts[@]}
    [ ${#v2_parts[@]} -lt $length ] && length=${#v2_parts[@]}
    for ((i = 0; i < length; i++)); do
        if (( v1_parts[i] > v2_parts[i] )); then
            _nc_version_cmp_result="older=false"; return
        elif (( v1_parts[i] < v2_parts[i] )); then
            _nc_version_cmp_result="older=true"; return
        fi
    done
    if [ ${#v1_parts[@]} -gt ${#v2_parts[@]} ]; then
        _nc_version_cmp_result="older=false"
    elif [ ${#v1_parts[@]} -lt ${#v2_parts[@]} ]; then
        _nc_version_cmp_result="older=true"
    else
        _nc_version_cmp_result="older=false"
    fi
}

# ─── 更新用户 QQ 配置（来自上游 NapCat.sh）─────────────────

_nc_update_qq_config() {
    local target_ver="$1"
    local build_id="$2"
    _nc_log "正在更新用户QQ配置..."

    local confs=""
    confs=$(find /home -name "config.json" -path "*/.config/QQ/versions/*" 2>/dev/null)
    if [ -f "/root/.config/QQ/versions/config.json" ]; then
        confs="/root/.config/QQ/versions/config.json ${confs}"
    fi

    [ -z "$confs" ] && { _nc_log "未找到用户QQ配置，跳过"; return 0; }

    local count=0
    for conf in $confs; do
        jq --arg targetVer "$target_ver" --arg buildId "$build_id" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' \
            "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf" && {
            _nc_log "已更新: $conf"
            count=$((count + 1))
        } || _nc_log "更新失败: $conf"
    done

    _nc_log "已更新 $count 个用户QQ配置"
}

# ─── QQ 版本检测与安装 ──────────────────────────────────────

_nc_check_linuxqq() {
    local qqnt_json="${_NC_WORK_DIR}/NapCat/qqnt.json"
    if [ ! -f "$qqnt_json" ]; then
        _nc_log "找不到 qqnt.json"
        exit 1
    fi

    linuxqq_target_version=$(jq -r '.linuxVersion' "$qqnt_json")
    linuxqq_target_verhash=$(jq -r '.linuxVerHash' "$qqnt_json")

    if [[ -z "$linuxqq_target_version" || "$linuxqq_target_version" == "null" ]] || \
       [[ -z "$linuxqq_target_verhash" || "$linuxqq_target_verhash" == "null" ]]; then
        _nc_log "无法获取目标QQ版本"
        exit 1
    fi

    linuxqq_target_build=${linuxqq_target_version##*-}
    _nc_log "所需LinuxQQ版本: ${linuxqq_target_version}, 构建: ${linuxqq_target_build}"

    # 三重验证：包管理器 + 目录 + 可执行文件
    local need_install=false
    local installed_version=""

    if [ "$_nc_package_installer" = "dpkg" ]; then
        if dpkg -l | grep linuxqq &>/dev/null; then
            installed_version=$(dpkg -l | grep "^ii" | grep "linuxqq" | awk '{print $3}')
            _nc_log "LinuxQQ 已安装: $installed_version"
            [ "$installed_version" != "$linuxqq_target_version" ] && need_install=true
        else
            need_install=true
        fi
    elif [ "$_nc_package_installer" = "rpm" ]; then
        if rpm -q linuxqq &>/dev/null; then
            installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq)
            _nc_log "LinuxQQ 已安装: $installed_version"
            [ "$installed_version" != "$linuxqq_target_version" ] && need_install=true
        else
            need_install=true
        fi
    fi

    # 即使包管理器说已安装，也验证目录和可执行文件是否真实存在
    if [ "$need_install" = false ]; then
        if [ ! -d "/opt/QQ" ] || [ ! -d "/opt/QQ/resources/app" ] || [ ! -f "/opt/QQ/qq" ]; then
            _nc_log "QQ 包已注册但文件不完整，强制重装"
            need_install=true
        fi
    fi

    if [ "$need_install" = true ]; then
        _nc_install_linuxqq
    else
        _nc_log "LinuxQQ 版本已满足要求"
        _nc_update_qq_config "$linuxqq_target_version" "$linuxqq_target_build"
    fi
}

_nc_install_linuxqq() {
    _nc_log "卸载旧版本LinuxQQ..."
    if [ "$_nc_package_installer" = "dpkg" ]; then
        apt-get remove -y -qq linuxqq 2>/dev/null || true
    elif [ "$_nc_package_installer" = "rpm" ]; then
        rpm -e linuxqq 2>/dev/null || true
    fi

    _nc_get_system_arch
    base_url="https://dldir1.qq.com/qqfile/qq/QQNT/${linuxqq_target_verhash}/linuxqq_${linuxqq_target_version}"

    _nc_log "下载LinuxQQ..."
    if [ "$_nc_system_arch" = "amd64" ]; then
        if [ "$_nc_package_installer" = "rpm" ]; then
            qq_url="${base_url}_x86_64.rpm"; qq_file="QQ.rpm"
        else
            qq_url="${base_url}_amd64.deb"; qq_file="QQ.deb"
        fi
    elif [ "$_nc_system_arch" = "arm64" ]; then
        if [ "$_nc_package_installer" = "rpm" ]; then
            qq_url="${base_url}_aarch64.rpm"; qq_file="QQ.rpm"
        else
            qq_url="${base_url}_arm64.deb"; qq_file="QQ.deb"
        fi
    fi

    if [ -z "$qq_url" ]; then
        _nc_log "获取QQ下载链接失败"; exit 1
    fi
    _nc_log "QQ下载链接: ${qq_url}"

    if command -v wget &>/dev/null; then
        wget -q "$qq_url" -O "$qq_file" || { _nc_log "QQ下载失败"; exit 1; }
    elif command -v curl &>/dev/null; then
        curl -sL "$qq_url" -o "$qq_file" || { _nc_log "QQ下载失败"; exit 1; }
    fi

    if [ "$_nc_package_installer" = "dpkg" ]; then
        _nc_run_cmd "apt-get install -f -y -qq ./$qq_file" "安装QQ"
        _nc_run_cmd "apt-get install -y -qq libnss3 libgbm1" "安装依赖库"
        _nc_log "安装libasound2中..."
        apt-get install -y -qq libasound2 2>/dev/null || \
        apt-get install -y -qq libasound2t64 2>/dev/null || \
        { _nc_log "安装libasound2 失败"; exit 1; }
    elif [ "$_nc_package_installer" = "rpm" ]; then
        _nc_run_cmd "$_nc_package_manager localinstall -y ./$qq_file" "安装QQ"
    fi
    rm -f "$qq_file"

    # 安装后验证目录
    if [ ! -d "/opt/QQ" ]; then
        _nc_log "QQ 安装后 /opt/QQ 目录不存在，安装异常"
        exit 1
    fi

    # 创建符号链接，确保 qq 命令可用
    if [ -f "/opt/QQ/qq" ]; then
        ln -sf /opt/QQ/qq /usr/local/bin/qq
        _nc_log "已创建符号链接 /usr/local/bin/qq -> /opt/QQ/qq"
    fi

    # 更新所有用户的 QQ 配置
    _nc_update_qq_config "$linuxqq_target_version" "$linuxqq_target_build"
}

# ─── 安装 NapCat ────────────────────────────────────────────

_nc_install_napcat() {
    _nc_log "检查QQ安装目录..."
    for dir in /opt/QQ /opt/QQ/resources /opt/QQ/resources/app; do
        [ ! -d "$dir" ] && { _nc_log "QQ安装不完整，缺少 $dir"; exit 1; }
    done

    mkdir -p /root/cs
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    _nc_log "正在复制NapCat文件到 $INSTALL_DIR ..."
    cp -r -f "${_NC_WORK_DIR}/NapCat/"* "$INSTALL_DIR/" || {
        _nc_log "文件复制失败"; exit 1
    }
    chmod -R 777 "$INSTALL_DIR/"

    _nc_log "正在注入NapCat加载脚本..."
    echo "(async () => {await import('file:///root/cs/Napcat/napcat.mjs');})();" > /opt/QQ/resources/app/loadNapCat.js

    _nc_log "正在修改QQ启动配置..."
    if [ -f "/opt/QQ/resources/app/package.json" ]; then
        cp "/opt/QQ/resources/app/package.json" "/opt/QQ/resources/app/package.json.bak"
        _nc_log "已备份原始 package.json"
        jq '.main = "./loadNapCat.js"' /opt/QQ/resources/app/package.json > /opt/QQ/resources/app/package.json.tmp
        mv /opt/QQ/resources/app/package.json.tmp /opt/QQ/resources/app/package.json
    fi

    _nc_log "NapCat 安装成功"
}

# ─── 安装 CLI ───────────────────────────────────────────────

_nc_install_cli() {
    _nc_log "安装 napcat CLI..."
    local cli_url="https://raw.githubusercontent.com/NapNeko/NapCat-Installer/refs/heads/main/script/napcat"

    if command -v wget &>/dev/null; then
        wget -q "$cli_url" -O /tmp/napcatcli || true
    elif command -v curl &>/dev/null; then
        curl -sL "$cli_url" -o /tmp/napcatcli || true
    fi

    if [ -f /tmp/napcatcli ] && [ -s /tmp/napcatcli ]; then
        cp /tmp/napcatcli "$NAPCAT_CLI" 2>/dev/null && chmod +x "$NAPCAT_CLI" 2>/dev/null
        rm -f /tmp/napcatcli
        _nc_log "napcat CLI 安装成功"
    else
        _nc_log "napcat CLI 下载失败，跳过"
    fi
}

# ─── 安装 nt 启动器 ─────────────────────────────────────────

_nc_install_nt() {
    local nt_source=""

    if [ -f "$NAPCATBOT_FILE" ]; then
        local nt_path
        nt_path=$(jq -r '.[].nt // empty' "$NAPCATBOT_FILE" 2>/dev/null | head -n 1)
        if [ -n "$nt_path" ] && [ -f "$nt_path" ]; then
            nt_source="$nt_path"
            _nc_log "从 Napcatbot 读取到 nt 源文件: $nt_source"
        fi
    fi

    if [ -z "$nt_source" ]; then
        nt_source="${PROJECT_ROOT}/.log/nt"
    fi

    if [ -f "$nt_source" ]; then
        cp "$nt_source" "$NT_CLI" && chmod +x "$NT_CLI"
        _nc_log "nt 启动器安装成功"
    else
        _nc_log "nt 源文件不存在: $nt_source"
    fi
}

# ─── 清理 ───────────────────────────────────────────────────

_nc_clean() {
    rm -rf "${_NC_WORK_DIR}"
}

# ─── 主流程 ─────────────────────────────────────────────────

_nc_main() {
    clear
    echo ""
    echo "    (\\_/)"
    echo "    ( •_•)"
    echo "    / >🐹< \\"
    echo ""
    echo "      NapCat 安装脚本"
    echo ""

    _nc_install_dependency
    _nc_download_napcat
    _nc_check_linuxqq
    _nc_install_napcat
    _nc_install_cli
    _nc_install_nt
    _nc_clean

    echo ""
    _nc_log "================== NapCat 安装完成 =================="
    _nc_log "NapCat 目录: $INSTALL_DIR"
    _nc_log "配置目录: $CONFIG_DIR"
    _nc_log "账户数据: $NAPCATBOT_FILE"
    _nc_log "WEBUI_TOKEN 请查看: $CONFIG_DIR/webui.json"
    echo ""
}

_nc_main "$@"
