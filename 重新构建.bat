@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title landcheck - 重新构建
echo.
echo [landcheck] 重新构建：停止服务 -^> 拉取代码 -^> 构建前后端 -^> 启动
echo 请勿关闭本窗口，完成后会提示。若已有运维任务在跑，会直接拒绝。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ops-rebuild.ps1"
set ERR=%ERRORLEVEL%
echo.
if %ERR% equ 0 (
  echo [完成] 重新构建成功。
) else (
  echo [失败] 退出码 %ERR%。请向上滚动查看错误信息。
)
echo.
pause
exit /b %ERR%
