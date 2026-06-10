#!/bin/bash
# NapCat 管理脚本
# 整合上游 NapCat.sh 核心逻辑：版本比较、自动强制重装、QQ配置更新、依赖加载
# 账户管理：QQ号与端口绑定，支持多开（单一 Napcatbot JSON 文件）
# 启动逻辑：前台启动选中QQ号

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$(dirname "$SCRIPT_DIR")/.." && pwd)"

# 加载项目 UI 库
source "$PROJECT_ROOT/lib/core.sh"
load_lib "ui" 2>/dev/null || source "$PROJECT_ROOT/lib/ui.sh" 2>/dev/null
load_lib "log" 2>/dev/null || source "$PROJECT_ROOT/lib/log.sh" 2>/dev/null

# ═══════════════════════════════════════════════════════════════
#  路径常量（与 install.sh 完全一致）
# ═══════════════════════════════════════════════════════════════

INSTALL_DIR="/root/cs/Napcat"
CONFIG_DIR="/root/cs/Napcat/config"
NAPCATBOT_FILE="/root/cs/Napcat/Napcatbot"
NAPCAT_DIR="/root/cs/Napcat"
QQ_PACKAGE_JSON="/opt/QQ/resources/app/package.json"
LOAD_NAPCAT_JS="/opt/QQ/resources/app/loadNapCat.js"
QQ_BIN="/opt/QQ/qq"

# ═══════════════════════════════════════════════════════════════
#  依赖加载（三级回退：本地 → 相对路径 → 跳过）
# ═══════════════════════════════════════════════════════════════

_nc_load_deps() {
    # 尝试加载上游 common.sh（如果存在）
    local common_sh=""
    if [ -f "/xrk/shell_modules/common.sh" ]; then
        common_sh="/xrk/shell_modules/common.sh"
    elif [ -f "${SCRIPT_DIR}/../../shell_modules/common.sh" ]; then
        common_sh="${SCRIPT_DIR}/../../shell_modules/common.sh"
    fi
    [ -n "$common_sh" ] && source "$common_sh" 2>/dev/null || true

    # 检查关键依赖
    for pkg in jq xvfb-run; do
        if ! command -v "$pkg" &>/dev/null; then
            if type install_pkg &>/dev/null; then
                install_pkg "$pkg" 2>/dev/null || {
                    ui_error "缺少 $pkg，请安装后再运行"
                    return 1
                }
            else
                ui_error "缺少 $pkg，请先安装: apt install $pkg / dnf install $pkg"
                return 1
            fi
        fi
    done
}

# ═══════════════════════════════════════════════════════════════
#  版本比较逻辑（来自上游 NapCat.sh）
# ═══════════════════════════════════════════════════════════════

