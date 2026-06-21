#!/bin/bash
# NapCat 安装脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
工具引导

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── LinuxQQ 安装 hook ──────────────────────────────────────
工具钩子_安装LinuxQQ() {
    _NapCat_从钩子安装LinuxQQ
}

_NapCat_从钩子安装LinuxQQ() {
    if [[ ! -d "/opt/QQ" ]]; then
        日志信息 "正在安装 LinuxQQ..."
        local qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/Linux/QQ_3.2.16_250513_x86_64_01.deb"
        local qq_file="/tmp/qq.deb"
        
        wget -q -O "$qq_file" "$qq_url"
        dpkg -i "$qq_file" 2>/dev/null || apt-get install -f -y
        rm -f "$qq_file"
    fi
}

# ─── 架构检测 ───────────────────────────────────────────────

_NapCat_获取系统架构() {
    local arch=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
    [ -z "$arch" ] && { 界面错误 "无法识别的系统架构"; exit 1; }
    界面信息 "当前系统架构: ${arch}"
    echo "$arch"
}

# ─── 安装依赖 ───────────────────────────────────────────────

_NapCat_安装依赖() {
    界面信息 "开始安装依赖..."
    
    local packages=(zip unzip jq curl xvfb screen xauth procps)
    for pkg in "${packages[@]}"; do
        包管理_安装 "$pkg" || true
    done
    
    界面成功 "依赖安装完成"
}

# ─── 下载 NapCat ────────────────────────────────────────────

_NapCat_下载NapCat() {
    local work_dir=$(mktemp -d)
    local default_file="${work_dir}/NapCat.Shell.zip"
    mkdir -p "${work_dir}/NapCat"

    界面信息 "开始下载 NapCat 安装包..."
    local napcat_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"

    if ! 包管理_下载文件 "$napcat_url" "$default_file"; then
        界面错误 "文件下载失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    界面信息 "正在验证文件..."
    if ! unzip -t "${default_file}" > /dev/null 2>&1; then
        界面错误 "文件验证失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    界面信息 "正在解压..."
    if ! unzip -q -o -d "${work_dir}/NapCat" "$default_file"; then
        界面错误 "文件解压失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    echo "$work_dir"
}

