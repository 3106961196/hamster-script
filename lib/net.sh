#!/bin/bash

# 网络与下载管理

# 获取公网 IP
sys_get_public_ip() {
    local ip
    if command_exists curl; then
        ip=$(curl -s ifconfig.me 2>/dev/null || curl -s icanhazip.com 2>/dev/null)
    elif command_exists wget; then
        ip=$(wget -qO- ifconfig.me 2>/dev/null || wget -qO- icanhazip.com 2>/dev/null)
    fi
    echo "$ip"
}

# 获取本地 IP
sys_get_local_ip() {
    hostname -I 2>/dev/null | awk '{print $1}' || ip route get 1 | awk '{print $7; exit}'
}

# 检查端口是否被监听
sys_check_port() {
    local port="$1"
    if command_exists ss; then
        ss -tuln | grep -q ":$port "
    elif command_exists netstat; then
        netstat -tuln | grep -q ":$port "
    else
        return 1
    fi
}

# 获取所有开放端口
sys_get_open_ports() {
    if command_exists ss; then
        ss -tuln | awk 'NR>1 {print $5}' | cut -d: -f2 | sort -n | uniq
    elif command_exists netstat; then
        netstat -tuln | awk 'NR>2 {print $4}' | cut -d: -f2 | sort -n | uniq
    fi
}

# 终止进程
sys_kill_process() {
    local process_name="$1"
    local signal="${2:-TERM}"
    pkill -"$signal" "$process_name"
}

# 获取占用资源最多的进程
sys_get_top_processes() {
    local sort_by="${1:-cpu}"
    local count="${2:-10}"
    
    case "$sort_by" in
        cpu) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
        mem) ps aux --sort=-%mem | head -n $((count + 1)) ;;
        *) ps aux --sort=-%cpu | head -n $((count + 1)) ;;
    esac
}

# 解析进程列表
sys_parse_process_list() {
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
download() {
    local url="$1"
    local target_dir="$2"
    local folder_name="$3"
    
    if [[ -z "$url" || -z "$target_dir" || -z "$folder_name" ]]; then
        log_error "参数不完整"
        echo "用法: download <URL> <目标目录> <文件夹名称>"
        return 1
    fi
    
    local final_target="$target_dir/$folder_name"
    
    if [[ -d "$final_target" ]]; then
        log_warn "目标目录已存在，正在清理..."
        rm -rf "$final_target"
    fi
    
    ensure_dir "$target_dir"
    
    if [[ "$url" == git@* ]] || [[ "$url" == https://*git* ]] || [[ "$url" == *.git ]]; then
        download_git "$url" "$final_target"
    else
        download_file "$url" "$target_dir" "$folder_name"
    fi
}

# Git 克隆（自动使用 GitHub 代理）
download_git() {
    local url="$1"
    local target="$2"
    
    # 自动添加 GitHub 代理
    if [[ "$url" == *"github.com"* ]] && [[ -n "${GITHUB_PROXY:-}" ]]; then
        url="${GITHUB_PROXY}${url}"
    fi
    
    log_info "Git 仓库: $url"
    log_info "目标目录: $target"
    log_info "开始克隆..."
    
    local retry=0
    local max_retry=3
    
    while [[ $retry -lt $max_retry ]]; do
        if git clone --depth 1 --progress "$url" "$target" 2>&1; then
            log_success "克隆完成"
            return 0
        fi
        
        ((retry++))
        if [[ $retry -lt $max_retry ]]; then
            log_warn "克隆失败，第 $retry 次重试..."
            sleep 2
        fi
    done
    
    log_error "克隆失败"
    return 1
}

# 下载文件
download_file() {
    local url="$1"
    local target_dir="$2"
    local folder_name="$3"
    
    log_info "下载地址: $url"
    log_info "目标目录: $target_dir/$folder_name"
    
    local temp_dir
    temp_dir=$(mktemp -d)
    local filename
    filename=$(basename "$url" | cut -d'?' -f1)
    local temp_file="$temp_dir/$filename"
    
    trap "rm -rf '$temp_dir'" RETURN
    
    log_info "开始下载..."
    
    local retry=0
    local max_retry=3
    
    while [[ $retry -lt $max_retry ]]; do
        if command_exists wget; then
            if wget -q --show-progress -O "$temp_file" "$url" 2>&1; then
                break
            fi
        elif command_exists curl; then
            if curl -L --progress-bar -o "$temp_file" "$url" 2>&1; then
                break
            fi
        else
            log_error "需要 wget 或 curl"
            return 1
        fi
        
        ((retry++))
        if [[ $retry -lt $max_retry ]]; then
            log_warn "下载失败，第 $retry 次重试..."
            sleep 2
        else
            log_error "下载失败"
            return 1
        fi
    done
    
    log_success "下载完成"
    
    log_info "解压文件..."
    
    local extract_dir="$temp_dir/extract"
    mkdir -p "$extract_dir"
    
    if download_extract "$temp_file" "$extract_dir"; then
        log_success "解压完成"
    else
        log_error "解压失败"
        return 1
    fi
    
    local extracted_content
    extracted_content=$(find "$extract_dir" -mindepth 1 -maxdepth 1 | head -1)
    
    if [[ -z "$extracted_content" ]]; then
        log_error "解压内容为空"
        return 1
    fi
    
    local final_target="$target_dir/$folder_name"
    
    if [[ -d "$extracted_content" ]]; then
        mv "$extracted_content" "$final_target"
    else
        mkdir -p "$final_target"
        mv "$extract_dir"/* "$final_target"/ 2>/dev/null
    fi
    
    log_success "安装完成: $final_target"
    return 0
}

# 解压文件
download_extract() {
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
            if command_exists unzip; then
                unzip -q "$file" -d "$target"
            else
                log_error "需要 unzip"
                return 1
            fi
            ;;
        *.gz)
            gunzip -c "$file" > "$target/$(basename "${file%.gz}")"
            ;;
        *)
            log_error "不支持的压缩格式: $file"
            return 1
            ;;
    esac
}
