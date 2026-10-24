# Build the launcher and install it on the TV over adb, then open it for testing. It does not change Home,
# disable any app, debloat or touch the TV's settings: tools\set-home.ps1 makes it the default Home, and
# tools\disable.ps1 does the debloat, each recorded for tools\restore.ps1.
#
# Usage: launcher\build-and-install.ps1 [-Serial <ip:5555>] [-Debug]
#        -Debug   debug build (adds the adb test hook for the azan screen, see src\debug\AndroidManifest.xml)
#        Uses JAVA_HOME (JDK 17+) or Android Studio's bundled JDK, and ANDROID_HOME or the default SDK folder.
param(
    [string]$Serial = $env:TV_SERIAL,
    [switch]$Debug
)
$ErrorActionPreference = 'Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'tools\adb.ps1')
$pkg = 'com.majnioui.cleanxiaomitv'
$activity = "$pkg/com.gathin.tvhome.MainActivity"

# 1. Prerequisites: a JDK 17+, the Android SDK, adb, and the TV.
function Get-JavaMajor([string]$home_) {
    # java -version prints to stderr; through cmd, so Windows PowerShell does not turn that into an error.
    $v = (cmd /c "`"$home_\bin\java.exe`" -version 2>&1" | Out-String)
    if ($v -match 'version "(\d+)') { [int]$Matches[1] } else { 0 }
}
if (-not $env:JAVA_HOME -or -not (Test-Path "$env:JAVA_HOME\bin\java.exe")) {
    $jbr = Get-ChildItem 'C:\Program Files\Android' -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName 'jbr' } | Where-Object { Test-Path "$_\bin\java.exe" } | Select-Object -First 1
    if (-not $jbr) { throw 'No JDK found: set JAVA_HOME to a JDK 17 or newer (Android Studio ships one in its jbr folder).' }
    $env:JAVA_HOME = $jbr
}
$javaMajor = Get-JavaMajor $env:JAVA_HOME
if ($javaMajor -lt 17) { throw "JAVA_HOME ($env:JAVA_HOME) is Java $javaMajor; the build needs 17 or newer." }
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
if (-not (Test-Path "$sdk\platforms\android-34")) { throw "Android SDK platform 34 not found in $sdk (sdkmanager `"platforms;android-34`" `"build-tools;34.0.0`")." }
Set-Location $PSScriptRoot
if (-not (Test-Path local.properties)) { "sdk.dir=$($sdk -replace '\\', '\\')" | Out-File -Encoding ascii local.properties }
$Serial = Resolve-TvSerial $Serial
Write-Host "Java $javaMajor, SDK $sdk, TV $Serial"

# 2. Build, and check the result before anything goes to the TV.
$task = if ($Debug) { 'assembleDebug' } else { 'assembleRelease' }
# Through cmd with stderr merged: Windows PowerShell 5.1 turns any native stderr line (javac's "Note: ... deprecated
# API") into an error, which $ErrorActionPreference = 'Stop' makes fatal. The exit code decides instead.
cmd /c ".\gradlew.bat $task -q --console=plain 2>&1" | Write-Host
if ($LASTEXITCODE -ne 0) { throw "Gradle $task failed" }
$apk = if ($Debug) { 'app\build\outputs\apk\debug\app-debug.apk' } else { 'app\build\outputs\apk\release\app-release.apk' }
if (-not (Test-Path $apk)) { throw "build reported success but $apk is missing" }
$aapt = Get-ChildItem "$sdk\build-tools" -Directory | Sort-Object Name -Descending |
    ForEach-Object { Join-Path $_.FullName 'aapt.exe' } | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($aapt) {
    $badging = (& $aapt dump badging $apk) -join "`n"
    if ($badging -notmatch "package: name='$pkg'") { throw "$apk is not $pkg" }
    $minSdk = if ($badging -match "sdkVersion:'(\d+)'") { [int]$Matches[1] } else { 0 }
    $tvSdk = [int](Invoke-Tv $Serial 'getprop ro.build.version.sdk').Out.Trim()
    if ($minSdk -gt $tvSdk) { throw "the APK needs Android SDK $minSdk; the TV has $tvSdk" }
    Write-Host "Built $apk ($([math]::Round((Get-Item $apk).Length / 1MB, 1)) MB), minSdk $minSdk, TV SDK $tvSdk"
}

# 3. Install (replacing only an earlier build of this launcher) and open it.
$r = Invoke-Adb $Serial "install -r `"$((Resolve-Path $apk).Path)`""
if ($r.Out -notmatch 'Success') { throw "install failed: $($r.Out.Trim()) $($r.Err.Trim())" }
Write-Host 'Installed.'
$r = Invoke-Tv $Serial "am start -W -n $activity"
if ($r.Out -notmatch 'Status: ok') { throw "installed, but it did not open: $($r.Out.Trim())" }
Write-Host 'Opened on the TV. Make it the default Home with tools\set-home.ps1 (see README).'
