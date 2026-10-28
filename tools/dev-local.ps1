# 本地模拟器回路：构建 profile x64 → 覆盖安装 → 启动 → 跟踪日志。
#
# 用途边界（重要）：
#   能测：布局/视觉/交互/崩溃/状态机/冷启动的代码路径、日志埋点。
#   不能测：每帧耗时、fps、CPU%、PSS —— 模拟器是 x86_64 软件渲染，
#           与车机 MSM8996 + Adreno 530 不可比。性能数字必须上车。
#
# 例：
#   .\tools\dev-local.ps1                      # 默认 emulator-5554
#   .\tools\dev-local.ps1 -NoBuild             # 只重装已构建的包
#   .\tools\dev-local.ps1 -Attach              # 装完挂 DevTools profiler

param(
    [string]$Serial = 'emulator-5554',
    [switch]$NoBuild,
    [switch]$Attach,
    [string]$Filter = 'UNI-Startup|UNI app|E/flutter|FATAL',
    [switch]$Screenshot
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$app = Join-Path $root 'app'
$adb = 'D:\platform-tools\adb.exe'
$flutter = 'C:\dev\flutter\bin\flutter.bat'
$apk = Join-Path $app 'build\app\outputs\flutter-apk\app-profile.apk'
$pkg = 'xyz.i4o.uni.launcher'

if (-not (Test-Path $adb)) { throw "找不到 adb: $adb" }

& $adb devices | Select-String $Serial | ForEach-Object { "设备: $($_.Line.Trim())" }

if (-not $NoBuild) {
    Push-Location $app
    try {
        & $flutter build apk --profile --target-platform android-x64 2>&1 |
            Select-String 'Built|Error|error:' | ForEach-Object { $_.Line.Trim() }
        if ($LASTEXITCODE -ne 0) { throw 'flutter build 失败（不要复用旧的 APK）' }
    } finally { Pop-Location }
}
if (-not (Test-Path $apk)) { throw "缺少 $apk" }

# 安装器 UI 在模拟器上会自己崩（GrantPermissionsActivity），所以走 pm install。
& $adb -s $Serial push $apk /data/local/tmp/uni-test.apk | Out-Null
& $adb -s $Serial shell pm uninstall $pkg | Out-Null
$result = & $adb -s $Serial shell "pm install -r -g /data/local/tmp/uni-test.apk" 2>&1
if ($result -notmatch 'Success') { throw "安装失败: $result" }
"安装: Success"

& $adb -s $Serial logcat -c
& $adb -s $Serial shell am force-stop $pkg | Out-Null
$total = (& $adb -s $Serial shell am start -W -n "$pkg/.MainActivity" 2>&1 |
    Select-String 'TotalTime') -replace '.*TotalTime:\s*', ''
"启动: TotalTime ${total}ms"

Start-Sleep -Seconds 6
& $adb -s $Serial logcat -d 2>&1 |
    Select-String $Filter | ForEach-Object { $_.Line.Trim() } | Select-Object -Last 8

if ($Screenshot) {
    $dir = Join-Path (Split-Path -Parent $PSScriptRoot) 'artifacts'
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $file = Join-Path $dir ("local-{0:yyyyMMdd-HHmmss}.png" -f (Get-Date))
    & $adb -s $Serial exec-out screencap -p > $file
    "截图: $file"
}

if ($Attach) {
    "挂 DevTools…（性能面板看 UI/raster 拆分，只看相对占比，不看绝对值）"
    Push-Location $app
    try { & $flutter attach -d $Serial } finally { Pop-Location }
}
