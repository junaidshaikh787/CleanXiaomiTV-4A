# Undo what this project changed on the TV, using the change manifest: re-enable every package it
# disabled, give Home back to the original launcher, and put back settings it changed (only where the
# setting still has the value this project set, so later changes of your own are left alone).
# Safe to run more than once. Packages that were already disabled before the project stay as they were.
#
# Usage: tools\restore.ps1 [-Serial <ip:5555>] [-Manifest manifest\mi-tv-4a.json] [-UninstallLauncher]
param(
    [string]$Serial = $env:TV_SERIAL,
    [string]$Manifest,
    [switch]$UninstallLauncher
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in param defaults, so the default path is set here.
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\mi-tv-4a.json' }
. (Join-Path $PSScriptRoot 'adb.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
$Serial = Resolve-TvSerial $Serial
if (-not (Test-Path $Manifest)) { throw "no manifest at ${Manifest}: nothing was changed by this project, or pass -Manifest" }
$m = Read-Manifest $Manifest $Serial
$failed = @()

# 1. Packages, one adb call each, checked afterwards.
foreach ($c in $m.packages) {
    $p = $c.package
    $state = Get-PackageState $Serial $p
    if ($state -eq 'missing') { Write-Host "skip  $p  (no longer installed)"; continue }
    if ($state -eq 'enabled') { Write-Host "ok    $p  (already enabled)"; continue }
    $r = Invoke-Tv $Serial "pm enable --user 0 $p"
    if ((Get-PackageState $Serial $p) -eq 'enabled') { Write-Host "done  $p  re-enabled" }
    else { $failed += $p; Write-Warning "could not re-enable $p (exit $($r.Code)): $($r.Out.Trim()) $($r.Err.Trim())" }
}

# 2. Settings, only where the TV still holds the value this project set.
foreach ($s in $m.settings) {
    $now = (Invoke-Tv $Serial "settings get $($s.namespace) $($s.key)").Out.Trim()
    if ($now -ne $s.set) { Write-Host "skip  $($s.namespace)/$($s.key)  (now '$now', changed since; left alone)"; continue }
    $cmd = if ($s.key -eq 'location_providers_allowed') {
        # Android 9 only takes +provider / -provider here: switch off each provider this project switched on.
        (@($s.set -split ',' | Where-Object { $_ -and ($s.before -notmatch $_) }) | ForEach-Object { "settings put secure location_providers_allowed -$_" }) -join '; '
    } elseif ($s.key -eq 'location_mode' -and ($null -eq $s.before -or $s.before -eq 'null')) {
        'settings put secure location_mode 0'   # off; deleting the key would not switch Location off
    } elseif ($null -eq $s.before -or $s.before -eq 'null') { "settings delete $($s.namespace) $($s.key)" } else { "settings put $($s.namespace) $($s.key) '$($s.before)'" }
    Invoke-Tv $Serial $cmd | Out-Null
    Write-Host "done  $($s.namespace)/$($s.key) -> $($s.before)"
}

# 3. Runtime permissions granted to our apps (skipped when the app is gone).
foreach ($g in $m.permissions) {
    if ((Get-PackageState $Serial $g.package) -eq 'missing') { continue }
    Invoke-Tv $Serial "pm revoke $($g.package) $($g.permission)" | Out-Null
    Write-Host "done  $($g.permission) revoked from $($g.package)"
}

# 4. Home back to the launcher that had it before (after its package is enabled above).
$orig = $m.original_home
if ($orig -and $orig -match '/') {
    $r = Invoke-Tv $Serial "cmd package set-home-activity --user 0 $orig"
    $homeNow = (Invoke-Tv $Serial 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME').Out.Trim().Split("`n")[-1].Trim()
    if ($homeNow -eq $orig) { Write-Host "done  Home -> $homeNow" }
    else { $failed += 'home'; Write-Warning "Home resolves to '$homeNow', expected $orig. On the TV: press Home and pick the original launcher, or Settings > Apps to enable it." }
}

if ($UninstallLauncher) {
    $r = Invoke-Tv $Serial 'pm uninstall com.majnioui.cleanxiaomitv'
    Write-Host "launcher uninstall: $($r.Out.Trim())"
}

Write-Host ''
Write-Host 'Still disabled on the TV:'
(Invoke-Tv $Serial 'pm list packages -d').Out.Trim() | Write-Host
Write-Host 'Manual steps, if wanted: the screensaver is untouched by this project; anything you changed in TV Settings yourself is not undone here.'
if ($failed) { Write-Warning ('Not restored: ' + ($failed -join ', ')); exit 1 }
Write-Host 'Restore complete.'
