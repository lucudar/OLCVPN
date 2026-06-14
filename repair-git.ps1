# repair-git.ps1
# Fixes the case where C:\OLCVPN\OLCVPN-ios-unsigned exists but is NOT a git repo.
# IMPORTANT: put this file in C:\OLCVPN and run it FROM C:\OLCVPN (not from inside
# the folder it deletes), e.g.:
#   cd C:\OLCVPN
#   powershell -ExecutionPolicy Bypass -File .\repair-git.ps1
# ASCII-only on purpose.

$ErrorActionPreference = 'Stop'

$RepoUrl = 'https://github.com/lucudar/OLCVPN.git'
$Branch  = 'main'
$Dest    = 'C:\OLCVPN\OLCVPN-ios-unsigned'
$Backup  = 'C:\OLCVPN\_scripts_backup'

Write-Host '=== OLCVPN git repair ===' -ForegroundColor Cyan

# Safety: never run from inside the folder we are about to delete.
if ((Get-Location).Path -like ($Dest + '*')) {
    Write-Host ('Do NOT run this from inside ' + $Dest) -ForegroundColor Red
    Write-Host 'Open PowerShell in C:\OLCVPN and run it from there.' -ForegroundColor Red
    exit 1
}

# If it is already a proper git repo, do nothing destructive.
if (Test-Path (Join-Path $Dest '.git')) {
    Write-Host 'Folder is already a git repo. Nothing to repair.' -ForegroundColor Green
    Push-Location $Dest
    git remote -v
    git status -sb
    Pop-Location
    exit 0
}

# 1) Save any *.ps1 scripts sitting in the broken folder.
if (Test-Path $Dest) {
    New-Item -ItemType Directory -Force -Path $Backup | Out-Null
    Get-ChildItem -Path $Dest -Filter *.ps1 -File -ErrorAction SilentlyContinue | ForEach-Object {
        Copy-Item $_.FullName -Destination $Backup -Force
        Write-Host ('saved script: ' + $_.Name) -ForegroundColor Yellow
    }
}

# 2) Remove the broken (non-git) folder.
if (Test-Path $Dest) {
    Write-Host ('Removing broken folder ' + $Dest) -ForegroundColor Yellow
    Remove-Item -Recurse -Force $Dest
}

# 3) Fresh clone.
Write-Host ('Cloning ' + $RepoUrl + ' -> ' + $Dest) -ForegroundColor Yellow
Write-Host 'A browser window may open to sign in to GitHub (Git Credential Manager).' -ForegroundColor Cyan
git clone --branch $Branch $RepoUrl $Dest

# 4) Restore the saved scripts into the fresh clone.
if (Test-Path $Backup) {
    Get-ChildItem -Path $Backup -Filter *.ps1 -File | ForEach-Object {
        Copy-Item $_.FullName -Destination $Dest -Force
        Write-Host ('restored script: ' + $_.Name) -ForegroundColor Green
    }
}

# 5) Show state.
Push-Location $Dest
Write-Host '--- remote ---' -ForegroundColor Cyan
git remote -v
Write-Host '--- status ---' -ForegroundColor Cyan
git status -sb
git log --oneline -5
Pop-Location

Write-Host ''
Write-Host ('DONE. Real clone ready at ' + $Dest) -ForegroundColor Green
Write-Host 'Next: cd into it and run  .\apply-proxy-mode.ps1' -ForegroundColor Green
