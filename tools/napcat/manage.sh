#!/bin/bash
# NapCat 管理脚本
# 基于 nt（QQ多开启动器）逻辑，使用 fzf 界面

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

# 加载项目 UI 库
source "$PROJECT_ROOT/lib/core.sh"
load_lib "ui" 2>/dev/null || source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null
load_lib "log" 2>/dev/null || source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null

BASE_DIR="${XRK_ROOT:-/xrk}/body"
CONFIG_DIR="/opt/QQ/resources/app/app_launcher/napcat/config"
QQ_BIN="qq"

# ─── 状态检测 ────────────────────────────────────────────────

is_installed() {
    [ -f "/opt/QQ/resources/app/loadNapCat.js" ] && [ -d "/opt/QQ/resources/app/app_launcher/napcat" ]
}

is_running() {
    pgrep -f "qq --no-sandbox" > /dev/null 2>&1
}

get_running_qqs() {
    pgrep -f "qq --no-sandbox" 2>/dev/null | while read pid; do
        local cmdline
        cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ')
        echo "$cmdline" | grep -oP '\-q \K[0-9]+' 2>/dev/null
    done | sort -u
}

# ─── 添加/更新 QQ 账号配置 ──────────────────────────────────

add_update_qq() {
    local qq_num="$1"
    local port="${2:-2537}"
    mkdir -p "$BASE_DIR"
    echo '{"qq": "'$qq_num'", "port": '$port'}' > "${BASE_DIR}/qq_${qq_num}.json"
    ui_success "已添加 QQ $qq_num（端口: $port）"
}

remove_qq() {
    local qq_num="$1"
    rm -f "${BASE_DIR}/qq_${qq_num}.json"
    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json" "${CONFIG_DIR}/onebot11_${qq_num}.json"
    ui_success "已移除 QQ $qq_num 的配置"
}

get_qq_list() {
    if [ -d "$BASE_DIR" ]; then
        find "$BASE_DIR" -name "qq_*.json" -exec basename {} \; | sed 's/qq_//g' | sed 's/\.json//g' | sort
    fi
}

# ─── 生成 NapCat/OneBot 配置文件 ────────────────────────────

generate_configs() {
    local qq_num="$1"
    local port="$2"
    mkdir -p "$CONFIG_DIR"

    # napcat 配置
    cat > "${CONFIG_DIR}/napcat_${qq_num}.json" << EOF
{
    "fileLog": false,
    "consoleLog": true,
    "fileLogLevel": "debug",
    "consoleLogLevel": "info",
    "packetBackend": "auto",
    "packetServer": ""
}
EOF

    # onebot 配置
    local reverse_ws_url="ws://127.0.0.1:${port}/OneBotv11"
    cat > "${CONFIG_DIR}/onebot11_${qq_num}.json" << EOF
{
  "network": {
    "httpServers": [
      {
        "name": "http-server",
        "enable": false,
        "port": 3000,
        "host": "",
        "enableCors": true,
        "enableWebsocket": true,
        "messagePostFormat": "array",
        "token": "",
        "debug": false
      }
    ],
    "httpClients": [],
    "websocketServers": [
      {
        "name": "websocket-server",
        "enable": false,
        "host": "",
        "port": 3001,
        "messagePostFormat": "array",
        "reportSelfMessage": true,
        "token": "",
        "enableForcePushEvent": true,
        "debug": false,
        "heartInterval": 30000
      }
    ],
    "websocketClients": [
      {
        "name": "websocket-client",
        "enable": true,
        "url": "${reverse_ws_url}",
        "messagePostFormat": "array",
        "reportSelfMessage": true,
        "reconnectInterval": 5000,
        "token": "",
        "debug": false,
        "heartInterval": 30000
      }
    ]
  },
  "musicSignUrl": "",
  "enableLocalFile2Url": true
}
EOF
}

# ─── 启动 QQ ─────────────────────────────────────────────────

start_qq() {
    local qq_num="$1"
    local config_file="${BASE_DIR}/qq_${qq_num}.json"

    if [ ! -f "$config_file" ]; then
        ui_error "找不到 QQ $qq_num 的配置文件"
        return 1
    fi

    local port
    port=$(jq -r '.port // 2537' "$config_file")

    # 检查是否已在运行
    if pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1; then
        ui_msg "QQ $qq_num 已在运行中" "提示"
        return 0
    fi

    # 检查安装
    if ! is_installed; then
        ui_error "NapCat 未正确安装，请先安装"
        return 1
    fi

    # 生成配置文件
    generate_configs "$qq_num" "$port"

    ui_info "正在启动 QQ $qq_num（端口: $port）..."

    # 前台启动
    export DISPLAY="${DISPLAY:-:99}"
    xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num"
}

# ─── 停止 QQ ─────────────────────────────────────────────────

