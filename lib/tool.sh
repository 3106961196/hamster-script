#!/bin/bash

# ─── 工具通用框架 ──────────────────────────────────────────────

# 加载工具配置
工具_加载配置() {
    local tool_name="$1"
    local conf="$PROJECT_ROOT/tools/$tool_name/tool.conf"
    
    if [[ -f "$conf" ]]; then
        source "$conf"
        return 0
    else
        日志错误 "工具配置文件不存在: $conf"
        return 1
    fi
}

# 版本比较: 0 = 相等, 1 = v1 > v2, 2 = v1 < v2
工具_版本比较() {
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
工具_是否已安装() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    [[ -d "$TOOL_INSTALL_DIR" ]]
}

# 安装工具依赖
工具_安装依赖() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    日志信息 "正在安装依赖: ${TOOL_DEPS[*]}"
    
    for dep in "${TOOL_DEPS[@]}"; do
        case "$dep" in
            node|nodejs)
                包管理_确保Node 18
                ;;
            pnpm)
                包管理_确保Pnpm
                ;;
            redis|redis-server)
                包管理_确保Redis
                ;;
            mongodb|mongod)
                包管理_确保MongoDB
                ;;
            chromium|chromium-browser)
                包管理_确保Chromium
                ;;
            linuxqq)
                # 调用工具自定义的 hook
                if declare -F 工具钩子_安装LinuxQQ &>/dev/null; then
                    工具钩子_安装LinuxQQ
                else
                    日志错误 "未知依赖: $dep，请在 tool.conf 中定义安装 hook"
                    return 1
                fi
                ;;
            *)
                包管理_安装 "$dep"
                ;;
        esac
    done
}

# 克隆工具仓库
工具_克隆仓库() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    if [[ -d "$TOOL_INSTALL_DIR" ]]; then
        日志信息 "目录已存在: $TOOL_INSTALL_DIR"
        return 0
    fi
    
    日志信息 "正在克隆仓库: $TOOL_REPO"
    mkdir -p "$(dirname "$TOOL_INSTALL_DIR")"
    
    包管理_Git克隆 "$TOOL_REPO" "$TOOL_INSTALL_DIR"
}

# 安装 npm 依赖
工具_安装Npm依赖() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        日志错误 "工具目录不存在: $TOOL_INSTALL_DIR"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    if [[ -f "package.json" ]]; then
        日志信息 "正在安装 npm 依赖..."
        包管理_Npm安装
    fi
}

# 标准安装流程
工具_安装() {
    local tool_name="$1"
    
    日志信息 "开始安装 $tool_name..."
    
    工具_安装依赖 "$tool_name" || return 1
    工具_克隆仓库 "$tool_name" || return 1
    工具_安装Npm依赖 "$tool_name" || return 1
    
    日志成功 "$tool_name 安装完成"
}

# 启动工具
工具_启动() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        日志错误 "工具未安装: $tool_name"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    日志信息 "启动 $tool_name..."
    nohup bash -c "$TOOL_START_CMD" > /dev/null 2>&1 &
    local pid=$!
    echo "$pid" > "$TOOL_INSTALL_DIR/.pid"
    
    sleep 1
    if kill -0 "$pid" 2>/dev/null; then
        日志成功 "$tool_name 已启动 (PID: $pid)"
    else
        rm -f "$TOOL_INSTALL_DIR/.pid"
        日志错误 "$tool_name 启动失败"
        return 1
    fi
}

# 停止工具
工具_停止() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    local pid_file="$TOOL_INSTALL_DIR/.pid"
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid"
            rm -f "$pid_file"
            日志成功 "$tool_name 已停止"
        else
            rm -f "$pid_file"
            日志警告 "进程已不存在，清理 PID 文件"
        fi
    else
        日志警告 "$tool_name 未运行"
    fi
}

# 检查工具状态
工具_状态() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
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
工具_重启() {
    local tool_name="$1"
    
    工具_停止 "$tool_name"
    sleep 1
    工具_启动 "$tool_name"
}

# 更新工具
工具_更新() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    if [[ ! -d "$TOOL_INSTALL_DIR" ]]; then
        日志错误 "工具未安装: $tool_name"
        return 1
    fi
    
    cd "$TOOL_INSTALL_DIR"
    
    日志信息 "正在更新 $tool_name..."
    
    # 备份配置
    if [[ -f ".env" ]]; then
        cp .env .env.backup
    fi
    
    # 拉取最新代码
    git pull origin main 2>/dev/null || git pull origin master
    
    # 重新安装依赖
    if [[ -f "package.json" ]]; then
        包管理_Npm安装
    fi
    
    日志成功 "$tool_name 更新完成"
}

# 卸载工具
工具_卸载() {
    local tool_name="$1"
    工具_加载配置 "$tool_name" || return 1
    
    工具_停止 "$tool_name" 2>/dev/null
    
    if [[ -d "$TOOL_INSTALL_DIR" ]]; then
        日志信息 "正在删除 $TOOL_INSTALL_DIR..."
        rm -rf "$TOOL_INSTALL_DIR"
        日志成功 "$tool_name 已卸载"
    else
        日志警告 "工具目录不存在"
    fi
}
