#!/bin/bash

# 防火墙管理

# 获取防火墙类型
防火墙_获取类型() {
    if 命令存在 ufw && ufw status &>/dev/null; then
        echo "ufw"
    elif 命令存在 firewall-cmd && firewall-cmd --state &>/dev/null; then
        echo "firewalld"
    elif 命令存在 iptables && iptables -L &>/dev/null 2>&1; then
        echo "iptables"
    else
        echo "none"
    fi
}

# 查看防火墙状态
防火墙_状态() {
    local fw_type
    fw_type=$(防火墙_获取类型)
    
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
防火墙_启用() {
    local fw_type
    fw_type=$(防火墙_获取类型)
    
    case "$fw_type" in
        ufw)
            ufw enable
            日志成功 "UFW 防火墙已启用"
            ;;
        firewalld)
            systemctl enable firewalld
            systemctl start firewalld
            日志成功 "Firewalld 防火墙已启用"
            ;;
        iptables)
            日志警告 "iptables 需要手动配置规则"
            return 1
            ;;
        *)
            if 命令存在 apt; then
                apt install -y ufw
                ufw enable
                日志成功 "已安装并启用 UFW"
            elif 命令存在 yum; then
                yum install -y firewalld
                systemctl enable firewalld
                systemctl start firewalld
                日志成功 "已安装并启用 Firewalld"
            else
                日志错误 "无法自动安装防火墙"
                return 1
            fi
            ;;
    esac
}

# 禁用防火墙
防火墙_禁用() {
    local fw_type
    fw_type=$(防火墙_获取类型)
    
    case "$fw_type" in
        ufw)
            ufw disable
            日志成功 "UFW 防火墙已禁用"
            ;;
        firewalld)
            systemctl stop firewalld
            systemctl disable firewalld
            日志成功 "Firewalld 防火墙已禁用"
            ;;
        iptables)
            日志警告 "iptables 规则清空可能影响远程连接，请手动保存规则"
            iptables -F
            iptables -X
            日志成功 "iptables 规则已清空"
            ;;
        *)
            日志警告 "未检测到防火墙"
            ;;
    esac
}

# 开放端口
防火墙_开放端口() {
    local port="$1"
    local protocol="${2:-tcp}"
    local fw_type
    fw_type=$(防火墙_获取类型)
    
    if [[ -z "$port" ]]; then
        日志错误 "端口号不能为空"
        return 1
    fi
    
    case "$fw_type" in
        ufw)
            ufw allow "$port/$protocol"
            日志成功 "已开放端口 $port/$protocol"
            ;;
        firewalld)
            firewall-cmd --permanent --add-port="$port/$protocol"
            firewall-cmd --reload
            日志成功 "已开放端口 $port/$protocol"
            ;;
        iptables)
            iptables -I INPUT -p "$protocol" --dport "$port" -j ACCEPT
            日志成功 "已开放端口 $port/$protocol"
            日志警告 "注意: iptables 规则重启后会丢失，请手动保存"
            ;;
        *)
            日志错误 "未检测到防火墙，请先启用防火墙"
            return 1
            ;;
    esac
}
