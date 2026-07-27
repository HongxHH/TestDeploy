@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title landcheck - 取消开机自启
echo.
echo [landcheck] 取消开机自启：移除 landcheck 相关计划任务
echo 可能弹出 UAC 管理员确认，请点「是」。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ops-disable-autostart.ps1"
set ERR=%ERRORLEVEL%
echo.
if %ERR% equ 0 (
  echo [完成] 已取消开机自启。
) else (
  echo [失败] 退出码 %ERR%。请向上滚动查看错误信息。
)
echo.
pause
exit /b %ERR%
