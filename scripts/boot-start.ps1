#Requires -Version 5.1
<#
.SYNOPSIS
  开机/计划任务静默启动 landcheck（写 logs\boot-start.log）。
  不等待 OCR 就绪，避免开机任务超时；OCR 容器会在后台自行 warmup。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\boot-start.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

function Write-BootLog {
    param([Parameter(Mandatory = $true)][string]$Message)
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
    if ($script:BootLogFile) {
        Add-Content -Path $script:BootLogFile -Value $line -Encoding UTF8
    }
}

try {
    $cfg = Import-DeployConfig
    Ensure-DeployDirs $cfg
    $script:BootLogFile = Join-Path $cfg.LOG_DIR 'boot-start.log'

    Write-BootLog '======== boot-start 开始 ========'

    if (-not (Test-Path (Join-Path $cfg.DEPLOY_BACKEND_DIR 'lc-start.jar'))) {
        Write-BootLog 'ERROR: 未找到 deploy\backend\lc-start.jar，请先运行 scripts\setup.ps1'
        exit 1
    }

    Write-BootLog '等待 Docker 引擎就绪（最多 10 分钟）...'
    if (-not (Wait-DockerEngineReady -TimeoutSec 600)) {
        Write-BootLog 'ERROR: Docker 未就绪。请确认 Docker Desktop 已安装且勾选「登录时启动」'
        exit 1
    }
    Write-BootLog 'Docker 引擎已就绪'

    Ensure-LandcheckDocker -Cfg $cfg
    Write-BootLog 'Docker 容器已启动（OCR 在后台 warmup，不阻塞开机）'

    Start-LandcheckBackend -Cfg $cfg
    Write-BootLog '后端 JAR 已启动'

    Wait-BackendHealthy -Cfg $cfg -TimeoutSec 180
    Write-BootLog '后端健康检查通过'

    Wait-ProxyHealthy -Cfg $cfg -TimeoutSec 90
    Write-BootLog "OK: 服务就绪 http://localhost:$($cfg.PROXY_PORT)/"
    exit 0
}
catch {
    Write-BootLog "ERROR: $($_.Exception.Message)"
    exit 1
}
