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
        apt) apt search "$package" 2>/dev/null | grep -E "^[^/]+/" | sed 's|/[^ ]*||' | head -30 ;;
        yum) yum search "$package" 2>/dev/null | grep -E "^[^ ]+\." | awk '{print $1}' | head -30 ;;
        pacman) pacman -Ss "$package" 2>/dev/null | grep -E "^[^/]+/" | sed 's|/.*||' | head -30 ;;
        apk) apk search "$package" 2>/dev/null | head -30 ;;
        *) return 1 ;;
    esac
}

pkg_list_installed() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) dpkg -l | awk '/^ii/ {print $2, $3}' ;;
        yum) rpm -qa --queryformat '%{NAME} %{VERSION}-%{RELEASE}\n' ;;
        pacman) pacman -Q ;;
        apk) apk info -v | sed 's/-\([0-9].*\)/ \1/' ;;
        *) return 1 ;;
    esac
}

pkg_list_upgradable() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt)
            apt list --upgradable 2>/dev/null | tail -n +2 | while read -r line; do
                local name old_ver new_ver
                name=$(echo "$line" | cut -d'/' -f1)
                old_ver=$(echo "$line" | awk -F' ' '{print $2}')
                new_ver=$(echo "$line" | awk -F' ' '{print $3}' | tr -d ']')
                echo "$name $old_ver $new_ver"
            done
            ;;
        yum)
            yum check-update --quiet 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
        pacman)
            pacman -Qu 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
        apk)
            apk version -l '<' 2>/dev/null | awk '{print $1, $2}' | head -50
            ;;
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

pkg_get_version() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) dpkg -l "$package" 2>/dev/null | awk '/^ii/ {print $3}' ;;
        yum) rpm -q "$package" 2>/dev/null | awk -F- '{print $2}' ;;
        pacman) pacman -Q "$package" 2>/dev/null | awk '{print $2}' ;;
        apk) apk info -v "$package" 2>/dev/null | sed 's/.*-//' ;;
        *) echo "unknown" ;;
    esac
}

pkg_get_upgradable_version() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt)
            apt list --upgradable 2>/dev/null | grep "^$package/" | awk -F' ' '{print $3}' | tr -d ']'
            ;;
        yum)
            yum check-update --quiet "$package" 2>/dev/null | awk '{print $2}'
            ;;
        pacman)
            pacman -Qu "$package" 2>/dev/null | awk '{print $2}'
            ;;
        apk)
            apk version -l '<' "$package" 2>/dev/null | awk '{print $2}'
            ;;
        *) echo "" ;;
    esac
}

pkg_get_versions() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt)
            apt-cache madison "$package" 2>/dev/null | awk -F'|' '{print $2}' | tr -d ' ' | head -10
            ;;
        yum)
            yum --showduplicates list "$package" 2>/dev/null | awk '{print $2}' | head -10
            ;;
        pacman)
            pacman -Si "$package" 2>/dev/null | grep -E "^Version" | awk '{print $3}'
            ;;
        apk)
            apk policy "$package" 2>/dev/null | grep -E "^[0-9]" | head -10
            ;;
        *) echo "latest" ;;
    esac
}

pkg_show_info() {
    local package="$1"
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt)
            apt-cache show "$package" 2>/dev/null | head -30
            ;;
        yum)
            yum info "$package" 2>/dev/null
            ;;
        pacman)
            pacman -Si "$package" 2>/dev/null
            ;;
        apk)
            apk info -a "$package" 2>/dev/null
            ;;
        *) echo "无法获取软件包信息" ;;
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

pkg_upgrade_all() {
    local pkg_manager
    pkg_manager=$(pkg_get_manager)
    case "$pkg_manager" in
        apt) DEBIAN_FRONTEND=noninteractive apt full-upgrade -y -o Dpkg::Options::="--force-confold" ;;
        yum) yum upgrade -y ;;
        pacman) pacman -Syu --noconfirm ;;
        apk) apk upgrade ;;
        *) return 1 ;;
    esac
}
