#!/bin/bash
# NapCat 管理（UI 层；逻辑在 common.sh）

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"
NapCat_加载配置

UI_BACKTITLE="NapCat · ${UI_BACKTITLE:-Hamster Script}"

_NapCat_状态摘要() {
    local ver count running
    if NapCat_是否就绪; then
        ver=$(jq -r '.version' "${TOOL_INSTALL_DIR}/package.json" 2>/dev/null)
        [[ "$ver" == "null" || -z "$ver" ]] && ver="?"
        count=$(jq 'length' "$NAPCATBOT_FILE" 2>/dev/null || echo 0)
        running=$(NapCat_获取运行中QQ | grep -c . 2>/dev/null || echo 0)
        printf '状态: 已就绪 v%s | 账号 %s | 运行 %s' "$ver" "$count" "$running"
    elif NapCat_是否已安装; then
        printf '状态: 已安装但未完成注入，请重装'
    else
        printf '状态: 未安装'
    fi
}

_NapCat_菜单提示() {
    printf '%s\n\n请选择操作:' "$(_NapCat_状态摘要)"
}

_NapCat_添加或更新QQ() {
    NapCat_添加或更新QQ "$1" "$2" || { 界面警告 "写入 Napcatbot 失败"; return 1; }
    界面完成 "已添加 QQ $1（端口: $2）"
}

_NapCat_移除QQ() {
    NapCat_移除QQ "$1" || { 界面警告 "删除账号失败"; return 1; }
    界面完成 "已删除 QQ $1 的所有配置"
}

_NapCat_启动QQ() {
    local qq_num="$1" bg_mode="${2:-false}" port
    port=$(NapCat_获取QQ端口 "$qq_num")
    [[ -z "$port" ]] && port="${NAPCAT_DEFAULT_PORT:-2537}"

    if NapCat_QQ是否运行 "$qq_num"; then
        界面提示 "QQ $qq_num 已在运行中\n端口: $port" "注意"
        return 0
    fi
    if ! NapCat_是否就绪; then
        界面警告 "NapCat 未正确安装\n请先在项目列表中安装"
        return 1
    fi

    if [[ "$bg_mode" == "true" ]]; then
        if NapCat_启动QQ "$qq_num" true; then
            界面完成 "QQ $qq_num 已在后台启动\n端口: $port"
        else
            界面警告 "QQ $qq_num 启动失败\n请检查 xvfb / QQ 安装"
        fi
    else
        NapCat_启动QQ "$qq_num" false
    fi
}

_NapCat_停止QQ() {
    local qq_num="$1"
    if ! NapCat_QQ是否运行 "$qq_num"; then
        界面提示 "QQ $qq_num 未在运行"
        return 0
    fi
    if NapCat_停止QQ "$qq_num"; then
        界面完成 "QQ $qq_num 已停止"
    else
        界面警告 "QQ $qq_num 停止失败\n请手动检查进程"
        return 1
    fi
}

