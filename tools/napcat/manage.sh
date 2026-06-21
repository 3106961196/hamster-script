#!/bin/bash
# NapCat 管理脚本（精简版）

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

source "$PROJECT_ROOT/lib/core.sh"
工具引导

# 加载工具配置
source "$SCRIPT_DIR/tool.conf"

# ─── 状态检测 ────────────────────────────────────────────────

_NapCat_是否已安装() {
    [ -f "$TOOL_INSTALL_DIR/napcat.mjs" ] && [ -f "/opt/QQ/resources/app/loadNapCat.js" ]
}

_NapCat_是否运行中() {
    pgrep -f "qq --no-sandbox" > /dev/null 2>&1
}

_NapCat_获取运行中QQ() {
    pgrep -f "qq --no-sandbox" 2>/dev/null | while read pid; do
        local cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
        echo "$cmdline" | grep -oP '\-q \K[0-9]+' 2>/dev/null
    done | sort -u
}

_NapCat_QQ是否运行() {
    local qq_num="$1"
    pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1
}

# ─── 账号配置管理 ────────────────────────────────────────────

_NapCat_确保Bot() {
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        mkdir -p "$(dirname "$NAPCATBOT_FILE")"
        echo '[]' > "$NAPCATBOT_FILE"
    fi
}

_NapCat_添加或更新QQ() {
    local qq_num="$1"
    local port="$2"

    _NapCat_确保Bot

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
        界面成功 "已添加 QQ $qq_num（端口: $port）"
    else
        rm -f "$tmp"
        界面错误 "写入 Napcatbot 失败"
    fi
}

_NapCat_移除QQ() {
    local qq_num="$1"

    # 先停止该 QQ 进程
    if _NapCat_QQ是否运行 "$qq_num"; then
        界面信息 "正在停止 QQ $qq_num..."
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
            界面错误 "从 Napcatbot 删除失败"
            return 1
        fi
    fi

    # 删除对应的配置文件
    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json"
    rm -f "${CONFIG_DIR}/onebot11_${qq_num}.json"

    界面成功 "已删除 QQ $qq_num 的所有配置"
}

