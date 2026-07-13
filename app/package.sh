#!/bin/bash

# 常用软件列表
_常用软件() {
    echo "git|版本控制"
    echo "curl|HTTP工具"
    echo "wget|下载工具"
    echo "jq|JSON处理"
    echo "tmux|终端复用"
    echo "vim|编辑器"
    echo "htop|系统监控"
    echo "node|Node.js"
    echo "redis|Redis"
    echo "mongodb|MongoDB"
    echo "chromium|浏览器"
    echo "docker|容器"
    echo "nginx|Web服务"
    echo "python3|Python"
}

软件包_菜单() {
    while true; do
        local choice
        choice=$(界面子菜单 "📦 软件管理" "请选择:" \
            "1" "安装软件" \
            "2" "已装列表" \
            "3" "环境与工具" \
            "4" "更新软件源" \
            "5" "更换系统源")

        case "$choice" in
            1) 软件包_安装 ;;
            2) 软件包_已装列表 ;;
            3) 环境_菜单 ;;
            4) 软件包_更新软件源 ;;
            5) 软件包_换源 ;;
            b|'') break ;;
        esac
    done
}

# 构建常用软件列表，标记安装状态
# $1 = "all" 显示全部 / "installed" 只显示已装
_构建常用列表() {
    local mode="${1:-all}"

    while IFS='|' read -r name desc; do
        [[ -z "$name" ]] && continue

        local installed=false ver=""
        if 包管理_是否已安装 "$name" 2>/dev/null; then
            installed=true
            ver=$(包管理_获取版本 "$name" 2>/dev/null)
        fi

        case "$mode" in
            installed)
                [[ "$installed" != "true" ]] && continue
                echo "$name|✓ ${ver:-已装}"
                ;;
            *)
                if [[ "$installed" == "true" ]]; then
                    echo "$name|✓ ${ver:-已装}"
                else
                    echo "$name|未安装"
                fi
                ;;
        esac
    done < <(_常用软件)
}

软件包_安装() {
    local items=()
    while IFS='|' read -r name status; do
        [[ -z "$name" ]] && continue
        items+=("$name" "$status")
    done < <(_构建常用列表 "all")

    items+=("__search__" "🔍 搜索软件源...")

    local selected
    selected=$(界面选择 "📦 安装软件" "选择软件 (键盘输入可快速定位):" "${items[@]}")
    [[ -z "$selected" ]] && return

    if [[ "$selected" == "__search__" ]]; then
        软件包_搜索安装
        return
    fi

    软件包_装 "$selected"
}

软件包_搜索安装() {
    local search
    search=$(界面输入 "🔍 输入关键词")
    [[ -z "$search" ]] && return

    界面清屏
    printf '搜索: %s...\n' "$search" >&2
    local items=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name desc
        name=$(echo "$line" | awk '{print $1}')
        desc=$(echo "$line" | cut -d' ' -f2-)
        [[ -n "$name" ]] && items+=("$name" "${desc:-}")
    done < <(包管理_搜索 "$search" 2>/dev/null | head -20)
    界面清屏

    [[ ${#items[@]} -eq 0 ]] && { 界面消息 "未找到"; return; }

    local selected
    selected=$(界面选择 "🔍 搜索结果" "选择:" "${items[@]}")
    [[ -z "$selected" ]] && return

    软件包_装 "$selected"
}

软件包_装() {
    local pkg="$1"
    pkg=$(包管理_规范化包名 "$pkg")

    if 包管理_是否已安装 "$pkg"; then
        界面消息 "$pkg 已安装\n$(包管理_获取版本 "$pkg" 2>/dev/null)" "提示"
        return
    fi

    if 界面任务 "正在安装 $pkg..." 包管理_安装 "$pkg"; then
        界面成功 "$pkg 安装成功"
    else
        界面错误 "$pkg 安装失败"
    fi
}

软件包_已装列表() {
    local items=()
    while IFS='|' read -r name status; do
        [[ -z "$name" ]] && continue
        items+=("$name" "$status")
    done < <(_构建常用列表 "installed")

    items+=("__search__" "🔍 搜索全部已装...")

    local selected
    selected=$(界面选择 "📦 已装列表" "选择软件 (键盘输入可快速定位):" "${items[@]}")
    [[ -z "$selected" ]] && return

    if [[ "$selected" == "__search__" ]]; then
        软件包_搜索已装
        return
    fi

    软件包_操作 "$selected"
}

软件包_搜索已装() {
    local search
    search=$(界面输入 "🔍 输入关键词")
    [[ -z "$search" ]] && return

    界面清屏
    printf '搜索: %s...\n' "$search" >&2
    local tmp="${CONFIG[temp_dir]}/pkg_search.txt"
    包管理_已安装列表 > "$tmp" 2>/dev/null
    local items=()
    while IFS= read -r line; do
        [[ -z "$line" ]] && continue
        local name ver
        name=$(echo "$line" | awk '{print $1}')
        ver=$(echo "$line" | awk '{print $2}')
        [[ "$name" == *"$search"* ]] && items+=("$name" "$ver")
    done < "$tmp"
    界面清屏

    [[ ${#items[@]} -eq 0 ]] && { 界面消息 "未找到"; return; }

    local selected
    selected=$(界面选择 "🔍 搜索结果" "选择:" "${items[@]}")
    [[ -z "$selected" ]] && return

    软件包_操作 "$selected"
}

软件包_操作() {
    local pkg="$1"
    local cur new

    cur=$(包管理_获取版本 "$pkg" 2>/dev/null)
    new=$(包管理_获取可升级版本 "$pkg" 2>/dev/null)

    local acts=()
    [[ -n "$new" && "$new" != "$cur" ]] && acts+=("upgrade" "升级 $new")
    acts+=("info" "详情" "uninstall" "卸载")

    local act
    act=$(界面动作 "📦 $pkg ($cur)" "${acts[@]}")
    界面已取消 "$act" && return

    case "$act" in
        upgrade)
            界面确认 "升级 $pkg？" || return
            if 界面任务 "升级中..." 包管理_升级 "$pkg"; then
                界面成功 "升级成功"
            else
                界面错误 "升级失败"
            fi
            ;;
        info)
            界面文本 "$(包管理_显示信息 "$pkg" 2>/dev/null)" "$pkg 详情"
            软件包_操作 "$pkg"
            ;;
        uninstall)
            界面确认 "卸载 $pkg？" || return
            if 界面任务 "卸载中..." 包管理_卸载 "$pkg"; then
                界面成功 "卸载成功"
            else
                界面错误 "卸载失败"
            fi
            ;;
    esac
}

软件包_更新软件源() {
    if 界面任务 "更新中..." 包管理_更新源; then
        界面成功 "更新成功"
    else
        界面错误 "更新失败"
    fi
}

软件包_换源() {
    local choice
    choice=$(界面子菜单 "🔄 换源" "选择:" \
        "1" "apt 镜像" \
        "2" "npm/pnpm 镜像" \
        "b" "返回")

    case "$choice" in
        1)
            [[ $EUID -ne 0 ]] && { 界面错误 "需要 root"; return; }
            界面确认 "启动 linuxmirrors 换源？" || return
            界面清屏
            if 包管理_Linux换源; then
                界面确认 "换源完成，apt update？" && 软件包_更新软件源
            else
                界面错误 "换源失败"
            fi
            ;;
        2)
            if 界面任务 "配置中..." 包管理_换源Js; then
                界面成功 "已配置"
            else
                界面错误 "失败"
            fi
            ;;
    esac
}
