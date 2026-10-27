#!/usr/bin/env pwsh
<#
.SYNOPSIS
  Repeatable performance probe for uni_launcher on a device or head unit.

.DESCRIPTION
  Read-mostly. Does not clear app data, change preferences, or uninstall
  anything. Everything it needs works on a non-rooted Android 9 device:
  am start -W, dumpsys gfxinfo/meminfo, logcat, screencap, pm path + apk pull.

  One pass produces:
    - identity: model, sdk, versionCode/Name, installed certificate, Impeller backend
    - coldStart: three force-stop + am start -W rounds, median total
    - idle: frames produced in 10s with the launcher untouched
    - interaction: gfxinfo reset, N horizontal page swipes, summary percentiles
    - memory: total PSS, native heap, graphics
    - artifacts: a screencap per pass, raw framestats CSV

.PARAMETER Label
  Name of this pass; becomes the report file name (e.g. before, after).

.EXAMPLE
  pwsh tools/car_perf_probe.ps1 -Label before -Serial 192.168.1.42:5555
#>
[CmdletBinding()]
param(
    [string]$Label = 'pass',
    [string]$Serial = '',
    [string]$Package = 'xyz.i4o.uni.launcher',
    [int]$ColdStartRounds = 3,
    [int]$IdleSeconds = 10,
    [int]$Swipes = 6,
    [string]$OutDir = '',
    [switch]$ClearData
)

$ErrorActionPreference = 'Stop'
$script:Adb = $null
$script:OutPath = $null

function Resolve-Tool([string]$Name, [string[]]$Candidates) {
    $cmd = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue
    # PATH may hold several adb copies; take the first one deterministically.
    if ($cmd) { return (@($cmd)[0]).Source }
    foreach ($c in $Candidates) { if (Test-Path $c) { return $c } }
    throw "Cannot find $Name. Pass its path or add it to PATH."
}

function Invoke-Adb([string]$Arguments) {
    # adb must receive each token as its own argv entry; none of the tokens this
    # probe sends contain spaces.
    $argv = @($Arguments -split '\s+' | Where-Object { $_ -ne '' })
    if ($Serial) { $raw = & $script:Adb -s $Serial @argv 2>&1 }
    else { $raw = & $script:Adb @argv 2>&1 }
    return ($raw | Out-String).Trim()
}

function Invoke-AdbLines([string]$Arguments) {
    $text = Invoke-Adb $Arguments
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    return $text -split "`r?`n"
}

function Median([double[]]$Values) {
    if (-not $Values -or $Values.Count -eq 0) { return $null }
    $sorted = $Values | Sort-Object
    $mid = [int][math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) { return [double]$sorted[$mid] }
    return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2
}

function Get-DeviceSize {
    $line = (Invoke-AdbLines 'shell wm size' | Where-Object { $_ -match '(\d+)x(\d+)' } | Select-Object -First 1)
    if (-not $line) { return @{ Width = 1920; Height = 1080 } }
    $null = $line -match '(\d+)x(\d+)'
    return @{ Width = [int]$Matches[1]; Height = [int]$Matches[2] }
}

function Parse-GfxSummary([string]$Text) {
    $result = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match 'Total frames rendered:\s*(\d+)') { $result.frames = [int]$Matches[1] }
        elseif ($line -match 'Janky frames:\s*(\d+)\s*\(([\d.]+)%\)') {
            $result.janky = [int]$Matches[1]; $result.jankyPercent = [double]$Matches[2]
        }
        elseif ($line -match '50th percentile:\s*(\d+)ms') { $result.p50Ms = [int]$Matches[1] }
        elseif ($line -match '90th percentile:\s*(\d+)ms') { $result.p90Ms = [int]$Matches[1] }
        elseif ($line -match '95th percentile:\s*(\d+)ms') { $result.p95Ms = [int]$Matches[1] }
        elseif ($line -match '99th percentile:\s*(\d+)ms') { $result.p99Ms = [int]$Matches[1] }
        elseif ($line -match 'Number Missed Vsync:\s*(\d+)') { $result.missedVsync = [int]$Matches[1] }
        elseif ($line -match 'Number Slow UI thread:\s*(\d+)') { $result.slowUi = [int]$Matches[1] }
        elseif ($line -match 'Number Slow issue draw commands:\s*(\d+)') { $result.slowDraw = [int]$Matches[1] }
    }
    return $result
}

