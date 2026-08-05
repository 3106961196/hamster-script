#!/bin/bash
# 区域检测（对齐 xrk-projects-scripts bootstrap：覆盖 → IP → 时区 → overseas）
# 任意环境可测：TZ=… / HAMSTER_REGION=cn|overseas

HAMSTER_DETECT_METHOD="${HAMSTER_DETECT_METHOD:-}"

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

# 输出 cn|overseas，并设置 HAMSTER_DETECT_METHOD=override|ip|timezone|default
网络_检测区域() {
    local json country

    case "${HAMSTER_REGION:-${XRK_REGION:-}}" in
        cn|overseas)
            HAMSTER_DETECT_METHOD="override"
            printf '%s\n' "${HAMSTER_REGION:-$XRK_REGION}"
            return 0
            ;;
    esac

    if command -v curl &>/dev/null; then
        json=$(curl -s --connect-timeout 3 --max-time 5 "http://ip-api.com/json" 2>/dev/null || true)
        country=$(printf '%s' "$json" | grep -oE '"countryCode":"[^"]*"' | cut -d'"' -f4)
        if [[ -n "$country" ]]; then
            HAMSTER_DETECT_METHOD="ip"
            [[ "$country" == "CN" ]] && { echo cn; return 0; }
            echo overseas
            return 0
        fi
        case "$json" in
            *'"country":"China"'*)
                HAMSTER_DETECT_METHOD="ip"
                echo cn
                return 0
                ;;
        esac
    fi

    if 系统_是否国内时区; then
        HAMSTER_DETECT_METHOD="timezone"
        echo cn
        return 0
    fi

    HAMSTER_DETECT_METHOD="default"
    echo overseas
}

是否国内区域() {
    [[ "$(网络_检测区域)" == "cn" ]]
}

# 兼容旧名
_是否国内区域() { 是否国内区域; }
_是否国内时区() { 系统_是否国内时区; }

区域_报告() {
    local info region method tz
    # 同一次子壳内回传 method，避免 $() 丢掉 HAMSTER_DETECT_METHOD
    info=$(网络_检测区域; printf '\t%s' "${HAMSTER_DETECT_METHOD:-?}")
    region="${info%%$'\t'*}"
    method="${info#*$'\t'}"
    tz=$(系统_检测时区 2>/dev/null || echo "?")
    cat <<EOF
区域:     ${region:-?} (依据: ${method:-?})
时区:     ${tz:-未知}
覆盖:     HAMSTER_REGION=cn|overseas 或 TZ=<IANA时区>
EOF
}
