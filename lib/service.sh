#!/bin/bash

# 服务管理

# 检查是否为 systemd 系统
服务_是否Systemd() {
    命令存在 systemctl && [[ -d /run/systemd/system ]]
}

# 启动服务
服务_启动() {
    local service="$1"
    if 服务_是否Systemd; then
        systemctl start "$service"
    else
        service "$service" start
    fi
}

# 停止服务
服务_停止() {
    local service="$1"
    if 服务_是否Systemd; then
        systemctl stop "$service"
    else
        service "$service" stop
    fi
}

# 重启服务
服务_重启() {
    local service="$1"
    if 服务_是否Systemd; then
        systemctl restart "$service"
    else
        service "$service" restart
    fi
}

# 查看服务状态
服务_状态() {
    local service="$1"
    if 服务_是否Systemd; then
        systemctl status "$service"
    else
        service "$service" status
    fi
}

# 检查服务是否运行
服务_是否运行中() {
    local service="$1"
    if 服务_是否Systemd; then
        systemctl is-active --quiet "$service"
    else
        service "$service" status &>/dev/null
    fi
}
