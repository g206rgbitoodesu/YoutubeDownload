@echo off
chcp 65001 > nul
title YoutubeDownload Web申請フォーム
cd /d "%~dp0"

echo.
echo ============================================================
echo   🎵 YoutubeDownload Web申請フォーム
echo ============================================================
echo.

REM --- Python 存在確認 ---
where python > nul 2>&1
if errorlevel 1 (
    echo [ERROR] Python が見つかりません。
    echo https://www.python.org/ からインストールしてください。
    echo.
    pause
    exit /b 1
)

REM --- Flask 存在確認 ---
python -c "import flask" > nul 2>&1
if errorlevel 1 (
    echo [INFO] Flask が見つかりません。インストールします...
    python -m pip install --quiet flask
    if errorlevel 1 (
        echo [ERROR] Flask のインストールに失敗しました。
        pause
        exit /b 1
    )
    echo [OK] Flask をインストールしました。
    echo.
)

REM --- 起動 ---
python app.py

echo.
pause