#Requires -Version 5
param([switch]$KeepData)
$ErrorActionPreference = 'Stop'

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\gilya'

Write-Host "Removing gilya ..."

if (Test-Path $installDir) {
    try {
        Remove-Item $installDir -Recurse -Force
        Write-Host "  removed $installDir"
    } catch {
        Write-Host "  could not remove $installDir ($($_.Exception.Message))"
    }
}

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if ($userPath) {
    $parts = $userPath -split ';' | Where-Object { $_ -and $_ -ne $installDir }
    $newPath = $parts -join ';'
    if ($newPath -ne $userPath) {
        [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        Write-Host "  removed $installDir from user PATH"
    }
}

function Remove-GilyaBlock([string]$path) {
    if (-not (Test-Path $path)) { return }
    $t = Get-Content -Raw -Path $path -ErrorAction SilentlyContinue
    if ($null -eq $t -or $t -notmatch '# >>> gilya >>>') { return }
    if (-not (Test-Path "$path.gilya.bak")) { Copy-Item $path "$path.gilya.bak" -Force }
    $t = [regex]::Replace($t, '(?s)# >>> gilya >>>.*?# <<< gilya <<<\r?\n?', '')
    Set-Content -Path $path -Value $t.TrimEnd() -Encoding UTF8
    Write-Host "  cleaned $path"
}

$docs = [Environment]::GetFolderPath('MyDocuments')
$targets = [System.Collections.Generic.List[string]]::new()
$targets.Add((Join-Path $docs 'PowerShell\profile.ps1'))
$targets.Add((Join-Path $docs 'WindowsPowerShell\profile.ps1'))

if ($PROFILE.CurrentUserAllHosts) { $targets.Add($PROFILE.CurrentUserAllHosts) }

foreach ($p in ($targets | Select-Object -Unique)) { Remove-GilyaBlock $p }

$data = Join-Path $env:LOCALAPPDATA 'gilya'
if (-not (Test-Path $data) -and $env:APPDATA) { $data = Join-Path $env:APPDATA 'gilya' }
if ($KeepData) {
    if (Test-Path $data) { Write-Host "  kept remembered files in $data" }
} elseif (Test-Path $data) {
    Remove-Item $data -Recurse -Force
    Write-Host "  removed data $data"
}

Write-Host ""
Write-Host "Done. Restart PowerShell / VS Code so it drops the PATH and history"
Write-Host "settings from the current session. *.gilya.bak backups remain."
