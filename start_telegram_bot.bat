@echo off
chcp 65001 >nul
cd /d "%~dp0"

rem 优先用 PATH 里的 python，找不到再提示
where python >nul 2>nul
if %errorlevel%==0 (
    python -u telegram_bot.py
) else (
    where py >nul 2>nul
    if %errorlevel%==0 (
        py -3 -u telegram_bot.py
    ) else (
        echo [ERROR] python not found in PATH
        echo Install Python 3.8+ first: https://www.python.org/downloads/
        pause
        exit /b 1
    )
)
pause
