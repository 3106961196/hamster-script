#!/bin/bash
# NapCat 管理（UI 层；逻辑在 common.sh / security.sh）
# 对齐 xrk nt：多 QQ · 多框架 · WebUI

_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=/dev/null
source "$_root/lib/core.sh"
工具引导
工具_加载 "${BASH_SOURCE[0]}"
NapCat_加载配置
NapCat_确保Bot

UI_BACKTITLE="NapCat · ${UI_BACKTITLE:-Hamster Script}"

# dialog 结果写 stderr；用临时文件捕获（对齐 xrk nt_dialog_capture，避免 form 丢字段）
_NapCat_dialog捕获() {
    local __var=$1; shift
    local tmp __out __st=0
    tmp="$(mktemp "${TMPDIR:-/tmp}/napcat_dialog.XXXXXX")"
    dialog --clear --backtitle "$UI_BACKTITLE" "$@" 2>"$tmp" >/dev/tty || __st=$?
    __out="$(cat "$tmp")"
    rm -f "$tmp"
    printf -v "$__var" '%s' "$__out"
    return "$__st"
}

_NapCat_字段修剪() {
    local s="$1"
    s="${s//$'\r'/}"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# 解析 dialog --form：每行一字段；尾部空字段可能无换行
_NapCat_解析表单() {
    local values="$1" expect="$2"
    shift 2
    local -a names=("$@") fields=() out=() line i n
    mapfile -t fields <<< "$values"
    for line in "${fields[@]}"; do
        out+=("$(_NapCat_字段修剪 "$line")")
    done
    if [[ ${#out[@]} -eq $((expect + 1)) && -z "${out[$expect]:-}" ]]; then
        unset "out[$expect]"
    fi
    while [[ ${#out[@]} -lt "$expect" ]]; do
        out+=("")
    done
    n="${#out[@]}"
    if [[ "$n" -gt "$expect" ]]; then
        NAPCAT_LAST_ERR="表单字段过多(期望${expect}行,实际${n})"
        return 1
    fi
    for i in $(seq 0 $((expect - 1))); do
        [[ -n "${out[$i]:-}" ]] && break
        [[ "$i" -eq $((expect - 1)) ]] && { NAPCAT_LAST_ERR="表单为空"; return 1; }
    done
    for i in $(seq 0 $((expect - 1))); do
        printf -v "${names[$i]}" '%s' "${out[$i]}"
    done
}

_NapCat_表单默认() {
    printf '%s' "$1" | tr -d '\r\n' | tr '"' "'"
}

_NapCat_框架菜单项() {
    napcat_load_prefs | jq -r '.frameworks[]? | "\(.id)|\(.label)|\(.default_port)"'
}

_NapCat_选择QQ() {
    local title="$1"
    _PICKED_QQ=""
    NapCat_确保Bot

    local items=() qq summary idx=1 selected
    local -a qq_list=()
    local list
    list=$(NapCat_获取QQ列表)
    if [[ -z "$list" ]]; then
        界面警告 "没有已配置的 QQ 账号\n请先添加账号"
        return 1
    fi

    while IFS= read -r qq; do
        [[ -z "$qq" ]] && continue
        summary="$(napcat_qq_links_summary "$(NapCat_QQ配置文件 "$qq")")"
        qq_list+=("$qq")
        items+=("$idx" "QQ ${qq}  ${summary}")
        idx=$((idx + 1))
    done <<< "$list"

    [[ ${#items[@]} -eq 0 ]] && { 界面警告 "账号列表为空"; return 1; }
    selected=$(界面选择 "$title" "选择 QQ 账号:" "${items[@]}")
    界面有选择 "$selected" || return 1
    if ! [[ "$selected" =~ ^[0-9]+$ ]] || [[ "$selected" -lt 1 || "$selected" -gt ${#qq_list[@]} ]]; then
        return 1
    fi
    _PICKED_QQ="${qq_list[$((selected - 1))]}"
}

_NapCat_端口在听() {
    local port="$1"
    [[ "$port" =~ ^[0-9]+$ ]] || return 1
    if command -v ss >/dev/null 2>&1; then
        ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$" && return 0
    fi
    if command -v netstat >/dev/null 2>&1; then
        netstat -ltn 2>/dev/null | awk '{print $4}' | grep -qE ":${port}$" && return 0
    fi
    return 1
}

# 勾选框架：展示 名称 · :端口 · 运行中/未启动；未启动也可选
_NapCat_勾选框架() {
    local qq="${1:-}" raw old="" id label port state items=() run_tag
    napcat_refresh_frameworks >/dev/null 2>&1 || true
    [[ -n "$qq" && -f "$(NapCat_QQ配置文件 "$qq")" ]] && \
        old="$(jq -r '.links[]?|select((.enabled==true) or (.enabled=="true") or (.enabled==null))|.framework_id' \
            "$(NapCat_QQ配置文件 "$qq")" 2>/dev/null || true)"

    while IFS='|' read -r id label port; do
        [[ -z "$id" ]] && continue
        port="$(napcat_coerce_port "$port" "2537")"
        state=off
        echo "$old" | grep -qxF "$id" && state=on
        if _NapCat_端口在听 "$port"; then
            run_tag="运行中"
        else
            run_tag="未启动"
        fi
        items+=("$id" "${label} · :${port} · ${run_tag}" "$state")
    done < <(_NapCat_框架菜单项)

    if [[ ${#items[@]} -eq 0 ]]; then
        界面警告 "未检测到框架\n请确认已安装 XRK-AGT / Yunzai 等"
        return 1
    fi

    raw=$(界面多选 "连接框架" "空格切换 · 回车确认 · 可多选（未启动也可选）" "${items[@]}") || return 1
    [[ -z "$raw" ]] && return 1
    printf '%s' "$raw"
}

_NapCat_由勾选生成Links() {
    local qq="$1" raw="$2" old='[]' links='[]' id fw port token root
    [[ -f "$(NapCat_QQ配置文件 "$qq")" ]] && old="$(jq -c '.links // []' "$(NapCat_QQ配置文件 "$qq")")"
    old="$(napcat_json_or "$old" '[]')"
    while IFS= read -r id; do
        id="${id//$'\r'/}"
        id="${id#"${id%%[![:space:]]*}"}"
        id="${id%"${id##*[![:space:]]}"}"
        [[ -z "$id" ]] && continue
        fw="$(napcat_get_framework "$id" 2>/dev/null)" || continue
        [[ -n "$fw" ]] || continue
        root="$(echo "$fw" | jq -r '.root // empty')"
        [[ -n "$root" ]] || continue
        # 端口跟框架走；若该 QQ 曾绑定过同框架则保留原端口
        port="$(echo "$old" | jq -r --arg id "$id" '.[]|select(.framework_id==$id)|.port//empty' | head -n1)"
        [[ -z "$port" ]] && port="$(echo "$fw" | jq -r '.default_port // empty')"
        port="$(napcat_coerce_port "$port" "$(napcat_guess_framework_port "$root")")"
        token=""
        links="$(jq -n --argjson a "$(napcat_json_or "$links" '[]')" --arg id "$id" --argjson port "$port" --arg token "$token" \
            '$a + [{framework_id:$id,enabled:true,port:$port,token:$token}]')" || continue
    done <<< "$raw"
    printf '%s' "$(napcat_json_or "$links" '[]')"
}

# 保存绑定并尽量同步 onebot（有 QQ 在跑则只保存）
_NapCat_保存并同步() {
    local qq="$1" links="$2" old_qq="${3:-}"
    NapCat_保存QQ配置 "$qq" "$links" "" "$old_qq" || {
        界面警告 "保存失败\n${NAPCAT_LAST_ERR:-}"
        return 1
    }
    if ! NapCat_是否运行中; then
        NapCat_准备运行时 "$qq" || {
            界面警告 "QQ 已保存，但 onebot 同步失败\n${NAPCAT_LAST_ERR:-}\n关掉前台 QQ 窗口后重试，或: nt --sync-onebot $qq"
            return 1
        }
    else
        界面警告 "QQ 已保存\n有 QQ 在前台运行，未写入 onebot\n关掉窗口后启动或: nt --sync-onebot $qq"
    fi
    return 0
}

_NapCat_交互添加QQ() {
    local wqq checklist links
    _WIZARD_QQ=""
    wqq=$(界面输入 "QQ 账号" "")
    wqq="$(_NapCat_字段修剪 "${wqq:-}")"
    [[ -z "$wqq" ]] && return 0
    if ! [[ "$wqq" =~ ^[0-9]{5,15}$ ]]; then
        界面警告 "QQ 号格式无效\n请输入 5-15 位数字"
        return 1
    fi
    if [[ -f "$(NapCat_QQ配置文件 "$wqq")" ]]; then
        界面警告 "QQ $wqq 已存在\n请到「管理 QQ」修改连接，或先删除"
        return 1
    fi

    checklist="$(_NapCat_勾选框架)" || return 0
    links="$(_NapCat_由勾选生成Links "$wqq" "$checklist")"
    if [[ "$(echo "$links" | jq 'length')" -eq 0 ]]; then
        界面警告 "请至少选择一个框架"
        return 1
    fi

    _NapCat_保存并同步 "$wqq" "$links" || return 1
    _WIZARD_QQ="$wqq"
    界面完成 "已保存 QQ $_WIZARD_QQ\n登录：扫码（无需 Token）"
    if 界面确认 "立即启动 $_WIZARD_QQ？" "启动确认"; then
        NapCat_是否就绪 || { 界面警告 "NapCat 未正确安装"; return 1; }
        NapCat_启动QQ "$_WIZARD_QQ"
    fi
}

_NapCat_交互修改连接() {
    local qq="${1:-}" checklist links
    if [[ -z "$qq" ]]; then
        _NapCat_选择QQ "修改框架连接" || return 0
        qq="$_PICKED_QQ"
    fi
    [[ -f "$(NapCat_QQ配置文件 "$qq")" ]] || {
        界面警告 "找不到 QQ $qq 配置"
        return 1
    }
    checklist="$(_NapCat_勾选框架 "$qq")" || return 0
    links="$(_NapCat_由勾选生成Links "$qq" "$checklist")"
    if [[ "$(echo "$links" | jq 'length')" -eq 0 ]]; then
        界面警告 "请至少选择一个框架"
        return 1
    fi
    _NapCat_保存并同步 "$qq" "$links" || return 1
    界面完成 "已更新 QQ $qq 的框架连接"
}

_NapCat_交互删除QQ() {
    local qq="${1:-}"
    if [[ -z "$qq" ]]; then
        _NapCat_选择QQ "删除 QQ 账号" || return 0
        qq="$_PICKED_QQ"
    fi
    界面确认 "确定删除 QQ ${qq} ？\n\n将删除：\n· 脚本绑定 qq_${qq}.json\n· onebot/napcat 运行配置\n\n若该号在前台跑着，请先关掉对应 tmux 窗格" "删除确认" || return 0
    if ! NapCat_移除QQ "$qq"; then
        界面警告 "删除失败\n${NAPCAT_LAST_ERR:-未知错误}"
        return 1
    fi
    界面完成 "已删除 QQ $qq"
}

_NapCat_交互启动QQ() {
    _NapCat_选择QQ "启动 QQ" || return 0
    NapCat_是否就绪 || {
        界面警告 "NapCat 未正确安装\n请先在项目列表中安装"
        return 1
    }
    NapCat_启动QQ "$_PICKED_QQ"
}

_NapCat_交互停止QQ() {
    _NapCat_选择QQ "停止 QQ" || return 0
    NapCat_停止QQ "$_PICKED_QQ" || {
        界面警告 "QQ $_PICKED_QQ 停止失败\n请手动检查进程"
        return 1
    }
    界面完成 "QQ $_PICKED_QQ 已停止"
}

_NapCat_添加框架交互() {
    local path port label id prefs fw
    path=$(界面输入 "框架根目录" "${HOME:-/root}")
    [[ -z "$path" || ! -d "$path" ]] && { 界面警告 "目录无效"; return 1; }
    port=$(界面输入 "默认端口" "$(napcat_guess_framework_port "$path")")
    [[ -z "$port" ]] && port="$(napcat_guess_framework_port "$path")"
    port="$(napcat_coerce_port "$port" "$(napcat_guess_framework_port "$path")")"
    [[ "$port" =~ ^[0-9]+$ ]] || { 界面警告 "端口无效"; return 1; }
    label="$(napcat_framework_label "$path")"
    id="$(napcat_framework_id_from_root "$path")"
    # jq≤1.6：label 是保留字，不能用 --arg label / $label
    fw="$(jq -n --arg id "$id" --arg fw_label "$label" --arg root "$path" --argjson port "$port" \
        '{id:$id,"label":$fw_label,root:$root,default_port:$port,ws_host:"127.0.0.1",ws_path:"OneBotv11"}')" || {
        界面警告 "生成框架 JSON 失败"; return 1
    }
    prefs="$(napcat_json_or "$(napcat_load_prefs)" '{}')"
    napcat_save_prefs "$(echo "$prefs" | jq --argjson fw "$fw" \
        '.frameworks = ([.frameworks[]|select(.root!=$fw.root)] + [$fw])')" \
        || { 界面警告 "${NAPCAT_LAST_ERR:-保存失败}"; return 1; }
    界面完成 "已添加 $label"
}

_NapCat_框架管理() {
    napcat_refresh_frameworks >/dev/null 2>&1 || true
    local items=() id label port sel prefs fw new_port fw_count cur_port

    while true; do
        fw_count="$(napcat_json_or "$(napcat_load_prefs)" '{"frameworks":[]}' | jq '.frameworks|length')"
        if [[ "${fw_count:-0}" -eq 0 ]]; then
            sel=$(界面子菜单 "框架管理" "未扫描到框架，请先扫描或手动添加:" \
                "scan" "扫描磁盘" "add" "手动添加目录")
            case "$sel" in
                b|"") return 0 ;;
                scan)
                    napcat_refresh_frameworks >/dev/null
                    界面完成 "扫描完成"
                    ;;
                add) _NapCat_添加框架交互 || true ;;
            esac
            continue
        fi

        items=("scan" "重新扫描磁盘" "add" "手动添加目录" "port" "改默认端口" "del" "移除框架")
        while IFS='|' read -r id label port; do
            [[ -z "$id" ]] && continue
            items+=("$id" "$label :$port")
        done < <(_NapCat_框架菜单项)

        sel=$(界面子菜单 "框架管理" "已注册框架 / 操作:" "${items[@]}")
        case "$sel" in
            b|"") return 0 ;;
            scan)
                napcat_refresh_frameworks >/dev/null
                界面完成 "扫描完成"
                ;;
            add) _NapCat_添加框架交互 || true ;;
            port)
                items=()
                while IFS='|' read -r id label _; do items+=("$id" "$label"); done < <(_NapCat_框架菜单项)
                [[ ${#items[@]} -eq 0 ]] && { 界面警告 "无框架"; continue; }
                id=$(界面选择 "改端口" "选择框架:" "${items[@]}")
                界面有选择 "$id" || continue
                fw="$(napcat_get_framework "$id" 2>/dev/null)" || { 界面警告 "框架无效，请重新扫描"; continue; }
                cur_port="$(echo "$fw" | jq -r '.default_port // empty')"
                new_port=$(界面输入 "新默认端口" "$(napcat_coerce_port "$cur_port" 2537)")
                new_port="$(napcat_coerce_port "$new_port" "")"
                [[ "$new_port" =~ ^[0-9]+$ ]] || { 界面警告 "端口无效"; continue; }
                prefs="$(napcat_json_or "$(napcat_load_prefs)" '{}')"
                napcat_save_prefs "$(echo "$prefs" | jq --arg id "$id" --argjson port "$new_port" \
                    '.frameworks = [.frameworks[]|if .id==$id then .default_port=$port else . end]')" \
                    || { 界面警告 "${NAPCAT_LAST_ERR:-保存失败}"; continue; }
                if 界面确认 "同步已有 QQ 绑定中该框架的端口？"; then
                    napcat_sync_qq_link_ports "$id" "$new_port"
                    界面完成 "已更新并同步 QQ 绑定"
                else
                    界面完成 "已更新框架默认端口"
                fi
                ;;
            del)
                items=()
                while IFS='|' read -r id label _; do items+=("$id" "$label"); done < <(_NapCat_框架菜单项)
                [[ ${#items[@]} -eq 0 ]] && { 界面警告 "无框架"; continue; }
                id=$(界面选择 "移除框架" "选择:" "${items[@]}")
                界面有选择 "$id" || continue
                界面确认 "确认移除 $id？" || continue
                prefs="$(napcat_json_or "$(napcat_load_prefs)" '{}')"
                napcat_save_prefs "$(echo "$prefs" | jq --arg id "$id" '.frameworks = [.frameworks[]|select(.id!=$id)]')"
                界面完成 "已移除"
                ;;
            *)
                fw="$(napcat_get_framework "$sel" 2>/dev/null || true)"
                [[ -z "$fw" ]] && continue
                界面文本 "$(echo "$fw" | jq -r \
                    '"名称: \(.label)\n目录: \(.root)\n端口: \(.default_port)\napi_key: \(.root)/config/server_config/api_key.json"')" \
                    "框架详情"
                ;;
        esac
    done
}

_NapCat_WebUI菜单() {
    local prefs h p t r dp eff wf new_prefs url show_token values st dp_json=false dp_saved

    if NapCat_是否运行中; then
        界面警告 "NapCat/QQ 正在运行\n\n运行中 WebUI 会按内存配置写回 webui.json\n请先停止 QQ 再改"
        return 1
    fi

    prefs="$(napcat_load_prefs)" || true
    prefs="$(napcat_json_or "$prefs" "")"
    if [[ -n "${NAPCAT_LAST_ERR:-}" ]]; then
        界面警告 "加载配置时出现问题（已用默认值继续）\n${NAPCAT_LAST_ERR}"
        NAPCAT_LAST_ERR=""
    fi
    [[ -z "$prefs" ]] && { 界面警告 "无法加载 napcat_prefs.json"; return 1; }
    eff="$(napcat_webui_effective)"
    show_token="$(_NapCat_表单默认 "$(echo "$eff" | jq -r '.token // ""')")"

    _NapCat_dialog捕获 values --title "WebUI（全局）" --form \
        "读取 webui.json · 仅改 host/port/token/loginRate · 保留 theme 等" 18 68 5 \
        "监听地址:" 1 1 "$(_NapCat_表单默认 "$(echo "$eff" | jq -r '.host')")" 1 14 44 0 \
        "端口:"     2 1 "$(_NapCat_表单默认 "$(echo "$eff" | jq -r '.port')")" 2 14 44 0 \
        "Token:"    3 1 "$show_token" 3 14 44 0 \
        "限速/分:"  4 1 "$(_NapCat_表单默认 "$(echo "$eff" | jq -r '.loginRate')")" 4 14 44 0 \
        "禁用pty:"  5 1 "$(_NapCat_表单默认 "$(echo "$prefs" | jq -r 'if .disable_pty then "yes" else "no" end')")" 5 14 44 0
    st=$?
    case $st in
        0) ;;
        1) return 0 ;;
        *) 界面警告 "对话框打开失败 (exit=$st)\n${values:-请检查 Token 是否含特殊字符}"; return 1 ;;
    esac

    if [[ -z "$(printf '%s' "$values" | tr -d '[:space:]')" ]]; then
        界面警告 "未读到表单输入（dialog 返回值丢失）"
        return 1
    fi

    _NapCat_解析表单 "$values" 5 h p t r dp || {
        界面警告 "WebUI 表单解析失败\n${NAPCAT_LAST_ERR:-}"
        return 1
    }
    h="$(_NapCat_字段修剪 "$h")"
    [[ -n "$h" ]] || { 界面警告 "监听地址为空"; return 1; }
    [[ -z "$t" ]] && t="$(echo "$eff" | jq -r '.token // ""')"
    p="$(napcat_coerce_port "$(_NapCat_字段修剪 "$p")" "$(echo "$eff" | jq -r '.port // 4071')")"
    r="$(napcat_coerce_port "$(_NapCat_字段修剪 "$r")" "3")"

    case "$(printf '%s' "$dp" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
        y|yes|1|true|是) dp_json=true ;;
    esac

    if ! new_prefs="$(echo "$prefs" | jq \
        --arg h "$h" --argjson p "$p" --arg t "$t" --argjson r "$r" --argjson dp "$dp_json" \
        '.webui_host=$h|.webui_port=$p|.webui_token=$t|.login_rate=$r|.disable_pty=$dp' 2>&1)"; then
        界面警告 "合并配置失败\n$new_prefs"
        return 1
    fi
    napcat_save_prefs "$new_prefs" || {
        界面警告 "保存 prefs 失败\n${NAPCAT_LAST_ERR:-}"
        return 1
    }
    napcat_apply_webui || {
        界面警告 "写入 webui.json 失败\n${NAPCAT_LAST_ERR:-}\n目标: $(napcat_webui_file)"
        return 1
    }
    wf="$(napcat_webui_file)"
    new_prefs="$(echo "$new_prefs" | jq --arg t "$(jq -r '.token // ""' "$wf")" '.webui_token=$t')"
    napcat_save_prefs "$new_prefs"
    eff="$(napcat_webui_effective)"
    dp_saved="$(echo "$new_prefs" | jq -r 'if .disable_pty then "yes" else "no" end')"
    if url="$(napcat_webui_url 2>/dev/null)"; then
        界面完成 "已保存\n\nhost=$(echo "$eff"|jq -r .host)\nport=$(echo "$eff"|jq -r .port)\nloginRate=$(echo "$eff"|jq -r .loginRate)\ndisable_pty=$dp_saved\n\n$url"
    else
        界面完成 "WebUI 已关闭（port=0）\ndisable_pty=$dp_saved\n$wf"
    fi
}

_NapCat_显示全部状态() {
    local tmp info
    tmp="$(mktemp)"
    {
        if NapCat_是否就绪; then
            echo "安装: 已就绪  v$(jq -r '.version' "${TOOL_INSTALL_DIR}/package.json" 2>/dev/null)"
            echo "目录: ${TOOL_INSTALL_DIR}"
        elif NapCat_是否已安装; then
            echo "安装: 文件存在，未完成注入"
            echo "目录: ${TOOL_INSTALL_DIR}"
        else
            echo "安装: 未安装"
            echo "将安装到: ${TOOL_INSTALL_DIR}"
        fi
        echo ""
        echo "运行中 QQ:"
        local running qq
        running=$(NapCat_获取运行中QQ)
        if [[ -n "$running" ]]; then
            while IFS= read -r qq; do
                [[ -n "$qq" ]] && echo "  [运行] $qq"
            done <<< "$running"
        else
            echo "  (无)"
        fi
        echo ""
        napcat_status_text
        echo ""
        echo "启动: nt <QQ号>"
        echo "同步: nt --sync-onebot <QQ>"
        echo "WebUI: nt --webui-apply"
    } > "$tmp"
    info="$(cat "$tmp")"
    rm -f "$tmp"
    界面文本 "$info" "NapCat 状态"
}

_NapCat_重装项目() {
    界面确认 "重装 NapCat 将：\n\n· 停止所有 QQ 进程\n· 重新下载并安装 NapCat + LinuxQQ\n· 保留 data/napcat 下 QQ 绑定\n\n确定继续？" "重装确认" || return 0
    NapCat_停止全部
    界面清屏
    bash "${TOOL_SCRIPT_DIR}/install.sh" --force
    界面清屏
    界面完成 "NapCat 重装流程已结束"
}

_NapCat_卸载项目() {
    界面确认 "卸载 NapCat 将清空：\n\n· ${TOOL_INSTALL_DIR}\n· QQ 注入（loadNapCat.js）\n\nLinuxQQ（${QQ_ROOT}）与脚本侧 QQ 绑定默认保留\n\n确定？" "卸载确认" || return 0
    NapCat_卸载文件
    if 界面确认 "同时删除脚本侧 QQ 绑定与 prefs？\n$(napcat_qq_dir)"; then
        rm -rf "$(napcat_qq_dir)" 2>/dev/null || true
    fi
    界面完成 "NapCat 已卸载"
}

_NapCat_更新NapCat() {
    界面确认 "更新 NapCat Shell？\n\n仅当有新版本时覆盖\n保留 QQ 绑定与 LinuxQQ" "更新 NapCat" || return 0
    界面清屏
    if NapCat_执行仅Shell n; then
        界面完成 "NapCat 更新完成\n${TOOL_INSTALL_DIR}"
    else
        界面警告 "更新失败\n${NAPCAT_LAST_ERR:-请查看上方日志}"
    fi
}

_NapCat_重装NapCat() {
    界面确认 "强制重装 NapCat Shell？\n\n将覆盖 ${TOOL_INSTALL_DIR}\n保留 QQ 绑定" "重装 NapCat" || return 0
    NapCat_停止全部
    界面清屏
    if NapCat_执行仅Shell y; then
        界面完成 "NapCat 重装完成"
    else
        界面警告 "重装失败\n${NAPCAT_LAST_ERR:-请查看上方日志}"
    fi
}

_NapCat_更新LinuxQQ() {
    界面确认 "更新 LinuxQQ？\n\n仅当版本过旧时重装客户端\n完成后会重新注入 NapCat" "更新 LinuxQQ" || return 0
    界面清屏
    if NapCat_执行仅LinuxQQ n y; then
        界面完成 "LinuxQQ 更新完成\n${QQ_ROOT}"
    else
        界面警告 "更新失败\n${NAPCAT_LAST_ERR:-请查看上方日志}"
    fi
}

_NapCat_重装LinuxQQ() {
    界面确认 "强制重装 LinuxQQ？\n\n将重装 ${QQ_ROOT}\n完成后重新注入 NapCat" "重装 LinuxQQ" || return 0
    NapCat_停止全部
    界面清屏
    if NapCat_执行仅LinuxQQ y y; then
        界面完成 "LinuxQQ 重装完成"
    else
        界面警告 "重装失败\n${NAPCAT_LAST_ERR:-请查看上方日志}"
    fi
}

_NapCat_卸载LinuxQQ交互() {
    界面确认 "卸载 LinuxQQ 客户端？\n\n· 停止 QQ 进程\n· 卸载 linuxqq 包\n· 恢复 QQ 注入\n\nNapCat 目录与账号绑定保留\n\n确定？" "卸载 LinuxQQ" || return 0
    界面清屏
    NapCat_卸载LinuxQQ
    界面完成 "LinuxQQ 已卸载"
}

_NapCat_高级菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "高级" "较少使用:" \
            "1" "框架管理" \
            "2" "WebUI" \
            "3" "查看状态")
        case "$choice" in
            1) _NapCat_框架管理 ;;
            2) _NapCat_WebUI菜单 ;;
            3) _NapCat_显示全部状态 ;;
            b|"") return 0 ;;
        esac
    done
}

# 主屏副标题：账号数 / 运行数
_NapCat_主屏摘要() {
    local total=0 running=0 q
    while IFS= read -r q; do
        [[ -z "$q" ]] && continue
        total=$((total + 1))
        NapCat_QQ是否运行 "$q" && running=$((running + 1))
    done < <(NapCat_获取QQ列表 2>/dev/null)
    printf '账号 %s · 运行中 %s' "$total" "$running"
}

# 管理 QQ：账号列表 → 改连接 / 删除
_NapCat_管理QQ菜单() {
    while true; do
        local items=() qq summary run_tag list sel act
        local -a qq_list=()
        list=$(NapCat_获取QQ列表)
        if [[ -z "$list" ]]; then
            界面警告 "还没有 QQ 账号\n请先「新增 QQ」"
            return 0
        fi
        while IFS= read -r qq; do
            [[ -z "$qq" ]] && continue
            summary="$(napcat_qq_links_summary "$(NapCat_QQ配置文件 "$qq")")"
            if NapCat_QQ是否运行 "$qq"; then
                run_tag="运行中"
            else
                run_tag="未运行"
            fi
            qq_list+=("$qq")
            items+=("$qq" "${qq} · ${summary} · ${run_tag}")
        done <<< "$list"

        sel=$(界面子菜单 "管理 QQ" "$(_NapCat_主屏摘要)" "${items[@]}")
        case "$sel" in
            b|"") return 0 ;;
        esac
        [[ -n "$sel" ]] || continue
        [[ -f "$(NapCat_QQ配置文件 "$sel")" ]] || continue

        act=$(界面子菜单 "QQ ${sel}" "$(napcat_qq_links_summary "$(NapCat_QQ配置文件 "$sel")")" \
            "1" "修改框架连接" \
            "2" "删除账号")
        case "$act" in
            1) _NapCat_交互修改连接 "$sel" ;;
            2) _NapCat_交互删除QQ "$sel" ;;
            b|"") ;;
        esac
    done
}

