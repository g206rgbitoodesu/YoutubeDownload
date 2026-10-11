@echo off
chcp 65001 > nul
title YoutubeDownload 環境セットアップ
cd /d "%~dp0"

echo.
echo ============================================================
echo   YoutubeDownload 環境自動セットアップ
echo ============================================================
echo.

REM --- PowerShell 存在確認 ---
where powershell > nul 2>&1
if errorlevel 1 (
    echo [エラー] PowerShell が見つかりません。
    echo Windows 標準の PowerShell が必要です。
    echo.
    pause
    exit /b 1
)

REM --- setup_env.ps1 存在確認 ---
if not exist "%~dp0setup_env.ps1" (
    echo [エラー] setup_env.ps1 が見つかりません。
    echo この .bat と同じフォルダに setup_env.ps1 を配置してください。
    echo.
    pause
    exit /b 1
)

REM --- 実行 ---
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0setup_env.ps1"
set EXITCODE=%ERRORLEVEL%

echo.
echo ============================================================
if %EXITCODE% equ 0 (
    echo   セットアップ完了
) else (
    echo   未完了 - 上記のメッセージを確認してください
)
echo ============================================================
echo.
pause
exit /b %EXITCODE%