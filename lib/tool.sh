#!/bin/bash

# ─── 工具通用框架 ──────────────────────────────────────────────

# 加载 conf（去 CRLF，避免 source 报错与数组解析失败）
_Conf_加载() {
    local conf="$1"
    [[ -f "$conf" ]] || return 1
    # shellcheck source=/dev/null
    source <(sed 's/\r$//' "$conf")
}

_工具_规范化Deps() {
    local d cleaned=()

    if ! declare -p TOOL_DEPS 2>/dev/null | grep -q 'declare -a'; then
        local s="${TOOL_DEPS:-}"
        s="${s//[$'\r'()]/}"
        read -ra TOOL_DEPS <<< "$s"
    fi

    for d in "${TOOL_DEPS[@]}"; do
        d="${d//$'\r'/}"
        d="${d#"${d%%[![:space:]]*}"}"
        d="${d%"${d##*[![:space:]]}"}"
        [[ -n "$d" ]] && cleaned+=("$d")
    done
    TOOL_DEPS=("${cleaned[@]}")
}

# 安装目录跟随 config work_dir（与 install_dir 一致，避免装到 A 目录却去 B 目录检测）
_工具_清除配置() {
    unset TOOL_KIND TOOL_NAME TOOL_REPO TOOL_INSTALL_DIR TOOL_INSTALL_SUBDIR
    unset NAPCAT_ZIP_URL NAPCAT_LAUNCHER NAPCAT_DEFAULT_PORT
    unset CONFIG_DIR NAPCATBOT_FILE QQ_PACKAGE_JSON QQ_MAIN_ORIGINAL LOAD_NAPCAT_JS QQ_BIN
    unset TOOL_DEPS
    TOOL_DEPS=()
}

_工具_解析安装目录() {
    local tool_name="$1"
    local work_dir
    work_dir="$(获取工作目录)"

    if [[ -n "${TOOL_INSTALL_SUBDIR:-}" ]]; then
        TOOL_INSTALL_DIR="${work_dir}/${TOOL_INSTALL_SUBDIR}"
        return 0
    fi

    # NapCat 等 tool.conf 写死的绝对路径
    if [[ -n "${TOOL_INSTALL_DIR:-}" && "${TOOL_INSTALL_DIR:0:1}" == "/" ]]; then
        return 0
    fi

    TOOL_INSTALL_DIR="${work_dir}/${tool_name}"
}

# 加载工具配置
工具_加载配置() {
    local tool_name="$1"
    local conf="$PROJECT_ROOT/tools/$tool_name/tool.conf"

    _工具_清除配置

    if [[ -f "$conf" ]]; then
        _Conf_加载 "$conf" || return 1
        _工具_规范化Deps
        _工具_解析安装目录 "$tool_name"
        return 0
    fi

    日志错误 "工具配置文件不存在: $conf"
    return 1
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
    local common="$PROJECT_ROOT/tools/${tool_name}/common.sh"

    工具_加载配置 "$tool_name" || return 1
    [[ -f "$common" ]] && source "$common"

    case "$tool_name" in
        napcat) NapCat_是否就绪 ;;
        *)
            [[ -d "$TOOL_INSTALL_DIR" ]] || return 1
            [[ -f "$TOOL_INSTALL_DIR/package.json" || -d "$TOOL_INSTALL_DIR/.git" || -f "$TOOL_INSTALL_DIR/app.js" ]]
            ;;
    esac
}

# 安装工具依赖（已满足的跳过，避免 AGT 等重复从零安装）
工具_安装依赖() {
    local tool_name="$1"
    local dep missing=()

    工具_加载配置 "$tool_name" || return 1

    for dep in "${TOOL_DEPS[@]}"; do
        case "$dep" in
            node|nodejs)
                包管理_验证Node环境 && 包管理_Node已满足 && _包管理_Pnpm就绪 && continue
                missing+=("$dep")
                ;;
            pnpm)
                command -v pnpm &>/dev/null && continue
                missing+=("node")
                ;;
            redis|redis-server)
                包管理_Redis已安装 && continue
                missing+=("$dep")
                ;;
            mongodb|mongod)
                包管理_MongoDB已安装 && continue
                missing+=("$dep")
                ;;
            chromium|chromium-browser)
                包管理_Chromium已安装 && continue
                missing+=("$dep")
                ;;
            *)
                包管理_是否已安装 "$dep" && continue
                missing+=("$dep")
                ;;
        esac
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        日志信息 "依赖已满足: ${TOOL_DEPS[*]}"
        return 0
    fi

    日志信息 "待安装依赖: ${missing[*]}"

    for dep in "${missing[@]}"; do
        case "$dep" in
            node|nodejs|pnpm) 包管理_确保Node ;;
            redis|redis-server) 包管理_确保Redis ;;
            mongodb|mongod) 包管理_确保MongoDB ;;
            chromium|chromium-browser) 包管理_确保Chromium ;;
            *) 包管理_安装 "$dep" ;;
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
    工具_加载配置 "$tool_name" || return 1

    if [[ "$tool_name" == "napcat" ]]; then
        日志错误 "NapCat 请使用 tools/napcat/install.sh 安装"
        return 1
    fi

    日志信息 "开始安装 $tool_name..."
    declare -F _界面_重置终端 &>/dev/null && _界面_重置终端
    export HAMSTER_UI_TASK=1
    工具_安装依赖 "$tool_name" || { unset HAMSTER_UI_TASK; return 1; }
    工具_克隆仓库 "$tool_name" || { unset HAMSTER_UI_TASK; return 1; }
    工具_安装Npm依赖 "$tool_name" || { unset HAMSTER_UI_TASK; return 1; }
    unset HAMSTER_UI_TASK
    declare -F _界面_重置终端 &>/dev/null && _界面_重置终端
    日志成功 "$tool_name 安装完成"
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

    if [[ -d "$TOOL_INSTALL_DIR" ]]; then
        日志信息 "正在删除 $TOOL_INSTALL_DIR..."
        rm -rf "$TOOL_INSTALL_DIR"
        日志成功 "$tool_name 已卸载"
    else
        日志警告 "工具目录不存在"
    fi
}
