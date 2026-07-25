@echo off
setlocal
title Codex SyncKit Setup

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install-CodexSyncKit.ps1" -Recommended %*
set "setup_exit_code=%ERRORLEVEL%"

echo.
if not "%setup_exit_code%"=="0" (
    echo Codex SyncKit setup failed with exit code %setup_exit_code%.
    echo Review the messages above, then run this file again.
    if not defined CODEX_SYNCKIT_NO_PAUSE pause
    exit /b %setup_exit_code%
)

echo Codex SyncKit setup is complete.
echo Start ChatGPT anytime from the managed Start menu shortcut.
if not defined CODEX_SYNCKIT_NO_PAUSE pause
exit /b 0
