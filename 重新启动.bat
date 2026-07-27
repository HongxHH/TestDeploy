@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title landcheck - 重新启动
echo.
echo [landcheck] 重新启动：停止后端 -^> 等待 OCR -^> 启动服务
echo 请勿关闭本窗口。若「重新构建」等运维任务正在进行，会直接拒绝。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ops-restart.ps1"
set ERR=%ERRORLEVEL%
echo.
if %ERR% equ 0 (
  echo [完成] 重新启动成功。
) else (
  echo [失败] 退出码 %ERR%。请向上滚动查看错误信息。
)
echo.
pause
exit /b %ERR%
