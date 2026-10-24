@echo off
rem Launcher for setup-agentic.ps1. Runs the PowerShell script with execution
rem policy bypassed for this one process, so no system policy change is needed.
rem powershell.exe is called by absolute path: an unqualified name needs
rem WindowsPowerShell\v1.0 on PATH, which is missing on some builds and in SSH
rem sessions, and the failure reads as if PowerShell is not installed at all.
rem Forwards any arguments, e.g.:  setup-agentic.bat -Ctx 32768 -Force
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup-agentic.ps1" %*
exit /b %ERRORLEVEL%
