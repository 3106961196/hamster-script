#!/bin/bash
# Strip CRLF under install dir (WSL copy from /mnt/c). ASCII-only on purpose.
set -e
ROOT="${1:-/cs}"
[[ -d "$ROOT" ]] || { echo "missing: $ROOT" >&2; exit 1; }
find "$ROOT" -type f \( -name '*.sh' -o -path '*/bin/*' -o -name '*.conf' \) \
    -exec sed -i 's/\r$//' {} + 2>/dev/null || true
find "$ROOT" -type f \( -name '*.sh' -o -path '*/bin/*' \) \
    -exec chmod +x {} + 2>/dev/null || true
if [[ -f "$ROOT/lib/bin_sync.sh" ]]; then
    # shellcheck source=/dev/null
    source "$ROOT/lib/bin_sync.sh"
    命令同步 "$ROOT"
fi
echo "CRLF fixed under $ROOT"
