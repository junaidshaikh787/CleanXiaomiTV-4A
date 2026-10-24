# Disable the packages in a debloat list on the TV, one `pm disable-user` per adb call, checking each
# one before going on. Every package this script disables is recorded in the change manifest, which
# tools\restore.ps1 reads to undo exactly these changes. Nothing is uninstalled.
#
# Usage: tools\disable.ps1 debloat-mitv4a.txt [-Serial <ip:5555>] [-Manifest manifest\mi-tv-4a.json]
#        tools\disable.ps1 -Package <name>          (one package, same checks)
param(
    [Parameter(Position = 0)][string]$List,
    [string]$Package,
    [string]$Serial = $env:TV_SERIAL,
    [string]$Manifest
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in param defaults, so the default path is set here.
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\mi-tv-4a.json' }
. (Join-Path $PSScriptRoot 'adb.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
$Serial = Resolve-TvSerial $Serial

# Never disabled here: core Android, TV inputs, remote, keyboard, Play, casting, updates, and the two apps
# that can answer Home when the launcher is missing. The stock launcher has its own step after the new
# launcher is verified (launcher\set-home.ps1).
$protected = @(
    'android', 'com.android.systemui', 'com.android.settings', 'com.android.tv.settings', 'com.android.tv',
    'com.android.providers.tv', 'com.android.providers.settings', 'com.android.bluetooth', 'com.android.shell',
    'com.android.vending', 'com.google.android.gms', 'com.google.android.gsf', 'com.google.android.inputmethod.latin',
    'com.google.android.tv.remote.service', 'com.google.android.apps.mediashell', 'com.google.android.tvlauncher',
    'com.google.android.tungsten.setupwraith', 'com.duokan.factorytest', 'com.mitv.milinkservice',
    'com.xiaomi.mitv.updateservice', 'mitv.service', 'com.xiaomi.mitv.res', 'com.mitv.tvlock',
    'com.xiaomi.android.tvsetup.partnercustomizer'
)

if ($Package) { $pkgs = @($Package) }
elseif ($List) { $pkgs = @(Get-Content $List | ForEach-Object { ($_ -replace '#.*$', '').Trim() } | Where-Object { $_ }) }
else { throw 'pass a debloat list or -Package <name>' }

$m = Read-Manifest $Manifest $Serial
$installed = (Invoke-Tv $Serial 'pm list packages').Out -split "`n" | ForEach-Object { $_.Trim() -replace '^package:', '' }

foreach ($p in $pkgs) {
    if ($protected -contains $p -or $p -like 'com.droidlogic*') { throw "$p is protected and must stay enabled; remove it from the list" }
    if ($installed -notcontains $p) { Write-Host "skip  $p  (not installed on this TV)"; continue }
    $before = Get-PackageState $Serial $p
    if ($before -ne 'enabled') { Write-Host "skip  $p  (already $before before this project)"; continue }

    $r = Invoke-Tv $Serial "pm disable-user --user 0 $p"
    $after = Get-PackageState $Serial $p
    if ($r.Code -ne 0 -or $after -ne 'disabled') {
        throw "disabling $p failed (exit $($r.Code), state now '$after'): $($r.Out.Trim()) $($r.Err.Trim()). Stopped; nothing after it was touched."
    }
    Add-PackageChange $m $p $before
    Save-Manifest $m $Manifest
    Write-Host "done  $p  ($before -> disabled)"
}
Write-Host "Manifest: $Manifest"