function Parse-Meminfo([string]$Text) {
    $result = @{}
    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '^\s*TOTAL\s+(\d+)') { $result.totalPssKb = [int]$Matches[1] }
        elseif ($line -match '^\s*Native Heap\s+(\d+)') { $result.nativeHeapKb = [int]$Matches[1] }
        elseif ($line -match '^\s*Java Heap:\s+(\d+)') { $result.javaHeapKb = [int]$Matches[1] }
        elseif ($line -match '^\s*Graphics:\s+(\d+)') { $result.graphicsKb = [int]$Matches[1] }
    }
    return $result
}

function Write-Step([string]$Message) { Write-Host "[$Label] $Message" }

# --- setup -------------------------------------------------------------------
$script:Adb = Resolve-Tool 'adb' @('E:\Android\Sdk\platform-tools\adb.exe', "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe")
if (-not $Serial) {
    $first = (Invoke-AdbLines 'devices' | Where-Object { $_ -match '^(\S+)\s+device$' } | Select-Object -First 1)
    if (-not $first -or $first -notmatch '^(\S+)\s+device$') { throw 'No authorised device. Run: Invoke-Adb devices' }
    $Serial = $Matches[1]
}
$repo = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) { $OutDir = Join-Path $repo 'car-reports\perf' }
$script:OutPath = Join-Path $OutDir $Label
New-Item -ItemType Directory -Force -Path $script:OutPath | Out-Null

$report = [ordered]@{
    label      = $Label
    checkedAt  = (Get-Date).ToString('o')
    serial     = $Serial
    package    = $Package
    device     = @{}
    identity   = @{}
    coldStart  = @{}
    idle       = @{}
    interaction = @{}
    memory     = @{}
    notes      = @()
}

Write-Step "device $Serial"
$report.device = @{
    model   = (Invoke-Adb 'shell getprop ro.product.model')
    sdk     = (Invoke-Adb 'shell getprop ro.build.version.sdk')
    build   = (Invoke-Adb 'shell getprop ro.build.display.id')
    size    = (Invoke-Adb 'shell wm size')
    density = (Invoke-Adb 'shell wm density')
}

# --- identity ----------------------------------------------------------------
$dumpsysPackage = Invoke-Adb "shell dumpsys package $Package"
$versionCode = if ($dumpsysPackage -match 'versionCode=(\d+)') { [int]$Matches[1] } else { $null }
$versionName = if ($dumpsysPackage -match 'versionName=([^\s]+)') { $Matches[1] } else { $null }
$apkPath = ((Invoke-AdbLines "shell pm path $Package") | Where-Object { $_ -match '^package:(.+)$' } | ForEach-Object { $Matches[1] } | Select-Object -First 1)
$certSha256 = $null
if ($apkPath) {
    $localApk = Join-Path $script:OutPath 'installed-base.apk'
    if ($Serial) { & $script:Adb -s $Serial pull $apkPath $localApk 1>$null 2>$null }
    else { & $script:Adb pull $apkPath $localApk 1>$null 2>$null }
    if (Test-Path $localApk) {
        $apksigner = Resolve-Tool 'apksigner' @(
            'E:\Android\Sdk\build-tools\37.0.0\apksigner.bat',
            'E:\Android\Sdk\build-tools\36.0.0\apksigner.bat')
        $certText = (& $apksigner verify --print-certs $localApk 2>&1 | Out-String)
        if ($certText -match 'certificate SHA-256 digest:\s*([0-9a-f]+)') { $certSha256 = $Matches[1] }
        Remove-Item $localApk -Force -ErrorAction SilentlyContinue
    }
}
# The backend line only appears in logs written while the engine starts.
Invoke-Adb 'logcat -c' | Out-Null
$report.identity = @{
    versionCode    = $versionCode
    versionName    = $versionName
    certificate    = $certSha256
    expectedCertificate = 'c8a2e9bccf597c2fb6dc66bee293fc13f2fc47ec77bc6b2b0d52c11f51192ab8'
}

if ($ClearData) {
    Write-Step 'clearing app data (-ClearData)'
    Invoke-Adb "shell pm clear $Package" | Out-Null
}

if ($null -eq $versionCode) {
    throw "$Package is not installed on $Serial (or dumpsys returned nothing). Install a build before probing."
}

