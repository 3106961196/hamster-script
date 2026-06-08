#!/bin/bash
# NapCat 安装脚本
# 基于 NapCat.sh 核心逻辑改写，适配 hamster-script 框架

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

TARGET_FOLDER="/opt/QQ/resources/app/app_launcher"
INSTALL_DIR="$TARGET_FOLDER/napcat"
NAPCAT_CLI="/usr/local/bin/napcat"
NT_CLI="/usr/local/bin/nt"

# ─── 颜色 ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local msg="[$(date +'%Y-%m-%d %H:%M:%S')]: $1"
    case "$1" in
        *"失败"*|*"错误"*|*"无法连接"*|*"不存在"*) echo -e "${RED}${msg}${NC}" ;;
        *"成功"*) echo -e "${GREEN}${msg}${NC}" ;;
        *"忽略"*|*"跳过"*) echo -e "${YELLOW}${msg}${NC}" ;;
        *) echo -e "${CYAN}${msg}${NC}" ;;
    esac
}

run_cmd() {
    log "$2中..."
    if ! eval "$1"; then
        log "$2失败"
        exit 1
    fi
    log "$2成功"
}

# ─── 架构检测 ───────────────────────────────────────────────

get_system_arch() {
    system_arch=$(uname -m | sed 's/aarch64/arm64/;s/x86_64/amd64/')
    [ -z "$system_arch" ] && { log "无法识别的系统架构"; exit 1; }
    log "当前系统架构: ${system_arch}"
}

# ─── 包管理器检测 ───────────────────────────────────────────

set_package_tool() {
    if command -v apt-get &>/dev/null; then
        package_manager="apt-get"; package_installer="dpkg"
    elif command -v dnf &>/dev/null; then
        package_manager="dnf"; package_installer="rpm"
    elif command -v yum &>/dev/null; then
        package_manager="yum"; package_installer="rpm"
    else
        log "未找到 apt-get/dnf/yum"
        exit 1
    fi
    log "当前包管理器: ${package_manager}"
}

# ─── 安装依赖 ───────────────────────────────────────────────

install_dependency() {
    log "开始更新依赖..."
    set_package_tool

    if [ "$package_manager" = "apt-get" ]; then
        apt-get update -y -qq 2>/dev/null || true
        for p in zip unzip jq curl xvfb screen xauth procps; do
            log "安装 $p..."
            apt-get install -y -qq "$p" 2>/dev/null || true
        done
    elif [ "$package_manager" = "dnf" ] || [ "$package_manager" = "yum" ]; then
        [ "$package_manager" = "dnf" ] && dnf install -y epel-release 2>/dev/null || true
        for p in zip unzip jq curl xorg-x11-server-Xvfb screen procps-ng; do
            log "安装 $p..."
            $package_manager install -y "$p" 2>/dev/null || true
        done
    fi
    log "更新依赖成功"
}

# ─── 下载 NapCat ────────────────────────────────────────────

download_napcat() {
    if [ -d "./NapCat" ] && [ "$(ls -A ./NapCat 2>/dev/null)" ]; then
        log "文件夹已存在且不为空(./NapCat)，请重命名后重新执行脚本以防误删"
        exit 1
    fi
    mkdir -p ./NapCat

    default_file="NapCat.Shell.zip"
    if [ -f "${default_file}" ]; then
        log "检测到已下载NapCat安装包,跳过下载..."
    else
        log "开始下载NapCat安装包,请稍等..."
        napcat_download_url="https://github.com/NapNeko/NapCatQQ/releases/latest/download/NapCat.Shell.zip"
        
        if command -v wget &>/dev/null; then
            wget -q "$napcat_download_url" -O "$default_file" || {
                # 带代理重试
                wget -q "https://gh-proxy.com/${napcat_download_url}" -O "$default_file" || {
                    log "文件下载失败"; exit 1
                }
            }
        elif command -v curl &>/dev/null; then
            curl -sL "$napcat_download_url" -o "$default_file" || {
                curl -sL "https://gh-proxy.com/${napcat_download_url}" -o "$default_file" || {
                    log "文件下载失败"; exit 1
                }
            }
        else
            log "需要 wget 或 curl"
            exit 1
        fi
        log "${default_file} 成功下载"
    fi

    log "正在验证 ${default_file}..."
    unzip -t "${default_file}" > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        log "文件验证失败"
        rm -rf ./NapCat ./NapCat.Shell.zip
        exit 1
    fi

    log "正在解压 ${default_file}..."
    unzip -q -o -d ./NapCat NapCat.Shell.zip || {
        log "文件解压失败"
        rm -rf ./NapCat ./NapCat.Shell.zip
        exit 1
    }
}

