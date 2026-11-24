@echo off
cd /d "%~dp0"
title FoodGo
echo.
echo  FoodGo shuru hocche... (browser nije khulbe)
echo.
rem 1) Windows er nijer PowerShell diye - kisu install korte hoy na
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0serve.ps1"
if not errorlevel 1 goto :end
rem 2) Fallback: Python
where py >nul 2>nul
if %errorlevel%==0 (
  start "" cmd /c "timeout /t 2 >nul & start http://localhost:8080"
  py -m http.server 8080
  goto :end
)
where node >nul 2>nul
if %errorlevel%==0 (
  start "" cmd /c "timeout /t 4 >nul & start http://localhost:8080"
  npx --yes serve -l 8080 .
  goto :end
)
echo.
echo  Server chalu hoy nai (port 8080-8090 shob busy hote pare). Onno program bondho kore abar chalao.
pause
:end
