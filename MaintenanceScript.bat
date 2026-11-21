@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Maintenance Tool 4.0

rem ============================================================================
rem  Lanzador de Maintenance Tool. Toda la logica vive en Maintenance.ps1;
rem  este archivo solo pide permisos de administrador y lo ejecuta.
rem
rem  Uso:  MaintenanceScript.bat [-DryRun] [-Unattended] [-DiagnosticOnly]
rem                              [-Steps a,b] [-Skip a,b] [-TempDays 7]
rem                              [-InstallTask] [-RemoveTask]
rem ============================================================================

set "MB_PS1=%~dp0Maintenance.ps1"
if not exist "%MB_PS1%" goto :Missing

rem Ya elevado por este mismo lanzador: no volver a intentarlo.
echo %* | find /I "-InvokedBy" >nul
if not errorlevel 1 goto :Run

rem fltmc solo funciona con permisos de administrador.
fltmc >nul 2>&1
if not errorlevel 1 goto :Run

echo.
echo  Se necesitan permisos de administrador. Acepta el aviso de Windows...
set "MB_SELF=%~f0"
set "MB_ARGS=%*"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$q=[char]34; $a=('-InvokedBy ' + $q + $env:USERNAME + $q + ' ' + $env:MB_ARGS).Trim(); Start-Process -FilePath $env:MB_SELF -ArgumentList $a -Verb RunAs"
if errorlevel 1 goto :ElevateFailed
exit /b 0

:Run
powershell -NoProfile -ExecutionPolicy Bypass -File "%MB_PS1%" %*
exit /b %ERRORLEVEL%

:ElevateFailed
echo.
echo  No se pudo elevar. Haz clic derecho y elige Ejecutar como administrador.
pause
exit /b 1

:Missing
echo.
echo  Falta el archivo Maintenance.ps1.
echo  Debe estar en la misma carpeta que este .bat:
echo    %~dp0
echo  Descarga el proyecto completo, no solo el .bat.
pause
exit /b 1
