#!/bin/bash

module_update() {
    ui_clear
    
    log_section "更新脚本"
    
    if [[ ! -d "$PROJECT_ROOT/.git" ]]; then
        log_error "脚本不是 git 仓库，无法更新"
        ui_pause "按任意键返回..."
        return 1
    fi
    
    log_info "正在检查更新..."
    
    cd "$PROJECT_ROOT"
    
    local current_branch
    current_branch=$(git branch --show-current 2>/dev/null || echo "main")
    
    git fetch origin "$current_branch" 2>&1
    
    if [[ $? -ne 0 ]]; then
        log_error "网络连接失败，无法检查更新"
        ui_pause "按任意键返回..."
        return 1
    fi
    
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null)
    
    if [[ -z "$local_commit" || -z "$remote_commit" ]]; then
        log_error "无法获取提交信息"
        ui_pause "按任意键返回..."
        return 1
    fi
    
    if [[ "$local_commit" == "$remote_commit" ]]; then
        log_success "脚本已是最新版本"
        ui_pause "按任意键返回..."
        return 0
    fi
    
    log_info "发现新版本，正在更新..."
    
    git reset --hard HEAD 2>&1
    git clean -f -d 2>&1
    
    if git pull --rebase origin "$current_branch" 2>&1; then
        log_success "更新成功"
        
        # 确保所有脚本都有执行权限
        find "$PROJECT_ROOT" -type f -name "*.sh" -exec chmod +x {} \;
        
        # 特别确保bin/cs有执行权限
        chmod +x "$PROJECT_ROOT/bin/cs" 2>&1
        
        echo ""
        log_info "重启脚本以应用更新..."
        ui_pause "按任意键重启..."
        
        # 使用绝对路径执行
        exec "$PROJECT_ROOT/bin/cs"
    else
        log_error "更新失败"
        ui_pause "按任意键返回..."
        return 1
    fi
}
