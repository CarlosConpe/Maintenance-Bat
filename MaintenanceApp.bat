@echo off
setlocal EnableExtensions DisableDelayedExpansion

rem ============================================================================
rem  Abre Maintenance Tool con interfaz grafica. Pide permisos de
rem  administrador y lanza MaintenanceApp.ps1 sin ventana de consola.
rem ============================================================================

set "MB_APP=%~dp0MaintenanceApp.ps1"
if not exist "%MB_APP%" goto :Missing
if not exist "%~dp0Maintenance.ps1" goto :Missing

echo %* | find /I "-InvokedBy" >nul
if not errorlevel 1 goto :Run

fltmc >nul 2>&1
if not errorlevel 1 goto :Run

set "MB_SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; Start-Process -FilePath $env:MB_SELF -ArgumentList ('-InvokedBy ' + $q + $env:USERNAME + $q) -Verb RunAs -WindowStyle Hidden"
if errorlevel 1 goto :ElevateFailed
exit /b 0

:Run
start "" powershell -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%MB_APP%" %*
exit /b 0

:ElevateFailed
echo.
echo  No se pudo elevar. Haz clic derecho y elige Ejecutar como administrador.
pause
exit /b 1

:Missing
echo.
echo  Faltan archivos. MaintenanceApp.ps1 y Maintenance.ps1 deben estar
echo  en la misma carpeta que este .bat:
echo    %~dp0
pause
exit /b 1
