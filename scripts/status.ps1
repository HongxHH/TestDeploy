#Requires -Version 5.1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig

Write-Host 'landcheck 状态' -ForegroundColor White
Write-Host "Mongo 目录: $($cfg.MONGO_DATA_DIR)"
Write-Host "backend commit: $(Read-DeployedRev (Join-Path $cfg.DEPLOY_META_DIR 'backend.deployed'))"
Write-Host "frontend commit: $(Read-DeployedRev (Join-Path $cfg.DEPLOY_META_DIR 'frontend.deployed'))"

$pidFile = Join-Path $cfg.DEPLOY_BACKEND_DIR 'backend.pid'
if (Test-Path $pidFile) {
    $backendPid = [int](Get-Content $pidFile -TotalCount 1)
    if (Get-Process -Id $backendPid -ErrorAction SilentlyContinue) { Write-Ok "后端运行中 PID=$backendPid" }
    else { Write-WarnMsg 'backend.pid 存在但进程不在' }
} else { Write-WarnMsg '后端未运行' }

Write-Step 'Docker 容器'
$null = Test-LandcheckDockerContainers

Write-Host "访问: http://localhost:$($cfg.PROXY_PORT)/" -ForegroundColor Cyan
