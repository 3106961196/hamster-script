#!/bin/bash
# 区域检测（对齐 xrk-projects-scripts：覆盖 → IP → 时区 → overseas）
# 任意环境可测：TZ=… / HAMSTER_REGION=cn|overseas
# 自测：bash scripts/region-selftest.sh

HAMSTER_DETECT_METHOD="${HAMSTER_DETECT_METHOD:-}"
HAMSTER_REGION_RESULT="${HAMSTER_REGION_RESULT:-}"

# 读系统时区：显式 TZ > timedatectl > /etc/timezone > localtime→zoneinfo
系统_检测时区() {
    local tz="${TZ:-}"
    [[ -n "$tz" ]] && { printf '%s\n' "$tz"; return 0; }
    tz=$(timedatectl show -p Timezone --value 2>/dev/null) && [[ -n "$tz" ]] && { printf '%s\n' "$tz"; return 0; }
    [[ -f /etc/timezone ]] && { cat /etc/timezone; return 0; }
    readlink -f /etc/localtime 2>/dev/null | sed -n 's|.*/zoneinfo/||p'
}

# 中国相关时区（含港澳台；禁止 *"Asia"* 以免东京/新加坡误判）
系统_是否国内时区() {
    case "$(系统_检测时区)" in
        Asia/Shanghai|Asia/Chongqing|Asia/Harbin|Asia/Urumqi|Asia/Kashgar|PRC \
        |Asia/Hong_Kong|Asia/Macau|Asia/Taipei) return 0 ;;
    esac
    return 1
}

# 无代理探测：能开国内站、打不开 GitHub → 典型国内出网（含只切外网的机房）
_网络_像国内出网() {
    command -v curl &>/dev/null || return 1
    # 百度通 + GitHub 不通（均绕过本机/环境代理）
    curl -fsS --noproxy '*' --connect-timeout 3 --max-time 5 \
        -o /dev/null "https://www.baidu.com" 2>/dev/null || return 1
    curl -fsS --noproxy '*' --connect-timeout 3 --max-time 5 \
        -o /dev/null "https://api.github.com" 2>/dev/null && return 1
    return 0
}

# 多源取国家码（部分机房墙掉 ip-api）
_网络_探测国家码() {
    local body code
    command -v curl &>/dev/null || return 1
    body=$(curl -fsS --connect-timeout 3 --max-time 5 "http://ip-api.com/json" 2>/dev/null || true)
    code=$(printf '%s' "$body" | grep -oE '"countryCode":"[^"]*"' | cut -d'"' -f4)
    [[ -n "$code" ]] && { printf '%s\n' "$code"; return 0; }
    case "$body" in
        *'"country":"China"'*) echo CN; return 0 ;;
    esac
    code=$(curl -fsS --connect-timeout 3 --max-time 5 "https://ipinfo.io/country" 2>/dev/null | tr -d '\r\n' || true)
    [[ "$code" =~ ^[A-Z]{2}$ ]] && { printf '%s\n' "$code"; return 0; }
    code=$(curl -fsS --connect-timeout 3 --max-time 5 "https://ifconfig.co/country-iso" 2>/dev/null | tr -d '\r\n' || true)
    [[ "$code" =~ ^[A-Z]{2}$ ]] && { printf '%s\n' "$code"; return 0; }
    return 1
}

# 输出 "cn|override" / "overseas|ip" 等（便于 $() 一次拿全）
_网络_区域详情() {
    local country

    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn|overseas) printf '%s|override\n' "${HAMSTER_REGION:-$XRK_REGION}"; return 0 ;;
    esac

    if country=$(_网络_探测国家码); then
        [[ "$country" == "CN" ]] && { echo "cn|ip"; return 0; }
        echo "overseas|ip"
        return 0
    fi

    if 系统_是否国内时区; then
        echo "cn|timezone"
        return 0
    fi

    # 时区常为 Etc/UTC 的国内机：用出网特征兜底，否则会误判海外、跳过 GitHub 镜像
    if _网络_像国内出网; then
        echo "cn|connectivity"
        return 0
    fi

    echo "overseas|default"
}

# 输出 cn|overseas；同时写入 HAMSTER_REGION_RESULT / HAMSTER_DETECT_METHOD（当前壳调用时）
网络_检测区域() {
    local detail
    detail=$(_网络_区域详情)
    HAMSTER_REGION_RESULT="${detail%%|*}"
    HAMSTER_DETECT_METHOD="${detail#*|}"
    printf '%s\n' "$HAMSTER_REGION_RESULT"
}

是否国内区域() {
    [[ "$(网络_检测区域)" == "cn" ]]
}

_是否国内区域() { 是否国内区域; }
_是否国内时区() { 系统_是否国内时区; }

区域_报告() {
    local detail region method tz
    detail=$(_网络_区域详情)
    region="${detail%%|*}"
    method="${detail#*|}"
    tz=$(系统_检测时区 2>/dev/null || echo "?")
    cat <<EOF
区域:     ${region} (依据: ${method})
时区:     ${tz:-未知}
覆盖:     HAMSTER_REGION=cn|overseas 或 TZ=<IANA时区>
EOF
}