_NapCat_比较版本() {
    local ver1="$1"
    local ver2="$2"
    
    IFS='.-' read -r -a v1_parts <<< "$ver1"
    IFS='.-' read -r -a v2_parts <<< "$ver2"
    
    local length=${#v1_parts[@]}
    [ ${#v2_parts[@]} -lt $length ] && length=${#v2_parts[@]}
    
    for ((i = 0; i < length; i++)); do
        if (( v1_parts[i] > v2_parts[i] )); then
            echo "newer"
            return
        elif (( v1_parts[i] < v2_parts[i] )); then
            echo "older"
            return
        fi
    done
    
    echo "equal"
}

# ─── 更新 QQ 配置 ───────────────────────────────────────────

_NapCat_更新QQ配置() {
    local target_ver="$1"
    local build_id="$2"
    
    界面信息 "正在更新用户 QQ 配置..."
    
    local confs=""
    confs=$(find /home -name "config.json" -path "*/.config/QQ/versions/*" 2>/dev/null)
    if [ -f "/root/.config/QQ/versions/config.json" ]; then
        confs="/root/.config/QQ/versions/config.json ${confs}"
    fi

    [ -z "$confs" ] && { 界面信息 "未找到用户 QQ 配置，跳过"; return 0; }

    local count=0
    for conf in $confs; do
        jq --arg targetVer "$target_ver" --arg buildId "$build_id" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' \
            "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf" && {
            界面信息 "已更新: $conf"
            count=$((count + 1))
        } || 界面错误 "更新失败: $conf"
    done

    界面成功 "已更新 $count 个用户 QQ 配置"
}

# ─── 安装 LinuxQQ ───────────────────────────────────────────

_NapCat_安装LinuxQQ() {
    local work_dir="$1"
    local qqnt_json="${work_dir}/NapCat/qqnt.json"
    
    if [ ! -f "$qqnt_json" ]; then
        界面错误 "找不到 qqnt.json"
        exit 1
    fi

    local linuxqq_target_version=$(jq -r '.linuxVersion' "$qqnt_json")
    local linuxqq_target_verhash=$(jq -r '.linuxVerHash' "$qqnt_json")
    local linuxqq_target_build=${linuxqq_target_version##*-}

    if [[ -z "$linuxqq_target_version" || "$linuxqq_target_version" == "null" ]] || \
       [[ -z "$linuxqq_target_verhash" || "$linuxqq_target_verhash" == "null" ]]; then
        界面错误 "无法获取目标 QQ 版本"
        exit 1
    fi

    界面信息 "所需 LinuxQQ 版本: ${linuxqq_target_version}"

    # 检查是否已安装
    local installed_version=""
    if dpkg -l 2>/dev/null | grep -q linuxqq; then
        installed_version=$(dpkg -l 2>/dev/null | grep "^ii" | grep "linuxqq" | awk '{print $3}')
    elif rpm -q linuxqq &>/dev/null; then
        installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq)
    fi

    if [ -n "$installed_version" ]; then
        local cmp_result=$(_NapCat_比较版本 "$installed_version" "$linuxqq_target_version")
        if [ "$cmp_result" != "older" ]; then
            界面成功 "LinuxQQ 版本已满足要求"
            _NapCat_更新QQ配置 "$linuxqq_target_version" "$linuxqq_target_build"
            return 0
        fi
    fi

    # 卸载旧版本
    界面信息 "卸载旧版本 LinuxQQ..."
    apt-get remove -y linuxqq 2>/dev/null || rpm -e linuxqq 2>/dev/null || true

    # 下载安装
    local arch=$(_NapCat_获取系统架构)
    local base_url="https://dldir1.qq.com/qqfile/qq/QQNT/${linuxqq_target_verhash}/linuxqq_${linuxqq_target_version}"
    local qq_url=""
    local qq_file=""

    if [ "$arch" = "amd64" ]; then
        if command -v dpkg &>/dev/null; then
            qq_url="${base_url}_amd64.deb"
            qq_file="QQ.deb"
        else
            qq_url="${base_url}_x86_64.rpm"
            qq_file="QQ.rpm"
        fi
    elif [ "$arch" = "arm64" ]; then
        if command -v dpkg &>/dev/null; then
            qq_url="${base_url}_arm64.deb"
            qq_file="QQ.deb"
        else
            qq_url="${base_url}_aarch64.rpm"
            qq_file="QQ.rpm"
        fi
    fi

    [ -z "$qq_url" ] && { 界面错误 "获取 QQ 下载链接失败"; exit 1; }

    界面信息 "下载 LinuxQQ..."
    if ! 包管理_下载文件 "$qq_url" "/tmp/$qq_file"; then
        界面错误 "QQ 下载失败"
        exit 1
    fi

    if command -v dpkg &>/dev/null; then
        apt-get install -f -y /tmp/$qq_file || { 界面错误 "安装 QQ 失败"; exit 1; }
        apt-get install -y libnss3 libgbm1 libasound2 2>/dev/null || true
    else
        yum localinstall -y /tmp/$qq_file || { 界面错误 "安装 QQ 失败"; exit 1; }
    fi

    rm -f "/tmp/$qq_file"

    # 创建符号链接
    if [ -f "/opt/QQ/qq" ]; then
        ln -sf /opt/QQ/qq /usr/local/bin/qq
    fi

    _NapCat_更新QQ配置 "$linuxqq_target_version" "$linuxqq_target_build"
    界面成功 "LinuxQQ 安装完成"
}

# ─── 安装 NapCat ────────────────────────────────────────────

_NapCat_安装NapCat() {
    local work_dir="$1"
    
    界面信息 "检查 QQ 安装目录..."
    for dir in /opt/QQ /opt/QQ/resources /opt/QQ/resources/app; do
        [ ! -d "$dir" ] && { 界面错误 "QQ 安装不完整，缺少 $dir"; exit 1; }
    done

    mkdir -p "$TOOL_INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    界面信息 "正在复制 NapCat 文件..."
    cp -r -f "${work_dir}/NapCat/"* "$TOOL_INSTALL_DIR/" || {
        界面错误 "文件复制失败"
        exit 1
    }
    chmod -R 777 "$TOOL_INSTALL_DIR/"

    界面信息 "正在注入 NapCat 加载脚本..."
    echo "(async () => {await import('file://${TOOL_INSTALL_DIR}/napcat.mjs');})();" > /opt/QQ/resources/app/loadNapCat.js

    界面信息 "正在修改 QQ 启动配置..."
    if [ -f "/opt/QQ/resources/app/package.json" ]; then
        cp "/opt/QQ/resources/app/package.json" "/opt/QQ/resources/app/package.json.bak"
        jq '.main = "./loadNapCat.js"' /opt/QQ/resources/app/package.json > /opt/QQ/resources/app/package.json.tmp
        mv /opt/QQ/resources/app/package.json.tmp /opt/QQ/resources/app/package.json
    fi

    界面成功 "NapCat 安装完成"
}

# ─── 主流程 ─────────────────────────────────────────────────

_NapCat_主流程() {
    界面清屏
    界面文本 "    (\\_/)\n    ( •_•)\n    / >🐹< \\\n\n      NapCat 安装脚本" "NapCat"

    _NapCat_安装依赖
    
    local work_dir=$(_NapCat_下载NapCat)
    _NapCat_安装LinuxQQ "$work_dir"
    _NapCat_安装NapCat "$work_dir"
    
    rm -rf "${work_dir}"

    界面文本 "NapCat 目录: $TOOL_INSTALL_DIR\n配置目录: $CONFIG_DIR\n账户数据: $NAPCATBOT_FILE\nWEBUI_TOKEN 请查看: $CONFIG_DIR/webui.json" "安装完成"
}

_NapCat_主流程 "$@"
