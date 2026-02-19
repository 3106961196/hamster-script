#!/bin/bash

deps_check() {
    local deps=("$@")
    
    if [[ ${#deps[@]} -eq 0 ]]; then
        log_error "缺少依赖参数"
        return 1
    fi
    
    log_section "检查依赖"
    
    echo "依赖列表:"
    for dep in "${deps[@]}"; do
        echo "  - $dep"
    done
    echo ""
    
    local failed=()
    
    for dep in "${deps[@]}"; do
        if [[ "$dep" == *" "* || "$dep" == *"&&"* || "$dep" == *"|"* ]]; then
            continue
        fi
        
        log_info "检查: $dep"
        
        if command_exists "$dep"; then
            log_success "$dep 已安装"
        else
            log_info "$dep 未安装，正在安装..."
            if deps_install "$dep"; then
                log_success "$dep 安装成功"
            else
                log_error "$dep 安装失败"
                failed+=("$dep")
            fi
        fi
    done
    
    echo ""
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        log_section "依赖检查失败"
        log_error "以下依赖安装失败: ${failed[*]}"
        return 1
    else
        log_section "依赖检查完成"
        log_success "所有依赖已就绪"
        return 0
    fi
}

deps_install() {
    local dep="$1"
    
    case "$dep" in
        yq)
            deps_install_yq
            ;;
        node|npm)
            deps_install_node
            ;;
        pnpm)
            deps_install_pnpm
            ;;
        *)
            pkg_ensure_installed "$dep"
            ;;
    esac
}

deps_install_yq() {
    if command_exists yq; then
        return 0
    fi
    
    log_info "安装 yq..."
    
    local yq_url="https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64"
    
    if command_exists wget; then
        wget -q "$yq_url" -O /usr/local/bin/yq
    elif command_exists curl; then
        curl -sL "$yq_url" -o /usr/local/bin/yq
    else
        log_error "需要 wget 或 curl"
        return 1
    fi
    
    chmod +x /usr/local/bin/yq
    command_exists yq
}

deps_install_node() {
    if command_exists node; then
        return 0
    fi
    
    log_info "安装 Node.js..."
    
    local system_type
    system_type=$(pkg_get_system_type)
    
    case "$system_type" in
        debian)
            curl -fsSL https://deb.nodesource.com/setup_current.x | bash -
            apt install -y nodejs
            ;;
        rhel)
            curl -fsSL https://rpm.nodesource.com/setup_current.x | bash -
            yum install -y nodejs
            ;;
        arch)
            pacman -S --noconfirm nodejs npm
            ;;
        alpine)
            apk add nodejs npm
            ;;
        *)
            log_error "不支持的系统"
            return 1
            ;;
    esac
    
    command_exists node
}

deps_install_pnpm() {
    if command_exists pnpm; then
        return 0
    fi
    
    if ! command_exists node; then
        deps_install_node
    fi
    
    log_info "安装 pnpm..."
    npm install -g pnpm
    
    command_exists pnpm
}

deps_check_version() {
    local cmd="$1"
    local min_version="$2"
    
    if ! command_exists "$cmd"; then
        return 1
    fi
    
    local version
    version=$($cmd --version 2>/dev/null | head -1 | sed 's/[^0-9.]//g')
    
    if [[ -z "$version" ]]; then
        return 0
    fi
    
    local min_major min_minor min_patch
    local cur_major cur_minor cur_patch
    
    IFS='.' read -r min_major min_minor min_patch <<< "$min_version"
    IFS='.' read -r cur_major cur_minor cur_patch <<< "$version"
    
    min_major=${min_major:-0}
    min_minor=${min_minor:-0}
    min_patch=${min_patch:-0}
    cur_major=${cur_major:-0}
    cur_minor=${cur_minor:-0}
    cur_patch=${cur_patch:-0}
    
    if [[ $cur_major -gt $min_major ]]; then
        return 0
    elif [[ $cur_major -eq $min_major ]]; then
        if [[ $cur_minor -gt $min_minor ]]; then
            return 0
        elif [[ $cur_minor -eq $min_minor ]]; then
            if [[ $cur_patch -ge $min_patch ]]; then
                return 0
            fi
        fi
    fi
    
    return 1
}

deps_main() {
    deps_check "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$PROJECT_ROOT/lib/core.sh"
    deps_main "$@"
fi
