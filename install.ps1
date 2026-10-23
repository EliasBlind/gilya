#Requires -Version 5
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$src = Join-Path (Join-Path $scriptDir 'src') 'main.cpp'
if (-not (Test-Path $src)) {
    Write-Error "cannot find src\main.cpp (looked at $src)"
    exit 1
}

$cxx = $null
foreach ($c in @('g++', 'clang++', 'cl')) {
    if (Get-Command $c -ErrorAction SilentlyContinue) { $cxx = $c; break }
}
if (-not $cxx) {
    Write-Error "No C++ compiler found. Install one of:
  - MSVC Build Tools, then run this from 'Developer PowerShell for VS' (gives 'cl')
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

if (-not (Test-Path $PROFILE)) { New-Item -ItemType File -Force -Path $PROFILE | Out-Null }
Copy-Item $PROFILE "$PROFILE.gilya.bak" -Force

$profileText = Get-Content -Raw -Path $PROFILE -ErrorAction SilentlyContinue
if ($null -eq $profileText) { $profileText = '' }
$profileText = [regex]::Replace($profileText, '(?s)# >>> gilya >>>.*?# <<< gilya <<<\r?\n?', '')

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

$profileText = ($profileText.TrimEnd() + "`r`n" + $block + "`r`n").TrimStart("`r", "`n")
Set-Content -Path $PROFILE -Value $profileText -Encoding UTF8
Write-Host "Configured $PROFILE  (backup: $PROFILE.gilya.bak)"

Write-Host ""
Write-Host "Done. Open a NEW PowerShell window, then check:  Get-Command gilya ; gilya"