stop_qq() {
    local qq_num="$1"

    if ! pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1; then
        ui_msg "QQ $qq_num 未在运行" "提示"
        return 0
    fi

    ui_info "正在停止 QQ $qq_num..."
    pkill -f "qq --no-sandbox -q $qq_num" 2>/dev/null
    sleep 2

    if pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1; then
        pkill -9 -f "qq --no-sandbox -q $qq_num" 2>/dev/null
    fi

    ui_success "QQ $qq_num 已停止"
}

# ─── 添加新 QQ 账号（fzf 交互） ─────────────────────────────

add_qq_interactive() {
    local qq_num
    qq_num=$(ui_input "请输入 QQ 账号" "")
    [ -z "$qq_num" ] && return

    local port
    port=$(ui_input "请输入 WebSocket 端口" "2537")
    [ -z "$port" ] && port=2537

    add_update_qq "$qq_num" "$port"

    if ui_confirm "是否立即启动 QQ $qq_num？"; then
        qq_manage_start "$qq_num"
    fi
}

# ─── 修改 QQ 配置（fzf 交互） ──────────────────────────────

modify_qq_interactive() {
    local qq_list
    qq_list=$(get_qq_list)
    [ -z "$qq_list" ] && { ui_msg "没有已配置的 QQ 账号" "提示"; return; }

    local items=()
    for qq in $qq_list; do
        local port
        port=$(jq -r '.port // 2537' "${BASE_DIR}/qq_${qq}.json")
        items+=("$qq" "端口: $port")
    done

    local selected
    selected=$(ui_select "📋 选择要修改的 QQ 账号" "选择:" "${items[@]}")
    [ -z "$selected" ] && return

    local current_port
    current_port=$(jq -r '.port // 2537' "${BASE_DIR}/qq_${selected}.json")

    local new_qq
    new_qq=$(ui_input "QQ 账号" "$selected")
    [ -z "$new_qq" ] && return

    local new_port
    new_port=$(ui_input "端口" "$current_port")
    [ -z "$new_port" ] && new_port="$current_port"

    if [ "$selected" != "$new_qq" ]; then
        rm -f "${BASE_DIR}/qq_${selected}.json"
    fi
    add_update_qq "$new_qq" "$new_port"
}

# ─── Debug 启动 QQ ──────────────────────────────────────────

start_qq_debug() {
    local qq_num="$1"
    local config_file="${BASE_DIR}/qq_${qq_num}.json"

    if [ ! -f "$config_file" ]; then
        ui_error "找不到 QQ $qq_num 的配置文件"
        return 1
    fi

    local port
    port=$(jq -r '.port // 2537' "$config_file")

    # 检查是否已在运行
    if pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1; then
        ui_msg "QQ $qq_num 已在运行中" "提示"
        return 0
    fi

    # 检查安装
    if ! is_installed; then
        ui_error "NapCat 未正确安装，请先安装"
        return 1
    fi

    # 生成配置文件
    generate_configs "$qq_num" "$port"

    ui_info "正在启动 QQ $qq_num（Debug 模式，端口: $port）..."

    # 前台 Debug 启动
    export DISPLAY="${DISPLAY:-:99}"
    xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num" --debug
}

# ─── QQ 操作函数 ────────────────────────────────────────────

qq_manage_start() {
    local qq_num="$1"
    start_qq "$qq_num"
}

qq_manage_debug() {
    local qq_num="$1"
    start_qq_debug "$qq_num"
}

qq_manage_remove() {
    local qq_num="$1"
    if ui_confirm "确定要移除 QQ $qq_num 的配置吗？"; then
        stop_qq "$qq_num" 2>/dev/null
        remove_qq "$qq_num"
    fi
}

# ─── 选择一个 QQ 进行操作 ──────────────────────────────────

select_qq_and_action() {
    local action_name="$1"   # 操作名称（显示用）
    local action_func="$2"   # 操作函数名

    local qq_list
    qq_list=$(get_qq_list)
    [ -z "$qq_list" ] && { ui_msg "没有已配置的 QQ 账号，请先添加" "提示"; return; }

    local items=()
    for qq in $qq_list; do
        local port status
        port=$(jq -r '.port // 2537' "${BASE_DIR}/qq_${qq}.json")
        if pgrep -f "qq --no-sandbox -q $qq" > /dev/null 2>&1; then
            status="🟢 运行中"
        else
            status="🔴 已停止"
        fi
        items+=("$qq" "端口: $port | $status")
    done

    local selected
    selected=$(ui_select "📋 选择 QQ 账号 - $action_name" "选择:" "${items[@]}")
    [ -z "$selected" ] && return

    $action_func "$selected"
}

# ─── 直接启动（同时输入 QQ 号和端口） ──────────────────────

