@echo off
setlocal EnableExtensions DisableDelayedExpansion
title Maintenance Tool 2.0

rem ============================================================================
rem  Maintenance Tool 2.0
rem
rem  Reglas de seguridad de este script:
rem   - Nunca borra nada fuera de carpetas de cache / temporales conocidas.
rem   - Nunca borra perfiles de navegador (marcadores, claves, extensiones).
rem   - Solo borra temporales con mas de TEMP_DAYS dias sin modificarse.
rem   - Si un navegador esta abierto, se salta (no lo cierra a la fuerza).
rem   - Toda ruta va entre comillas y toda variable se valida antes de usarse.
rem ============================================================================

set "TEMP_DAYS=7"
set "SAGE_ID=64"

rem --- 1. Permisos de administrador (SFC, DISM y cleanmgr los necesitan) -------
net session >nul 2>&1
if errorlevel 1 goto :Elevate

rem --- 2. Carpeta de registros -------------------------------------------------
set "STAMP="
for /f "usebackq delims=" %%T in (`powershell -NoProfile -Command "Get-Date -Format yyyy-MM-dd_HH-mm-ss"`) do set "STAMP=%%T"
if not defined STAMP set "STAMP=sin-fecha-%RANDOM%"

set "DESKTOP="
for /f "usebackq delims=" %%D in (`powershell -NoProfile -Command "[Environment]::GetFolderPath('Desktop')"`) do set "DESKTOP=%%D"
if not defined DESKTOP set "DESKTOP=%USERPROFILE%\Desktop"
if not exist "%DESKTOP%\" set "DESKTOP=%USERPROFILE%"

set "LOG=%DESKTOP%\Maintenance\%STAMP%"
mkdir "%LOG%" >nul 2>&1
if not exist "%LOG%\" goto :NoLogDir
set "MAINLOG=%LOG%\resumen.log"

echo.
echo  ==========================================
echo    Maintenance Tool 2.0
echo  ==========================================
echo   Usuario  : %USERNAME%
echo   Registros: %LOG%
echo.
echo   Guarda tu trabajo antes de continuar.
echo   Este script NO borra documentos, descargas, papelera,
echo   marcadores, contrasenas ni extensiones.
echo.
echo   [1] Mantenimiento completo recomendado
echo   [2] Personalizado - elegir cada paso
echo   [3] Salir
echo.
choice /C 123 /N /M "  Elige una opcion [1/2/3]: "
if errorlevel 3 goto :EndNoPause
if errorlevel 2 goto :Custom

set "DO_RESTORE=1"
set "DO_DISK=1"
set "DO_REPAIR=1"
set "DO_UPDATE=1"
set "DO_STORE=0"
set "DO_TEMP=1"
set "DO_CHROME=1"
set "DO_EDGE=1"
set "DO_FIREFOX=1"
set "DO_AUTO=0"
goto :Run

:Custom
echo.
call :Ask DO_RESTORE "Crear punto de restauracion antes de empezar"
call :Ask DO_DISK    "Liberar espacio en disco - sin tocar papelera ni Descargas"
call :Ask DO_REPAIR  "Reparar archivos de Windows con DISM y SFC - puede tardar 30-60 min"
call :Ask DO_UPDATE  "Buscar actualizaciones de Windows"
call :Ask DO_STORE   "Restablecer cache de Microsoft Store"
call :Ask DO_TEMP    "Borrar temporales con mas de %TEMP_DAYS% dias"
call :Ask DO_CHROME  "Limpiar cache de Chrome - solo cache"
call :Ask DO_EDGE    "Limpiar cache de Edge - solo cache"
call :Ask DO_FIREFOX "Limpiar cache de Firefox - solo cache"
call :Ask DO_AUTO    "Lanzar el mantenimiento automatico de Windows"

:Run
echo Inicio: %DATE% %TIME% > "%MAINLOG%"
echo.

call :Step "0. Punto de restauracion"
if "%DO_RESTORE%"=="1" call :RestorePoint
if not "%DO_RESTORE%"=="1" call :Skip