_NapCat_NapCat管理菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "NapCat 管理" "更新 · 重装 · 卸载:" \
            "1" "更新 NapCat" \
            "2" "重装 NapCat" \
            "3" "更新 LinuxQQ" \
            "4" "重装 LinuxQQ" \
            "5" "卸载 NapCat" \
            "6" "卸载 LinuxQQ" \
            "7" "高级")
        case "$choice" in
            1) _NapCat_更新NapCat ;;
            2) _NapCat_重装NapCat ;;
            3) _NapCat_更新LinuxQQ ;;
            4) _NapCat_重装LinuxQQ ;;
            5) _NapCat_卸载项目 && exit 0 ;;
            6) _NapCat_卸载LinuxQQ交互 ;;
            7) _NapCat_高级菜单 ;;
            b|"") return 0 ;;
        esac
    done
}

_NapCat_管理() {
    while true; do
        local choice
        choice=$(界面选择 "NapCat" "$(_NapCat_主屏摘要)" \
            "1" "启动" \
            "2" "新增 QQ" \
            "3" "管理 QQ" \
            "4" "NapCat 管理" \
            "5" "返回")
        case "$choice" in
            1) _NapCat_交互启动QQ ;;
            2) _NapCat_交互添加QQ ;;
            3) _NapCat_管理QQ菜单 ;;
            4) _NapCat_NapCat管理菜单 ;;
            5|b|"") exit 0 ;;
        esac
    done
}

