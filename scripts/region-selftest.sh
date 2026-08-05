#!/bin/bash
# 区域检测自测（不依赖网络 IP 时也能用 TZ / HAMSTER_REGION 验时区路径）
# 用法：bash scripts/region-selftest.sh
# 或在服务器：cd /cs && bash scripts/region-selftest.sh

set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$ROOT/lib/region.sh"

_fail=0
_assert() {
    local name="$1" got="$2" want="$3"
    if [[ "$got" == "$want" ]]; then
        echo "OK  $name → $got"
    else
        echo "FAIL $name → got=$got want=$want"
        _fail=1
    fi
}

echo "=== TZ 强制时区（不读系统）==="
_assert "TZ=Asia/Shanghai 时区" "$(TZ=Asia/Shanghai 系统_检测时区)" "Asia/Shanghai"
_assert "TZ=UTC 时区" "$(TZ=UTC 系统_检测时区)" "UTC"
TZ=Asia/Shanghai 系统_是否国内时区 && echo "OK  TZ=Asia/Shanghai 国内时区" || { echo "FAIL 国内时区"; _fail=1; }
TZ=UTC 系统_是否国内时区 && { echo "FAIL UTC 不应国内"; _fail=1; } || echo "OK  TZ=UTC 非国内时区"
TZ=Asia/Tokyo 系统_是否国内时区 && { echo "FAIL Tokyo 不应国内"; _fail=1; } || echo "OK  TZ=Asia/Tokyo 非国内时区"

echo "=== HAMSTER_REGION 覆盖（不依赖 IP）==="
_assert "强制 cn" "$(HAMSTER_REGION=cn 网络_检测区域)" "cn"
_assert "强制 overseas" "$(HAMSTER_REGION=overseas 网络_检测区域)" "overseas"
export HAMSTER_REGION=cn
网络_检测区域 >/dev/null
_assert "method=override" "$HAMSTER_DETECT_METHOD" "override"
unset HAMSTER_REGION

echo "=== 时区路径强制区域（HAMSTER_REGION 空 + 伪造无 IP：只验时区函数链）==="
# 用 TZ 模拟「IP 失败后走时区」：临时把 curl 藏起来
_curl_bin="$(command -v curl || true)"
if [[ -n "$_curl_bin" ]]; then
    _tmpdir="$(mktemp -d)"
    # PATH 前置空 curl，使 IP 探测失败
    printf '%s\n' '#!/bin/sh' 'exit 1' > "$_tmpdir/curl"
    chmod +x "$_tmpdir/curl"
    _assert "无IP+上海→cn" "$(PATH="$_tmpdir:$PATH" TZ=Asia/Shanghai HAMSTER_REGION= 网络_检测区域)" "cn"
    _assert "无IP+UTC→overseas" "$(PATH="$_tmpdir:$PATH" TZ=UTC HAMSTER_REGION= 网络_检测区域)" "overseas"
    rm -rf "$_tmpdir"
fi

echo "=== 当前环境报告（清除覆盖变量）==="
env -u HAMSTER_REGION -u XRK_REGION bash -c '
  # shellcheck source=/dev/null
  source "'"$ROOT"'/lib/region.sh"
  区域_报告
'

[[ "$_fail" -eq 0 ]] && echo "=== ALL PASS ===" || { echo "=== FAILED ==="; exit 1; }
