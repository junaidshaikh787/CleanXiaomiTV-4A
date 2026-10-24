# Push a theme folder (config.json and optionally wallpaper.jpg) to the launcher on the TV and restart Home,
# no rebuild needed. See themes/README.md for the keys. -Reset removes the theme again.
#
# Usage: tools\theme.ps1 themes\aurora [-Serial <ip:5555>]
#        tools\theme.ps1 -Reset [-Serial <ip:5555>]
param(
    [Parameter(Position = 0)][string]$Theme,
    [switch]$Reset,
    [string]$Serial = $env:TV_SERIAL
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'adb.ps1')
$Serial = Resolve-TvSerial $Serial
$pkg = 'com.majnioui.cleanxiaomitv'
$restart = "am force-stop $pkg; am start -n $pkg/com.gathin.tvhome.MainActivity >/dev/null"
$dir = "/sdcard/Android/data/$pkg/files"

if ($Reset) {
    Invoke-Tv $Serial "rm -f $dir/config.json $dir/wallpaper.jpg; $restart" | Out-Null
    Write-Host 'Theme removed; the launcher uses config.xml again.'
    exit 0
}
if (-not $Theme) { throw 'usage: theme.ps1 <theme folder> | -Reset' }
$Theme = (Resolve-Path $Theme).Path
$config = Join-Path $Theme 'config.json'
if (-not (Test-Path $config)) { throw "no config.json in $Theme" }
try { Get-Content $config -Raw | ConvertFrom-Json | Out-Null } catch { throw "$config is not valid JSON" }

Invoke-Tv $Serial "mkdir -p $dir" | Out-Null
$r = Invoke-Adb $Serial "push `"$config`" $dir/config.json"
if ($r.Code -ne 0) { throw "could not push config.json: $($r.Err.Trim())" }
$wall = Join-Path $Theme 'wallpaper.jpg'
if (Test-Path $wall) {
    $r = Invoke-Adb $Serial "push `"$wall`" $dir/wallpaper.jpg"
    if ($r.Code -ne 0) { throw "could not push wallpaper.jpg: $($r.Err.Trim())" }
} else {
    Invoke-Tv $Serial "rm -f $dir/wallpaper.jpg" | Out-Null
}
Invoke-Tv $Serial $restart | Out-Null
Write-Host "Theme $(Split-Path $Theme -Leaf) is on the TV. Undo with: tools\theme.ps1 -Reset"
