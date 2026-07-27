#Requires -Version 5.1
<#
.SYNOPSIS
  检测远程仓库是否有比当前部署更新的提交。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\check-updates.ps1
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\check-updates.ps1 -Json
#>
[CmdletBinding()]
param(
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

$cfg = Import-DeployConfig
Ensure-DeployDirs $cfg

function Get-LatestRev {
    param([Parameter(Mandatory = $true)][string]$RepoUrl)

    $remoteShort = Get-RemoteShortRev -RepoUrl $RepoUrl -Branch $cfg.GIT_BRANCH
    if (-not $remoteShort) {
        return @{ available = $false; reason = "无法读取远程仓库: $RepoUrl" }
    }
    $hashLine = git ls-remote $RepoUrl "refs/heads/$($cfg.GIT_BRANCH)" 2>$null
    $remoteFull = if ($hashLine) { ($hashLine -split '\s+')[0] } else { $remoteShort }
    return @{
        available   = $true
        latestShort = $remoteShort
        latestFull  = $remoteFull
    }
}

$backendMeta = Join-Path $cfg.DEPLOY_META_DIR 'backend.deployed'
$frontendMeta = Join-Path $cfg.DEPLOY_META_DIR 'frontend.deployed'
$deployedBackend = Read-DeployedRev $backendMeta
$deployedFrontend = Read-DeployedRev $frontendMeta

$backendLatest = Get-LatestRev -RepoUrl $cfg.BACKEND_REPO_URL
$frontendLatest = Get-LatestRev -RepoUrl $cfg.FRONTEND_REPO_URL

$backendNeeds = $false
$frontendNeeds = $false
$reasons = @()

if (-not $deployedBackend) {
    $backendNeeds = $true
    $reasons += 'backend: 尚未部署'
}
elseif ($backendLatest.available -and $deployedBackend -ne $backendLatest.latestShort) {
    $backendNeeds = $true
    $reasons += "backend: 已部署 $deployedBackend -> 最新 $($backendLatest.latestShort)"
}

if (-not $deployedFrontend) {
    $frontendNeeds = $true
    $reasons += 'frontend: 尚未部署'
}
elseif ($frontendLatest.available -and $deployedFrontend -ne $frontendLatest.latestShort) {
    $frontendNeeds = $true
    $reasons += "frontend: 已部署 $deployedFrontend -> 最新 $($frontendLatest.latestShort)"
}

$report = [ordered]@{
    checkedAt            = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    branch               = $cfg.GIT_BRANCH
    deployed             = [ordered]@{
        backend  = $deployedBackend
        frontend = $deployedFrontend
    }
    latest               = [ordered]@{
        backend  = if ($backendLatest.available) { $backendLatest.latestShort } else { $null }
        frontend = if ($frontendLatest.available) { $frontendLatest.latestShort } else { $null }
    }
    needsUpdate          = ($backendNeeds -or $frontendNeeds)
    backendNeedsUpdate   = $backendNeeds
    frontendNeedsUpdate  = $frontendNeeds
    reasons              = $reasons
}

if ($Json) {
    $report | ConvertTo-Json -Depth 5
    if ($report.needsUpdate) { exit 2 }
    exit 0
}

Write-Host 'landcheck 更新检测（远程仓库）' -ForegroundColor White
Write-Host "分支: $($cfg.GIT_BRANCH)"
Write-Host ''
Write-Host "已部署 backend : $(if ($deployedBackend) { $deployedBackend } else { '(无)' })"
Write-Host "最新   backend : $(if ($backendLatest.available) { $backendLatest.latestShort } else { $backendLatest.reason })"
Write-Host "已部署 frontend: $(if ($deployedFrontend) { $deployedFrontend } else { '(无)' })"
Write-Host "最新   frontend: $(if ($frontendLatest.available) { $frontendLatest.latestShort } else { $frontendLatest.reason })"
Write-Host ''

if ($report.needsUpdate) {
    Write-WarnMsg '检测到可更新内容:'
    foreach ($r in $reasons) { Write-Host "  - $r" -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '执行更新: powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1' -ForegroundColor Cyan
    exit 2
}

Write-Ok '当前已是最新部署版本，无需更新'
exit 0
