#!/bin/bash

# 防火墙管理（Ubuntu / ufw 为主；启用前必放行 SSH，避免小白锁死远程）

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

# 探测当前 SSH 监听端口（失败回退 22）
防火墙_当前SSH端口() {
    local port=""

    if 命令存在 sshd; then
        port=$(sshd -T 2>/dev/null | awk '/^port / {print $2; exit}')
    fi

    if [[ -z "$port" && -f /etc/ssh/sshd_config ]]; then
        port=$(awk '/^[Pp]ort[[:space:]]+/ {print $2; exit}' /etc/ssh/sshd_config)
    fi

    if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]; then
        echo "$port"
    else
        echo "22"
    fi
}

# 启用前放行 SSH，防止远程断连
防火墙_放行SSH() {
    local fw_type="$1"
    local port
    port=$(防火墙_当前SSH端口)

    case "$fw_type" in
        ufw)
            # OpenSSH 应用规则（若存在）+ 明确端口，双保险
            ufw allow OpenSSH >/dev/null 2>&1 || true
            ufw allow "${port}/tcp" >/dev/null 2>&1 || true
            日志信息 "已放行 SSH 端口 ${port}/tcp"
            ;;
        firewalld)
            firewall-cmd --permanent --add-service=ssh >/dev/null 2>&1 || true
            firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 || true
            firewall-cmd --reload >/dev/null 2>&1 || true
            日志信息 "已放行 SSH 端口 ${port}/tcp"
            ;;
        *)
            return 0
            ;;
    esac
}

# 查看防火墙状态
防火墙_状态() {
    local fw_type
    fw_type=$(防火墙_获取类型)
    
    case "$fw_type" in
        ufw)
            echo "防火墙类型: UFW"
            echo "SSH 端口: $(防火墙_当前SSH端口)"
            ufw status verbose
            ;;
        firewalld)
            echo "防火墙类型: Firewalld"
            echo "状态: $(firewall-cmd --state)"
            echo "SSH 端口: $(防火墙_当前SSH端口)"
            echo ""
            echo "开放区域: $(firewall-cmd --get-active-zones)"
            echo "开放服务: $(firewall-cmd --list-services)"
            echo "开放端口: $(firewall-cmd --list-ports)"
            ;;
        iptables)
            echo "防火墙类型: iptables"
            echo "SSH 端口: $(防火墙_当前SSH端口)"
            iptables -L -n --line-numbers
            ;;
        *)
            echo "未检测到防火墙"
            echo "建议安装: apt install ufw"
            ;;
    esac
}

# 启用防火墙
防火墙_启用() {
    local fw_type
    fw_type=$(防火墙_获取类型)
    
    case "$fw_type" in
        ufw)
            防火墙_放行SSH ufw
            # noninteractive：避免远程 tty 卡在确认提示
            ufw --force enable
            日志成功 "UFW 防火墙已启用（已放行 SSH）"
            ;;
        firewalld)
            防火墙_放行SSH firewalld
            systemctl enable firewalld
            systemctl start firewalld
            日志成功 "Firewalld 防火墙已启用（已放行 SSH）"
            ;;
        iptables)
            日志警告 "iptables 需要手动配置规则（本脚本不自动改 iptables，以免断 SSH）"
            return 1
            ;;
        *)
            if 命令存在 apt; then
                apt install -y ufw
                防火墙_放行SSH ufw
                ufw --force enable
                日志成功 "已安装并启用 UFW（已放行 SSH）"
            elif 命令存在 yum; then
                yum install -y firewalld
                systemctl enable firewalld
                systemctl start firewalld
                防火墙_放行SSH firewalld
                日志成功 "已安装并启用 Firewalld（已放行 SSH）"
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
            日志警告 "不会自动清空 iptables（避免误断远程）。如需清理请手动执行并确认 SSH 规则保留"
            return 1
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
