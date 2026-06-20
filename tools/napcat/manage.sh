#!/bin/bash
# NapCat 管理脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
tool_bootstrap

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── 状态检测 ────────────────────────────────────────────────

_nc_is_installed() {
    [ -f "$TOOL_INSTALL_DIR/napcat.mjs" ] && [ -f "/opt/QQ/resources/app/loadNapCat.js" ]
}

_nc_is_running() {
    pgrep -f "qq --no-sandbox" > /dev/null 2>&1
}

_nc_get_running_qqs() {
    pgrep -f "qq --no-sandbox" 2>/dev/null | while read pid; do
        local cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
        echo "$cmdline" | grep -oP '\-q \K[0-9]+' 2>/dev/null
    done | sort -u
}

_nc_is_qq_running() {
    local qq_num="$1"
    pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1
}

# ─── 账号配置管理 ────────────────────────────────────────────

_nc_ensure_napcatbot() {
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        mkdir -p "$(dirname "$NAPCATBOT_FILE")"
        echo '[]' > "$NAPCATBOT_FILE"
    fi
}

_nc_add_update_qq() {
    local qq_num="$1"
    local port="$2"

    _nc_ensure_napcatbot

    local tmp="${NAPCATBOT_FILE}.tmp"
    jq --arg qq "$qq_num" --argjson port "$port" \
        'if any(.[]; .qq == $qq) then
            map(if .qq == $qq then .port = $port else . end)
        else
            . + [{"qq": $qq, "port": $port}]
        end' \
        "$NAPCATBOT_FILE" > "$tmp"
    if [ $? -eq 0 ]; then
        mv "$tmp" "$NAPCATBOT_FILE"
        ui_success "已添加 QQ $qq_num（端口: $port）"
    else
        rm -f "$tmp"
        ui_error "写入 Napcatbot 失败"
    fi
}

_nc_remove_qq() {
    local qq_num="$1"

    # 先停止该 QQ 进程
    if _nc_is_qq_running "$qq_num"; then
        ui_info "正在停止 QQ $qq_num..."
        pkill -f "qq --no-sandbox -q $qq_num" 2>/dev/null
        sleep 2
        pkill -9 -f "qq --no-sandbox -q $qq_num" 2>/dev/null
        sleep 1
    fi

    # 从 Napcatbot 中移除该 QQ 条目
    if [ -f "$NAPCATBOT_FILE" ]; then
        local tmp="${NAPCATBOT_FILE}.tmp"
        jq --arg qq "$qq_num" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "$tmp"
        if [ $? -eq 0 ]; then
            mv "$tmp" "$NAPCATBOT_FILE"
        else
            rm -f "$tmp"
            ui_error "从 Napcatbot 删除失败"
            return 1
        fi
    fi

    # 删除对应的配置文件
    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json"
    rm -f "${CONFIG_DIR}/onebot11_${qq_num}.json"

    ui_success "已删除 QQ $qq_num 的所有配置"
}