# ─── QQ 版本检测与安装 ──────────────────────────────────────

check_linuxqq() {
    local qqnt_json="./NapCat/qqnt.json"
    if [ ! -f "$qqnt_json" ]; then
        log "找不到 qqnt.json"
        exit 1
    fi

    linuxqq_target_version=$(jq -r '.linuxVersion' "$qqnt_json")
    linuxqq_target_verhash=$(jq -r '.linuxVerHash' "$qqnt_json")

    if [[ -z "$linuxqq_target_version" || "$linuxqq_target_version" == "null" ]] || \
       [[ -z "$linuxqq_target_verhash" || "$linuxqq_target_verhash" == "null" ]]; then
        log "无法获取目标QQ版本"
        exit 1
    fi

    linuxqq_target_build=${linuxqq_target_version##*-}
    log "所需LinuxQQ版本: ${linuxqq_target_version}, 构建: ${linuxqq_target_build}"

    # 检查是否已安装
    local need_install=false
    if [ "$package_installer" = "dpkg" ]; then
        if dpkg -l | grep linuxqq &>/dev/null; then
            local installed_version
            installed_version=$(dpkg -l | grep "^ii" | grep "linuxqq" | awk '{print $3}')
            log "LinuxQQ 已安装: $installed_version"
            # 简化版版本比较：直接强制安装所需版本
            if [ "$installed_version" != "$linuxqq_target_version" ]; then
                need_install=true
            fi
        else
            need_install=true
        fi
    elif [ "$package_installer" = "rpm" ]; then
        if rpm -q linuxqq &>/dev/null; then
            local installed_version
            installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq)
            log "LinuxQQ 已安装: $installed_version"
            if [ "$installed_version" != "$linuxqq_target_version" ]; then
                need_install=true
            fi
        else
            need_install=true
        fi
    fi

    if [ "$need_install" = true ]; then
        install_linuxqq
    else
        log "LinuxQQ 版本已满足要求"
    fi
}

install_linuxqq() {
    log "卸载旧版本LinuxQQ..."
    if [ "$package_installer" = "dpkg" ]; then
        apt-get remove -y -qq linuxqq 2>/dev/null || true
    elif [ "$package_installer" = "rpm" ]; then
        rpm -e linuxqq 2>/dev/null || true
    fi

    get_system_arch
    base_url="https://dldir1.qq.com/qqfile/qq/QQNT/${linuxqq_target_verhash}/linuxqq_${linuxqq_target_version}"

    log "下载LinuxQQ..."
    if [ "$system_arch" = "amd64" ]; then
        if [ "$package_installer" = "rpm" ]; then
            qq_url="${base_url}_x86_64.rpm"
            qq_file="QQ.rpm"
        else
            qq_url="${base_url}_amd64.deb"
            qq_file="QQ.deb"
        fi
    elif [ "$system_arch" = "arm64" ]; then
        if [ "$package_installer" = "rpm" ]; then
            qq_url="${base_url}_aarch64.rpm"
            qq_file="QQ.rpm"
        else
            qq_url="${base_url}_arm64.deb"
            qq_file="QQ.deb"
        fi
    fi

    if [ -z "$qq_url" ]; then
        log "获取QQ下载链接失败"
        exit 1
    fi
    log "QQ下载链接: ${qq_url}"

    if command -v wget &>/dev/null; then
        wget -q "$qq_url" -O "$qq_file" || { log "QQ下载失败"; exit 1; }
    elif command -v curl &>/dev/null; then
        curl -sL "$qq_url" -o "$qq_file" || { log "QQ下载失败"; exit 1; }
    fi

    if [ "$package_installer" = "dpkg" ]; then
        run_cmd "apt-get install -f -y -qq ./$qq_file" "安装QQ"
        run_cmd "apt-get install -y -qq libnss3 libgbm1" "安装依赖库"
        log "安装libasound2中..."
        apt-get install -y -qq libasound2 2>/dev/null || \
        apt-get install -y -qq libasound2t64 2>/dev/null || \
        { log "安装libasound2 失败"; exit 1; }
    elif [ "$package_installer" = "rpm" ]; then
        run_cmd "$package_manager localinstall -y ./$qq_file" "安装QQ"
    fi
    rm -f "$qq_file"
}

