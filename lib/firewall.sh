#!/bin/bash

# 防火墙管理

# 获取防火墙类型
sys_get_firewall_type() {
    if command_exists ufw && ufw status &>/dev/null; then
        echo "ufw"
    elif command_exists firewall-cmd && firewall-cmd --state &>/dev/null; then
        echo "firewalld"
    elif command_exists iptables && iptables -L &>/dev/null 2>&1; then
        echo "iptables"
    else
        echo "none"
    fi
}

# 查看防火墙状态
sys_firewall_status() {
    local fw_type
    fw_type=$(sys_get_firewall_type)
    
    case "$fw_type" in
        ufw)
            echo "防火墙类型: UFW"
            ufw status verbose
            ;;
        firewalld)
            echo "防火墙类型: Firewalld"
            echo "状态: $(firewall-cmd --state)"
            echo ""
            echo "开放区域: $(firewall-cmd --get-active-zones)"
            echo "开放服务: $(firewall-cmd --list-services)"
            echo "开放端口: $(firewall-cmd --list-ports)"
            ;;
        iptables)
            echo "防火墙类型: iptables"
            iptables -L -n --line-numbers
            ;;
        *)
            echo "未检测到防火墙"
            echo "建议安装: apt install ufw 或 yum install firewalld"
            ;;
    esac
}

# 启用防火墙
sys_firewall_enable() {
    local fw_type
    fw_type=$(sys_get_firewall_type)
    
    case "$fw_type" in
        ufw)
            ufw enable
            log_success "UFW 防火墙已启用"
            ;;
        firewalld)
            systemctl enable firewalld
            systemctl start firewalld
            log_success "Firewalld 防火墙已启用"
            ;;
        iptables)
            log_warn "iptables 需要手动配置规则"
            return 1
            ;;
        *)
            if command_exists apt; then
                apt install -y ufw
                ufw enable
                log_success "已安装并启用 UFW"
            elif command_exists yum; then
                yum install -y firewalld
                systemctl enable firewalld
                systemctl start firewalld
                log_success "已安装并启用 Firewalld"
            else
                log_error "无法自动安装防火墙"
                return 1
            fi
            ;;
    esac
}

# 禁用防火墙
sys_firewall_disable() {
    local fw_type
    fw_type=$(sys_get_firewall_type)
    
    case "$fw_type" in
        ufw)
            ufw disable
            log_success "UFW 防火墙已禁用"
            ;;
        firewalld)
            systemctl stop firewalld
            systemctl disable firewalld
            log_success "Firewalld 防火墙已禁用"
            ;;
        iptables)
            iptables -F
            iptables -X
            log_success "iptables 规则已清空"
            ;;
        *)
            log_warn "未检测到防火墙"
            ;;
    esac
}

# 开放端口
sys_firewall_open_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local fw_type
    fw_type=$(sys_get_firewall_type)
    
    if [[ -z "$port" ]]; then
        log_error "端口号不能为空"
        return 1
    fi
    
    case "$fw_type" in
        ufw)
            ufw allow "$port/$protocol"
            log_success "已开放端口 $port/$protocol"
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="$port/$protocol"
            firewall-cmd --reload
            log_success "已开放端口 $port/$protocol"
            ;;
        iptables)
            iptables -I INPUT -p "$protocol" --dport "$port" -j ACCEPT
            log_success "已开放端口 $port/$protocol"
            log_warn "注意: iptables 规则重启后会丢失，请手动保存"
            ;;
        *)
            log_error "未检测到防火墙，请先启用防火墙"
            return 1
            ;;
    esac
}

# 关闭端口
sys_firewall_close_port() {
    local port="$1"
    local protocol="${2:-tcp}"
    local fw_type
    fw_type=$(sys_get_firewall_type)
    
    if [[ -z "$port" ]]; then
        log_error "端口号不能为空"
        return 1
    fi
    
    case "$fw_type" in
        ufw)
            ufw delete allow "$port/$protocol"
            log_success "已关闭端口 $port/$protocol"
            ;;
        firewalld)
            firewall-cmd --permanent --remove-port="$port/$protocol"
            firewall-cmd --reload
            log_success "已关闭端口 $port/$protocol"
            ;;
        iptables)
            iptables -D INPUT -p "$protocol" --dport "$port" -j ACCEPT
            log_success "已关闭端口 $port/$protocol"
            ;;
        *)
            log_error "未检测到防火墙"
            return 1
            ;;
    esac
}
