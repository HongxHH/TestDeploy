@echo off
chcp 65001 >nul
setlocal
cd /d "%~dp0"
title landcheck - 设置开机自启
echo.
echo [landcheck] 设置开机自启：登录后延迟 2 分钟启动前后端
echo 可能弹出 UAC 管理员确认，请点「是」。
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\ops-enable-autostart.ps1"
set ERR=%ERRORLEVEL%
echo.
if %ERR% equ 0 (
  echo [完成] 开机自启已设置（登录 + 2 分钟）。
) else (
  echo [失败] 退出码 %ERR%。请向上滚动查看错误信息。
)
echo.
pause
exit /b %ERR%
