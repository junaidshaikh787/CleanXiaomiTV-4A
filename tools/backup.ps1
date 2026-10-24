# Read-only snapshot of the TV before anything is changed: package lists, settings, Home, inputs and a
# screenshot, into backups\<model>-<yyyyMMdd-HHmmss>\. Nothing on the TV is modified.
# The folder holds the TV's serial and network names, so backups\ stays out of git (.gitignore).
#
# Usage: tools\backup.ps1 [-Serial <ip:5555>]     (default: $env:TV_SERIAL, else the only adb device)
param([string]$Serial = $env:TV_SERIAL)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'adb.ps1')
$Serial = Resolve-TvSerial $Serial

$model = (Invoke-Tv $Serial 'getprop ro.product.device').Out.Trim()
$dir = Join-Path (Split-Path -Parent $PSScriptRoot) ("backups\$model-" + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Force $dir | Out-Null
$failed = @()

# One file per command; stderr goes to <name>.err only when there is any.
function Save([string]$Name, [string]$Command) {
    $r = Invoke-Tv $Serial $Command
    [IO.File]::WriteAllText((Join-Path $dir "$Name.txt"), $r.Out)
    if ($r.Err.Trim()) { [IO.File]::WriteAllText((Join-Path $dir "$Name.err"), $r.Err) }
    if ($r.Code -ne 0) { $script:failed += "$Name (exit $($r.Code))" }
}

Save 'getprop'               'getprop'
Save 'packages-all'          'pm list packages -f -U'
Save 'packages-disabled'     'pm list packages -d'
Save 'packages-enabled'      'pm list packages -e'
Save 'packages-system'       'pm list packages -s'
Save 'packages-third-party'  'pm list packages -3'
Save 'settings-global'       'settings list global'
Save 'settings-system'       'settings list system'
Save 'settings-secure'       'settings list secure'
Save 'home-resolved'         'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
Save 'home-candidates'       'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
Save 'leanback-launchable'   'cmd package query-activities --brief -a android.intent.action.MAIN -c android.intent.category.LEANBACK_LAUNCHER'
Save 'preferred-activities'  'dumpsys package preferred-xml'
Save 'dumpsys-package'       'dumpsys package'
Save 'display'               'wm size; wm density; dumpsys display | grep -E "mBaseDisplayInfo|DisplayDeviceInfo" | head -5'
Save 'tv-inputs'             'dumpsys tv_input'
Save 'input-method'          'dumpsys input_method'
Save 'accessibility'         'dumpsys accessibility'
Save 'meminfo'               'cat /proc/meminfo'
Save 'storage'               'df -h /data'
Save 'usb-devices'           'for d in /sys/bus/usb/devices/*; do echo "$d $(cat $d/product 2>/dev/null)"; done'

# Original Home screen: go Home, then capture on the TV and pull (binary-safe, unlike piping exec-out).
Invoke-Tv $Serial 'input keyevent KEYCODE_HOME' | Out-Null
Start-Sleep -Seconds 3
$shot = Join-Path $dir 'home-original.png'
Invoke-Tv $Serial 'screencap -p /sdcard/backup-home.png' | Out-Null
Invoke-Adb $Serial "pull /sdcard/backup-home.png `"$shot`"" | Out-Null
Invoke-Tv $Serial 'rm -f /sdcard/backup-home.png' | Out-Null
$png = if (Test-Path $shot) { [IO.File]::ReadAllBytes($shot) } else { @() }
if ($png.Length -lt 8 -or $png[0] -ne 0x89 -or $png[1] -ne 0x50) { $failed += 'home-original.png (not a PNG)' }

# Summary for humans and for restore.ps1: original Home and the packages already disabled before us.
$prop = { param($p) (Invoke-Tv $Serial "getprop $p").Out.Trim() }
$stockPkg = (Invoke-Tv $Serial 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME').Out.Trim().Split("`n")[-1].Trim()
$summary = [ordered]@{
    taken           = (Get-Date -Format 's')
    model           = & $prop 'ro.product.model'
    device          = $model
    android         = & $prop 'ro.build.version.release'
    sdk             = & $prop 'ro.build.version.sdk'
    build           = & $prop 'ro.build.display.id'
    security_patch  = & $prop 'ro.build.version.security_patch'
    home_activity   = $stockPkg
    already_disabled = @((Invoke-Tv $Serial 'pm list packages -d').Out -split "`n" | ForEach-Object { $_.Trim() -replace '^package:', '' } | Where-Object { $_ })
    private_dns_mode = (Invoke-Tv $Serial 'settings get global private_dns_mode').Out.Trim()
    screensaver     = (Invoke-Tv $Serial 'settings get secure screensaver_components').Out.Trim()
    accessibility   = (Invoke-Tv $Serial 'settings get secure enabled_accessibility_services').Out.Trim()
}
$summary | ConvertTo-Json | Out-File -Encoding utf8 (Join-Path $dir 'summary.json')

Write-Host "Backup: $dir"
Get-ChildItem $dir | ForEach-Object { '{0,-28} {1,10:N0} bytes' -f $_.Name, $_.Length } | Write-Host
if ($failed) { Write-Warning ("Not captured: " + ($failed -join ', ')); exit 1 }
