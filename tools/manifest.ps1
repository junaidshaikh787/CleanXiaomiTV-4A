# The change manifest: every package, setting and Home change this project makes on the TV, with the
# value it had before, so tools\restore.ps1 can undo exactly those and nothing else. It holds no serial,
# IP or network names, so it is committed. Dot-source after adb.ps1.

function Read-Manifest([string]$Path, [string]$Serial) {
    if (Test-Path $Path) {
        $m = Get-Content $Path -Raw | ConvertFrom-Json
        $m.packages = @($m.packages)
        $m.settings = @($m.settings)
        if (-not $m.PSObject.Properties['permissions']) { $m | Add-Member -NotePropertyName permissions -NotePropertyValue @() }
        $m.permissions = @($m.permissions)
        return $m
    }
    $prop = { param($p) (Invoke-Tv $Serial "getprop $p").Out.Trim() }
    [pscustomobject]@{
        device        = "$(& $prop 'ro.product.model') ($(& $prop 'ro.product.device')), Android $(& $prop 'ro.build.version.release'), $(& $prop 'ro.build.display.id')"
        original_home = (Invoke-Tv $Serial 'cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME').Out.Trim().Split("`n")[-1].Trim()
        packages      = @()
        settings      = @()
        permissions   = @()
        home          = $null
    }
}

# A runtime permission granted to one of our apps; restore.ps1 revokes it.
function Add-PermissionChange($m, [string]$Package, [string]$Permission) {
    if ($m.permissions | Where-Object { $_.package -eq $Package -and $_.permission -eq $Permission }) { return }
    $m.permissions += [pscustomobject]@{ package = $Package; permission = $Permission; at = (Get-Date -Format 's') }
}

function Save-Manifest($m, [string]$Path) {
    New-Item -ItemType Directory -Force (Split-Path -Parent $Path) | Out-Null
    [IO.File]::WriteAllText($Path, ($m | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
}

function Add-PackageChange($m, [string]$Package, [string]$Before) {
    if ($m.packages | Where-Object { $_.package -eq $Package }) { return }
    $m.packages += [pscustomobject]@{ package = $Package; before = $Before; action = 'disable-user'; at = (Get-Date -Format 's') }
}

# A setting we change: kept with its old value (null = was unset) and the value we put.
function Add-SettingChange($m, [string]$Namespace, [string]$Key, [string]$Before, [string]$Set) {
    if ($m.settings | Where-Object { $_.namespace -eq $Namespace -and $_.key -eq $Key }) { return }
    $m.settings += [pscustomobject]@{ namespace = $Namespace; key = $Key; before = $Before; set = $Set; at = (Get-Date -Format 's') }
}

# enabled / disabled / missing, from the package manager's own lists.
function Get-PackageState([string]$Serial, [string]$Package) {
    $all = (Invoke-Tv $Serial 'pm list packages').Out -split "`n" | ForEach-Object { $_.Trim() }
    if ($all -notcontains "package:$Package") { return 'missing' }
    $dis = (Invoke-Tv $Serial 'pm list packages -d').Out -split "`n" | ForEach-Object { $_.Trim() }
    if ($dis -contains "package:$Package") { 'disabled' } else { 'enabled' }
}