call :Step "1. Liberar espacio en disco"
if "%DO_DISK%"=="1" call :DiskCleanup
if not "%DO_DISK%"=="1" call :Skip

call :Step "2. Reparar archivos de Windows"
if "%DO_REPAIR%"=="1" call :Repair
if not "%DO_REPAIR%"=="1" call :Skip

call :Step "3. Windows Update"
if "%DO_UPDATE%"=="1" call :WindowsUpdate
if not "%DO_UPDATE%"=="1" call :Skip

call :Step "4. Microsoft Store"
if "%DO_STORE%"=="1" call :StoreReset
if not "%DO_STORE%"=="1" call :Skip

call :Step "5. Archivos temporales"
if "%DO_TEMP%"=="1" call :TempFiles
if not "%DO_TEMP%"=="1" call :Skip

call :Step "6. Cache de navegadores"
if "%DO_CHROME%"=="1"  call :CleanChromium "Chrome" "chrome.exe" "%LOCALAPPDATA%\Google\Chrome\User Data"
if "%DO_EDGE%"=="1"    call :CleanChromium "Edge" "msedge.exe" "%LOCALAPPDATA%\Microsoft\Edge\User Data"
if "%DO_FIREFOX%"=="1" call :CleanFirefox

call :Step "7. Vaciar cache DNS"
ipconfig /flushdns > "%LOG%\flush-dns.log" 2>&1
call :Result

call :Step "8. Informe de bateria"
powercfg /batteryreport /output "%LOG%\battery-report.html" > "%LOG%\battery-report.log" 2>&1
if errorlevel 1 call :Note "Sin informe - normal en equipos sin bateria."
if not errorlevel 1 call :Note "OK - battery-report.html"

call :Step "9. Lista de procesos"
tasklist /v > "%LOG%\tasklist.txt" 2>&1
call :Result

call :Step "10. Mantenimiento automatico de Windows"
if "%DO_AUTO%"=="1" call :AutoMaintenance
if not "%DO_AUTO%"=="1" call :Skip

echo Fin: %DATE% %TIME% >> "%MAINLOG%"
echo.
echo  ==========================================
echo    Terminado. Registros en:
echo    %LOG%
echo  ==========================================
if "%DO_REPAIR%"=="1" echo    Se recomienda reiniciar el equipo.
echo.
start "" "%LOG%"
pause
goto :EndNoPause

rem ============================================================================
rem  Pasos
rem ============================================================================

:RestorePoint
rem Windows solo permite un punto cada 24 h y requiere Proteccion del sistema
rem activada; si falla se avisa y se sigue.
powershell -NoProfile -ExecutionPolicy Bypass -Command "try { Checkpoint-Computer -Description 'Maintenance Tool' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop; exit 0 } catch { Write-Output $_.Exception.Message; exit 1 }" > "%LOG%\restore-point.log" 2>&1
if errorlevel 1 call :Note "No se pudo crear - ver restore-point.log. Se continua."
if not errorlevel 1 call :Note "OK"
goto :eof

:DiskCleanup
rem Se marcan SOLO categorias seguras y se ejecuta cleanmgr con ese perfil.
rem Quedan fuera a proposito: Papelera, carpeta Descargas e instalaciones
rem anteriores de Windows.
set "VC=HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches"
for /f "delims=" %%K in ('reg query "%VC%" 2^>nul') do reg delete "%%K" /v StateFlags00%SAGE_ID% /f >nul 2>&1
call :SageFlag "Temporary Files"
call :SageFlag "Temporary Setup Files"
call :SageFlag "Internet Cache Files"
call :SageFlag "Thumbnail Cache"
call :SageFlag "Old ChkDsk Files"
call :SageFlag "Windows Error Reporting Files"
call :SageFlag "Delivery Optimization Files"
call :SageFlag "D3D Shader Cache"
call :SageFlag "Update Cleanup"
call :Note "Ejecutando cleanmgr, puede tardar varios minutos..."
start "" /wait cleanmgr.exe /sagerun:%SAGE_ID%
call :Note "OK"
goto :eof