# --- cold start --------------------------------------------------------------
$cold = @()
for ($i = 1; $i -le $ColdStartRounds; $i++) {
    Invoke-Adb "shell am force-stop $Package" | Out-Null
    Start-Sleep -Milliseconds 1200
    $startOutput = Invoke-Adb "shell am start -W -n $Package/.MainActivity"
    $total = if ($startOutput -match 'TotalTime:\s*(\d+)') { [int]$Matches[1] } else { $null }
    $state = if ($startOutput -match 'LaunchState:\s*(\w+)') { $Matches[1] } else { $null }
    $cold += [pscustomobject]@{ round = $i; totalTimeMs = $total; launchState = $state }
    Start-Sleep -Milliseconds 800
}
$coldValues = @($cold | Where-Object { $_.totalTimeMs } | ForEach-Object { [double]$_.totalTimeMs })
$report.coldStart = @{
    rounds      = $cold
    medianTotalMs = (Median $coldValues)
    minTotalMs  = if ($coldValues) { ($coldValues | Measure-Object -Minimum).Minimum } else { $null }
    maxTotalMs  = if ($coldValues) { ($coldValues | Measure-Object -Maximum).Maximum } else { $null }
}

# The engine start line is now in logcat.
$backendLog = (Invoke-Adb 'logcat -d -t 400') -split "`r?`n" |
    Where-Object { $_ -match '(?i)impeller|vulkan|opengles|gl_es' } |
    Select-Object -First 12
$report.identity['backendLog'] = @($backendLog)

Start-Sleep -Seconds 3

# --- idle --------------------------------------------------------------------
Write-Step "idle ${IdleSeconds}s"
Invoke-Adb "shell dumpsys gfxinfo $Package reset" | Out-Null
Start-Sleep -Seconds $IdleSeconds
$idleSummary = Parse-GfxSummary (Invoke-Adb "shell dumpsys gfxinfo $Package")
$report.idle = @{
    seconds = $IdleSeconds
    frames  = $idleSummary.frames
    fps     = if ($idleSummary.frames -ne $null) { [math]::Round($idleSummary.frames / $IdleSeconds, 2) } else { $null }
    percentile = $idleSummary
    hint    = 'fps near 60 means something animates forever; a handful of frames is normal'
}

# --- interaction -------------------------------------------------------------
Write-Step "$Swipes page swipes"
$size = Get-DeviceSize
$y = [int]($size.Height * 0.42)
$xStart = [int]($size.Width * 0.72)
$xEnd = [int]($size.Width * 0.28)
Invoke-Adb "shell dumpsys gfxinfo $Package reset" | Out-Null
for ($i = 1; $i -le $Swipes; $i++) {
    if ($i % 2 -eq 1) { Invoke-Adb "shell input swipe $xStart $y $xEnd $y 260" | Out-Null }
    else { Invoke-Adb "shell input swipe $xEnd $y $xStart $y 260" | Out-Null }
    Start-Sleep -Milliseconds 450
}
Start-Sleep -Milliseconds 600
$framestatsPath = Join-Path $script:OutPath 'framestats.csv'
Invoke-Adb "shell dumpsys gfxinfo $Package framestats" | Set-Content -Path $framestatsPath -Encoding utf8
$interactionSummary = Parse-GfxSummary (Invoke-Adb "shell dumpsys gfxinfo $Package")
$report.interaction = @{
    swipes     = $Swipes
    summary    = $interactionSummary
    framestats = $framestatsPath
}

# --- memory ------------------------------------------------------------------
$memText = Invoke-Adb "shell dumpsys meminfo $Package"
$report.memory = Parse-Meminfo $memText
($memText -split "`r?`n") | Where-Object { $_ -match 'TOTAL:|Native Heap|Graphics|App Summary|Dart|Flutter' } |
    Set-Content -Path (Join-Path $script:OutPath 'meminfo.txt') -Encoding utf8

# --- artifacts ---------------------------------------------------------------
$shot = Join-Path $script:OutPath 'screen.png'
$remote = '/sdcard/uni-perf-probe.png'
Invoke-Adb "shell screencap -p $remote" | Out-Null
if ($Serial) { & $script:Adb -s $Serial pull $remote $shot 1>$null 2>$null } else { & $script:Adb pull $remote $shot 1>$null 2>$null }
Invoke-Adb "shell rm -f $remote" | Out-Null

$report['artifacts'] = @{
    dir     = $script:OutPath
    screen  = $shot
    rawGfx  = $framestatsPath
}

$jsonPath = Join-Path $OutDir "$Label.json"
$report | ConvertTo-Json -Depth 8 | Set-Content -Path $jsonPath -Encoding utf8
Write-Step "report: $jsonPath"
Write-Host ((Get-Content $jsonPath -Raw))

# Two passes are only comparable when this line is identical.
if ($certSha256 -and $certSha256 -ne $report.identity.expectedCertificate) {
    Write-Warning "installed certificate $certSha256 differs from the IP753 certificate; A/B across builds is not meaningful"
}
