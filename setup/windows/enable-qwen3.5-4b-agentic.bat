@echo off
rem Launcher for enable-qwen3.5-4b-agentic.ps1. Runs it with execution policy
rem bypassed for this one process. The script writes .claude\settings.json into
rem the CURRENT directory, so run this from the lab directory, not by double-
rem click. Forwards arguments, e.g.:  enable-qwen3.5-4b-agentic.bat -Anywhere
rem
rem powershell.exe is called by absolute path on purpose: an unqualified name
rem needs WindowsPowerShell\v1.0 on PATH, which is missing on some builds and in
rem SSH sessions, and the failure reads as if PowerShell were not installed.
setlocal
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable-qwen3.5-4b-agentic.ps1" %*
exit /b %ERRORLEVEL%
