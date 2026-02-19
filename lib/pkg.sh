#!/bin/bash

pkg_get_system_type() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        case "$ID" in
            ubuntu|debian) echo "debian" ;;
            centos|rhel|fedora|rocky|almalinux) echo "rhel" ;;
            arch|manjaro) echo "arch" ;;
            alpine) echo "alpine" ;;
            *) echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

pkg_get_manager() {
    local system_type
    system_type=$(pkg_get_system_type)
    case "$system_type" in
        debian) echo "apt" ;;
        rhel) echo "yum" ;;
        arch) echo "pacman" ;;
        alpine) echo "apk" ;;
        *) echo "unknown" ;;
    esac
}

pkg_get_distro_version() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "${VERSION_CODENAME:-unknown}"
    else
        echo "unknown"
    fi
}

pkg_update() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt update ;;
        yum) yum makecache ;;
        pacman) pacman -Sy ;;
        apk) apk update ;;
        *) return 1 ;;
    esac
}

pkg_upgrade() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt upgrade -y -o Dpkg::Options::="--force-confold" ;;
        yum) yum upgrade -y ;;
        pacman) pacman -Syu --noconfirm ;;
        apk) apk upgrade ;;
        *) return 1 ;;
    esac
}

pkg_install() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt install -y "$package" ;;
        yum) yum install -y "$package" ;;
        pacman) pacman -S --noconfirm "$package" ;;
        apk) apk add "$package" ;;
        *) return 1 ;;
    esac
}

pkg_remove() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt remove -y "$package" ;;
        yum) yum remove -y "$package" ;;
        pacman) pacman -R --noconfirm "$package" ;;
        apk) apk del "$package" ;;
        *) return 1 ;;
    esac
}

pkg_search() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt search "$package" 2>/dev/null ;;
        yum) yum search "$package" ;;
        pacman) pacman -Ss "$package" ;;
        apk) apk search "$package" ;;
        *) return 1 ;;
    esac
}

pkg_list_installed() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) dpkg -l | awk '/^ii/ {print $2, $3}' ;;
        yum) yum list installed ;;
        pacman) pacman -Q ;;
        apk) apk info ;;
        *) return 1 ;;
    esac
}

pkg_list_upgradable() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt list --upgradable 2>/dev/null ;;
        yum) yum check-update ;;
        pacman) pacman -Qu ;;
        apk) apk version -l '<' ;;
        *) return 1 ;;
    esac
}

pkg_is_installed() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) dpkg -l | grep -q "^ii  $package " ;;
        yum) rpm -q "$package" &>/dev/null ;;
        pacman) pacman -Q "$package" &>/dev/null ;;
        apk) apk info -e "$package" &>/dev/null ;;
        *) return 1 ;;
    esac
}

pkg_autoremove() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt autoremove -y ;;
        yum) yum autoremove -y ;;
        pacman) pacman -Rns --noconfirm "$(pacman -Qdtq)" 2>/dev/null || true ;;
        apk) apk cache clean ;;
        *) return 1 ;;
    esac
}

pkg_clean() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) apt autoclean -y && apt clean ;;
        yum) yum clean all ;;
        pacman) pacman -Sc --noconfirm ;;
        apk) apk cache clean ;;
        *) return 1 ;;
    esac
}

pkg_install_packages() {
    local packages=("$@")
    local failed=()
    
    for pkg in "${packages[@]}"; do
        if pkg_is_installed "$pkg"; then
            log_info "$pkg 已安装"
        else
            log_info "正在安装 $pkg..."
            if pkg_install "$pkg"; then
                log_success "$pkg 安装成功"
            else
                log_error "$pkg 安装失败"
                failed+=("$pkg")
            fi
        fi
    done
    
    if [[ ${#failed[@]} -gt 0 ]]; then
        log_error "以下软件包安装失败: ${failed[*]}"
        return 1
    fi
    return 0
}

pkg_ensure_installed() {
    local package="$1"
    
    if pkg_is_installed "$package"; then
        return 0
    fi
    
    log_info "正在安装 $package..."
    pkg_install "$package"
}
