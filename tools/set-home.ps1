# Make the installed launcher the TV's default Home, and optionally let it show the Wi-Fi name. Each change
# is recorded in the change manifest; tools\restore.ps1 gives Home back to the original launcher and revokes
# the permission. The stock launcher is disabled only with -DisableStock.
#
# Usage: tools\set-home.ps1 [-Serial <ip:5555>] [-WifiName] [-DisableStock] [-Manifest manifest\mi-tv-4a.json]
#        -DisableStock  disable Android TV's stock launcher, whose higher HOME priority beats any default;
#                       re-enabled straight away if Home still does not switch. Undo: tools\restore.ps1.
#        -LocationOn    turn the TV's Location on (system-wide), which Android 9 needs to show the Wi-Fi name.
#        -WifiName   grant location permission to the launcher: Android 9 hides the network name from apps
#                    without it (and also while Location is off in the TV's settings).
param(
    [string]$Serial = $env:TV_SERIAL,
    [switch]$WifiName,
    [switch]$DisableStock,
    [switch]$LocationOn,
    [string]$Manifest
)
$ErrorActionPreference = 'Stop'
# Windows PowerShell leaves $PSScriptRoot empty in param defaults, so the default path is set here.
if (-not $Manifest) { $Manifest = Join-Path (Split-Path -Parent $PSScriptRoot) 'manifest\mi-tv-4a.json' }
. (Join-Path $PSScriptRoot 'adb.ps1')
. (Join-Path $PSScriptRoot 'manifest.ps1')
$Serial = Resolve-TvSerial $Serial

$pkg = 'com.majnioui.cleanxiaomitv'
$component = "$pkg/com.gathin.tvhome.MainActivity"
$homeQuery = 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME'
if ((Get-PackageState $Serial $pkg) -ne 'enabled') { throw "$pkg is not installed (or disabled); run launcher\build-and-install.ps1 first" }
$m = Read-Manifest $Manifest $Serial

if ($WifiName) {
    $perm = 'android.permission.ACCESS_FINE_LOCATION'
    $r = Invoke-Tv $Serial "pm grant $pkg $perm"
    $granted = (Invoke-Tv $Serial "dumpsys package $pkg").Out -match "$perm`: granted=true"
    if (-not $granted) { throw "could not grant $perm ($($r.Out.Trim()) $($r.Err.Trim()))" }
    Add-PermissionChange $m $pkg $perm
    Save-Manifest $m $Manifest
    Write-Host "done  $perm granted to $pkg"
    $loc = (Invoke-Tv $Serial 'settings get secure location_providers_allowed').Out.Trim()
    if (-not $LocationOn -and (-not $loc -or $loc -eq 'null')) {
        Write-Warning 'Location is off on the TV, and Android 9 also hides the Wi-Fi name while it is. Turning it on is a system-wide choice: -LocationOn, or Settings > Device Preferences > Location.'
    }
}

# Location on, recorded with the old values so restore.ps1 turns it off again. This TV has no network location
# provider (+network is silently dropped); location_mode 3 is what Settings' own switch sets, and Android 9 then
# lists the provider it can (gps) and counts Location as on.
if ($LocationOn) {
    $oldMode = (Invoke-Tv $Serial 'settings get secure location_mode').Out.Trim()
    $oldProviders = (Invoke-Tv $Serial 'settings get secure location_providers_allowed').Out.Trim()
    if ($oldMode -and $oldMode -ne 'null' -and $oldMode -ne '0') {
        Write-Host "skip  Location already on (location_mode $oldMode)"
    } else {
        Invoke-Tv $Serial 'settings put secure location_mode 3' | Out-Null
        $newMode = (Invoke-Tv $Serial 'settings get secure location_mode').Out.Trim()
        $newProviders = (Invoke-Tv $Serial 'settings get secure location_providers_allowed').Out.Trim()
        if ($newMode -ne '3' -or -not $newProviders) { throw "Location did not turn on (location_mode '$newMode', providers '$newProviders')" }
        Add-SettingChange $m 'secure' 'location_providers_allowed' $(if ($oldProviders) { $oldProviders } else { 'null' }) $newProviders
        Add-SettingChange $m 'secure' 'location_mode' $(if ($oldMode) { $oldMode } else { 'null' }) $newMode
        Save-Manifest $m $Manifest
        Write-Host "done  Location on (location_mode '$oldMode' -> 3, providers '$newProviders')"
    }
}

# A system launcher with a higher HOME priority (Android TV's stock one has 2; apps get 0) wins over any default,
# so it has to be disabled for this launcher to become Home. Only with -DisableStock, and undone on failure.
if ($DisableStock) {
    $stock = 'com.google.android.tvlauncher'
    $state = Get-PackageState $Serial $stock
    if ($state -eq 'enabled') {
        $r = Invoke-Tv $Serial "pm disable-user --user 0 $stock"
        if ((Get-PackageState $Serial $stock) -ne 'disabled') { throw "could not disable $stock ($($r.Out.Trim()) $($r.Err.Trim()))" }
        Add-PackageChange $m $stock 'enabled'
        Save-Manifest $m $Manifest
        Write-Host "done  $stock disabled"
    } else {
        Write-Host "skip  $stock is $state"
    }
}

$before = (Invoke-Tv $Serial $homeQuery).Out.Trim().Split("`n")[-1].Trim()
if ($before -eq $component) {
    Write-Host "Home already opens $component"
} else {
    # Android 9 accepts only a component here (Android 10+ also takes a package).
    $r = Invoke-Tv $Serial "cmd package set-home-activity --user 0 $component"
    # Recorded before checking: the preference is stored even when a higher-priority Home still wins.
    if (-not $m.home) { $m.home = [pscustomobject]@{ before = $before; set = $component; at = (Get-Date -Format 's') } }
    Save-Manifest $m $Manifest
    $after = (Invoke-Tv $Serial $homeQuery).Out.Trim().Split("`n")[-1].Trim()
    if ($after -ne $component) {
        if ($DisableStock -and (Get-PackageState $Serial 'com.google.android.tvlauncher') -eq 'disabled') {
            Invoke-Tv $Serial 'pm enable --user 0 com.google.android.tvlauncher' | Out-Null
            Write-Warning 'Home did not switch, so the stock launcher was enabled again.'
        }
        throw "Home still resolves to '$after' (set-home-activity: $($r.Out.Trim()) $($r.Err.Trim())). A system launcher with a higher HOME priority wins over any default; it has to be disabled first, which this script does not do."
    }
    Write-Host "done  Home: $before -> $component"
}
