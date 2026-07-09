@echo off
setlocal
title Reprise - Web

REM ------------------------------------------------------------------
REM  Double-click launcher for Reprise (Windows).
REM  Starts the local server and opens your browser. Zero dependencies.
REM ------------------------------------------------------------------

cd /d "%~dp0"

where node >nul 2>nul
if errorlevel 1 (
  echo.
  echo   Node.js 18+ is required but was not found on your PATH.
  echo   Install it from https://nodejs.org and try again.
  echo.
  pause
  exit /b 1
)

if not defined PORT set PORT=4747

echo.
echo   Starting Reprise on http://127.0.0.1:%PORT%
echo   (Close this window to stop the server.)
echo.

REM Give the server a moment to bind, then open the default browser.
start "" cmd /c "timeout /t 2 >nul & start "" http://127.0.0.1:%PORT%"

node server.js

endlocal
