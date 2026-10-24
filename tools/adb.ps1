# Shared helpers for the PowerShell tools: talk to the TV with the stock adb.exe (platform-tools).
# Dot-source it: . (Join-Path $PSScriptRoot 'adb.ps1')

if (-not (Get-Command adb -ErrorAction SilentlyContinue)) {
    $pt = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools'
    if (Test-Path (Join-Path $pt 'adb.exe')) { $env:PATH = "$pt;$env:PATH" }
    else { throw 'adb not found: install Android SDK platform-tools or put adb.exe on PATH' }
}

# The TV to use: the given serial (ip:5555), else the only device adb knows. Connects if needed.
function Resolve-TvSerial([string]$Serial) {
    if ($Serial) {
        if ($Serial -match ':') { & adb connect $Serial 2>&1 | Out-Null }
        $state = (& adb -s $Serial get-state 2>&1 | Out-String).Trim()
        if ($state -ne 'device') { throw "TV $Serial is '$state'. Check the IP, that the TV is on, and accept the debugging prompt on the TV." }
        return $Serial
    }
    $devs = @(& adb devices | Select-Object -Skip 1 | Where-Object { $_ -match '\tdevice$' } | ForEach-Object { ($_ -split "`t")[0] })
    if ($devs.Count -eq 1) { return $devs[0] }
    throw "adb sees $($devs.Count) devices; pass -Serial <ip:5555> or set `$env:TV_SERIAL"
}

# Run one shell command on the TV; returns Out, Err and Code separately (no PowerShell stderr wrapping).
function Invoke-Tv([string]$Serial, [string]$Command) {
    Invoke-Adb $Serial ("shell `"" + ($Command -replace '"', '\"') + "`"")
}

# Run adb with a raw argument string (pull, install, ...), same result shape as Invoke-Tv.
function Invoke-Adb([string]$Serial, [string]$Arguments) {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = (Get-Command adb).Source
    $psi.Arguments = "-s $Serial $Arguments"
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.StandardOutputEncoding = [Text.Encoding]::UTF8
    $p = [Diagnostics.Process]::Start($psi)
    $errTask = $p.StandardError.ReadToEndAsync()
    $out = $p.StandardOutput.ReadToEnd()
    $p.WaitForExit()
    [pscustomobject]@{ Out = ($out -replace "`r", ''); Err = $errTask.Result; Code = $p.ExitCode }
}