:SageFlag
reg query "%VC%\%~1" >nul 2>&1
if errorlevel 1 goto :eof
reg add "%VC%\%~1" /v StateFlags00%SAGE_ID% /t REG_DWORD /d 2 /f >nul 2>&1
goto :eof

:Repair
rem Orden correcto: primero DISM repara el almacen de componentes y despues
rem SFC lo usa para reparar los archivos del sistema.
rem La salida se muestra en pantalla para que se vea el progreso.
echo.
echo     NO cierres esta ventana ni apagues el equipo durante este paso.
echo.
echo     --- DISM /RestoreHealth ---
DISM /Online /Cleanup-Image /RestoreHealth
echo DISM RestoreHealth errorlevel=%ERRORLEVEL% >> "%MAINLOG%"
echo.
echo     --- SFC /scannow ---
sfc /scannow
echo SFC errorlevel=%ERRORLEVEL% >> "%MAINLOG%"
copy /y "%SystemRoot%\Logs\DISM\dism.log" "%LOG%\dism.log" >nul 2>&1
findstr /c:"[SR]" "%SystemRoot%\Logs\CBS\CBS.log" > "%LOG%\sfc-detalle.log" 2>nul
goto :eof

:WindowsUpdate
rem wuauclt ya no hace nada en Windows 10/11; se usa UsoClient.
if exist "%SystemRoot%\System32\UsoClient.exe" goto :WU_Uso
wuauclt /detectnow /updatenow
call :Note "Busqueda solicitada con wuauclt."
goto :eof
:WU_Uso
"%SystemRoot%\System32\UsoClient.exe" StartInteractiveScan >nul 2>&1
call :Note "Busqueda iniciada. Revisa Configuracion - Windows Update."
goto :eof

:StoreReset
call :Note "Se abrira la Tienda al terminar; puedes cerrarla."
start "" /wait wsreset.exe
call :Note "OK"
goto :eof

:TempFiles
call :CleanOld "%TEMP%"
call :CleanOld "%SystemRoot%\Temp"
goto :eof

:CleanOld
rem Borra solo archivos con mas de TEMP_DAYS dias sin modificarse dentro de la
rem carpeta indicada. No sigue enlaces ni junctions, y los archivos en uso se
rem saltan solos. Nunca se mueve ni se borra la carpeta en si.
set "MB_TARGET=%~1"
if not defined MB_TARGET goto :eof
if not exist "%MB_TARGET%\" goto :eof
set "MB_DAYS=%TEMP_DAYS%"
set "MB_MAINLOG=%MAINLOG%"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$t=$env:MB_TARGET; if(-not $t -or $t.Length -lt 10 -or -not (Test-Path -LiteralPath $t -PathType Container)){ Write-Output 'Ruta no valida, se omite.'; exit 1 }; $lim=(Get-Date).AddDays(-[int]$env:MB_DAYS); $script:n=0; $script:b=0; function W($d){ foreach($i in @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)){ if($i.Attributes -band [IO.FileAttributes]::ReparsePoint){ continue }; if($i.PSIsContainer){ W $i.FullName; if($i.LastWriteTime -lt $lim -and -not @(Get-ChildItem -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue).Count){ Remove-Item -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue } } elseif($i.LastWriteTime -lt $lim){ $len=$i.Length; Remove-Item -LiteralPath $i.FullName -Force -ErrorAction SilentlyContinue; if(-not (Test-Path -LiteralPath $i.FullName)){ $script:n++; $script:b+=$len } } } }; W $t; $m='    ' + $t + ': ' + $script:n + ' archivos, ' + [math]::Round($script:b/1MB,1) + ' MB liberados'; Write-Output $m; Add-Content -LiteralPath $env:MB_MAINLOG -Value $m"
goto :eof