_NapCat_获取QQ列表() {
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r '.[].qq' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

_NapCat_获取QQ端口() {
    local qq_num="$1"
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r --arg qq "$qq_num" '.[] | select(.qq == $qq) | .port' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

# ─── 生成配置文件 ────────────────────────────────────────────

_NapCat_生成配置() {
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

_NapCat_启动QQ() {
    local qq_num="$1"
    local bg_mode="${2:-false}"

    # 检查 Napcatbot 中是否存在该 QQ
    if [ ! -f "$NAPCATBOT_FILE" ] || ! jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        界面错误 "找不到 QQ $qq_num 的配置，请先添加账号"
        return 1
    fi

    local port=$(_NapCat_获取QQ端口 "$qq_num")

    # 检查是否已在运行
    if _NapCat_QQ是否运行 "$qq_num"; then
        界面消息 "QQ $qq_num 已在运行中" "注意"
        return 0
    fi

    # 检查 NapCat 安装
    if ! _NapCat_是否已安装; then
        界面错误 "NapCat 未正确安装，请先安装"
        return 1
    fi

    # 生成配置文件
    _NapCat_生成配置 "$qq_num" "$port"

    界面信息 "正在启动 QQ $qq_num（端口: $port）..."
    export DISPLAY="${DISPLAY:-:99}"

    if [[ "$bg_mode" == "true" ]]; then
        nohup xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num" > /dev/null 2>&1 &
        sleep 2
        if _NapCat_QQ是否运行 "$qq_num"; then
            界面成功 "QQ $qq_num 已在后台启动（端口: $port）"
        else
            界面错误 "QQ $qq_num 启动失败，请检查日志"
            return 1
        fi
    else
        xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num"
    fi
}

_NapCat_停止QQ() {
    local qq_num="$1"

    if ! _NapCat_QQ是否运行 "$qq_num"; then
        界面信息 "QQ $qq_num 未在运行"
        return 0
    fi

    界面信息 "正在停止 QQ $qq_num..."
    pkill -f "qq --no-sandbox -q $qq_num" 2>/dev/null
    sleep 2

    # 强制杀死残留进程
    if _NapCat_QQ是否运行 "$qq_num"; then
        pkill -9 -f "qq --no-sandbox -q $qq_num" 2>/dev/null
        sleep 1
    fi

    # 最终确认
    if _NapCat_QQ是否运行 "$qq_num"; then
        界面错误 "QQ $qq_num 停止失败，请手动处理"
        return 1
    fi

    界面成功 "QQ $qq_num 已停止"
}

# ─── 交互式操作 ──────────────────────────────────────────────

_NapCat_选择QQ() {
    local title="$1"
    _PICKED_QQ=""

    # 检查配置文件是否存在且有内容
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        界面错误 "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    local count=$(jq 'length' "$NAPCATBOT_FILE" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ] 2>/dev/null; then
        界面错误 "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    local items=()
    while IFS=$'\t' read -r qq display; do
        [ -z "$qq" ] && continue
        items+=("$qq" "$display")
    done < <(jq -r '.[] | "\(.qq)\tQQ: \(.qq) | 端口: \(.port)"' "$NAPCATBOT_FILE" 2>/dev/null)

    if [ ${#items[@]} -eq 0 ]; then
        界面错误 "没有已配置的 QQ 账号，请先添加"
        return 1
    fi

    _PICKED_QQ=$(界面选择 "$title" "选择: " "${items[@]}")
}

_NapCat_交互添加QQ() {
    local qq_num port

    qq_num=$(界面输入 "请输入 QQ 账号" "")
    [ -z "$qq_num" ] && { 界面错误 "QQ 号不能为空"; return 1; }

    # 检查是否已存在
    if [ -f "$NAPCATBOT_FILE" ] && jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        if ! 界面确认 "QQ $qq_num 已存在，是否覆盖配置？"; then
            return 0
        fi
    fi

    while true; do
        port=$(界面输入 "请输入 WebSocket 端口号（1-65535）" "")
        [ -z "$port" ] && { 界面错误 "端口号不能为空"; continue; }
        if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
            界面错误 "端口号无效（1-65535）"
            continue
        fi
        break
    done

    _NapCat_添加或更新QQ "$qq_num" "$port"

    if 界面确认 "QQ $qq_num 已添加（端口: $port），是否立即启动？"; then
        _NapCat_启动QQ "$qq_num"
    fi
}

_NapCat_交互修改QQ() {
    _NapCat_选择QQ "📋 选择要修改的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    local current_port=$(_NapCat_获取QQ端口 "$selected")

    local new_qq=$(界面输入 "QQ 账号" "$selected")
    [ -z "$new_qq" ] && { 界面错误 "QQ 号不能为空"; return 1; }

    local new_port=$(界面输入 "端口" "$current_port")
    [ -z "$new_port" ] && new_port="$current_port"

    # 验证端口号
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        界面错误 "端口号无效（1-65535）"
        return 1
    fi

    # 如果 QQ 号变了，删除旧配置
    if [ "$selected" != "$new_qq" ]; then
        _NapCat_停止QQ "$selected" 2>/dev/null
        rm -f "${CONFIG_DIR}/napcat_${selected}.json" "${CONFIG_DIR}/onebot11_${selected}.json"
        if [ -f "$NAPCATBOT_FILE" ]; then
            local tmp="${NAPCATBOT_FILE}.tmp"
            jq --arg qq "$selected" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "$tmp"
            [ $? -eq 0 ] && mv "$tmp" "$NAPCATBOT_FILE" || rm -f "$tmp"
        fi
    fi

    _NapCat_添加或更新QQ "$new_qq" "$new_port"
}

_NapCat_交互删除QQ() {
    _NapCat_选择QQ "🗑️ 选择要删除的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    if 界面确认 "确定要删除 QQ $selected 吗？\n将同时停止该 QQ 并删除所有配置"; then
        _NapCat_移除QQ "$selected"

        # 确认删除结果
        if [ -f "$NAPCATBOT_FILE" ] && jq -e --arg qq "$selected" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
            界面错误 "删除失败，Napcatbot 中仍存在该条目"
        else
            界面成功 "QQ $selected 已彻底删除"
        fi
    fi
}

_NapCat_交互启动QQ() {
    _NapCat_选择QQ "🚀 选择要启动的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    _NapCat_启动QQ "$selected"
}

# ─── 重装/卸载 ───────────────────────────────────────────────

_NapCat_重装项目() {
    if ! 界面确认 "重装 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 重新下载并安装 NapCat\n3. 自动检测版本，按需更新\n4. 保留账号配置\n\n确定继续？"; then
        return 0
    fi

    界面信息 "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2
    pkill -9 -f "qq --no-sandbox" 2>/dev/null
    sleep 1

    界面清屏
    bash "$(dirname "$0")/install.sh"
    界面清屏
}

_NapCat_卸载项目() {
    if ! 界面确认 "卸载 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 删除 NapCat 文件\n3. 恢复 QQ 配置\n4. 删除所有账号配置\n\n确定继续？"; then
        return 0
    fi

    界面信息 "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2
    pkill -9 -f "qq --no-sandbox" 2>/dev/null
    sleep 1

    界面信息 "删除 NapCat 文件..."
    rm -rf "$TOOL_INSTALL_DIR" 2>/dev/null
    rm -f "$LOAD_NAPCAT_JS"

    界面信息 "恢复 QQ 启动配置..."
    if [ -f "${QQ_PACKAGE_JSON}.bak" ]; then
        cp "${QQ_PACKAGE_JSON}.bak" "$QQ_PACKAGE_JSON"
    elif [ -f "$QQ_PACKAGE_JSON" ]; then
        jq '.main = "./launcher.node.js"' "$QQ_PACKAGE_JSON" > /tmp/package.json 2>/dev/null
        mv /tmp/package.json "$QQ_PACKAGE_JSON" 2>/dev/null || true
    fi

    界面信息 "删除所有账号配置..."
    local qq_list=$(_NapCat_获取QQ列表)
    for qq in $qq_list; do
        rm -f "${CONFIG_DIR}/napcat_${qq}.json"
        rm -f "${CONFIG_DIR}/onebot11_${qq}.json"
    done
    rm -f "$NAPCATBOT_FILE" 2>/dev/null
    rm -f /usr/local/bin/napcat 2>/dev/null

    界面成功 "NapCat 已彻底卸载"
}

# ─── 状态展示 ────────────────────────────────────────────────

_NapCat_显示全部状态() {
    local info=""
    info+="=== NapCat 状态 ===\n"
    if _NapCat_是否已安装; then
        info+="安装状态: ✅ 已安装\n"
        local napcat_ver=$(jq -r '.version' "$TOOL_INSTALL_DIR/package.json" 2>/dev/null)
        [ -n "$napcat_ver" ] && info+="NapCat 版本: v${napcat_ver}\n"
    else
        info+="安装状态: ❌ 未安装\n"
    fi

    info+="\n=== 运行中的 QQ ===\n"
    local running_qqs=$(_NapCat_获取运行中QQ)
    if [ -n "$running_qqs" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && info+="  QQ $qq  🟢 运行中（端口: $(_NapCat_获取QQ端口 "$qq")）\n"
        done <<< "$running_qqs"
    else
        info+="  无\n"
    fi

    info+="\n=== 已配置的 QQ 账号 ===\n"
    local qq_list=$(_NapCat_获取QQ列表)
    if [ -n "$qq_list" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && {
                local port=$(_NapCat_获取QQ端口 "$qq")
                local status="🔴"
                if _NapCat_QQ是否运行 "$qq"; then
                    status="🟢"
                fi
                info+="  ${status} QQ $qq（端口: $port）\n"
            }
        done <<< "$qq_list"
    else
        info+="  无\n"
    fi

    界面文本 "$info" "📊 NapCat 状态"
}

# ─── 交互式主菜单 ────────────────────────────────────────────

_NapCat_管理() {
    while true; do
        local choice
        choice=$(界面子菜单 "📁 NapCat 管理" "请选择操作:" \
            "1" "🚀 启动 QQ" \
            "2" "➕ 添加账号" \
            "3" "✏️  修改配置" \
            "4" "🗑️  删除账号" \
            "5" "🔄 重装 NapCat" \
            "6" "🗑️  卸载 NapCat")

        case "$choice" in
            1) _NapCat_交互启动QQ ;;
            2) _NapCat_交互添加QQ ;;
            3) _NapCat_交互修改QQ ;;
            4) _NapCat_交互删除QQ ;;
            5) _NapCat_重装项目 ;;
            6) _NapCat_卸载项目 && exit 0 ;;
            b) exit 0 ;;
        esac
    done
}

# ─── 入口 ─────────────────────────────────────────────────────

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)       _NapCat_启动QQ "$3" "true" ;;
        stop)        _NapCat_停止QQ "$3" ;;
        is-installed) _NapCat_是否已安装 && echo "yes" || echo "no" ;;
        uninstall)   _NapCat_卸载项目 ;;
        *)
            echo "用法: manage.sh --auto {start <qq>|stop <qq>|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    _NapCat_管理
fi
