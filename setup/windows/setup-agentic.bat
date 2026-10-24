@echo off
rem Launcher for setup-agentic.ps1. Runs the PowerShell script with execution
rem policy bypassed for this one process, so no system policy change is needed.
rem Forwards any arguments, e.g.:  setup-agentic.bat -Ctx 32768 -Force
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-agentic.ps1" %*
exit /b %ERRORLEVEL%
