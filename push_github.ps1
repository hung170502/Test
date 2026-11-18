# Push Steal-An-Egg to GitHub (public)
# Run after: gh auth login

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$gh = "C:\Program Files\GitHub CLI\gh.exe"
$git = "C:\Program Files\Git\cmd\git.exe"

if (-not (Test-Path $gh)) { throw "Install GitHub CLI: winget install GitHub.cli" }
if (-not (Test-Path $git)) { throw "Install Git: winget install Git.Git" }

& $gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "Login first: gh auth login"
    & $gh auth login --hostname github.com --git-protocol https --web
}

$repoName = "Steal-An-Egg"
$remote = & $git remote get-url origin 2>$null
if (-not $remote) {
    & $gh repo create $repoName --public --source=. --remote=origin --description "Auto farm hub for Steal An Egg (Roblox / Potassium)"
    & $git push -u origin main
} else {
    & $git push -u origin main
}

Write-Host "Done. Repo: https://github.com/$(& $gh api user -q .login)/$repoName"
