@echo off
setlocal EnableExtensions
set "PSModulePath=%SystemRoot%\System32\WindowsPowerShell\v1.0\Modules;%PSModulePath%"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\windows\release-tools.ps1" -Action StartAndroidTV %*
exit /b %ERRORLEVEL%