_nc_compare_versions() {
    local ver1="$1"  # 当前版本
    local ver2="$2"  # 目标版本

    IFS='.-' read -r -a v1_parts <<< "$ver1"
    IFS='.-' read -r -a v2_parts <<< "$ver2"

    local length=${#v1_parts[@]}
    [ ${#v2_parts[@]} -lt $length ] && length=${#v2_parts[@]}

    for ((i = 0; i < length; i++)); do
        if (( v1_parts[i] > v2_parts[i] )); then
            _nc_version_cmp_result="older=false"
            return
        elif (( v1_parts[i] < v2_parts[i] )); then
            _nc_version_cmp_result="older=true"
            return
        fi
    done

    if [ ${#v1_parts[@]} -gt ${#v2_parts[@]} ]; then
        _nc_version_cmp_result="older=false"
    elif [ ${#v1_parts[@]} -lt ${#v2_parts[@]} ]; then
        _nc_version_cmp_result="older=true"
    else
        _nc_version_cmp_result="older=false"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  QQ 用户配置更新（来自上游 NapCat.sh）
#  更新所有用户的 QQ 版本配置，确保与已安装版本匹配
# ═══════════════════════════════════════════════════════════════

_nc_update_qq_user_configs() {
    local target_ver="$1"
    local build_id="$2"

    ui_info "正在更新用户 QQ 配置..."

    local confs=""
    # 查找所有用户的 QQ 配置
    confs=$(find /home -name "config.json" -path "*/.config/QQ/versions/*" 2>/dev/null)
    if [ -f "/root/.config/QQ/versions/config.json" ]; then
        confs="/root/.config/QQ/versions/config.json ${confs}"
    fi

    [ -z "$confs" ] && { ui_info "未找到用户 QQ 配置，跳过"; return 0; }

    local count=0
    for conf in $confs; do
        jq --arg targetVer "$target_ver" --arg buildId "$build_id" \
            '.baseVersion = $targetVer | .curVersion = $targetVer | .buildId = $buildId' \
            "$conf" > "${conf}.tmp" && mv "${conf}.tmp" "$conf" && {
            ui_info "已更新: $conf"
            count=$((count + 1))
        } || ui_error "更新失败: $conf"
    done

    ui_success "已更新 $count 个用户 QQ 配置"
}

# ═══════════════════════════════════════════════════════════════
#  NapCat 版本检测与自动强制重装
# ═══════════════════════════════════════════════════════════════

_nc_check_napcat_version() {
    local napcat_pkg="$NAPCAT_DIR/package.json"
    if [ ! -f "$napcat_pkg" ]; then
        ui_info "NapCat 未安装或缺少 package.json"
        return 1
    fi

    local installed_ver
    installed_ver=$(jq -r '.version' "$napcat_pkg" 2>/dev/null)
    [[ -z "$installed_ver" || "$installed_ver" == "null" ]] && {
        ui_info "无法读取已安装的 NapCat 版本"
        return 1
    }

    # 获取 NapCat 解压包中的目标版本
    local target_pkg="./NapCat/package.json"
    if [ ! -f "$target_pkg" ]; then
        ui_info "未找到 NapCat 安装包，跳过版本检查"
        return 1
    fi

    local target_ver
    target_ver=$(jq -r '.version' "$target_pkg" 2>/dev/null)
    [[ -z "$target_ver" || "$target_ver" == "null" ]] && {
        ui_info "无法读取目标 NapCat 版本"
        return 1
    }

    ui_info "已安装 NapCat: v${installed_ver}，目标版本: v${target_ver}"

    _nc_compare_versions "$installed_ver" "$target_ver"
    if [[ "$_nc_version_cmp_result" == "older=true" ]]; then
        ui_info "NapCat 版本过旧，需要更新"
        return 0  # 需要重装
    else
        ui_success "NapCat 已是最新版本"
        return 2  # 无需重装
    fi
}

# ═══════════════════════════════════════════════════════════════
#  LinuxQQ 版本检测与自动强制重装（来自上游 NapCat.sh）
# ═══════════════════════════════════════════════════════════════

_nc_get_linuxqq_info() {
    local qqnt_json="./NapCat/qqnt.json"
    if [ ! -f "$qqnt_json" ]; then
        ui_error "找不到 qqnt.json"
        return 1
    fi

    _nc_qq_target_version=$(jq -r '.linuxVersion' "$qqnt_json")
    _nc_qq_target_verhash=$(jq -r '.linuxVerHash' "$qqnt_json")
    _nc_qq_target_build=${_nc_qq_target_version##*-}

    if [[ -z "$_nc_qq_target_version" || "$_nc_qq_target_version" == "null" ]] || \
       [[ -z "$_nc_qq_target_verhash" || "$_nc_qq_target_verhash" == "null" ]]; then
        ui_error "无法获取目标 QQ 版本"
        return 1
    fi

    ui_info "所需 LinuxQQ: ${_nc_qq_target_version}（构建: ${_nc_qq_target_build}）"
    return 0
}

_nc_get_installed_qq_version() {
    if dpkg -l 2>/dev/null | grep -q linuxqq; then
        _nc_qq_installed_version=$(dpkg -l 2>/dev/null | grep "^ii" | grep "linuxqq" | awk '{print $3}')
        _nc_qq_installed_installer="dpkg"
    elif rpm -q linuxqq &>/dev/null; then
        _nc_qq_installed_version=$(rpm -q --queryformat '%{VERSION}' linuxqq)
        _nc_qq_installed_installer="rpm"
    else
        _nc_qq_installed_version=""
        _nc_qq_installed_installer=""
    fi
}

_nc_check_linuxqq_version() {
    _nc_get_linuxqq_info || return 1
    _nc_get_installed_qq_version

    if [ -z "$_nc_qq_installed_version" ]; then
        ui_info "LinuxQQ 未安装，需要安装"
        return 0  # 需要安装
    fi

    ui_info "已安装 LinuxQQ: $_nc_qq_installed_version"

    _nc_compare_versions "$_nc_qq_installed_version" "$_nc_qq_target_version"
    if [[ "$_nc_version_cmp_result" == "older=true" ]]; then
        ui_info "LinuxQQ 版本过旧，需要更新"
        return 0  # 需要重装
    else
        ui_success "LinuxQQ 版本已满足要求"
        # 即使版本满足，也更新用户配置
        _nc_update_qq_user_configs "$_nc_qq_target_version" "$_nc_qq_target_build"
        return 2  # 无需重装
    fi
}

# ═══════════════════════════════════════════════════════════════
#  状态检测
# ═══════════════════════════════════════════════════════════════

is_installed() {
    [ -f "$NAPCAT_DIR/napcat.mjs" ] && [ -f "$LOAD_NAPCAT_JS" ]
}

is_running() {
    pgrep -f "qq --no-sandbox" > /dev/null 2>&1
}

get_running_qqs() {
    pgrep -f "qq --no-sandbox" 2>/dev/null | while read pid; do
        local cmdline
        cmdline=$(tr '\0' ' ' < /proc/$pid/cmdline 2>/dev/null)
        echo "$cmdline" | grep -oP '\-q \K[0-9]+' 2>/dev/null
    done | sort -u
}

is_qq_running() {
    local qq_num="$1"
    pgrep -f "qq --no-sandbox -q $qq_num" > /dev/null 2>&1
}

# ═══════════════════════════════════════════════════════════════
#  账号配置管理（基于 Napcatbot 单一 JSON 文件）
# ═══════════════════════════════════════════════════════════════

# 确保 Napcatbot 文件存在（空数组）
_ensure_napcatbot() {
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        mkdir -p "$(dirname "$NAPCATBOT_FILE")"
        echo '[]' > "$NAPCATBOT_FILE"
    fi
}

add_update_qq() {
    local qq_num="$1"
    local port="$2"

    _ensure_napcatbot

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

remove_qq() {
    local qq_num="$1"

    # 先停止该 QQ 进程
    if is_qq_running "$qq_num"; then
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

    # 删除对应的 NapCat/OneBot 配置
    rm -f "${CONFIG_DIR}/napcat_${qq_num}.json"
    rm -f "${CONFIG_DIR}/onebot11_${qq_num}.json"

    ui_success "已删除 QQ $qq_num 的所有配置"
}

get_qq_list() {
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r '.[].qq' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

get_qq_port() {
    local qq_num="$1"
    if [ -f "$NAPCATBOT_FILE" ]; then
        jq -r --arg qq "$qq_num" '.[] | select(.qq == $qq) | .port' "$NAPCATBOT_FILE" 2>/dev/null
    fi
}

# ═══════════════════════════════════════════════════════════════
#  生成 NapCat/OneBot 配置文件
# ═══════════════════════════════════════════════════════════════

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

# ═══════════════════════════════════════════════════════════════
#  启动 QQ（前台启动）
# ═══════════════════════════════════════════════════════════════

start_qq() {
    local qq_num="$1"
    local bg_mode="${2:-false}"

    # 检查 Napcatbot 中是否存在该 QQ
    if [ ! -f "$NAPCATBOT_FILE" ] || ! jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        ui_error "找不到 QQ $qq_num 的配置，请先添加账号"
        return 1
    fi

    local port
    port=$(get_qq_port "$qq_num")

    # 检查是否已在运行
    if is_qq_running "$qq_num"; then
        ui_msg "QQ $qq_num 已在运行中" "注意"
        return 0
    fi

    # 检查 NapCat 安装
    if ! is_installed; then
        ui_error "NapCat 未正确安装，请先安装"
        return 1
    fi

    # 生成配置文件
    generate_configs "$qq_num" "$port"

    ui_info "正在启动 QQ $qq_num（端口: $port）..."
    export DISPLAY="${DISPLAY:-:99}"

    if [[ "$bg_mode" == "true" ]]; then
        nohup xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num" > /dev/null 2>&1 &
        sleep 2
        if is_qq_running "$qq_num"; then
            ui_success "QQ $qq_num 已在后台启动（端口: $port）"
        else
            ui_error "QQ $qq_num 启动失败，请检查日志"
            return 1
        fi
    else
        xvfb-run -a "$QQ_BIN" --no-sandbox -q "$qq_num"
    fi
}

# ═══════════════════════════════════════════════════════════════
#  停止 QQ
# ═══════════════════════════════════════════════════════════════

stop_qq() {
    local qq_num="$1"

    if ! is_qq_running "$qq_num"; then
        ui_info "QQ $qq_num 未在运行"
        return 0
    fi

    ui_info "正在停止 QQ $qq_num..."
    pkill -f "qq --no-sandbox -q $qq_num" 2>/dev/null
    sleep 2

    # 强制杀死残留进程
    if is_qq_running "$qq_num"; then
        pkill -9 -f "qq --no-sandbox -q $qq_num" 2>/dev/null
        sleep 1
    fi

    # 最终确认
    if is_qq_running "$qq_num"; then
        ui_error "QQ $qq_num 停止失败，请手动处理"
        return 1
    fi

    ui_success "QQ $qq_num 已停止"
}

# ═══════════════════════════════════════════════════════════════
#  交互式操作
# ═══════════════════════════════════════════════════════════════

# 添加新 QQ 账号（同时输入 QQ 号和端口）
add_qq_interactive() {
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

    add_update_qq "$qq_num" "$port"

    if ui_confirm "QQ $qq_num 已添加（端口: $port），是否立即启动？"; then
        start_qq "$qq_num"
    fi
}

# 选择 QQ 号（通用函数，结果存入 _PICKED_QQ）
_pick_qq() {
    local title="$1"
    _PICKED_QQ=""

    # 检查配置文件是否存在且有内容
    if [ ! -f "$NAPCATBOT_FILE" ]; then
        ui_error "没有已配置的 QQ 账号，请先添加"
  ui_pause "按 Enter 返回."
        return 1
    fi

    local count
    count=$(jq 'length' "$NAPCATBOT_FILE" 2>/dev/null)
    if [ -z "$count" ] || [ "$count" -eq 0 ] 2>/dev/null; then
        ui_error "没有已配置的 QQ 账号，请先添加"
  ui_pause "按 Enter 返回."
        return 1
    fi

    local items=()
    while IFS=$'\t' read -r qq display; do
        [ -z "$qq" ] && continue
        items+=("$qq" "$display")
    done < <(jq -r '.[] | "\(.qq)\tQQ: \(.qq) | 端口: \(.port)"' "$NAPCATBOT_FILE" 2>/dev/null)

    if [ ${#items[@]} -eq 0 ]; then
        ui_error "没有已配置的 QQ 账号，请先添加"
  ui_pause "按 Enter 返回."
        return 1
    fi

    _PICKED_QQ=$(ui_select "$title" "选择: " "${items[@]}")
}

# 修改 QQ 配置
modify_qq_interactive() {
    _pick_qq "📋 选择要修改的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    local current_port
    current_port=$(get_qq_port "$selected")

    local new_qq
    new_qq=$(ui_input "QQ 账号" "$selected")
    [ -z "$new_qq" ] && { ui_error "QQ 号不能为空"; return 1; }

    local new_port
    new_port=$(ui_input "端口" "$current_port")
    [ -z "$new_port" ] && new_port="$current_port"

    # 验证端口号
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [ "$new_port" -lt 1 ] || [ "$new_port" -gt 65535 ]; then
        ui_error "端口号无效（1-65535）"
        return 1
    fi

    # 如果 QQ 号变了，删除旧配置
    if [ "$selected" != "$new_qq" ]; then
        stop_qq "$selected" 2>/dev/null
        rm -f "${CONFIG_DIR}/napcat_${selected}.json" "${CONFIG_DIR}/onebot11_${selected}.json"
        if [ -f "$NAPCATBOT_FILE" ]; then
            local tmp="${NAPCATBOT_FILE}.tmp"
            jq --arg qq "$selected" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "$tmp"
            [ $? -eq 0 ] && mv "$tmp" "$NAPCATBOT_FILE" || rm -f "$tmp"
        fi
    fi

    add_update_qq "$new_qq" "$new_port"
}

# 删除 QQ 账号
delete_qq_interactive() {
    _pick_qq "🗑️ 选择要删除的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    if ui_confirm "确定要删除 QQ $selected 吗？\n将同时停止该 QQ 并删除所有配置"; then
        remove_qq "$selected"

        # 确认删除结果
        if [ -f "$NAPCATBOT_FILE" ] && jq -e --arg qq "$selected" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
            ui_error "删除失败，Napcatbot 中仍存在该条目"
        else
            ui_success "QQ $selected 已彻底删除"
        fi
    fi
}

# 选择 QQ 并启动
start_qq_interactive() {
    _pick_qq "🚀 选择要启动的 QQ 账号"
    local selected="$_PICKED_QQ"
    [ -z "$selected" ] && return

    start_qq "$selected" "true"
}

# ═══════════════════════════════════════════════════════════════
#  重装（带版本比较和自动强制重装）
# ═══════════════════════════════════════════════════════════════

reinstall_project() {
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

# ═══════════════════════════════════════════════════════════════
#  卸载
# ═══════════════════════════════════════════════════════════════

uninstall_project() {
    if ! ui_confirm "卸载 NapCat 将会:\n1. 停止所有 QQ 进程\n2. 删除 NapCat 文件\n3. 恢复 QQ 配置\n4. 删除所有账号配置\n\n确定继续？"; then
        return 0
    fi

    ui_info "停止所有 QQ 进程..."
    pkill -f "qq --no-sandbox" 2>/dev/null
    sleep 2
    pkill -9 -f "qq --no-sandbox" 2>/dev/null
    sleep 1

    ui_info "删除 NapCat 文件..."
    rm -rf "$NAPCAT_DIR" 2>/dev/null
    rm -f "$LOAD_NAPCAT_JS"

    ui_info "恢复 QQ 启动配置..."
    if [ -f "${QQ_PACKAGE_JSON}.bak" ]; then
        cp "${QQ_PACKAGE_JSON}.bak" "$QQ_PACKAGE_JSON"
    elif [ -f "$QQ_PACKAGE_JSON" ]; then
        jq '.main = "./launcher.node.js"' "$QQ_PACKAGE_JSON" > /tmp/package.json 2>/dev/null
        mv /tmp/package.json "$QQ_PACKAGE_JSON" 2>/dev/null || true
    fi

    ui_info "删除所有账号配置..."
    # 删除每个 QQ 账号的配置
    local qq_list
    qq_list=$(get_qq_list)
    for qq in $qq_list; do
        rm -f "${CONFIG_DIR}/napcat_${qq}.json"
        rm -f "${CONFIG_DIR}/onebot11_${qq}.json"
    done
    rm -f "$NAPCATBOT_FILE" 2>/dev/null
    rm -f /usr/local/bin/napcat 2>/dev/null

    ui_success "NapCat 已彻底卸载"
}

# ═══════════════════════════════════════════════════════════════
#  交互式主菜单
# ═══════════════════════════════════════════════════════════════

napcat_manage() {
    # 加载依赖
    _nc_load_deps || return 1

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
            1) start_qq_interactive ;;
            2) add_qq_interactive ;;
            3) modify_qq_interactive ;;
            4) delete_qq_interactive ;;
            5) reinstall_project ;;
            6) uninstall_project ;;
            b) break ;;
        esac
    done
}

# ═══════════════════════════════════════════════════════════════
#  状态展示
# ═══════════════════════════════════════════════════════════════

show_all_status() {
    local info=""
    info+="=== NapCat 状态 ===\n"
    if is_installed; then
        info+="安装状态: ✅ 已安装\n"
        local napcat_ver
        napcat_ver=$(jq -r '.version' "$NAPCAT_DIR/package.json" 2>/dev/null)
        [ -n "$napcat_ver" ] && info+="NapCat 版本: v${napcat_ver}\n"
    else
        info+="安装状态: ❌ 未安装\n"
    fi

    info+="\n=== 运行中的 QQ ===\n"
    local running_qqs
    running_qqs=$(get_running_qqs)
    if [ -n "$running_qqs" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && info+="  QQ $qq  🟢 运行中（端口: $(get_qq_port "$qq")）\n"
        done <<< "$running_qqs"
    else
        info+="  无\n"
    fi

    info+="\n=== 已配置的 QQ 账号 ===\n"
    local qq_list
    qq_list=$(get_qq_list)
    if [ -n "$qq_list" ]; then
        while IFS= read -r qq; do
            [ -n "$qq" ] && {
                local port status
                port=$(get_qq_port "$qq")
                if is_qq_running "$qq"; then
                    status="🟢"
                else
                    status="🔴"
                fi
                info+="  ${status} QQ $qq（端口: $port）\n"
            }
        done <<< "$qq_list"
    else
        info+="  无\n"
    fi

    ui_text "$info" "📊 NapCat 状态"
}

# ═══════════════════════════════════════════════════════════════
#  入口
# ═══════════════════════════════════════════════════════════════

if [ "$1" == "--auto" ]; then
    case "$2" in
        start)       start_qq "$3" "true" ;;
        stop)        stop_qq "$3" ;;
        is-installed) is_installed && echo "yes" || echo "no" ;;
        uninstall)   uninstall_project ;;
        *)
            echo "用法: manage.sh --auto {start <qq>|stop <qq>|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    napcat_manage
fi