_nc_get_qq_list() {
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r '.[].qq' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

_nc_get_qq_port() {
    local qq_num="$1"
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r --arg qq "$qq_num" '.[] | select(.qq == $qq) | .port' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

# ─── 生成配置文件 ────────────────────────────────────────────

_nc_generate_configs() {
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

# ─── 启动/停止 QQ ────────────────────────────────────────────

_nc_start_qq() {
    local qq_num="$1"
    local bg_mode="${2:-false}"

    # 检查 Napcatbot 中是否存在该 QQ
    if [ ! -f "$NAPCATBOT_FILE" ] || ! jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        ui_error "找不到 QQ $qq_num 的配置，请先添加账号"
        return 1
    fi

    local port=$(_nc_get_qq_port "$qq_num")

    # 检查是否已在运行
    if _nc_is_qq_running "$qq_num"; then
        ui_msg "QQ $qq_num 已在运行中" "注意"
        return 0
    fi

    # 检查 NapCat 安装
    if ! _nc_is_installed; then
        ui_error "NapCat 未正确安装，请先安装"
        return 1
    fi

    # 生成配置文件
    _nc_generate_configs "$qq_num" "$port"

    ui_info "正在启动 QQ $qq_num（端口: $port）..."
    export DISPLAY="${DISPLAY:-:99}"

    if [[ "$bg_mode" == "true" ]]; then
        nohup xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num" > /dev/null 2>&1 &
        sleep 2
        if _nc_is_qq_running "$qq_num"; then
            ui_success "QQ $qq_num 已在后台启动（端口: $port）"
        else
            ui_error "QQ $qq_num 启动失败，请检查日志"
            return 1
        fi
    else
        xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num"
    fi
}

_nc_stop_qq() {
    local qq_num="$1"

    if ! _nc_is_qq_running "$qq_num"; then
        ui_info "QQ $qq_num 未在运行"
        return 0
    fi

    ui_info "正在停止 QQ $qq_num..."
    pkill -f "qq --no-sandbox -q $qq_num" 2>/dev/null
    sleep 2

    # 强制杀死残留进程
    if _nc_is_qq_running "$qq_num"; then
        pkill -9 -f "qq --no-sandbox -q $qq_num" 2>/dev/null
        sleep 1
    fi

    # 最终确认
    if _nc_is_qq_running "$qq_num"; then
        ui_error "QQ $qq_num 停止失败，请手动处理"
        return 1
    fi

    ui_success "QQ $qq_num 已停止"
}

# ─── 交互式操作 ──────────────────────────────────────────────

_nc_pick_qq() {
    local title="$1"
    _PICKED_QQ=""

    # 检查配置文件是否存在且有内容
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        ui_error "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    local count=$(jq 'length' "$NAPCATBOT_FILE" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ] 2>/dev/null; then
        ui_error "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    local items=()
    while IFS=$'\t' read -r qq display; do
        [ -z "$qq" ] && continue
        items+=("$qq" "$display")
    done < <(jq -r '.[] | "\(.qq)\tQQ: \(.qq) | 端口: \(.port)"' "$NAPCATBOT_FILE" 2>/dev/null)

    if [ ${#items[@]} -eq 0 ]; then
        ui_error "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    _PICKED_QQ=$(ui_select "$title" "选择: " "${items[@]}")
}

_nc_add_qq_interactive() {
    local qq_num port

    qq_num=$(ui_input "请输入 QQ 账号" "")
    [ -z "$qq_num" ] && { ui_error "QQ 号不能为空"; return 1; }

    # 检查是否已存在
    if [ -f "$NAPCATBOT_FILE" ] && jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        if ! ui_confirm "QQ $qq_num 已存在，是否覆盖配置？"; then
            return 0
        fi
    fi

    while true; do
        port=$(ui_input "请输入 WebSocket 端口号（1-65535）" "")
        [ -z "$port" ] && { ui_error "端口号不能为空"; continue; }
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            ui_error "端口号无效（1-65535）"
            continue
        fi
        break
    done

    _nc_add_update_qq "$qq_num" "$port"

    if ui_confirm "QQ $qq_num 已添加（端口: $port），是否立即启动？"; then
        _nc_start_qq "$qq_num"
    fi
}

_nc_modify_qq_interactive() {
    _nc_pick_qq "📋 选择要修改的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    local current_port=$(_nc_get_qq_port "$selected")

    local new_qq=$(ui_input "QQ 账号" "$selected")
    [ -z "$new_qq" ] && { ui_error "QQ 号不能为空"; return 1; }

    local new_port=$(ui_input "端口" "$current_port")
    [ -z "$new_port" ] && new_port="$current_port"

    # 验证端口号
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        ui_error "端口号无效（1-65535）"
        return 1
    fi

    # 如果 QQ 号变了，删除旧配置
    if [ "$selected" != "$new_qq" ]; then
        _nc_stop_qq "$selected" 2>/dev/null
        rm -f "${CONFIG_DIR}/napcat_${selected}.json" "${CONFIG_DIR}/onebot11_${selected}.json"
        if [ -f "$NAPCATBOT_FILE" ]; then
            local tmp="${NAPCATBOT_FILE}.tmp"
            jq --arg qq "$selected" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "$tmp"
            [ $? -eq 0 ] && mv "$tmp" "$NAPCATBOT_FILE" || rm -f "$tmp"
        fi
    fi

    _nc_add_update_qq "$new_qq" "$new_port"
}

_nc_delete_qq_interactive() {
    _nc_pick_qq "🗑️ 选择要删除的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    if ui_confirm "确定要删除 QQ $selected 吗？\n将同时停止该 QQ 并删除所有配置"; then
        _nc_remove_qq "$selected"

        # 确认删除结果
        if [ -f "$NAPCATBOT_FILE" ] && jq -e --arg qq "$selected" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
            ui_error "删除失败，Napcatbot 中仍存在该条目"
        else
            ui_success "QQ $selected 已彻底删除"
        fi
    fi
}

_nc_start_qq_interactive() {
    _nc_pick_qq "🚀 选择要启动的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    _nc_start_qq "$selected"
}

# ─── 重装/卸载 ───────────────────────────────────────────────

_nc_reinstall_project() {
    if ! ui_confirm "重装 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 重新下载并安装 NapCat\n3. 自动检测版本，按需更新\n4. 保留账号配置\n\n确定继续？"; then
        return 0
    fi

    ui_info "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2
    pkill -9 -f "qq --no-sandbox" 2>/dev/null
    sleep 1

    ui_clear
    bash "$(dirname "$0")/install.sh"
    ui_clear
}

_nc_uninstall_project() {
    if ! ui_confirm "卸载 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 删除 NapCat 文件\n3. 恢复 QQ 配置\n4. 删除所有账号配置\n\n确定继续？"; then
        return 0
    fi

    ui_info "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2
    pkill -9 -f "qq --no-sandbox" 2>/dev/null
    sleep 1

    ui_info "删除 NapCat 文件..."
    rm -rf "$TOOL_INSTALL_DIR" 2>/dev/null
    rm -f "$LOAD_NAPCAT_JS"

    ui_info "恢复 QQ 启动配置..."
    if [ -f "${QQ_PACKAGE_JSON}.bak" ]; then
        cp "${QQ_PACKAGE_JSON}.bak" "$QQ_PACKAGE_JSON"
    elif [ -f "$QQ_PACKAGE_JSON" ]; then
        jq '.main = "./launcher.node.js"' "$QQ_PACKAGE_JSON" > /tmp/package.json 2>/dev/null
        mv /tmp/package.json "$QQ_PACKAGE_JSON" 2>/dev/null || true
    fi

    ui_info "删除所有账号配置..."
    local qq_list=$(_nc_get_qq_list)
    for qq in $qq_list; do
        rm -f "${CONFIG_DIR}/napcat_${qq}.json"
        rm -f "${CONFIG_DIR}/onebot11_${qq}.json"
    done
    rm -f "$NAPCATBOT_FILE" 2>/dev/null
    rm -f /usr/local/bin/napcat 2>/dev/null

    ui_success "NapCat 已彻底卸载"
}

# ─── 状态展示 ────────────────────────────────────────────────

_nc_show_all_status() {
    local info=""
    info+="=== NapCat 状态 ===\n"
    if _nc_is_installed; then
        info+="安装状态: ✅ 已安装\n"
        local napcat_ver=$(jq -r '.version' "$TOOL_INSTALL_DIR/package.json" 2>/dev/null)
        [ -n "$napcat_ver" ] && info+="NapCat 版本: v${napcat_ver}\n"
    else
        info+="安装状态: ❌ 未安装\n"
    fi

    info+="\n=== 运行中的 QQ ===\n"
    local running_qqs=$(_nc_get_running_qqs)
    if [ -n "$running_qqs" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && info+="  QQ $qq  🟢 运行中（端口: $(_nc_get_qq_port "$qq")）\n"
        done <<< "$running_qqs"
    else
        info+="  无\n"
    fi

    info+="\n=== 已配置的 QQ 账号 ===\n"
    local qq_list=$(_nc_get_qq_list)
    if [ -n "$qq_list" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && {
                local port=$(_nc_get_qq_port "$qq")
                local status="🔴"
                if _nc_is_qq_running "$qq"; then
                    status="🟢"
                fi
                info+="  ${status} QQ $qq（端口: $port）\n"
            }
        done <<< "$qq_list"
    else
        info+="  无\n"
    fi

    ui_text "$info" "📊 NapCat 状态"
}

# ─── 交互式主菜单 ────────────────────────────────────────────

_nc_manage() {
    while true; do
        local choice
        choice=$(ui_submenu "📁 NapCat 管理" "请选择操作:" \
            "1" "🚀 启动 QQ" \
            "2" "➕ 添加账号" \
            "3" "✏️  修改配置" \
            "4" "🗑️  删除账号" \
            "5" "🔄 重装 NapCat" \
            "6" "🗑️  卸载 NapCat")

        case "$choice" in
            1) _nc_start_qq_interactive ;;
            2) _nc_add_qq_interactive ;;
            3) _nc_modify_qq_interactive ;;
            4) _nc_delete_qq_interactive ;;
            5) _nc_reinstall_project ;;
            6) _nc_uninstall_project && exit 0 ;;
            b) exit 0 ;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)       _nc_start_qq "$3" "true" ;;
        stop)        _nc_stop_qq "$3" ;;
        is-installed) _nc_is_installed && echo "yes" || echo "no" ;;
        uninstall)   _nc_uninstall_project ;;
        *)
            echo "用法: manage.sh --auto {start <qq>|stop <qq>|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    _nc_manage
fi
