# Small speed tweaks for a low-RAM TV, recorded in the change manifest so tools\restore.ps1 puts the old
# values back. Nothing here touches packages or Home.
#
# Usage: tools\tune.ps1 -Animations [-Scale 0.5] [-Serial <ip:5555>] [-Manifest manifest\mi-tv-4a.json]
#        -Animations   window, transition and animator speed (Developer options): 0.5 = twice as fast menus.
#                      It does not change video playback.
param(
    [switch]$Animations,
    [string]$Scale = '0.5',
    [string]$Serial = $env:TV_SERIAL,
    [string]$Manifest
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in param defaults, so the default path is set here.
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\mi-tv-4a.json' }
. (Join-Path $PSScriptRoot 'adb.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
$Serial = Resolve-TvSerial $Serial
if (-not $Animations) { throw 'nothing to do: pass -Animations' }

$m = Read-Manifest $Manifest $Serial
foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
    $old = (Invoke-Tv $Serial "settings get global $key").Out.Trim()
    if ($old -eq $Scale) { Write-Host "skip  global/$key  (already $Scale)"; continue }
    Invoke-Tv $Serial "settings put global $key $Scale" | Out-Null
    $new = (Invoke-Tv $Serial "settings get global $key").Out.Trim()
    if ($new -ne $Scale) { throw "global/$key did not change (now '$new')" }
    Add-SettingChange $m 'global' $key $(if ($old) { $old } else { 'null' }) $Scale
    Save-Manifest $m $Manifest
    Write-Host "done  global/$key  ($old -> $Scale)"
}
Write-Host "Manifest: $Manifest"
