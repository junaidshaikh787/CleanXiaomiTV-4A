# Small speed tweaks for a low-RAM TV, recorded in the change manifest so tools\restore.ps1 puts the old
# values back. Nothing here touches packages or Home.
#
# Usage: tools\tune.ps1 [-Animations [-Scale 0.5]] [-PrivateDns [-DnsHost dns.adguard-dns.com]]
#                       [-Serial <ip:5555>] [-Manifest manifest\mi-tv-4a.json]
#        -Animations   window, transition and animator speed (Developer options): 0.5 = twice as fast menus.
#                      It does not change video playback.
#        -PrivateDns   DNS over TLS for the whole TV (Settings > Network > Private DNS), by default AdGuard's
#                      ad and tracker blocking server. Ads served from the same hosts as the video (YouTube)
#                      are not blocked.
param(
    [switch]$Animations,
    [string]$Scale = '0.5',
    [switch]$PrivateDns,
    [string]$DnsHost = 'dns.adguard-dns.com',
    [string]$Serial = $env:TV_SERIAL,
    [string]$Manifest
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in param defaults, so the default path is set here.
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\mi-tv-4a.json' }
. (Join-Path $PSScriptRoot 'adb.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
$Serial = Resolve-TvSerial $Serial
if (-not ($Animations -or $PrivateDns)) { throw 'nothing to do: pass -Animations and/or -PrivateDns' }

$m = Read-Manifest $Manifest $Serial

function Set-GlobalSetting([string]$Key, [string]$Value) {
    $old = (Invoke-Tv $Serial "settings get global $Key").Out.Trim()
    if ($old -eq $Value) { Write-Host "skip  global/$Key  (already $Value)"; return }
    Invoke-Tv $Serial "settings put global $Key $Value" | Out-Null
    $new = (Invoke-Tv $Serial "settings get global $Key").Out.Trim()
    if ($new -ne $Value) { throw "global/$Key did not change (now '$new')" }
    Add-SettingChange $m 'global' $Key $(if ($old) { $old } else { 'null' }) $Value
    Save-Manifest $m $Manifest
    Write-Host "done  global/$Key  ($old -> $Value)"
}

if ($Animations) {
    foreach ($key in 'window_animation_scale', 'transition_animation_scale', 'animator_duration_scale') {
        Set-GlobalSetting $key $Scale
    }
}
if ($PrivateDns) {
    # The host first: with the mode on and no host, the TV would have no DNS in between.
    Set-GlobalSetting 'private_dns_specifier' $DnsHost
    Set-GlobalSetting 'private_dns_mode' 'hostname'
}
Write-Host "Manifest: $Manifest"
