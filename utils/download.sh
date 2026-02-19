#!/bin/bash

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

download_git() {
    local url="$1"
    local target="$2"
    
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

download_main() {
    download "$@"
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    source "$PROJECT_ROOT/lib/core.sh"
    download_main "$@"
fi
