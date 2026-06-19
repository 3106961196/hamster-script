#!/bin/bash
# NapCat 安装脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/../.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
tool_bootstrap

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── LinuxQQ 安装 hook ──────────────────────────────────────
tool_hook_install_linuxqq() {
    _nc_install_linuxqq_from_hook
}

_nc_install_linuxqq_from_hook() {
    if [[ ! -d "/opt/QQ" ]]; then
        log_info "正在安装 LinuxQQ..."
        local qq_url="https://dldir1.qq.com/qqfile/qq/QQNT/Linux/QQ_3.2.16_250513_x86_64_01.deb"
        local qq_file="/tmp/qq.deb"
        
        wget -q -O "$qq_file" "$qq_url"
        dpkg -i "$qq_file" 2>/dev/null || apt-get install -f -y
        rm -f "$qq_file"
    fi
}

# ─── 架构检测 ───────────────────────────────────────────────

_nc_get_system_arch() {
    local arch=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
    [ -z "$arch" ] && { ui_error "无法识别的系统架构"; exit 1; }
    ui_info "当前系统架构: ${arch}"
    echo "$arch"
}

# ─── 安装依赖 ───────────────────────────────────────────────

_nc_install_dependency() {
    ui_info "开始安装依赖..."
    
    local packages=(zip unzip jq curl xvfb screen xauth procps)
    for pkg in "${packages[@]}"; do
        pkg_install "$pkg" || true
    done
    
    ui_success "依赖安装完成"
}

# ─── 下载 NapCat ────────────────────────────────────────────

_nc_download_napcat() {
    local work_dir=$(mktemp -d)
    local default_file="${work_dir}/NapCat.Shell.zip"
    mkdir -p "${work_dir}/NapCat"

    ui_info "开始下载 NapCat 安装包..."
    local napcat_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"

    if ! pkg_download_file "$napcat_url" "$default_file"; then
        ui_error "文件下载失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    ui_info "正在验证文件..."
    if ! unzip -t "${default_file}" > /dev/null 2>&1; then
        ui_error "文件验证失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    ui_info "正在解压..."
    if ! unzip -q -o -d "${work_dir}/NapCat" "$default_file"; then
        ui_error "文件解压失败"
        rm -rf "${work_dir}"
        exit 1
    fi

    echo "$work_dir"
}

_nc_compare_versions() {
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

_nc_update_qq_config() {
    local target_ver="$1"
    local build_id="$2"
    
    ui_info "正在更新用户 QQ 配置..."
    
    local confs=""
    confs=$(find /home -name "config.json" -path "*/.config/QQ/versions/*" 2>/dev/null)
    if [ -f "/root/.config/QQ/versions/config.json" ]; then
        confs="/root/.config/QQ/versions/config.json ${confs}"
    fi

    [ -z "$confs" ] && { ui_info "未找到用户 QQ 配置，跳过"; return 0; }

    local count=0
    for conf in $confs; do
        jq --arg targetVer "$target_ver" --arg buildId "$build_id" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' \
            "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf" && {
            ui_info "已更新: $conf"
            count=$((count + 1))
        } || ui_error "更新失败: $conf"
    done

    ui_success "已更新 $count 个用户 QQ 配置"
}

# ─── 安装 LinuxQQ ───────────────────────────────────────────

