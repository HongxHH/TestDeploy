#Requires -Version 5.1
<#
.SYNOPSIS
  检查 deploy.env 与 Docker 容器状态。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\check-env.ps1
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig

Write-Step '配置文件'
if (Test-Path (Join-Path $cfg.DEPLOY_ROOT 'deploy.env')) { Write-Ok 'deploy.env 存在' }
else { Write-ErrMsg '缺少 deploy.env'; exit 1 }

if (-not (Test-DockerEngineRunning)) {
    Write-ErrMsg 'Docker 未运行'
    exit 1
}

Write-Step 'Docker 容器'
$containersOk = Test-LandcheckDockerContainers

if ($containersOk) {
    Write-Ok '全部检查通过'
    exit 0
}

Write-WarnMsg '部分容器未启动（首次 setup 正常，setup/deploy 会自动 docker compose）'
exit 1
