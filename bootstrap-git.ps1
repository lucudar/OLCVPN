# bootstrap-git.ps1
# One-time git setup on a fresh Windows machine for the OLCVPN repo.
# Run from PowerShell:  powershell -ExecutionPolicy Bypass -File .\bootstrap-git.ps1
# ASCII-only on purpose (no encoding surprises).

$ErrorActionPreference = 'Stop'

$RepoUrl  = 'https://github.com/lucudar/OLCVPN.git'
$Branch   = 'main'
$Dest     = 'C:\OLCVPN\OLCVPN-ios-unsigned'
$UserName = 'lucudar'
$UserMail = 'focus22889@mail.com'

function Have-Git {
    return [bool](Get-Command git -ErrorAction SilentlyContinue)
}

Write-Host '=== OLCVPN git bootstrap ===' -ForegroundColor Cyan

# 1) Ensure git is installed.
if (-not (Have-Git)) {
    Write-Host 'Git not found. Trying winget install...' -ForegroundColor Yellow
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        winget install --id Git.Git -e --source winget --accept-package-agreements --accept-source-agreements
        # Refresh PATH for this session.
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
    } else {
        Write-Host 'winget is not available. Install Git for Windows manually:' -ForegroundColor Red
        Write-Host '  https://git-scm.com/download/win' -ForegroundColor Red
        exit 1
    }
}

if (-not (Have-Git)) {
    Write-Host 'Git still not on PATH. Close and reopen PowerShell, then re-run this script.' -ForegroundColor Red
    exit 1
}

Write-Host ('git: ' + (git --version)) -ForegroundColor Green

# 2) Configure identity + sane defaults.
git config --global user.name  $UserName
git config --global user.email $UserMail
git config --global init.defaultBranch main
git config --global credential.helper manager
git config --global pull.rebase false
Write-Host ('identity: ' + (git config --global user.name) + ' <' + (git config --global user.email) + '>') -ForegroundColor Green

# 3) Clone (or update if it already exists).
if (Test-Path (Join-Path $Dest '.git')) {
    Write-Host ('Repo already present at ' + $Dest + ' - fetching latest...') -ForegroundColor Yellow
    Push-Location $Dest
    git fetch origin
    git checkout $Branch
    git pull --ff-only origin $Branch
    Pop-Location
} else {
    $parent = Split-Path $Dest -Parent
    if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    Write-Host ('Cloning ' + $RepoUrl + ' -> ' + $Dest) -ForegroundColor Yellow
    Write-Host 'A browser window may open to sign in to GitHub (Git Credential Manager).' -ForegroundColor Cyan
    git clone --branch $Branch $RepoUrl $Dest
}

# 4) Show state.
Push-Location $Dest
Write-Host '--- remote ---' -ForegroundColor Cyan
git remote -v
Write-Host '--- status ---' -ForegroundColor Cyan
git status -sb
git log --oneline -5
Pop-Location

Write-Host ''
Write-Host ('DONE. Repo ready at ' + $Dest) -ForegroundColor Green
Write-Host 'Next: drop apply-proxy-mode.ps1 into that folder and run it.' -ForegroundColor Green