_nc_install_linuxqq() {
    local work_dir="$1"
    local qqnt_json="${work_dir}/NapCat/qqnt.json"
    
    if [ ! -f "$qqnt_json" ]; then
        ui_error "找不到 qqnt.json"
        exit 1
    fi

    local linuxqq_target_version=$(jq -r '.linuxVersion' "$qqnt_json")
    local linuxqq_target_verhash=$(jq -r '.linuxVerHash' "$qqnt_json")
    local linuxqq_target_build=${linuxqq_target_version##*-}

    if [[ -z "$linuxqq_target_version" || "$linuxqq_target_version" == "null" ]] || \
       [[ -z "$linuxqq_target_verhash" || "$linuxqq_target_verhash" == "null" ]]; then
        ui_error "无法获取目标 QQ 版本"
        exit 1
    fi

    ui_info "所需 LinuxQQ 版本: ${linuxqq_target_version}"

    # 检查是否已安装
    local installed_version=""
    if dpkg -l 2>/dev/null | grep -q linuxqq; then
        installed_version=$(dpkg -l 2>/dev/null | grep "^ii" | grep "linuxqq" | awk '{print $3}')
    elif rpm -q linuxqq &>/dev/null; then
        installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq)
    fi

    if [ -n "$installed_version" ]; then
        local cmp_result=$(_nc_compare_versions "$installed_version" "$linuxqq_target_version")
        if [ "$cmp_result" != "older" ]; then
            ui_success "LinuxQQ 版本已满足要求"
            _nc_update_qq_config "$linuxqq_target_version" "$linuxqq_target_build"
            return 0
        fi
    fi

    # 卸载旧版本
    ui_info "卸载旧版本 LinuxQQ..."
    apt-get remove -y linuxqq 2>/dev/null || rpm -e linuxqq 2>/dev/null || true

    # 下载安装
    local arch=$(_nc_get_system_arch)
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

    [ -z "$qq_url" ] && { ui_error "获取 QQ 下载链接失败"; exit 1; }

    ui_info "下载 LinuxQQ..."
    if ! pkg_download_file "$qq_url" "/tmp/$qq_file"; then
        ui_error "QQ 下载失败"
        exit 1
    fi

    if command -v dpkg &>/dev/null; then
        apt-get install -f -y /tmp/$qq_file || { ui_error "安装 QQ 失败"; exit 1; }
        apt-get install -y libnss3 libgbm1 libasound2 2>/dev/null || true
    else
        yum localinstall -y /tmp/$qq_file || { ui_error "安装 QQ 失败"; exit 1; }
    fi

    rm -f "/tmp/$qq_file"

    # 创建符号链接
    if [ -f "/opt/QQ/qq" ]; then
        ln -sf /opt/QQ/qq /usr/local/bin/qq
    fi

    _nc_update_qq_config "$linuxqq_target_version" "$linuxqq_target_build"
    ui_success "LinuxQQ 安装完成"
}

# ─── 安装 NapCat ────────────────────────────────────────────

_nc_install_napcat() {
    local work_dir="$1"
    
    ui_info "检查 QQ 安装目录..."
    for dir in /opt/QQ /opt/QQ/resources /opt/QQ/resources/app; do
        [ ! -d "$dir" ] && { ui_error "QQ 安装不完整，缺少 $dir"; exit 1; }
    done

    mkdir -p "$TOOL_INSTALL_DIR"
    mkdir -p "$CONFIG_DIR"

    ui_info "正在复制 NapCat 文件..."
    cp -r -f "${work_dir}/NapCat/"* "$TOOL_INSTALL_DIR/" || {
        ui_error "文件复制失败"
        exit 1
    }
    chmod -R 777 "$TOOL_INSTALL_DIR/"

    ui_info "正在注入 NapCat 加载脚本..."
    echo "(async () => {await import('file://${TOOL_INSTALL_DIR}/napcat.mjs');})();" > /opt/QQ/resources/app/loadNapCat.js

    ui_info "正在修改 QQ 启动配置..."
    if [ -f "/opt/QQ/resources/app/package.json" ]; then
        cp "/opt/QQ/resources/app/package.json" "/opt/QQ/resources/app/package.json.bak"
        jq '.main = "./loadNapCat.js"' /opt/QQ/resources/app/package.json > /opt/QQ/resources/app/package.json.tmp
        mv /opt/QQ/resources/app/package.json.tmp /opt/QQ/resources/app/package.json
    fi

    ui_success "NapCat 安装完成"
}

# ─── 主流程 ─────────────────────────────────────────────────

_nc_main() {
    ui_clear
    ui_text "    (\\_/)\n    ( •_•)\n    / >🐹< \\\n\n      NapCat 安装脚本" "NapCat"

    _nc_install_dependency
    
    local work_dir=$(_nc_download_napcat)
    _nc_install_linuxqq "$work_dir"
    _nc_install_napcat "$work_dir"
    
    rm -rf "${work_dir}"

    ui_text "NapCat 目录: $TOOL_INSTALL_DIR\n配置目录: $CONFIG_DIR\n账户数据: $NAPCATBOT_FILE\nWEBUI_TOKEN 请查看: $CONFIG_DIR/webui.json" "安装完成"
}

_nc_main "$@"
