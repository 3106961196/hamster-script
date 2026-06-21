#!/bin/bash

# 网络与下载管理

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

# 检查端口是否被监听
网络_检查端口() {
    local port="$1"
    if 命令存在 ss; then
        ss -tuln | grep -q ":$port "
    elif 命令存在 netstat; then
        netstat -tuln | grep -q ":$port "
    else
        return 1
    fi
}

# 获取所有开放端口
网络_获取开放端口() {
    if 命令存在 ss; then
        ss -tuln | awk 'NR>1 {print $5}' | cut -d: -f2 | sort -n | uniq
    elif 命令存在 netstat; then
        netstat -tuln | awk 'NR>2 {print $4}' | cut -d: -f2 | sort -n | uniq
    fi
}

# 终止进程
网络_结束进程() {
    local process_name="$1"
    local signal="${2:-TERM}"
    pkill -"$signal" "$process_name"
}

# 获取占用资源最多的进程
网络_获取Top进程() {
    local sort_by="${1:-cpu}"
    local count="${2:-10}"
    
    case "$sort_by" in
        cpu) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
        mem) ps aux --sort=-%mem | head -n $((count + 1)) ;;
        *) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
    esac
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

# 下载文件（自动使用 GitHub 代理）
下载() {
    local url="$1"
    local target_dir="$2"
    local folder_name="$3"
    
    if [[ -z "$url" || -z "$target_dir" || -z "$folder_name" ]]; then
        日志错误 "参数不完整"
        echo "用法: 下载 <URL> <目标目录> <文件夹名称>"
        return 1
    fi
    
    local final_target="$target_dir/$folder_name"
    
    if [[ -d "$final_target" ]]; then
        日志警告 "目标目录已存在，正在清理..."
        rm -rf "$final_target"
    fi
    
    确保目录 "$target_dir"
    
    if [[ "$url" == git@* ]] || [[ "$url" == https://*git* ]] || [[ "$url" == *.git ]]; then
        下载Git仓库 "$url" "$final_target"
    else
        下载文件 "$url" "$target_dir" "$folder_name"
    fi
}

# Git 克隆（自动使用 GitHub 代理）
下载Git仓库() {
    local url="$1"
    local target="$2"
    
    # 自动添加 GitHub 代理
    if [[ "$url" == *"github.com"* ]] && [[ -n "${GITHUB_PROXY:-}" ]]; then
        url="${GITHUB_PROXY}${url}"
    fi
    
    日志信息 "Git 仓库: $url"
    日志信息 "目标目录: $target"
    日志信息 "开始克隆..."
    
    local retry=0
    local max_retry=3
    
    while [[ $retry -lt $max_retry ]]; do
        if git clone --depth 1 --progress "$url" "$target" 2>&1; then
            日志成功 "克隆完成"
            return 0
        fi
        
        ((retry++))
        if [[ $retry -lt $max_retry ]]; then
            日志警告 "克隆失败，第 $retry 次重试..."
            sleep 2
        fi
    done
    
    日志错误 "克隆失败"
    return 1
}

# 下载文件
下载文件() {
    local url="$1"
    local target_dir="$2"
    local folder_name="$3"
    
    日志信息 "下载地址: $url"
    日志信息 "目标目录: $target_dir/$folder_name"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local filename
    filename=$(basename "$url" | cut -d'?' -f1)
    local temp_file="$temp_dir/$filename"
    
    trap "rm -rf '$temp_dir'" RETURN
    
    日志信息 "开始下载..."
    
    local retry=0
    local max_retry=3
    
    while [[ $retry -lt $max_retry ]]; do
        if 命令存在 wget; then
            if wget -q --show-progress -O "$temp_file" "$url" 2>&1; then
                break
            fi
        elif 命令存在 curl; then
            if curl -L --progress-bar -o "$temp_file" "$url" 2>&1; then
                break
            fi
        else
            日志错误 "需要 wget 或 curl"
            return 1
        fi
        
        ((retry++))
        if [[ $retry -lt $max_retry ]]; then
            日志警告 "下载失败，第 $retry 次重试..."
            sleep 2
        else
            日志错误 "下载失败"
            return 1
        fi
    done
    
    日志成功 "下载完成"
    
    日志信息 "解压文件..."
    
    local extract_dir="$temp_dir/extract"
    mkdir -p "$extract_dir"
    
    if 下载并解压 "$temp_file" "$extract_dir"; then
        日志成功 "解压完成"
    else
        日志错误 "解压失败"
        return 1
    fi
    
    local extracted_content
    extracted_content=$(find "$extract_dir" -mindepth 1 -maxdepth 1 | head -1)
    
    if [[ -z "$extracted_content" ]]; then
        日志错误 "解压内容为空"
        return 1
    fi
    
    local final_target="$target_dir/$folder_name"
    
    if [[ -d "$extracted_content" ]]; then
        mv "$extracted_content" "$final_target"
    else
        mkdir -p "$final_target"
        mv "$extract_dir"/* "$final_target"/ 2>/dev/null
    fi
    
    日志成功 "安装完成: $final_target"
    return 0
}

# 解压文件
下载并解压() {
    local file="$1"
    local target="$2"
    
    case "$file" in
        *.tar.gz|*.tgz)
            tar -xzf "$file" -C "$target"
            ;;
        *.tar.bz2|*.tbz2)
            tar -xjf "$file" -C "$target"
            ;;
        *.tar.xz|*.txz)
            tar -xJf "$file" -C "$target"
            ;;
        *.tar)
            tar -xf "$file" -C "$target"
            ;;
        *.zip)
            if 命令存在 unzip; then
                unzip -q "$file" -d "$target"
            else
                日志错误 "需要 unzip"
                return 1
            fi
            ;;
        *.gz)
            gunzip -c "$file" > "$target/$(basename "${file%.gz}")"
            ;;
        *)
            日志错误 "不支持的压缩格式: $file"
            return 1
            ;;
    esac
}