if [[ "$1" == "--auto" ]]; then
    case "$2" in
        start)
            NapCat_启动QQ "$3"
            ;;
        stop)
            NapCat_停止QQ "$3"
            ;;
        stop-all)
            NapCat_停止全部
            ;;
        sync-onebot)
            [[ -n "${3:-}" ]] || { echo "用法: manage.sh --auto sync-onebot <qq>"; exit 1; }
            if NapCat_是否运行中; then
                echo "[nt] QQ 正在运行，请先 stop 再同步" >&2
                exit 1
            fi
            NapCat_准备运行时 "$3" || {
                echo "[nt ERROR] ${NAPCAT_LAST_ERR:-同步失败}" >&2
                exit 1
            }
            echo "[nt] onebot 已同步"
            napcat_format_connection_lines "$(NapCat_QQ配置文件 "$3")" | sed 's/^/  /'
            ;;
        webui-apply)
            if NapCat_是否运行中; then
                echo "[nt] NapCat/QQ 正在运行，请先 stop 再改 WebUI" >&2
                exit 1
            fi
            napcat_apply_webui || {
                echo "[nt] ${NAPCAT_LAST_ERR:-apply failed}" >&2
                exit 1
            }
            echo "[nt] webui 已写入: $(napcat_webui_file)"
            ;;
        is-installed)
            NapCat_是否就绪 && echo "yes" || echo "no"
            ;;
        uninstall)
            _NapCat_卸载项目
            ;;
        *)
            echo "用法: manage.sh --auto {start <qq>|stop <qq>|stop-all|sync-onebot <qq>|webui-apply|is-installed|uninstall}"
            exit 1
            ;;
    esac
else
    _NapCat_管理
fi