_NapCat_选择QQ() {
    local title="$1"
    _PICKED_QQ=""

    if [[ ! -f "$NAPCATBOT_FILE" ]]; then
        界面警告 "没有已配置的 QQ 账号\n请先添加账号"
        return 1
    fi

    local count
    count=$(jq 'length' "$NAPCATBOT_FILE" 2>/dev/null)
    if [[ -z "$count" || "$count" -eq 0 ]] 2>/dev/null; then
        界面警告 "没有已配置的 QQ 账号\n请先添加账号"
        return 1
    fi

    local items=() qq port status display
    while IFS=$'\t' read -r qq port; do
        [[ -z "$qq" ]] && continue
        if NapCat_QQ是否运行 "$qq"; then status="运行中"; else status="已停止"; fi
        display="QQ ${qq}  端口 ${port}  [${status}]"
        items+=("$qq" "$display")
    done < <(jq -r '.[] | "\(.qq)\t\(.port)"' "$NAPCATBOT_FILE" 2>/dev/null)

    [[ ${#items[@]} -eq 0 ]] && { 界面警告 "账号列表为空\n请重新添加"; return 1; }
    _PICKED_QQ=$(界面选择 "$title" "选择 QQ 账号:" "${items[@]}")
    界面有选择 "$_PICKED_QQ"
}

_NapCat_交互添加QQ() {
    local qq_num port default_port="${NAPCAT_DEFAULT_PORT:-2537}"

    qq_num=$(界面输入 "请输入 QQ 账号" "")
    [[ -z "$qq_num" ]] && return 0
    if ! [[ "$qq_num" =~ ^[0-9]{5,15}$ ]]; then
        界面警告 "QQ 号格式无效\n请输入 5-15 位数字"
        return 1
    fi

    if [[ -f "$NAPCATBOT_FILE" ]] \
        && jq -e --arg qq "$qq_num" 'any(.[]; .qq == $qq)' "$NAPCATBOT_FILE" &>/dev/null; then
        界面确认 "QQ $qq_num 已存在\n是否覆盖端口配置？" "覆盖确认" || return 0
    fi

    while true; do
        port=$(界面输入 "WebSocket 端口 (1-65535)" "$default_port")
        [[ -z "$port" ]] && port="$default_port"
        if [[ "$port" =~ ^[0-9]+$ ]] && [[ "$port" -ge 1 && "$port" -le 65535 ]]; then break; fi
        界面警告 "端口号无效\n请输入 1-65535 之间的数字"
    done

    _NapCat_添加或更新QQ "$qq_num" "$port" || return 1
    界面确认 "QQ $qq_num 已添加（端口 $port）\n是否立即后台启动？" "启动确认" \
        && _NapCat_启动QQ "$qq_num" true
}

_NapCat_交互修改QQ() {
    _NapCat_选择QQ "修改 QQ 配置" || return 0
    local selected="$_PICKED_QQ" current_port new_qq new_port

    current_port=$(NapCat_获取QQ端口 "$selected")
    new_qq=$(界面输入 "QQ 账号" "$selected")
    [[ -z "$new_qq" ]] && return 0
    if ! [[ "$new_qq" =~ ^[0-9]{5,15}$ ]]; then
        界面警告 "QQ 号格式无效"; return 1
    fi

    new_port=$(界面输入 "WebSocket 端口" "$current_port")
    [[ -z "$new_port" ]] && new_port="$current_port"
    if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
        界面警告 "端口号无效（1-65535）"; return 1
    fi

    if [[ "$selected" != "$new_qq" ]]; then
        NapCat_停止QQ "$selected" 2>/dev/null || true
        rm -f "${CONFIG_DIR}/napcat_${selected}.json" "${CONFIG_DIR}/onebot11_${selected}.json"
        jq --arg qq "$selected" 'map(select(.qq != $qq))' "$NAPCATBOT_FILE" > "${NAPCATBOT_FILE}.tmp" \
            && mv "${NAPCATBOT_FILE}.tmp" "$NAPCATBOT_FILE"
    fi
    _NapCat_添加或更新QQ "$new_qq" "$new_port"
}

_NapCat_交互删除QQ() {
    _NapCat_选择QQ "删除 QQ 账号" || return 0
    界面确认 "确定删除 QQ $_PICKED_QQ ？\n\n将停止进程并删除全部配置" "删除确认" \
        && _NapCat_移除QQ "$_PICKED_QQ"
}

_NapCat_交互启动QQ() { _NapCat_选择QQ "启动 QQ" || return 0; _NapCat_启动QQ "$_PICKED_QQ" true; }
_NapCat_交互停止QQ() { _NapCat_选择QQ "停止 QQ" || return 0; _NapCat_停止QQ "$_PICKED_QQ"; }

_NapCat_重装项目() {
    界面确认 "重装 NapCat 将：\n\n· 停止所有 QQ 进程\n· 重新下载并安装\n· 保留 Napcatbot 账号配置\n\n确定继续？" "重装确认" || return 0
    NapCat_停止全部
    界面清屏
    bash "${TOOL_SCRIPT_DIR}/install.sh"
    界面清屏
    界面完成 "NapCat 重装流程已结束"
}

_NapCat_卸载项目() {
    界面确认 "卸载 NapCat 将清空全部文件与账号配置\n\n此操作不可恢复！" "卸载确认" || return 0
    NapCat_卸载文件
    界面完成 "NapCat 已彻底卸载"
}

_NapCat_显示全部状态() {
    local info="" qq port running napcat_ver
    info+="━━━━━━━━ NapCat ━━━━━━━━\n\n"
    if NapCat_是否就绪; then
        info+="安装:  已就绪\n"
        napcat_ver=$(jq -r '.version' "${TOOL_INSTALL_DIR}/package.json" 2>/dev/null)
        [[ -n "$napcat_ver" && "$napcat_ver" != "null" ]] && info+="版本:  v${napcat_ver}\n"
    elif NapCat_是否已安装; then
        info+="安装:  文件存在，未完成注入\n"
    else
        info+="安装:  未安装\n"
    fi
    info+="\n── 运行中 ──\n"
    running=$(NapCat_获取运行中QQ)
    if [[ -n "$running" ]]; then
        while IFS= read -r qq; do
            [[ -n "$qq" ]] && info+="  [运行] QQ ${qq}  端口 $(NapCat_获取QQ端口 "$qq")\n"
        done <<< "$running"
    else
        info+="  (无)\n"
    fi
    info+="\n── 已配置账号 ──\n"
    local qq_list
    qq_list=$(NapCat_获取QQ列表)
    if [[ -n "$qq_list" ]]; then
        while IFS= read -r qq; do
            [[ -z "$qq" ]] && continue
            port=$(NapCat_获取QQ端口 "$qq")
            if NapCat_QQ是否运行 "$qq"; then info+="  [运行] QQ ${qq}  端口 ${port}\n"
            else info+="  [停止] QQ ${qq}  端口 ${port}\n"; fi
        done <<< "$qq_list"
    else
        info+="  (无)\n"
    fi
    info+="\n启动: nt [QQ号] [端口]\n配置: ${CONFIG_DIR}\n"
    界面文本 "$info" "NapCat 状态"
}

_NapCat_管理() {
    while true; do
        local choice
        choice=$(界面子菜单 "NapCat 管理" "$(_NapCat_菜单提示)" \
            "1" "启动 QQ" "2" "停止 QQ" "3" "添加账号" "4" "修改配置" \
            "5" "删除账号" "6" "查看状态" "7" "重装 NapCat" "8" "卸载 NapCat")
        case "$choice" in
            1) _NapCat_交互启动QQ ;;
            2) _NapCat_交互停止QQ ;;
            3) _NapCat_交互添加QQ ;;
            4) _NapCat_交互修改QQ ;;
            5) _NapCat_交互删除QQ ;;
            6) _NapCat_显示全部状态 ;;
            7) _NapCat_重装项目 ;;
            8) _NapCat_卸载项目 && exit 0 ;;
            b|"") exit 0 ;;
        esac
    done
}

if [[ "$1" == "--auto" ]]; then
    case "$2" in
        start)        _NapCat_启动QQ "$3" "true" ;;
        stop)         _NapCat_停止QQ "$3" ;;
        is-installed) NapCat_是否就绪 && echo "yes" || echo "no" ;;
        uninstall)    _NapCat_卸载项目 ;;
        *) echo "用法: manage.sh --auto {start <qq>|stop <qq>|is-installed|uninstall}"; exit 1 ;;
    esac
else
    _NapCat_管理
fi
