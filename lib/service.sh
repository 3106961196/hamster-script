#!/bin/bash

# 服务管理

# 检查是否为 systemd 系统
sys_is_systemd() {
    command_exists systemctl && [[ -d /run/systemd/system ]]
}

# 列出运行中的服务
sys_service_list() {
    if sys_is_systemd; then
        systemctl list-units --type=service --state=running
    else
        service --status-all 2>/dev/null | grep +
    fi
}

# 启动服务
sys_service_start() {
    local service="$1"
    if sys_is_systemd; then
        systemctl start "$service"
    else
        service "$service" start
    fi
}

# 停止服务
sys_service_stop() {
    local service="$1"
    if sys_is_systemd; then
        systemctl stop "$service"
    else
        service "$service" stop
    fi
}

# 重启服务
sys_service_restart() {
    local service="$1"
    if sys_is_systemd; then
        systemctl restart "$service"
    else
        service "$service" restart
    fi
}

# 查看服务状态
sys_service_status() {
    local service="$1"
    if sys_is_systemd; then
        systemctl status "$service"
    else
        service "$service" status
    fi
}

# 检查服务是否运行
sys_service_is_running() {
    local service="$1"
    if sys_is_systemd; then
        systemctl is-active --quiet "$service"
    else
        service "$service" status &>/dev/null
    fi
}