:CleanChromium
rem %1 nombre  %2 proceso  %3 carpeta "User Data"
rem Solo se borran carpetas de cache dentro de cada perfil. El perfil
rem (marcadores, contrasenas, historial, extensiones, sesiones) no se toca.
if not exist "%~3\" call :Note "%~1: no instalado, se omite."
if not exist "%~3\" goto :eof
tasklist /FI "IMAGENAME eq %~2" 2>nul | find /I "%~2" >nul
if not errorlevel 1 call :Note "%~1: esta abierto, se omite. Cierralo y vuelve a ejecutar."
if not errorlevel 1 goto :eof
call :ChromiumProfile "%~3\Default"
for /d %%P in ("%~3\Profile *") do call :ChromiumProfile "%%~fP"
call :Note "%~1: cache borrada."
goto :eof

:ChromiumProfile
if not exist "%~1\" goto :eof
call :RemoveDir "%~1\Cache"
call :RemoveDir "%~1\Code Cache"
call :RemoveDir "%~1\GPUCache"
goto :eof

:CleanFirefox
rem La cache de Firefox vive en LOCALAPPDATA. El perfil real (APPDATA, con
rem places.sqlite, logins, etc.) no se toca.
set "FF=%LOCALAPPDATA%\Mozilla\Firefox\Profiles"
if not exist "%FF%\" call :Note "Firefox: no instalado, se omite."
if not exist "%FF%\" goto :eof
tasklist /FI "IMAGENAME eq firefox.exe" 2>nul | find /I "firefox.exe" >nul
if not errorlevel 1 call :Note "Firefox: esta abierto, se omite. Cierralo y vuelve a ejecutar."
if not errorlevel 1 goto :eof
for /d %%P in ("%FF%\*") do call :RemoveDir "%%~fP\cache2"
for /d %%P in ("%FF%\*") do call :RemoveDir "%%~fP\startupCache"
call :Note "Firefox: cache borrada."
goto :eof

:RemoveDir
rem Unico punto del script que borra carpetas. Exige ruta no vacia, existente
rem y que termine en un nombre de cache conocido.
set "RD_TARGET=%~1"
if not defined RD_TARGET goto :eof
if not exist "%RD_TARGET%\" goto :eof
set "RD_OK="
if /I "%~nx1"=="Cache" set "RD_OK=1"
if /I "%~nx1"=="Code Cache" set "RD_OK=1"
if /I "%~nx1"=="GPUCache" set "RD_OK=1"
if /I "%~nx1"=="cache2" set "RD_OK=1"
if /I "%~nx1"=="startupCache" set "RD_OK=1"
if not defined RD_OK goto :eof
echo rd "%RD_TARGET%" >> "%LOG%\browser-cache.log"
rd /s /q "%RD_TARGET%" >> "%LOG%\browser-cache.log" 2>&1
goto :eof

:AutoMaintenance
MSchedExe.exe Start > "%LOG%\auto-maintenance.log" 2>&1
call :Note "Iniciado en segundo plano."
goto :eof

rem ============================================================================
rem  Utilidades
rem ============================================================================

:Ask
choice /C SN /N /M "  %~2 [S/N]: "
if errorlevel 2 set "%~1=0"
if not errorlevel 2 set "%~1=1"
goto :eof

:Step
echo.
echo  %~1
echo  -----------------------------
echo [%TIME%] %~1 >> "%MAINLOG%"
goto :eof

:Result
if errorlevel 1 call :Note "Termino con errores - revisa los registros."
if not errorlevel 1 call :Note "OK"
goto :eof

:Skip
call :Note "Omitido."
goto :eof

:Note
echo     %~1
echo     %~1 >> "%MAINLOG%"
goto :eof

:Elevate
echo.
echo  Se necesitan permisos de administrador. Acepta el aviso de Windows...
set "MB_SELF=%~f0"
powershell -NoProfile -Command "Start-Process -FilePath $env:MB_SELF -Verb RunAs" >nul 2>&1
if errorlevel 1 echo  No se pudo elevar. Clic derecho - Ejecutar como administrador.
if errorlevel 1 pause
goto :EndNoPause

:NoLogDir
echo.
echo  No se pudo crear la carpeta de registros:
echo    %LOG%
echo  No se hizo ningun cambio.
pause
goto :EndNoPause

:EndNoPause
endlocal
exit /b 0
