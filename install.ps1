#Requires -Version 5
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Join-Path $scriptDir 'src') 'main.cpp'
if (-not (Test-Path $src)) { Write-Error "cannot find src\main.cpp (looked at $src)"; exit 1 }

$cxx = $null
foreach ($c in @('g++', 'clang++', 'cl')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $cxx = $c; break }
}
if (-not $cxx) {
    Write-Error "No C++ compiler found. Install one of:
  - MSVC Build Tools, then run from 'Developer PowerShell for VS' (gives 'cl')
  - MSYS2/MinGW-w64 ('g++') or LLVM ('clang++'), added to PATH"
    exit 1
}

$installDir = Join-Path $env:LOCALAPPDATA 'Programs\gilya'
New-Item -ItemType Directory -Force -Path $installDir | Out-Null
$exe = Join-Path $installDir 'gilya.exe'

Write-Host "Building with $cxx ..."
if ($cxx -eq 'cl') {
    Push-Location $installDir
    try {
        & cl /std:c++17 /EHsc /utf-8 /nologo /O2 "/Fe:$exe" $src
        Get-ChildItem -Path $installDir -Filter *.obj -ErrorAction SilentlyContinue | Remove-Item -Force
    } finally { Pop-Location }
} else {
    & $cxx -std=c++17 -O2 -o $exe $src
}
if (-not (Test-Path $exe)) { Write-Error "compilation failed"; exit 1 }
Write-Host "Installed -> $exe"

$userPath = [Environment]::GetEnvironmentVariable('Path', 'User')
if (($userPath -split ';') -notcontains $installDir) {
    $newPath = if ([string]::IsNullOrEmpty($userPath)) { $installDir } else { "$installDir;$userPath" }
    [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
    Write-Host "Added $installDir to user PATH (restart the terminal to pick it up)."
}

$block = @'
# >>> gilya >>>
if (Get-Module -ListAvailable PSReadLine) {
    Set-PSReadLineOption -AddToHistoryHandler {
        param([string]$line)
        return (-not ($line -like 'gilya*'))
    }
}
# <<< gilya <<<
'@

function Set-GilyaBlock([string]$path, [string]$text) {
    $dir = Split-Path $path -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    if (-not (Test-Path $path)) { New-Item -ItemType File -Force -Path $path | Out-Null }
    Copy-Item $path "$path.gilya.bak" -Force
    $t = Get-Content -Raw -Path $path -ErrorAction SilentlyContinue
    if ($null -eq $t) { $t = '' }
    $t = [regex]::Replace($t, '(?s)# >>> gilya >>>.*?# <<< gilya <<<\r?\n?', '')
    $t = ($t.TrimEnd() + "`r`n" + $text + "`r`n").TrimStart("`r", "`n")
    Set-Content -Path $path -Value $t -Encoding UTF8
    Write-Host "  configured $path"
}

$docs = [Environment]::GetFolderPath('MyDocuments')
$targets = [System.Collections.Generic.List[string]]::new()
$targets.Add((Join-Path $docs 'PowerShell\profile.ps1'))        # PowerShell 7
$targets.Add((Join-Path $docs 'WindowsPowerShell\profile.ps1')) # PowerShell 5

if ($PROFILE.CurrentUserAllHosts) { $targets.Add($PROFILE.CurrentUserAllHosts) }
foreach ($p in ($targets | Select-Object -Unique)) { Set-GilyaBlock $p $block }

$psrlDir = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
try {
    $hp = (Get-PSReadLineOption).HistorySavePath
    if ($hp) { $psrlDir = Split-Path $hp -Parent }
} catch {}
if (Test-Path $psrlDir) {
    Get-ChildItem -Path $psrlDir -Filter '*_history.txt' -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName "$($_.FullName).gilya.bak" -Force
        (Get-Content -LiteralPath $_.FullName) |
            Where-Object { $_ -notmatch '^\s*gilya(\s|$)' } |
            Set-Content -LiteralPath $_.FullName -Encoding UTF8
        Write-Host "  scrubbed $($_.Name)"
    }
}

Write-Host ""
Write-Host "Done. From now on gilya is never recorded in PowerShell history."
Write-Host "Restart PowerShell / VS Code to drop the current session's old entries."
Write-Host "(cmd.exe does not persist history between sessions, so nothing to do there.)"
