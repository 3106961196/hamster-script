#!/bin/bash

# 网络与下载管理

_网络_是否TTY() {
    [[ -t 1 || -n "${HAMSTER_UI_TASK:-}" ]]
}

_网络_下载进度目标() {
    if [[ -n "${HAMSTER_UI_TASK:-}" && -e /dev/tty ]]; then
        echo /dev/tty
    elif [[ -t 2 ]]; then
        echo /dev/fd/2
    else
        echo /dev/null
    fi
}

_网络_准备下载器() {
    命令存在 curl && return 0
    命令存在 wget && return 0
    包管理_确保命令 curl curl 2>/dev/null || true
    命令存在 curl && return 0
    包管理_确保命令 wget wget 2>/dev/null || true
    命令存在 wget
}

_网络_下载一次() {
    local url="$1" out="$2" progress max_time="${HAMSTER_DL_MAX_TIME:-900}"
    progress=$(_网络_下载进度目标)
    if 命令存在 curl; then
        if [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || ! _网络_是否TTY; then
            curl -fsSL --connect-timeout 15 --max-time "$max_time" -o "$out" "$url" 2>/dev/null
        else
            curl -fL --progress-bar --connect-timeout 15 --max-time "$max_time" -o "$out" "$url" 2>"$progress"
        fi
        return $?
    fi
    if 命令存在 wget; then
        if [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || ! _网络_是否TTY; then
            wget -q --tries=3 --timeout=60 -O "$out" "$url" 2>/dev/null
        else
            wget --tries=3 --timeout=60 --show-progress -O "$out" "$url" 2>"$progress"
        fi
        return $?
    fi
    return 127
}

# 统一下载：GitHub 自动加速与多镜像回退、失败重试、临时文件落盘
网络_下载() {
    local url="$1" out="$2" tries="${3:-3}" i tmp dir name size dl_url
    local -a candidates=()

    [[ -z "$url" || -z "$out" ]] && return 1
    _网络_准备下载器 || { 日志错误 "缺少 curl/wget，且自动安装失败"; return 1; }

    dir=$(dirname "$out")
    [[ -n "$dir" && "$dir" != "." ]] && mkdir -p "$dir" 2>/dev/null || true

    name=$(basename "$out")
    tmp="${out}.tmp.$$"

    if type GitHub_下载候选 &>/dev/null; then
        mapfile -t candidates < <(GitHub_下载候选 "$url")
    fi
    if [[ ${#candidates[@]} -eq 0 ]]; then
        dl_url="$url"
        type getgh &>/dev/null && dl_url=$(getgh "$url" 2>/dev/null || true)
        candidates=("${dl_url:-$url}")
    fi

    [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || 日志信息 "下载 $name"
    for dl_url in "${candidates[@]}"; do
        [[ -z "$dl_url" ]] && continue
        [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || {
            case "$dl_url" in
                https://github.com/*) ;;
                *) 日志信息 "→ ${dl_url%%\?*}" ;;
            esac
        }
        for ((i=1; i<=tries; i++)); do
            rm -f "$tmp" 2>/dev/null || true
            if _网络_下载一次 "$dl_url" "$tmp"; then
                mv -f "$tmp" "$out" 2>/dev/null || { rm -f "$tmp" 2>/dev/null || true; return 1; }
                if [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" != "1" ]]; then
                    size=$(wc -c <"$out" 2>/dev/null | tr -d ' ')
                    [[ -n "$size" ]] && 日志成功 "$name (${size}B)" || 日志成功 "$name"
                fi
                return 0
            fi
            [[ "$i" -lt "$tries" ]] && {
                [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || 日志警告 "$name ($i/$tries)"
                sleep 1
            }
        done
    done
    rm -f "$tmp" 2>/dev/null || true
    [[ "${HAMSTER_DL_QUIET:-${XRK_DL_QUIET:-0}}" = "1" ]] || 日志错误 "$name 下载失败（已试 ${#candidates[@]} 条线路）"
    return 1
}

# 获取公网 IP
网络_获取公网IP() {
    local ip
    if 命令存在 curl; then
        ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    elif 命令存在 wget; then
        ip=$(wget -qO- ifconfig.me 2>/dev/null || wget -qO- icanhazip.com 2>/dev/null)
    fi
    echo "$ip"
}

# 获取本地 IP
网络_获取本地IP() {
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 | awk '{print $7; exit}'
}

# 获取所有开放端口
网络_获取开放端口() {
    if 命令存在 ss; then
        ss -tuln | awk 'NR>1 {print $5}' | cut -d: -f2 | sort -n | uniq
    elif 命令存在 netstat; then
        netstat -tuln | awk 'NR>2 {print $4}' | cut -d: -f2 | sort -n | uniq
    fi
}

# 解析进程列表
网络_解析进程列表() {
    local ps_output="$1"
    local max_count="${2:-20}"
    
    local count=0
    
    while IFS= read -r line; do
        if [[ -n "$line" ]] && [[ ! "$line" =~ ^USER ]]; then
            local pid cpu mem comm
            pid=$(echo "$line" | awk '{print $2}')
            cpu=$(echo "$line" | awk '{print $3}')
            mem=$(echo "$line" | awk '{print $4}')
            comm=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf $i " "; print ""}' | xargs)
            
            if [[ -n "$pid" ]]; then
                echo "$pid CPU:${cpu}% MEM:${mem}% - ${comm:0:40}"
                ((count++))
                if [[ $count -ge $max_count ]]; then
                    break
                fi
            fi
        fi
    done <<< "$ps_output"    
}