start_qq_interactive() {
    local qq_num
    qq_num=$(ui_input "请输入 QQ 账号" "")
    [ -z "$qq_num" ] && return

    local port
    port=$(ui_input "请输入 WebSocket 端口" "2537")
    [ -z "$port" ] && port=2537

    # 确保配置文件存在
    mkdir -p "$BASE_DIR"
    echo '{"qq": "'$qq_num'", "port": '$port'}' > "${BASE_DIR}/qq_${qq_num}.json"

    # 根据 action 调用对应函数
    start_qq "$qq_num"
}

# ─── Debug 启动（同时输入 QQ 号和端口） ────────────────────

debug_qq_interactive() {
    local qq_num
    qq_num=$(ui_input "请输入 QQ 账号" "")
    [ -z "$qq_num" ] && return

    local port
    port=$(ui_input "请输入 WebSocket 端口" "2537")
    [ -z "$port" ] && port=2537

    # 确保配置文件存在
    mkdir -p "$BASE_DIR"
    echo '{"qq": "'$qq_num'", "port": '$port'}' > "${BASE_DIR}/qq_${qq_num}.json"

    # 根据 action 调用对应函数
    start_qq_debug "$qq_num"
}

# ─── 重装 ───────────────────────────────────────────────────

reinstall_project() {
    if ! ui_confirm "重装 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 重新下载并安装 NapCat\n3. 保留账号配置\n\n确定继续？"; then
        return 0
    fi

    ui_info "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2

    ui_clear
    bash "$(dirname "$0")/install.sh"
}

# ─── 卸载 ───────────────────────────────────────────────────

uninstall_project() {
    if ! ui_confirm "卸载 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 删除 NapCat 文件\n3. 恢复 QQ 配置\n4. 删除账号配置\n\n确定继续？"; then
        return 0
    fi

    ui_info "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2

    ui_info "删除 NapCat 文件..."
    rm -rf "$CONFIG_DIR/../napcat" 2>/dev/null
    rm -f /opt/QQ/resources/app/loadNapCat.js

    ui_info "恢复 QQ 启动配置..."
    if [ -f "/opt/QQ/resources/app/package.json.bak" ]; then
        cp /opt/QQ/resources/app/package.json.bak /opt/QQ/resources/app/package.json
    else
        # 没有备份则只恢复 main 字段
        jq '.main = "./launcher.node.js"' /opt/QQ/resources/app/package.json > /tmp/package.json 2>/dev/null
        mv /tmp/package.json /opt/QQ/resources/app/package.json 2>/dev/null || true
    fi

    ui_info "删除账号配置..."
    rm -rf "$BASE_DIR" 2>/dev/null
    rm -f /usr/local/bin/napcat 2>/dev/null

    ui_success "NapCat 已卸载"
}

# ─── 交互式菜单 ──────────────────────────────────────────────

napcat_manage() {
    while true; do
        local status="已停止"
        is_running && status="运行中"

        local choice
        choice=$(ui_submenu "📁 NapCat 管理" "请选择操作:" \
            "1" "🚀 启动 NapCat" \
            "2" "🐛 Debug 启动 NapCat" \
            "3" "🔄 重装 NapCat" \
            "4" "🗑️  卸载 NapCat" \
            "5" "➕ 添加 QQ 账号" \
            "6" "✏️  修改 QQ 配置" \
            "7" "🗑️  删除 QQ 账号")

        case "$choice" in
            1) start_qq_interactive ;;
            2) debug_qq_interactive ;;
            3) reinstall_project ;;
            4) uninstall_project ;;
            5) add_qq_interactive ;;
            6) modify_qq_interactive ;;
            7) select_qq_and_action "删除" qq_manage_remove ;;
            b) break ;;
        esac
    done
}

# ─── 全部状态 ───────────────────────────────────────────────

show_all_status() {
    local info=""
    info+="=== NapCat 状态 ===\n"
    if is_installed; then
        info+="安装状态: ✅ 已安装\n"
    else
        info+="安装状态: ❌ 未安装\n"
    fi

    info+="\n=== 运行中的 QQ ===\n"
    local running_qqs
    running_qqs=$(get_running_qqs)
    if [ -n "$running_qqs" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && info+="  QQ $qq  🟢 运行中\n"
        done <<< "$running_qqs"
    else
        info+="  无\n"
    fi

    info+="\n=== 已配置的 QQ 账号 ===\n"
    local qq_list
    qq_list=$(get_qq_list)
    if [ -n "$qq_list" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && info+="  QQ $qq\n"
        done <<< "$qq_list"
    else
        info+="  无\n"
    fi

    ui_text "$info" "📊 NapCat 状态"
}

# ─── 辅助函数（供 --auto 使用） ──────────────────────────────

show_status() {
    if is_running; then echo "运行中"; else echo "已停止"; fi
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)       start_qq "$3" ;;
        debug)       start_qq_debug "$3" ;;
        status)      show_status ;;
        is-installed) is_installed && echo "yes" || echo "no" ;;
        uninstall)   uninstall_project ;;
        *)
            echo "用法: manage.sh --auto {start <qq>|debug <qq>|status|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    napcat_manage
fi
