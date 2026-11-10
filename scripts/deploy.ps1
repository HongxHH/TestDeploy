#Requires -Version 5.1
<#
.SYNOPSIS
  从 Git 拉取源码 -> 构建前后端 -> 拷贝产物 -> 删除源码 -> 重启服务。
  每次执行均强制重新构建（前后端一并更新）。
.PARAMETER SkipStart
  只构建产物，不启动后端和反代。
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\deploy.ps1
#>
[CmdletBinding()]
param(
    [switch]$SkipStart
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. "$PSScriptRoot\lib\DeployCommon.ps1"

$cfg = Import-DeployConfig
Ensure-DeployDirs $cfg

function Prepare-SourceTree {
    param(
        [Parameter(Mandatory = $true)][string]$Kind,
        [Parameter(Mandatory = $true)][string]$RepoUrl
    )

    $dest = Join-Path $cfg.WORK_DIR $Kind
    if (Test-Path $dest) {
        Remove-Item $dest -Recurse -Force
    }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null

    Write-Step "$Kind : git clone --depth 1 ($RepoUrl)"
    $null = Invoke-External -FilePath 'git' -ArgumentList @(
        'clone', '--depth', '1', '--branch', $cfg.GIT_BRANCH, $RepoUrl, $dest
    )
    $short = Get-GitShortRev -RepoPath $dest
    Push-Location $dest
    try { $full = (git rev-parse HEAD).Trim() } finally { Pop-Location }
    return [hashtable]@{ SrcPath = $dest; short = $short; full = $full; source = $RepoUrl }
}

function Get-SourceTreePath {
    param([Parameter(Mandatory = $true)][hashtable]$Tree)
    if (-not $Tree.ContainsKey('SrcPath')) { throw '源码树缺少 SrcPath' }
    $p = [string]$Tree['SrcPath'].Trim()
    if ([string]::IsNullOrWhiteSpace($p)) { throw '源码路径为空' }
    if (-not (Test-Path $p)) { throw "源码目录不存在: $p" }
    return $p
}

function Build-Backend {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $SourcePath = $SourcePath.Trim()
    Assert-BackendPdfPreprocessor -SourcePath $SourcePath
    Write-Step '构建后端 JAR (mvnw.cmd)'
    $mvnw = Join-Path $SourcePath 'mvnw.cmd'
    if (-not (Test-Path $mvnw)) { throw "未找到 mvnw.cmd: $mvnw" }

    $null = Invoke-External -FilePath $mvnw -ArgumentList @(
        '-pl', 'lc-start', '-am', 'clean', 'package', '-DskipTests'
    ) -WorkingDirectory $SourcePath

    $jar = Get-ChildItem (Join-Path $SourcePath 'lc-start\target\lc-start-*.jar') |
        Where-Object { $_.Name -notmatch 'original' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $jar) { throw '未找到 lc-start-*.jar 构建产物' }

    # 先写到 staging：等前后端构建完成后再停服务并替换正式 JAR，缩短停机窗口
    $stagingJar = Join-Path $cfg.DEPLOY_BACKEND_DIR 'lc-start.jar.staging'
    Copy-Item -LiteralPath $jar.FullName -Destination $stagingJar -Force
    if (-not (Test-JarContainsResource -JarPath $stagingJar -ResourceName 'pdf_preprocessor.py')) {
        throw 'JAR 内缺少 pdf_preprocessor.py，请确认后端 Git 仓库已包含该文件并重新构建'
    }
    Write-Ok "JAR 已构建并暂存: $stagingJar"
    return $stagingJar
}

function Build-Frontend {
    param([Parameter(Mandatory = $true)][string]$SourcePath)
    $SourcePath = $SourcePath.Trim()
    Write-Step '构建前端 (npm ci + npm run build)'
    $null = Invoke-External -FilePath 'npm.cmd' -ArgumentList @('ci') -WorkingDirectory $SourcePath
    $null = Invoke-External -FilePath 'npm.cmd' -ArgumentList @('run', 'build') -WorkingDirectory $SourcePath

    $dist = Join-Path $SourcePath 'dist'
    if (-not (Test-Path $dist)) { throw '未找到 dist 目录' }

    if (Test-Path $cfg.DEPLOY_FRONTEND_DIR) {
        Remove-Item $cfg.DEPLOY_FRONTEND_DIR -Recurse -Force
    }
    New-Item -ItemType Directory -Path $cfg.DEPLOY_FRONTEND_DIR -Force | Out-Null
    $rc = Start-Process -FilePath 'robocopy' -ArgumentList @($dist, $cfg.DEPLOY_FRONTEND_DIR, '/MIR') -NoNewWindow -Wait -PassThru
    if ($rc.ExitCode -gt 7) {
        throw "复制 dist 失败, exit=$($rc.ExitCode)"
    }
    Write-Ok "前端静态文件已部署: $($cfg.DEPLOY_FRONTEND_DIR)"
}

Write-Host 'landcheck 一键部署' -ForegroundColor White
Write-Host "根目录: $($cfg.DEPLOY_ROOT)" -ForegroundColor DarkGray

$stagingJar = $null
try {
    $backendTree = Prepare-SourceTree -Kind 'backend' -RepoUrl $cfg.BACKEND_REPO_URL
    $stagingJar = Build-Backend -SourcePath (Get-SourceTreePath -Tree $backendTree)
    Save-DeployedMeta -MetaDir $cfg.DEPLOY_META_DIR -Name 'backend' -Commit $backendTree['short'] -FullCommit $backendTree['full'] -Source $backendTree['source']

    $frontendTree = Prepare-SourceTree -Kind 'frontend' -RepoUrl $cfg.FRONTEND_REPO_URL
    Build-Frontend -SourcePath (Get-SourceTreePath -Tree $frontendTree)
    Save-DeployedMeta -MetaDir $cfg.DEPLOY_META_DIR -Name 'frontend' -Commit $frontendTree['short'] -FullCommit $frontendTree['full'] -Source $frontendTree['source']
}
finally {
    Write-Step '清理临时源码 (.work)'
    if (Test-Path $cfg.WORK_DIR) {
        Remove-Item $cfg.WORK_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if (-not $stagingJar -or -not (Test-Path $stagingJar)) {
    throw '未找到暂存 JAR，后端构建可能失败'
}

# 构建已完成后再停服务并替换正式 JAR（禁止运行中热覆盖）
Publish-LandcheckBackendJar -Cfg $cfg -SourceJar $stagingJar
Remove-Item -LiteralPath $stagingJar -Force -ErrorAction SilentlyContinue

Write-Ok '源码已删除，仅保留 deploy/ 产物'

if (-not $SkipStart) {
    Ensure-LandcheckDocker -Cfg $cfg -WaitOcr
    Start-LandcheckBackend -Cfg $cfg
    Wait-BackendHealthy -Cfg $cfg
    Wait-ProxyHealthy -Cfg $cfg
}

Write-Host ''
Write-Ok '部署完成'
Write-Host "  前端: http://localhost:$($cfg.PROXY_PORT)/" -ForegroundColor Green
Write-Host "  后端: http://localhost:$($cfg.BACKEND_PORT)/" -ForegroundColor Green
Write-Host "  日志: $($cfg.LOG_DIR)" -ForegroundColor DarkGray
