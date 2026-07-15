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

    local items=() qq summary
    local list
    list=$(NapCat_获取QQ列表)
    if [[ -z "$list" ]]; then
        界面警告 "没有已配置的 QQ 账号\n请先添加账号"
        return 1
    fi

    while IFS= read -r qq; do
        [[ -z "$qq" ]] && continue
        summary="$(napcat_qq_links_summary "$(NapCat_QQ配置文件 "$qq")")"
        items+=("$qq" "QQ ${qq}  ${summary}")
    done <<< "$list"

    [[ ${#items[@]} -eq 0 ]] && { 界面警告 "账号列表为空"; return 1; }
    _PICKED_QQ=$(界面选择 "$title" "选择 QQ 账号:" "${items[@]}")
    界面有选择 "$_PICKED_QQ"
}

_NapCat_勾选框架() {
    local qq="${1:-}" raw old="" id label port state items=()
    [[ -n "$qq" && -f "$(NapCat_QQ配置文件 "$qq")" ]] && \
        old="$(jq -r '.links[]?|select((.enabled==true) or (.enabled=="true") or (.enabled==null))|.framework_id' \
            "$(NapCat_QQ配置文件 "$qq")" 2>/dev/null || true)"

    while IFS='|' read -r id label port; do
        [[ -z "$id" ]] && continue
        state=off
        echo "$old" | grep -qxF "$id" && state=on
        items+=("$id" "$label · :$port" "$state")
    done < <(_NapCat_框架菜单项)

    if [[ ${#items[@]} -eq 0 ]]; then
        界面警告 "未注册框架\n请先在「框架管理」扫描或添加"
        return 1
    fi

    raw=$(界面多选 "连接框架" "空格切换 · 回车确认 · 可多选" "${items[@]}") || return 1
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
        port="$(echo "$old" | jq -r --arg id "$id" '.[]|select(.framework_id==$id)|.port//empty' | head -n1)"
        [[ -z "$port" ]] && port="$(echo "$fw" | jq -r '.default_port // empty')"
        port="$(napcat_coerce_port "$port" "$(napcat_guess_framework_port "$root")")"
        token="$(echo "$old" | jq -r --arg id "$id" '.[]|select(.framework_id==$id)|.token//""' | head -n1)"
        links="$(jq -n --argjson a "$(napcat_json_or "$links" '[]')" --arg id "$id" --argjson port "$port" --arg token "${token:-}" \
            '$a + [{framework_id:$id,enabled:true,port:$port,token:$token}]')" || continue
    done <<< "$raw"
    printf '%s' "$(napcat_json_or "$links" '[]')"
}

_NapCat_微调端口() {
    local links="$1" out='[]' link id fw label port new_port root
    links="$(napcat_json_or "$links" '[]')"
    while IFS= read -r link; do
        [[ -z "$link" ]] && continue
        id="$(echo "$link" | jq -r '.framework_id // empty')"
        [[ -n "$id" ]] || continue
        fw="$(napcat_get_framework "$id" 2>/dev/null)" || continue
        [[ -n "$fw" ]] || continue
        root="$(echo "$fw" | jq -r '.root // empty')"
        label="$(echo "$fw" | jq -r '.label // .id')"
        port="$(napcat_coerce_port "$(echo "$link" | jq -r '.port // empty')" "$(napcat_guess_framework_port "$root")")"
        new_port=$(界面输入 "$label 监听端口" "$port")
        [[ -z "$new_port" ]] && new_port="$port"
        if ! [[ "$new_port" =~ ^[0-9]+$ ]] || [[ "$new_port" -lt 1 || "$new_port" -gt 65535 ]]; then
            界面警告 "端口无效，保留 $port"
            new_port="$port"
        fi
        new_port="$(napcat_coerce_port "$new_port" "$port")"
        link="$(echo "$link" | jq --argjson port "$new_port" '.port=$port')" || continue
        out="$(jq -n --argjson a "$(napcat_json_or "$out" '[]')" --argjson l "$(napcat_json_or "$link" '{}')" '$a + [$l]')" || continue
    done < <(echo "$links" | jq -c '.[]?')
    printf '%s' "$(napcat_json_or "$out" '[]')"
}

_NapCat_QQ向导() {
    local title="$1" old_qq="${2:-}" wqq ob checklist links qf values st
    qf=""
    [[ -n "$old_qq" && -f "$(NapCat_QQ配置文件 "$old_qq")" ]] && qf="$(NapCat_QQ配置文件 "$old_qq")"

    local def_ob=""
    [[ -n "$qf" ]] && def_ob="$(jq -r '.ob_token // ""' "$qf")"

    _NapCat_dialog捕获 values --title "$title" --form \
        "第1步：填写 QQ · 点 OK 进入第2步勾选框架" 11 58 2 \
        "QQ 账号:" 1 1 "$(_NapCat_表单默认 "${old_qq:-}")" 1 12 36 0 \
        "全局Token:" 2 1 "$(_NapCat_表单默认 "$def_ob")" 2 12 36 0
    st=$?
    [[ "$st" -eq 0 ]] || return 1
    _NapCat_解析表单 "$values" 2 wqq ob || {
        界面警告 "QQ 表单解析失败\n${NAPCAT_LAST_ERR:-}"
        return 1
    }
    wqq="$(_NapCat_字段修剪 "$wqq")"
    [[ -z "$wqq" ]] && { 界面警告 "QQ 账号不能为空"; return 1; }
    if ! [[ "$wqq" =~ ^[0-9]{5,15}$ ]]; then
        界面警告 "QQ 号格式无效\n请输入 5-15 位数字"
        return 1
    fi

    napcat_refresh_frameworks >/dev/null 2>&1 || true
    checklist="$(_NapCat_勾选框架 "$wqq")" || return 1
    links="$(_NapCat_由勾选生成Links "$wqq" "$checklist")"
    if [[ "$(echo "$links" | jq 'length')" -eq 0 ]]; then
        界面警告 "请至少选择一个框架"
        return 1
    fi

    if 界面确认 "为每个框架确认端口？" "端口确认"; then
        links="$(_NapCat_微调端口 "$links")" || return 1
    fi

    NapCat_保存QQ配置 "$wqq" "$links" "$ob" "$old_qq"
    if ! NapCat_是否运行中; then
        NapCat_准备运行时 "$wqq" || {
            界面警告 "QQ 已保存，但 onebot 同步失败\n${NAPCAT_LAST_ERR:-}\n请先停止 QQ 后重试（或 nt --sync-onebot $wqq）"
            return 1
        }
    else
        界面警告 "QQ 已保存\n当前有 QQ 在运行，未写入 onebot/webui\n停止后再启动或 nt --sync-onebot $wqq"
    fi
    _WIZARD_QQ="$wqq"
    return 0
}

_NapCat_交互添加QQ() {
    _WIZARD_QQ=""
    _NapCat_QQ向导 "新增 QQ" || return 0
    界面完成 "已保存 QQ $_WIZARD_QQ"
    if 界面确认 "立即启动 $_WIZARD_QQ？" "启动确认"; then
        NapCat_是否就绪 || { 界面警告 "NapCat 未正确安装"; return 1; }
        NapCat_启动QQ "$_WIZARD_QQ"
    fi
}

_NapCat_交互修改QQ() {
    _NapCat_选择QQ "修改 QQ 配置" || return 0
    _WIZARD_QQ=""
    _NapCat_QQ向导 "修改 $_PICKED_QQ" "$_PICKED_QQ" || return 0
    界面完成 "已保存 QQ $_WIZARD_QQ"
}

_NapCat_交互删除QQ() {
    _NapCat_选择QQ "删除 QQ 账号" || return 0
    界面确认 "确定删除 QQ $_PICKED_QQ ？\n\n将停止进程并删除绑定配置" "删除确认" || return 0
    NapCat_移除QQ "$_PICKED_QQ" || { 界面警告 "删除失败"; return 1; }
    界面完成 "已删除 QQ $_PICKED_QQ"
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
        elif NapCat_是否已安装; then
            echo "安装: 文件存在，未完成注入"
        else
            echo "安装: 未安装"
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
    界面确认 "重装 NapCat 将：\n\n· 停止所有 QQ 进程\n· 重新下载并安装\n· 保留 data/napcat 下 QQ 绑定\n\n确定继续？" "重装确认" || return 0
    NapCat_停止全部
    界面清屏
    bash "${TOOL_SCRIPT_DIR}/install.sh"
    界面清屏
    界面完成 "NapCat 重装流程已结束"
}

_NapCat_卸载项目() {
    界面确认 "卸载 NapCat 将清空 /opt/QQ 内 NapCat 与注入\n\n脚本侧 QQ 绑定（data/napcat）默认保留\n\n确定？" "卸载确认" || return 0
    NapCat_卸载文件
    if 界面确认 "同时删除脚本侧 QQ 绑定与 prefs？\n$(napcat_qq_dir)"; then
        rm -rf "$(napcat_qq_dir)" 2>/dev/null || true
    fi
    界面完成 "NapCat 已卸载"
}

_NapCat_管理() {
    while true; do
        local choice
        choice=$(界面子菜单 "NapCat 管理" "多 QQ · 多框架 · WebUI:" \
            "1" "启动 QQ" "2" "停止 QQ" "3" "新增 QQ（可多选框架）" \
            "4" "修改 / 删除 QQ" "5" "框架管理" "6" "WebUI（全局）" \
            "7" "查看状态" "8" "重装 NapCat" "9" "卸载 NapCat")
        case "$choice" in
            1) _NapCat_交互启动QQ ;;
            2) _NapCat_交互停止QQ ;;
            3) _NapCat_交互添加QQ ;;
            4)
                local sub
                sub=$(界面子菜单 "修改 / 删除" "请选择:" "1" "修改配置" "2" "删除账号")
                case "$sub" in
                    1) _NapCat_交互修改QQ ;;
                    2) _NapCat_交互删除QQ ;;
                esac
                ;;
            5) _NapCat_框架管理 ;;
            6) _NapCat_WebUI菜单 ;;
            7) _NapCat_显示全部状态 ;;
            8) _NapCat_重装项目 ;;
            9) _NapCat_卸载项目 && exit 0 ;;
            b|"") exit 0 ;;
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
