# 返回桌面耗时验收：从第三方应用按 HOME 回到本桌面，量三段耗时。
#
#   1) HOME intent 投递 → onStart enter      （系统排程 + onNewIntent）
#   2) onStart → onResume done                （onStart/onResume 里的主线程活）
#   3) onResume → Dart 侧「返回桌面」          （快照送达 + UI 复位）
#
# 计时全部取自日志**内容里的 at=<epoch ms>**（Dart 侧是它自己打的 epoch），
# 不用 logcat 的行时间：日志落盘是异步队列，行时间会被主线程排队推迟几百
# 毫秒到几秒，拿来算差值就是错的。
# 目的：把「按 home 回来不够流畅」从体感变成数字，改一次量一次。
#
# 例：
#   .\tools\verify-home-return.ps1
#   .\tools\verify-home-return.ps1 -Serial emulator-5554 -Rounds 6
#
# 车机上跑：先 `adb connect <车机IP>:5555`，再带 -Serial 指过去。

param(
    [string]$Serial = 'emulator-5554',
    [int]$Rounds = 3,
    [string]$ThirdParty = 'com.android.settings/.Settings',
    [int]$DwellMs = 1800,
    [int]$SettleMs = 3000
)

$ErrorActionPreference = 'Stop'
$adb = 'D:\platform-tools\adb.exe'
$pkg = 'xyz.i4o.uni.launcher'
$homeAct = "$pkg/.MainActivity"

if (-not (Test-Path $adb)) { throw "找不到 adb: $adb" }
if (((& $adb devices) -join "`n") -notmatch "$([regex]::Escape($Serial))\s+device") {
    throw "设备不可达: $Serial"
}

function At([string]$line) {
    if ($line -match 'at=(\d{13})') { return [long]$Matches[1] }
    return $null
}

# 重新安装会把默认 HOME 清掉，这里补回去，否则按 home 回到的是 AOSP 桌面。
& $adb -s $Serial shell "cmd package set-home-activity $homeAct" 2>&1 | Out-Null
& $adb -s $Serial shell "am force-stop $pkg" | Out-Null
& $adb -s $Serial shell "am start -W -n $homeAct" 2>&1 | Select-String 'TotalTime' | ForEach-Object { "冷启动: $($_.Line.Trim())" }
Start-Sleep -Seconds 4

$rows = @()
for ($i = 1; $i -le $Rounds; $i++) {
    & $adb -s $Serial shell "am start -a android.intent.action.MAIN -n $ThirdParty" 2>&1 | Out-Null
    Start-Sleep -Milliseconds $DwellMs
    & $adb -s $Serial logcat -c
    & $adb -s $Serial shell "input keyevent 3"
    Start-Sleep -Milliseconds $SettleMs

    $log = & $adb -s $Serial logcat -d -v time 2>&1 |
        Select-String '分发入口请求|launcher/onStart enter|launcher/onResume done|UNI-RESUME'
    $intent = $null; $onStart = $null; $onResume = $null; $dartHome = $null
    foreach ($line in $log) {
        $text = $line.ToString()
        if ($text -match '分发入口请求') { $v = At $text; if ($v) { $intent = $v } }
        elseif ($text -match 'launcher/onStart enter') { $v = At $text; if ($v) { $onStart = $v } }
        elseif ($text -match 'launcher/onResume done') { $v = At $text; if ($v) { $onResume = $v } }
        elseif ($text -match 'UNI-RESUME\] home (\d{13})') { $dartHome = [long]$Matches[1] }
    }
    if ($null -eq $intent -or $null -eq $onResume -or $null -eq $dartHome) {
        Write-Warning "run $i 缺少日志：intent=$intent onStart=$onStart onResume=$onResume dart=$dartHome"
        continue
    }
    # 抓错轮次（上一轮的尾巴）会让同一轮里出现隔了几十秒的锚点；整轮丢弃。
    # onResume 晚于 dartHome 是**正常**的：Dart 在引擎回调 onResume 之前就处理完
    # home 消息了，这正是优化目标，所以第 3 段允许是负数。
    $span = $dartHome - $intent
    if ($span -lt 0 -or $span -gt 10000 -or $onResume -lt $intent -or $onResume -gt ($dartHome + 2000)) {
        Write-Warning "run $i 锚点不在一轮里，已丢弃（intent=$intent onStart=$onStart onResume=$onResume dart=$dartHome）"
        continue
    }
    # onStart 早于 intent 太多同样说明抓到了上一轮（或冷启动那次）的锚点。
    if ($null -ne $onStart -and $onStart -lt ($intent - 500)) {
        Write-Warning "run $i onStart 是上一轮的残留，已丢弃（intent=$intent onStart=$onStart）"
        continue
    }
    $rows += [pscustomobject]@{
        run                  = $i
        '1_intent→onStart'   = if ($onStart) { [int]($onStart - $intent) } else { $null }
        '2_onStart→onResume' = [int]($onResume - $onStart)
        '3_onResume→dart'    = [int]($dartHome - $onResume)
        total                = [int]($dartHome - $intent)
    }
}

if ($rows.Count -eq 0) { throw '没抓到任何一轮完整时间线' }
$rows | Format-Table -AutoSize | Out-String | Write-Output

function Avg($values) {
    $clean = @($values | Where-Object { $null -ne $_ })
    if ($clean.Count -eq 0) { return $null }
    return [int](($clean | Measure-Object -Average).Average)
}
$med = @($rows.total | Sort-Object)
$summary = [pscustomobject]@{
    run                  = "$($rows.Count) 轮"
    '1_intent→onStart'   = Avg $rows.'1_intent→onStart'
    '2_onStart→onResume' = Avg $rows.'2_onStart→onResume'
    '3_onResume→dart'    = Avg $rows.'3_onResume→dart'
    total_avg            = Avg $rows.total
    total_p50            = $med[[int][math]::Floor(($med.Count - 1) / 2)]
    total_max            = ($med | Measure-Object -Maximum).Maximum
}
$summary | Format-Table -AutoSize | Out-String | Write-Output
