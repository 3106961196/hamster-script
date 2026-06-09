$p = 'D:\bot\hamster-script\tools\napcat\manage.sh'
$enc = [System.Text.UTF8Encoding]::new($false)
$raw = [System.IO.File]::ReadAllText($p, $enc)
$arr = $raw -split "`n"

# Find lines containing 'ui_msg "没有已配置的 QQ 账号'
$msgLines = @()
for ($i = 0; $i -lt $arr.Count; $i++) {
 if ($arr[$i] -match 'ui_msg "没有已配置的 QQ 账号') {
 $msgLines += $i
 }
}
Write-Output "Found ui_msg lines at indices: $($msgLines -join ',')"
Write-Output "Total lines: $($arr.Count)"

# Replace the 3 occurrences: for each, replace the ui_msg line with ui_error + ui_pause
foreach ($idx in $msgLines) {
 Write-Output " Line $($idx+1): $($arr[$idx])"
}

# We will replace each ui_msg line with two new lines (ui_error + ui_pause)
# The replacement block looks like: " ui_error ..\n ui_pause ..\n"
# But we need to keep the original line's leading whitespace.

$newArr = @()
$skipNext = $false
for ($i = 0; $i -lt $arr.Count; $i++) {
 $line = $arr[$i]
 if ($skipNext) {
 # This is the 'return 1' line, we keep it
 $skipNext = $false
 $newArr += $line
 continue
 }
 if ($line -match '^(\s+)ui_msg "没有已配置的 QQ 账号，请先添加" "注意"(\s*)$') {
 $ws = $matches[1]
 $trail = $matches[2]
 $newArr += "${ws}ui_error "没有已配置的 QQ 账号，请先添加"$trail"
 $newArr += "${ws}ui_pause "按 Enter 返回."$trail"
 continue
 }
 $newArr += $line
}

Write-Output "New total: $($newArr.Count)"

$out = ($newArr -join "`n")
[System.IO.File]::WriteAllText($p, $out, $enc)
Write-Output "WROTE"
