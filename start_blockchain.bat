@echo off
title OncoVault Blockchain Gateway (Port 5001)
echo ==========================================================
echo Starting OncoVault Local Blockchain Gateway on port 5001...
echo ==========================================================
cd /d "%~dp0fabric\gateway"
if not exist "dist\index.js" (
    echo Building Gateway...
    call npm run build
)
node dist/index.js
pause
