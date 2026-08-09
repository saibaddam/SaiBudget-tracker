@echo off
REM Launch the TradingView desktop app with Chrome DevTools Protocol enabled.
REM
REM CDP can only be enabled at launch time, so TradingView must be started by
REM this script rather than from the Start menu.
REM
REM Usage: scripts\launch-tradingview-debug.bat [port]

setlocal enabledelayedexpansion

set PORT=%1
if "%PORT%"=="" set PORT=9222

REM -- Already listening? Nothing to do. ---------------------------------------
curl -sf -m 2 "http://127.0.0.1:%PORT%/json/version" >nul 2>&1
if !errorlevel! equ 0 (
  echo [ok] TradingView is already exposing CDP on port %PORT%.
  exit /b 0
)

REM -- Locate the app ----------------------------------------------------------
set TV_BIN=
for %%P in (
  "%LOCALAPPDATA%\Programs\TradingView\TradingView.exe"
  "%PROGRAMFILES%\TradingView\TradingView.exe"
  "%PROGRAMFILES(X86)%\TradingView\TradingView.exe"
) do (
  if exist %%P set TV_BIN=%%P
)

if "%TV_BIN%"=="" (
  echo [error] Could not find TradingView.exe. Launch it manually:
  echo         "C:\path\to\TradingView.exe" --remote-debugging-port=%PORT%
  exit /b 1
)

REM -- Restart any running instance (CDP only attaches at launch) --------------
tasklist /FI "IMAGENAME eq TradingView.exe" 2>nul | find /I "TradingView.exe" >nul
if !errorlevel! equ 0 (
  echo [warn] TradingView is running without CDP enabled and must be restarted.
  set /p REPLY="       Quit and relaunch it now? [y/N] "
  if /I not "!REPLY!"=="y" (
    echo [error] Aborted. Quit TradingView yourself, then re-run this script.
    exit /b 1
  )
  taskkill /IM TradingView.exe /F >nul 2>&1
  timeout /t 3 /nobreak >nul
)

REM -- Launch ------------------------------------------------------------------
echo [info] Launching TradingView with --remote-debugging-port=%PORT% ...
start "" %TV_BIN% --remote-debugging-port=%PORT%

for /l %%i in (1,1,20) do (
  curl -sf -m 2 "http://127.0.0.1:%PORT%/json/version" >nul 2>&1
  if !errorlevel! equ 0 (
    echo [ok] TradingView is up on CDP port %PORT%.
    echo [info] Leave it running, then use the tradingview MCP tools from Claude Code.
    exit /b 0
  )
  timeout /t 1 /nobreak >nul
)

echo [error] TradingView started but port %PORT% never answered.
echo         Make sure you are signed in, then re-run.
exit /b 1
