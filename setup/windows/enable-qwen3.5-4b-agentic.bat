@echo off
rem Launcher for enable-qwen3.5-4b-agentic.ps1. Runs it with execution policy
rem bypassed for this one process. The script writes .claude\settings.json into
rem the CURRENT directory, so run this from the lab directory, not by double-
rem click. Forwards arguments, e.g.:  enable-qwen3.5-4b-agentic.bat -Anywhere
setlocal
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0enable-qwen3.5-4b-agentic.ps1" %*
exit /b %ERRORLEVEL%
