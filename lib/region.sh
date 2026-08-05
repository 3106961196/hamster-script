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

# 输出 "cn|override" / "overseas|ip" 等（便于 $() 一次拿全）
_网络_区域详情() {
    local json country

    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn|overseas) printf '%s|override\n' "${HAMSTER_REGION:-$XRK_REGION}"; return 0 ;;
    esac

    if command -v curl &>/dev/null; then
        json=$(curl -s --connect-timeout 3 --max-time 5 "http://ip-api.com/json" 2>/dev/null || true)
        country=$(printf '%s' "$json" | grep -oE '"countryCode":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$country" ]]; then
            [[ "$country" == "CN" ]] && { echo "cn|ip"; return 0; }
            echo "overseas|ip"
            return 0
        fi
        case "$json" in
            *'"country":"China"'*) echo "cn|ip"; return 0 ;;
        esac
    fi

    if 系统_是否国内时区; then
        echo "cn|timezone"
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
