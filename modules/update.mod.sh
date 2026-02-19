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
    
    local local_commit remote_commit
    local_commit=$(git rev-parse HEAD 2>/dev/null)
    remote_commit=$(git rev-parse "origin/$current_branch" 2>/dev/null)
    
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
        
        find "$PROJECT_ROOT" -type f -name "*.sh" -exec chmod +x {} \;
        
        echo ""
        log_info "重启脚本以应用更新..."
        ui_pause "按任意键重启..."
        
        exec "$PROJECT_ROOT/bin/cs"
    else
        log_error "更新失败"
        ui_pause "按任意键返回..."
        return 1
    fi
}