# ─── 安装 NapCat ────────────────────────────────────────────

install_napcat() {
    log "检查目标文件夹..."
    for dir in /opt/QQ /opt/QQ/resources /opt/QQ/resources/app; do
        [ ! -d "$dir" ] && { log "QQ安装不完整，缺少 $dir"; exit 1; }
    done

    mkdir -p "$TARGET_FOLDER/napcat"

    log "正在复制NapCat文件..."
    cp -r -f ./NapCat/* "$TARGET_FOLDER/napcat/" || {
        log "文件复制失败"; exit 1
    }
    chmod -R 777 "$TARGET_FOLDER/napcat/"

    log "正在注入NapCat加载脚本..."
    echo "(async () => {await import('file:///${TARGET_FOLDER}/napcat/napcat.mjs');})();" > /opt/QQ/resources/app/loadNapCat.js

    log "正在修改QQ启动配置..."
    if [ -f "/opt/QQ/resources/app/package.json" ]; then
        jq '.main = "./loadNapCat.js"' /opt/QQ/resources/app/package.json > /opt/QQ/resources/app/package.json.tmp
        mv /opt/QQ/resources/app/package.json.tmp /opt/QQ/resources/app/package.json
    fi

    log "NapCat 安装成功"
}

# ─── 安装 CLI ───────────────────────────────────────────────

install_cli() {
    log "安装 napcat CLI..."
    local cli_url="https://raw.githubusercontent.com/NapNeko/NapCat-Installer/refs/heads/main/script/napcat"
    
    if command -v wget &>/dev/null; then
        wget -q "$cli_url" -O /tmp/napcatcli || true
    elif command -v curl &>/dev/null; then
        curl -sL "$cli_url" -o /tmp/napcatcli || true
    fi
    
    if [ -f /tmp/napcatcli ] && [ -s /tmp/napcatcli ]; then
        cp /tmp/napcatcli "$NAPCAT_CLI" 2>/dev/null && chmod +x "$NAPCAT_CLI" 2>/dev/null
        rm -f /tmp/napcatcli
        log "napcat CLI 安装成功"
    else
        log "napcat CLI 下载失败，跳过"
    fi
}

# ─── 安装 nt 启动器 ─────────────────────────────────────────

install_nt() {
    local nt_source="${PROJECT_ROOT}/.log/nt"
    if [ -f "$nt_source" ]; then
        cp "$nt_source" "$NT_CLI" && chmod +x "$NT_CLI"
        log "nt 启动器安装成功"
    else
        log "nt 源文件不存在: $nt_source"
    fi
}

# ─── 清理 ───────────────────────────────────────────────────

clean() {
    rm -rf ./NapCat ./NapCat.Shell.zip
}

# ─── 主流程 ─────────────────────────────────────────────────

main() {
    clear
    echo ""
    echo "    (\\_/)"
    echo "    ( •_•)"
    echo "    / >🐹< \\"
    echo ""
    echo "      NapCat 安装脚本"
    echo ""

    install_dependency
    download_napcat
    check_linuxqq
    install_napcat
    install_cli
    install_nt
    clean

    echo ""
    log "================== NapCat 安装完成 =================="
    log "NapCat 目录: $TARGET_FOLDER/napcat"
    log "WEBUI_TOKEN 请查看: $TARGET_FOLDER/napcat/config/webui.json"
    echo ""
}

main "$@"
