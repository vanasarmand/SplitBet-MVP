@echo off
title SplitBet Live Backend & Cloudflare Tunnel
echo ===================================================
echo     SplitBet Live Mode Server & Tunnel
echo ===================================================
echo.

:: Start Node.js backend in background if not already running
netstat -ano | findstr :4000 >nul 2>&1
if %errorlevel% neq 0 (
    echo [1/2] Starting Node.js backend on port 4000...
    start "SplitBet Backend" /B node server.js
    timeout /t 2 /nobreak >nul
) else (
    echo [1/2] Backend already running on port 4000.
)

echo [2/2] Launching Cloudflare Tunnel for secure HTTPS...
echo.
echo ===================================================
echo Look for the URL ending with '.trycloudflare.com' below:
echo Paste that URL into SplitBet Settings or open it with ?api=URL
echo ===================================================
echo.

.\cloudflared.exe tunnel --url http://localhost:4000
