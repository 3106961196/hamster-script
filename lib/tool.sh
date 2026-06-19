#!/bin/bash

# ─── 工具通用框架 ──────────────────────────────────────────────

# 加载工具配置
tool_load() {
    local tool_name="$1"
    local conf="$PROJECT_ROOT/tools/$tool_name/tool.conf"
    
    if [[ -f "$conf" ]]; then
        source "$conf"
        return 0
    else
        log_error "工具配置文件不存在: $conf"
        return 1
    fi
}

# 版本比较: 0 = 相等, 1 = v1 > v2, 2 = v1 < v2
tool_version_compare() {
    local v1="$1"
    local v2="$2"
    
    [[ "$v1" == "$v2" ]] && return 0
    
    local v1_parts=(${v1//./ })
    local v2_parts=(${v2//./ })
    
    local max_len=${#v1_parts[@]}
    [[ ${#v2_parts[@]} -gt $max_len ]] && max_len=${#v2_parts[@]}
    
    for ((i=0; i<max_len; i++)); do
        local p1=${v1_parts[i]:-0}
        local p2=${v2_parts[i]:-0}
        
        if [[ $p1 -gt $p2 ]]; then
            return 1
        elif [[ $p1 -lt $p2 ]]; then
            return 2
        fi
    done
    
    return 0
}

# 检查工具是否已安装
tool_is_installed() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    [[ -d "$TOOL_INSTALL_DIR" ]]
}

# 安装工具依赖
tool_install_deps() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    log_info "正在安装依赖: ${TOOL_DEPS[*]}"
    
    for dep in "${TOOL_DEPS[@]}"; do
        case "$dep" in
            node|nodejs)
                pkg_ensure_node 18
                ;;
            pnpm)
                pkg_ensure_pnpm
                ;;
            redis|redis-server)
                pkg_ensure_redis
                ;;
            mongodb|mongod)
                pkg_ensure_mongodb
                ;;
            chromium|chromium-browser)
                pkg_ensure_chromium
                ;;
            linuxqq)
                # 调用工具自定义的 hook
                if declare -F tool_hook_install_linuxqq &>/dev/null; then
                    tool_hook_install_linuxqq
                else
                    log_error "未知依赖: $dep，请在 tool.conf 中定义安装 hook"
                    return 1
                fi
                ;;
            *)
                pkg_install "$dep"
                ;;
        esac
    done
}

# 克隆工具仓库
tool_clone_repo() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    if [[ -d "$TOOL_INSTALL_DIR" ]]; then
        log_info "目录已存在: $TOOL_INSTALL_DIR"
        return 0
    fi
    
    log_info "正在克隆仓库: $TOOL_REPO"
    mkdir -p "$(dirname "$TOOL_INSTALL_DIR")"
    
    pkg_git_clone "$TOOL_REPO" "$TOOL_INSTALL_DIR"
}

# 安装 npm 依赖
tool_install_npm() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        log_error "工具目录不存在: $TOOL_INSTALL_DIR"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    if [[ -f "package.json" ]]; then
        log_info "正在安装 npm 依赖..."
        pkg_npm_install
    fi
}

# 标准安装流程
tool_install() {
    local tool_name="$1"
    
    log_info "开始安装 $tool_name..."
    
    tool_install_deps "$tool_name" || return 1
    tool_clone_repo "$tool_name" || return 1
    tool_install_npm "$tool_name" || return 1
    
    log_success "$tool_name 安装完成"
}

# 启动工具
tool_start() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        log_error "工具未安装: $tool_name"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    log_info "启动 $tool_name..."
    nohup bash -c "$TOOL_START_CMD" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$TOOL_INSTALL_DIR/.pid"
    
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        log_success "$tool_name 已启动 (PID: $pid)"
    else
        rm -f "$TOOL_INSTALL_DIR/.pid"
        log_error "$tool_name 启动失败"
        return 1
    fi
}

# 停止工具
tool_stop() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    local pid_file="$TOOL_INSTALL_DIR/.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            log_success "$tool_name 已停止"
        else
            rm -f "$pid_file"
            log_warn "进程已不存在，清理 PID 文件"
        fi
    else
        log_warn "$tool_name 未运行"
    fi
}

# 检查工具状态
tool_status() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    local pid_file="$TOOL_INSTALL_DIR/.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            echo "running"
            return 0
        fi
    fi
    
    echo "stopped"
    return 1
}

# 重启工具
tool_restart() {
    local tool_name="$1"
    
    tool_stop "$tool_name"
    sleep 1
    tool_start "$tool_name"
}

# 更新工具
tool_update() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        log_error "工具未安装: $tool_name"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    log_info "正在更新 $tool_name..."
    
    # 备份配置
    if [[ -f ".env" ]]; then
        cp .env .env.backup
    fi
    
    # 拉取最新代码
    git pull origin main 2>/dev/null || git pull origin master
    
    # 重新安装依赖
    if [[ -f "package.json" ]]; then
        pkg_npm_install
    fi
    
    log_success "$tool_name 更新完成"
}

# 卸载工具
tool_uninstall() {
    local tool_name="$1"
    tool_load "$tool_name" || return 1
    
    tool_stop "$tool_name" 2>/dev/null
    
    if [[ -d "$TOOL_INSTALL_DIR" ]]; then
        log_info "正在删除 $TOOL_INSTALL_DIR..."
        rm -rf "$TOOL_INSTALL_DIR"
        log_success "$tool_name 已卸载"
    else
        log_warn "工具目录不存在"
    fi
}
