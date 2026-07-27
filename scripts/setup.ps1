#Requires -Version 5.1
<#
.SYNOPSIS
  机器 B 一键首次部署：Docker -> Conda -> 构建 -> 启动。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\setup.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipConda,
    [switch]$SkipDeploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"
$cfg = Import-DeployConfig

Write-Host '========================================' -ForegroundColor White
Write-Host ' landcheck 一键部署 setup' -ForegroundColor White
Write-Host '========================================' -ForegroundColor White

if (-not (Test-Path $cfg.DEPLOY_ENV_FILE)) {
    throw '请先 copy deploy.env.example deploy.env 并修改 MONGO_DATA_DIR'
}

Write-Step '检查 Mongo 数据目录'
if (-not (Test-Path $cfg.MONGO_DATA_DIR)) {
    Write-WarnMsg "Mongo 目录不存在: $($cfg.MONGO_DATA_DIR)"
    Write-Host '       若从 A 机拷贝数据集，请将文件放到上述路径后重试' -ForegroundColor Yellow
    throw 'MONGO_DATA_DIR 无效'
}
Write-Ok "Mongo 数据目录: $($cfg.MONGO_DATA_DIR)（从 A 机拷贝的数据集可直接使用，无需 rs.initiate）"

if (-not $SkipConda) {
    if (Test-CommandExists conda) {
        & "$PSScriptRoot\setup-conda.ps1"
    }
    else {
        Write-WarnMsg '未安装 conda，跳过 SR 环境（PDF 预处理将不可用）'
        Write-Host '       安装 Miniconda 后执行: scripts\setup-conda.ps1' -ForegroundColor Yellow
    }
}

Ensure-LandcheckDocker -Cfg $cfg -WaitOcr

if (-not $SkipDeploy) {
    & "$PSScriptRoot\deploy.ps1" -SkipStart
    if ($LASTEXITCODE -ne 0) { throw 'deploy 失败' }
}

Start-LandcheckBackend -Cfg $cfg
Wait-BackendHealthy -Cfg $cfg
Wait-ProxyHealthy -Cfg $cfg

& "$PSScriptRoot\status.ps1"
Write-Host ''
Write-Ok "部署完成: http://localhost:$($cfg.PROXY_PORT)/"
