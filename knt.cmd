@echo off
setlocal
where pwsh >nul 2>nul
if %ERRORLEVEL%==0 (
  pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0.kinotch\scripts\knt.ps1" %*
) else (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0.kinotch\scripts\knt.ps1" %*
)
exit /b %ERRORLEVEL%
