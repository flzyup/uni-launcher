# 车机一条命令验收：构建 → 签名 → 安装 → 校验 → 冷启动 ×3 → 翻页 ×3。
#
# 目的：把车上调试压缩成"一条命令 + 一张表"，避免每次手工 adb。
#
# 例：
#   .\tools\car-verify.ps1                    # 全流程（约 6-8 分钟）
#   .\tools\car-verify.ps1 -SkipBuild         # 只装已签名包并测
#   .\tools\car-verify.ps1 -OnlyTurns         # 只测翻页

param(
    [string]$Serial = '192.168.22.197:5555',
    [switch]$SkipBuild,
    [switch]$OnlyTurns,
    [int]$Rounds = 3
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$adb = 'D:\platform-tools\adb.exe'
$flutter = 'C:\dev\flutter\bin\flutter.bat'
$signed = Join-Path $app 'build\app\outputs\flutter-apk\UNI-Launcher-0.6.18-IP753.apk'
$pkg = 'xyz.i4o.uni.launcher'

function Connect {
    $state = (& $adb devices) -join "`n"
    if ($state -notmatch [regex]::Escape($Serial) -or $state -match "$([regex]::Escape($Serial))\s+offline") {
        & $adb connect $Serial | Out-Null
        Start-Sleep -Seconds 2
    }
    if (((& $adb devices) -join "`n") -notmatch "$([regex]::Escape($Serial))\s+device") {
        throw "车机不可达（$Serial）。无线 adb 常因休眠掉线：唤醒车机后再跑，或先 adb connect。"
    }
}

function UpNs { [long]((((& $adb -s $Serial shell cat /proc/uptime) -join ' ') -split '\s+')[0] -as [double]) * 1e9 }

function Frames([long]$t0, [long]$t1) {
    $best = @()
    foreach ($l in ((& $adb -s $Serial shell 'dumpsys SurfaceFlinger --list' 2>&1) |
            Where-Object { $_ -match "^SurfaceView - $([regex]::Escape($pkg))/" })) {
        $rows = & $adb -s $Serial shell "dumpsys SurfaceFlinger --latency '$($l.Trim())'" 2>&1 | Select-Object -Skip 1
        $ts = @()
        foreach ($r in $rows) {
            $f = $r.Trim() -split '\s+'
            if ($f.Count -ge 3) {
                $pv = 0L
                if ([long]::TryParse($f[1], [ref]$pv) -and $pv -ge $t0 -and $pv -le $t1) { $ts += $pv }
            }
        }
        if ($ts.Count -gt $best.Count) { $best = $ts }
    }
    return , ($best | Sort-Object)
}

function Threads {
    $pid_ = ((& $adb -s $Serial shell pidof $pkg) -join '').Trim()
    $o = @{}
    foreach ($t in ((& $adb -s $Serial shell "ls /proc/$pid_/task") -split "`n")) {
        $t = $t.Trim(); if (-not $t) { continue }
        $st = ((& $adb -s $Serial shell "cat /proc/$pid_/task/$t/stat 2>/dev/null") -split '\s+')
        if ($st.Count -gt 14) { $o[$t] = @{ n = ($st[1] -replace '[()]', ''); c = ([long]$st[13] + [long]$st[14]) } }
    }
    return $o
}

Connect

if (-not $SkipBuild) {
    Push-Location $app
    try {
        & $flutter build apk --release --target-platform android-arm64 2>&1 |
            Select-String 'Built|Error|error:' | ForEach-Object { $_.Line.Trim() }
        if ($LASTEXITCODE -ne 0) { throw 'flutter build 失败（注意：失败时会留下旧 app-release.apk，别被它骗了）' }
    } finally { Pop-Location }
    python (Join-Path $env:TEMP 'make_car_apk.py') 2>&1 | Select-String 'sha256' | ForEach-Object { $_.Line.Trim() }
    if (-not (Test-Path $signed)) { throw "缺少签名包 $signed" }
}

& $adb -s $Serial install -r -d $signed 2>&1 | Select-String 'Success|Failure' | ForEach-Object { $_.Line.Trim() }

$path = ((& $adb -s $Serial shell pm path $pkg 2>&1) -join '').Trim() -replace '^package:', ''
$remote = ((& $adb -s $Serial shell "md5sum $path" 2>&1) -join '').Split(' ')[0]
$local = (Get-FileHash $signed -Algorithm MD5).Hash.ToLower()
"校验: 车上 $remote / 本地 $local → " + ($remote -eq $local)

& $adb -s $Serial shell svc power stayon true | Out-Null

if (-not $OnlyTurns) {
    "--- 冷启动（${Rounds} 轮）---"
    $starts = @()
    for ($i = 1; $i -le $Rounds; $i++) {
        & $adb -s $Serial shell am force-stop $pkg | Out-Null
        Start-Sleep -Seconds 3
        $t = ((& $adb -s $Serial shell am start -W -n "$pkg/.MainActivity" 2>&1 |
                Select-String 'TotalTime')) -replace '.*TotalTime:\s*', ''
        $starts += [int]$t
        "  第 $i 轮: ${t}ms"
    }
    $sorted = $starts | Sort-Object
    "  中位 $($sorted[[int]($sorted.Count / 2)])ms | 最快 $($sorted[0])ms | 最慢 $($sorted[-1])ms"
    & $adb -s $Serial shell input keyevent KEYCODE_HOME | Out-Null
    Start-Sleep -Seconds 8
}

"--- 地图容器配置（虚拟显示尺寸与密度）---"
$disp = ((& $adb -s $Serial shell "dumpsys display" 2>&1) -join "`n")
if ($disp -match '(?s)UNI Live Navigation.{0,400}?') {
    $block = $Matches[0]
    $size = if ($block -match '(\d+) x (\d+)') { "$($Matches[1])x$($Matches[2])" } else { '?' }
    $dpi = if ($block -match 'density (\d+)') { $Matches[1] } else { '?' }
    "  尺寸 $size @ $dpi dpi   （dp = 尺寸 ÷ (dpi/160)，应与 1:1 时一致）"
} else { '  地图容器未创建（桌面不在前台或导航未启动）' }

"--- 翻页（${Rounds} 轮，横向拖动 2.5s）---"
for ($i = 1; $i -le $Rounds; $i++) {
    & $adb -s $Serial shell input keyevent KEYCODE_HOME | Out-Null
    Start-Sleep -Seconds 4
    $a = Threads
    $ka = ($a.Keys | Where-Object { $a[$_].n -like '*uni.launcher' } | Select-Object -First 1)
    $kr = ($a.Keys | Where-Object { $a[$_].n -eq '1.raster' } | Select-Object -First 1)
    $t0 = UpNs
    & $adb -s $Serial shell input swipe 300 600 1400 600 2500 | Out-Null
    $t1 = UpNs
    $b = Threads
    $ts = Frames $t0 $t1
    $n = $ts.Count
    $sec = ($t1 - $t0) / 1e9
    if ($n -lt 10) { "  第 $i 轮: 只采到 $n 帧，作废（桌面可能不在前台或地图容器死了）"; continue }
    $ui = [math]::Round((($b[$ka].c - $a[$ka].c) / 100) / $n * 1000, 1)
    $ra = [math]::Round((($b[$kr].c - $a[$kr].c) / 100) / $n * 1000, 1)
    $d = @()
    for ($j = 1; $j -lt $n; $j++) { $d += [math]::Round(($ts[$j] - $ts[$j - 1]) / 1e6, 1) }
    $ds = $d | Sort-Object
    $p50 = $ds[[int]($ds.Count * 0.5)]
    $ok = [math]::Round((@($d | Where-Object { $_ -le 25 }).Count) / $d.Count * 100)
    "  第 $i 轮: $n 帧 = $([math]::Round($n / $sec, 1))fps | p50 ${p50}ms | UI ${ui}ms | raster ${ra}ms | 达 40fps 的帧占 ${ok}%"
}
