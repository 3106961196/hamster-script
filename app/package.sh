#!/bin/bash

软件包_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "📦 软件管理" "请选择功能:" \
            "1" "安装软件" \
            "2" "已装列表" \
            "3" "环境与工具" \
            "4" "更新软件源" \
            "5" "更换系统源")
        
        case "$choice" in
            1) 软件包_安装 ;;
            2) 软件包_已安装列表 ;;
            3) 环境_菜单 ;;
            4) 软件包_更新软件源 ;;
            5) 软件包_换源 ;;
            b|'') break ;;
        esac
    done
}

软件包_安装() {
    local search_term
    search_term=$(界面输入 "🔍 搜索软件 (留空显示常用软件)")
    
    local items=()
    
    if [[ -n "$search_term" ]]; then
        界面清屏
        printf '正在搜索: %s...\n\n' "$search_term" >&2
        search_results=$(包管理_搜索 "$search_term" 2>/dev/null | head -20)
        界面清屏
        
        if [[ -n "$search_results" ]]; then
            while IFS= read -r line; do
                if [[ -n "$line" ]]; then
                    local pkg_name pkg_desc
                    pkg_name=$(echo "$line" | awk '{print $1}')
                    pkg_desc=$(echo "$line" | cut -d' ' -f2- | xargs)
                    [[ -n "$pkg_name" ]] && items+=("$pkg_name" "$pkg_desc")
                fi
            done <<< "$search_results"
        fi
    fi
    
    # 常用软件列表：优先读取配置文件，否则使用默认值
    local common_file="${PROJECT_ROOT}/config/common_packages.conf"
    local common_packages=()
    if [[ -f "$common_file" ]]; then
        while IFS='|' read -r name desc _rest; do
            [[ -z "$name" || "$name" =~ ^# ]] && continue
            common_packages+=("$name" "${desc:-}")
        done < "$common_file"
    fi
    
    if [[ ${#common_packages[@]} -eq 0 ]]; then
        common_packages=("git" "版本控制" "curl" "网络工具" "wget" "下载工具"
            "jq" "JSON处理" "dialog" "对话框" "tmux" "终端复用"
            "node" "Node.js 26 + pnpm" "redis-server" "Redis"
            "mongodb" "MongoDB" "chromium" "Chromium" "htop" "系统监控")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        items=("${common_packages[@]}")
    else
        界面消息 "未找到 \"${search_term}\" 相关结果，显示常用软件" "提示"
        items+=("" "" "── 常用软件 ──" "")
        items+=("${common_packages[@]}")
    fi
    
    if [[ ${#items[@]} -eq 0 ]]; then
        界面消息 "未找到相关软件" "提示"
        return
    fi
    
    local selected
    selected=$(界面选择 "📦 安装软件" "选择要安装的软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    软件包_安装指定包 "$selected"
}

软件包_安装指定包() {
    local selected="$1"
    local pkg_name
    pkg_name=$(包管理_规范化包名 "$selected")

    # 特殊包：不走 apt 版本选择，直接安装
    case "$pkg_name" in
        node|chromium|mongodb|redis)
            if 包管理_是否已安装 "$pkg_name"; then
                local current_version
                current_version=$(包管理_获取版本 "$pkg_name" 2>/dev/null)
                界面消息 "${selected} 已安装\n当前版本: ${current_version:-未知}" "提示"
                return
            fi
            if 界面任务 "正在安装 $pkg_name..." 包管理_安装 "$pkg_name"; then
                界面成功 "$pkg_name 安装成功"
            elif 包管理_是否已安装 "$pkg_name"; then
                界面成功 "${pkg_name} 已就绪\n$(包管理_获取版本 "$pkg_name" 2>/dev/null)"
            else
                local detail="${HAMSTER_LAST_ERROR:-安装步骤返回失败}"
                界面错误 "${pkg_name} 安装失败\n\n${detail}"
            fi
            return
            ;;
    esac

    if 包管理_是否已安装 "$pkg_name"; then
        local current_version
        current_version=$(包管理_获取版本 "$pkg_name" 2>/dev/null)
        界面消息 "${selected} 已安装\n当前版本: ${current_version:-未知}" "提示"
        return
    fi
    
    local versions
    versions=$(包管理_获取版本列表 "$pkg_name" 2>/dev/null)
    
    local version_items=()
    if [[ -n "$versions" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                version_items+=("$line" "")
            fi
        done <<< "$versions"
    fi
    
    local selected_version
    if [[ ${#version_items[@]} -gt 2 ]]; then
        selected_version=$(界面选择 "📦 $pkg_name - 选择版本" "选择版本:" "${version_items[@]}")
        [[ -z "$selected_version" ]] && return
    else
        selected_version="latest"
    fi
    
    local action
    action=$(界面动作 "📦 $pkg_name" \
        "install" "安装" \
        "info" "查看详情")
    
    界面已取消 "$action" && return
    
    case "$action" in
        install)
            if 界面任务 "正在安装 $pkg_name..." 包管理_安装 "$pkg_name"; then
                界面成功 "$pkg_name 安装成功"
            else
                界面错误 "$pkg_name 安装失败"
            fi
            ;;
        info)
            local info
            info=$(包管理_显示信息 "$pkg_name" 2>/dev/null)
            界面文本 "$info" "📦 $pkg_name 详情"
            ;;
    esac
}

软件包_已安装列表() {
    local temp_file="${CONFIG[temp_dir]}/installed_packages.txt"
    界面清屏
    printf '正在获取已安装软件列表...\n\n' >&2
    包管理_已安装列表 > "$temp_file" 2>/dev/null
    界面清屏
    
    local upgrade_file="${CONFIG[temp_dir]}/upgradable_packages.txt"
    包管理_可升级列表 > "$upgrade_file" 2>/dev/null &
    local check_pid=$!
    
    local items=()
    while IFS= read -r line; do
        if [[ -n "$line" ]]; then
            local pkg_name pkg_version
            pkg_name=$(echo "$line" | awk '{print $1}')
            pkg_version=$(echo "$line" | awk '{print $2}')
            [[ -n "$pkg_name" ]] && items+=("$pkg_name" "$pkg_version")
        fi
    done < "$temp_file"
    
    if [[ ${#items[@]} -eq 0 ]]; then
        界面消息 "无法获取已安装软件列表" "错误"
        return
    fi
    
    local upgradable_count=0
    local upgrade_items=()
    
    界面加载动画 "$check_pid" "正在检查软件更新..."
    wait "$check_pid" 2>/dev/null
    
    if [[ -f "$upgrade_file" ]] && [[ -s "$upgrade_file" ]]; then
        while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                local upg_name upg_old upg_new
                upg_name=$(echo "$line" | awk '{print $1}')
                upg_old=$(echo "$line" | awk '{print $2}')
                upg_new=$(echo "$line" | awk '{print $3}')
                
                for i in "${!items[@]}"; do
                    if [[ $((i % 2)) -eq 0 ]] && [[ "${items[$i]}" == "$upg_name" ]]; then
                        items[$((i+1))]="${upg_old} ⬆️ ${upg_new}"
                        break
                    fi
                done
                
                upgradable_count=$((upgradable_count + 1))
            fi
        done < "$upgrade_file"
    fi
    
    local selected
    selected=$(界面选择 "📦 已装列表 (${upgradable_count}个可更新)" "选择软件:" "${items[@]}")
    
    [[ -z "$selected" ]] && return
    
    软件包_包操作 "$selected"
}

软件包_包操作() {
    local pkg_name="$1"
    local current_version new_version
    
    current_version=$(包管理_获取版本 "$pkg_name" 2>/dev/null)
    new_version=$(包管理_获取可升级版本 "$pkg_name" 2>/dev/null)
    
    local actions
    if [[ -n "$new_version" ]] && [[ "$new_version" != "$current_version" ]]; then
        actions=(
            "upgrade" "升级到 $new_version"
            "info" "查看详情"
            "uninstall" "卸载"
        )
    else
        actions=(
            "info" "查看详情"
            "uninstall" "卸载"
        )
    fi
    
    local action
    action=$(界面动作 "📦 $pkg_name ($current_version)" "${actions[@]}")
    
    界面已取消 "$action" && return
    
    case "$action" in
        upgrade)
            if 界面确认 "确定要升级 $pkg_name 吗？"; then
                if 界面任务 "正在升级 $pkg_name..." 包管理_升级 "$pkg_name"; then
                    界面成功 "$pkg_name 升级成功"
                else
                    界面错误 "$pkg_name 升级失败"
                fi
            fi
            ;;
        info)
            local info
            info=$(包管理_显示信息 "$pkg_name" 2>/dev/null)
            界面文本 "$info" "📦 $pkg_name 详情"
            软件包_包操作 "$pkg_name"
            ;;
        uninstall)
            if 界面确认 "确定要卸载 $pkg_name 吗？"; then
                if 界面任务 "正在卸载 $pkg_name..." 包管理_卸载 "$pkg_name"; then
                    界面成功 "$pkg_name 卸载成功"
                else
                    界面错误 "$pkg_name 卸载失败"
                fi
            fi
            ;;
    esac
}

软件包_更新软件源() {
    if 界面任务 "正在更新软件源...\n（出现 109 packages can be upgraded 表示 update 已完成，随后会返回菜单）" 包管理_更新源; then
        界面成功 "软件源更新成功"
    else
        界面错误 "软件源更新失败"
    fi
}

软件包_换源() {
    local choice
    choice=$(界面子菜单 "🔄 换源" "请选择:" \
        "1" "系统 apt 镜像 (linuxmirrors)" \
        "2" "npm/pnpm 国内镜像" \
        "b" "返回")

    case "$choice" in
        1) 软件包_Linux换源 ;;
        2)
            if 界面任务 "正在配置 npm/pnpm 镜像..." 包管理_换源Js; then
                界面成功 "npm/pnpm 镜像已配置"
            else
                界面错误 "配置失败（需已安装 node/npm）"
            fi
            ;;
        b|'') ;;
    esac
}

软件包_Linux换源() {
    if [[ $EUID -ne 0 ]]; then
        界面错误 "换源需要 root 权限\n\n请使用:\n  sudo cs"
        return
    fi

    界面确认 "将启动 linuxmirrors 交互式换源\n\n完成后建议返回执行「更新软件源」" "确认" || return

    界面清屏
    printf '正在加载 linuxmirrors...\n\n' >&2
    if 包管理_Linux换源; then
        if 界面确认 "换源完成，是否立即 apt update？" "更新软件源"; then
            软件包_更新软件源
        else
            界面成功 "换源完成\n\n请稍后手动执行「更新软件源」"
        fi
    else
        界面错误 "换源未完成或失败\n\n${HAMSTER_LAST_ERROR:-可在终端直接运行:\n  sudo bash <(curl -sSL https://linuxmirrors.cn/main.sh)}"
    fi
}
