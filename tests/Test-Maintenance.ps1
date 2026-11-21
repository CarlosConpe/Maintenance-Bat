# Pruebas del nucleo de borrado seguro. Se ejecutan sobre carpetas falsas dentro
# de una carpeta temporal; no tocan nada real del equipo.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tests\Test-Maintenance.ps1

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\Maintenance.ps1')

$script:Failures = 0
function Assert {
    param([bool]$Condition, [string]$Name)
    if ($Condition) { Write-Host ('  ok    ' + $Name) }
    else { Write-Host ('  FALLO ' + $Name); $script:Failures++ }
}

function New-TestFile {
    param([string]$Path, [int]$AgeDays = 0)
    $dir = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Set-Content -LiteralPath $Path -Value ('x' * 2048)
    if ($AgeDays -gt 0) { (Get-Item -LiteralPath $Path).LastWriteTime = (Get-Date).AddDays(-$AgeDays) }
}

$base = Join-Path ([IO.Path]::GetTempPath()) ('mb-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $base -Force | Out-Null
$onWindows = ($env:OS -eq 'Windows_NT')

try {
    # ------------------------------------------------------------------ temp
    Write-Host 'Temporales antiguos'
    $temp = Join-Path $base 'temp'
    $outside = Join-Path $base 'outside'
    New-TestFile (Join-Path $temp 'viejo.tmp') 30
    New-TestFile (Join-Path $temp 'nuevo.tmp') 0
    New-TestFile (Join-Path $temp 'sub\viejo.log') 30
    New-TestFile (Join-Path $temp 'sub2\nuevo.log') 0
    New-TestFile (Join-Path $temp 'solo lectura.tmp') 30
    (Get-Item -LiteralPath (Join-Path $temp 'solo lectura.tmp')).IsReadOnly = $true
    New-TestFile (Join-Path $outside 'importante.txt') 30
    (Get-Item -LiteralPath (Join-Path $temp 'sub')).LastWriteTime = (Get-Date).AddDays(-30)
    $link = Join-Path $temp 'enlace'
    if ($onWindows) { New-Item -ItemType Junction -Path $link -Target $outside | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path $link -Target $outside | Out-Null }

    $sim = Invoke-SafeClean -Path $temp -OlderThanDays 7 -Simulate $true
    Assert ($sim.Valid) 'simulacion: ruta aceptada'
    Assert ($sim.Files -eq 3) ('simulacion: cuenta 3 archivos antiguos (dio ' + $sim.Files + ')')
    Assert ($sim.Bytes -gt 6000) 'simulacion: suma el tamano'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'viejo.tmp')) 'simulacion: no borra nada'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'sub\viejo.log')) 'simulacion: no borra en subcarpetas'

    $real = Invoke-SafeClean -Path $temp -OlderThanDays 7 -Simulate $false
    Assert ($real.Files -eq 3) ('real: borra 3 archivos (dio ' + $real.Files + ')')
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'viejo.tmp'))) 'real: borra archivo antiguo'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'solo lectura.tmp'))) 'real: borra archivo antiguo de solo lectura'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'nuevo.tmp')) 'real: conserva archivo reciente'
    Assert (-not (Test-Path -LiteralPath (Join-Path $temp 'sub'))) 'real: quita subcarpeta antigua vacia'
    Assert (Test-Path -LiteralPath (Join-Path $temp 'sub2\nuevo.log')) 'real: conserva subcarpeta con archivos recientes'
    Assert (Test-Path -LiteralPath (Join-Path $outside 'importante.txt')) 'real: NO sigue enlaces fuera de la carpeta'
    Assert (Test-Path -LiteralPath $link) 'real: no borra el enlace'
    Assert (Test-Path -LiteralPath $temp) 'real: la carpeta raiz sigue existiendo'

    # ----------------------------------------------------------- rutas seguras
    Write-Host 'Rutas rechazadas'
    Assert (-not (Test-SafeTarget '')) 'rechaza ruta vacia'
    Assert (-not (Test-SafeTarget $null)) 'rechaza ruta nula'
    Assert (-not (Test-SafeTarget (Join-Path $base 'no-existe'))) 'rechaza ruta inexistente'
    Assert (-not (Test-SafeTarget $link)) 'rechaza un enlace como objetivo'
    Assert (-not (Test-SafeTarget ([IO.Path]::GetPathRoot($base)))) 'rechaza la raiz de la unidad'
    if ($onWindows) {
        Assert (-not (Test-SafeTarget $env:SystemRoot)) 'rechaza C:\Windows'
        Assert (-not (Test-SafeTarget $env:USERPROFILE)) 'rechaza el perfil de usuario'
        Assert (-not (Test-SafeTarget $env:LOCALAPPDATA)) 'rechaza AppData\Local'
        Assert (-not (Test-SafeTarget $env:ProgramFiles)) 'rechaza Program Files'
        Assert (-not (Test-SafeTarget ($env:SystemDrive + '\'))) 'rechaza C:\'
        Assert (Test-SafeTarget $env:TEMP) 'acepta %TEMP%'
    }
    $bad = Invoke-SafeClean -Path (Join-Path $base 'no-existe') -Simulate $false
    Assert (-not $bad.Valid) 'Invoke-SafeClean no actua sobre ruta invalida'

    # ----------------------------------------------------------------- caches
    Write-Host 'Cache de navegadores'
    $ud = Join-Path $base 'User Data'
    New-TestFile (Join-Path $ud 'Default\Cache\Cache_Data\f_0001')
    New-TestFile (Join-Path $ud 'Default\Code Cache\js\abc')
    New-TestFile (Join-Path $ud 'Default\GPUCache\data_1')
    New-TestFile (Join-Path $ud 'Default\Bookmarks')
    New-TestFile (Join-Path $ud 'Default\Login Data')
    New-TestFile (Join-Path $ud 'Default\Extensions\abc\manifest.json')
    New-TestFile (Join-Path $ud 'Profile 1\Cache\f_0002')
    New-TestFile (Join-Path $ud 'Profile 1\History')
    New-TestFile (Join-Path $ud 'Local State')
    New-TestFile (Join-Path $ud 'Otra Carpeta\Cache\no-tocar')

    $app = @{ Name = 'Falso'; Process = 'proceso-que-no-existe-mb'; Root = $ud; Profiles = @('Default', 'Profile *'); Caches = @('Cache', 'Code Cache', 'GPUCache') }

    $s = Clear-AppCache -App $app -Simulate $true
    Assert ($s.State -eq 'Limpio' -and $s.Files -eq 4) ('simulacion: cuenta 4 archivos de cache (dio ' + $s.Files + ')')
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Cache\Cache_Data\f_0001')) 'simulacion: no borra cache'

    $r = Clear-AppCache -App $app -Simulate $false
    Assert ($r.Files -eq 4) ('real: borra 4 archivos de cache (dio ' + $r.Files + ')')
    Assert (-not (Test-Path -LiteralPath (Join-Path $ud 'Default\Cache\Cache_Data\f_0001'))) 'real: vacia Cache'
    Assert (-not (Test-Path -LiteralPath (Join-Path $ud 'Default\Code Cache\js\abc'))) 'real: vacia Code Cache'
    Assert (-not (Test-Path -LiteralPath (Join-Path $ud 'Profile 1\Cache\f_0002'))) 'real: vacia Cache de Profile 1'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Bookmarks')) 'real: conserva marcadores'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Login Data')) 'real: conserva contrasenas'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Extensions\abc\manifest.json')) 'real: conserva extensiones'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Profile 1\History')) 'real: conserva historial'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Local State')) 'real: conserva Local State'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Otra Carpeta\Cache\no-tocar')) 'real: no toca carpetas que no son perfil'

    $no = Clear-CacheFolder -Path (Join-Path $ud 'Default') -Simulate $false
    Assert (-not $no.Valid) 'Clear-CacheFolder rechaza una carpeta que no es de cache'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Bookmarks')) 'y no borra nada al rechazarla'

    $missing = Clear-AppCache -App @{ Name = 'X'; Process = 'x'; Root = (Join-Path $base 'nada'); Profiles = @('Default'); Caches = @('Cache') }
    Assert ($missing.State -eq 'NoInstalado') 'aplicacion no instalada se omite'

    # Aplicacion abierta: se usa el propio proceso de PowerShell como "navegador".
    $me = (Get-Process -Id $PID).ProcessName
    New-TestFile (Join-Path $ud 'Default\Cache\otra-vez')
    $open = Clear-AppCache -App @{ Name = 'Abierta'; Process = $me; Root = $ud; Profiles = @('Default'); Caches = @('Cache') }
    Assert ($open.State -eq 'Abierto') 'aplicacion abierta se omite'
    Assert (Test-Path -LiteralPath (Join-Path $ud 'Default\Cache\otra-vez')) 'y su cache no se toca'

    # ------------------------------------------------- arranque y programador
    if ($onWindows) {
        Write-Host 'Programas de arranque'
        $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        $approved = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run'
        $fake = 'MB-Test-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
        if (-not (Test-Path $runKey)) { New-Item -Path $runKey -Force | Out-Null }
        New-ItemProperty -LiteralPath $runKey -Name $fake -Value 'notepad.exe' -PropertyType String -Force | Out-Null
        try {
            $e = @(Get-StartupApps | Where-Object { $_.Nombre -eq $fake })
            Assert ($e.Count -eq 1) 'detecta el programa de arranque de prueba'
            Assert ($e[0].Activo) 'aparece activado por defecto'
            Set-StartupAppEnabled -ApprovedKey $e[0].ApprovedKey -ValueName $e[0].ValueName -Enabled $false
            Assert (-not (@(Get-StartupApps | Where-Object { $_.Nombre -eq $fake })[0].Activo)) 'se desactiva'
            Assert ((Get-ItemProperty -LiteralPath $runKey -Name $fake).$fake -eq 'notepad.exe') 'desactivar no borra la entrada'
            Set-StartupAppEnabled -ApprovedKey $e[0].ApprovedKey -ValueName $e[0].ValueName -Enabled $true
            Assert (@(Get-StartupApps | Where-Object { $_.Nombre -eq $fake })[0].Activo) 'se vuelve a activar'
            $threw = $false
            try { Set-StartupAppEnabled -ApprovedKey 'HKCU:\Software\Otra' -ValueName 'x' -Enabled $false } catch { $threw = $true }
            Assert $threw 'rechaza claves fuera de StartupApproved'
        } finally {
            Remove-ItemProperty -LiteralPath $runKey -Name $fake -ErrorAction SilentlyContinue
            Remove-ItemProperty -LiteralPath $approved -Name $fake -ErrorAction SilentlyContinue
        }

        if (Test-IsAdmin) {
            Write-Host 'Tareas programadas'
            $tn = 'CI Prueba ' + [guid]::NewGuid().ToString('N').Substring(0, 6)
            try {
                New-MaintenanceSchedule -Name $tn -Frequency 'Semanal' -Day 'Sunday' -Time '03:15' -StepKeys @('Diagnostico', 'Dns')
                $t = @(Get-MaintenanceSchedules | Where-Object { $_.Nombre -eq $tn })
                Assert ($t.Count -eq 1) 'crea la tarea'
                Assert ($t[0].Pasos -eq 'Diagnostico,Dns') ('guarda los pasos (' + $t[0].Pasos + ')')
                Assert ($t[0].Cuando -like '*domingo*03:15*') ('describe cuando (' + $t[0].Cuando + ')')
                Assert ($t[0].Proxima.Length -gt 0) 'tiene proxima ejecucion'
                $act = (Get-ScheduledTask -TaskPath $script:TaskPath -TaskName $tn).Actions[0]
                Assert ($act.Arguments -like '*-Unattended -Steps Diagnostico,Dns*') 'la accion lanza el motor sin preguntas'
                Set-MaintenanceScheduleEnabled $tn $false
                Assert (@(Get-MaintenanceSchedules | Where-Object { $_.Nombre -eq $tn })[0].Estado -eq 'Pausada') 'se pausa'
                Set-MaintenanceScheduleEnabled $tn $true
                Assert (@(Get-MaintenanceSchedules | Where-Object { $_.Nombre -eq $tn })[0].Estado -eq 'Activa') 'se reanuda'
                New-MaintenanceSchedule -Name $tn -Frequency 'Diaria' -Time '04:00' -StepKeys @('Dns')
                Assert (@(Get-MaintenanceSchedules | Where-Object { $_.Nombre -eq $tn })[0].Cuando -eq 'Cada dia a las 04:00') 'se puede modificar'
                foreach ($bad in @(@{ Name = 'mal/nombre'; Time = '10:00'; Keys = @('Dns') }, @{ Name = 'ok'; Time = '25:00'; Keys = @('Dns') }, @{ Name = 'ok'; Time = '10:00'; Keys = @('NoExiste') }, @{ Name = 'ok'; Time = '10:00'; Keys = @() })) {
                    $threw = $false
                    try { New-MaintenanceSchedule -Name $bad.Name -Time $bad.Time -StepKeys $bad.Keys } catch { $threw = $true }
                    Assert $threw ('rechaza datos no validos: ' + $bad.Name + ' ' + $bad.Time + ' ' + ($bad.Keys -join ','))
                }
            } finally {
                try { Remove-MaintenanceSchedule $tn } catch { }
            }
            Assert (@(Get-MaintenanceSchedules | Where-Object { $_.Nombre -eq $tn }).Count -eq 0) 'se elimina'
        }

        Write-Host 'Estado rapido e historial'
        $q = Get-QuickStatus
        Assert ($q.RamTotalGB -gt 0) 'Get-QuickStatus lee la memoria'
        Assert (@($q.Volumes).Count -gt 0) 'Get-QuickStatus lee las unidades'
    }
    $hist = Join-Path $base 'hist'
    New-TestFile (Join-Path $hist '2026-01-02_10-00-00\resumen.log')
    Set-Content -LiteralPath (Join-Path $hist '2026-01-02_10-00-00\resumen.log') -Value 'Inicio: x   Modo: REAL'
    New-TestFile (Join-Path $hist '2026-03-04_11-30-00\resumen.log')
    Set-Content -LiteralPath (Join-Path $hist '2026-03-04_11-30-00\resumen.log') -Value 'Inicio: x   Modo: SIMULACION - no se modifica nada'
    New-Item -ItemType Directory -Path (Join-Path $hist 'sin-log') -Force | Out-Null
    $h = @(Get-RunHistory $hist)
    Assert ($h.Count -eq 2) 'historial ignora carpetas sin resumen'
    Assert ($h[0].Fecha -eq '04/03/2026 11:30' -and $h[0].Modo -eq 'Simulacion') 'historial ordenado, con fecha y modo'

    Write-Host 'Limpieza de registros antiguos'
    $lr = Join-Path $base 'logs'
    $old = Join-Path $lr ((Get-Date).AddDays(-120).ToString('yyyy-MM-dd_HH-mm-ss'))
    $recent = Join-Path $lr ((Get-Date).AddDays(-5).ToString('yyyy-MM-dd_HH-mm-ss'))
    $noLog = Join-Path $lr ((Get-Date).AddDays(-200).ToString('yyyy-MM-dd_HH-mm-ss'))
    $other = Join-Path $lr 'Mis cosas'
    New-TestFile (Join-Path $old 'resumen.log')
    New-TestFile (Join-Path $old 'sub\tasklist.txt')
    New-TestFile (Join-Path $recent 'resumen.log')
    New-TestFile (Join-Path $noLog 'otro.txt')
    New-TestFile (Join-Path $other 'resumen.log') 400
    $gone = Remove-OldLogs -Root $lr -Days 90
    Assert ($gone -eq 1) ('borra 1 ejecucion antigua (dio ' + $gone + ')')
    Assert (-not (Test-Path -LiteralPath $old)) 'la ejecucion antigua desaparece'
    Assert (Test-Path -LiteralPath $recent) 'conserva la reciente'
    Assert (Test-Path -LiteralPath (Join-Path $noLog 'otro.txt')) 'no toca carpetas sin resumen.log'
    Assert (Test-Path -LiteralPath (Join-Path $other 'resumen.log')) 'no toca carpetas con otro nombre'
    Assert ((Remove-OldLogs -Root (Join-Path $base 'no-existe') -Days 90) -eq 0) 'carpeta inexistente: no hace nada'
    $h2 = @(Get-RunHistory @($hist, $lr))
    Assert ($h2.Count -eq 3) ('historial combina varias carpetas (' + $h2.Count + ')')

    if ($onWindows) {
        Write-Host 'Notificacion'
        $n = Show-Notification 'Maintenance Tool' 'Prueba automatica'
        Assert ($n -is [bool]) ('Show-Notification no lanza errores (devolvio ' + $n + ')')

        Write-Host 'Acceso directo'
        $made = @(New-AppShortcut -Locations @('Desktop'))
        try {
            Assert ($made.Count -eq 1 -and (Test-Path -LiteralPath $made[0])) 'crea el acceso directo'
            $sc = (New-Object -ComObject WScript.Shell).CreateShortcut($made[0])
            Assert ($sc.TargetPath -like '*\MaintenanceApp.bat') ('apunta a MaintenanceApp.bat (' + $sc.TargetPath + ')')
        } finally { foreach ($m in $made) { Remove-Item -LiteralPath $m -Force -ErrorAction SilentlyContinue } }
    }

    Write-Host 'Preferencias'
    $sp = Join-Path $base 'cfg\settings.json'
    $d0 = Get-AppSettings -Path $sp
    Assert ($d0.Theme -eq 'Auto' -and $d0.TempDays -eq 7) 'valores por defecto sin archivo'
    Save-AppSettings @{ Theme = 'Oscuro'; TempDays = 14; MaintSteps = @('Dns', 'Temporales'); SpacePath = 'C:\x' } -Path $sp
    $d1 = Get-AppSettings -Path $sp
    Assert ($d1.Theme -eq 'Oscuro' -and $d1.TempDays -eq 14) 'guarda y lee tema y dias'
    Assert ((@($d1.MaintSteps) -join ',') -eq 'Dns,Temporales') ('guarda los pasos (' + (@($d1.MaintSteps) -join ',') + ')')
    Set-Content -LiteralPath $sp -Value '{"Theme":"Rosa","TempDays":9999,"MaintSteps":["Dns","NoExiste"]}'
    $d2 = Get-AppSettings -Path $sp
    Assert ($d2.Theme -eq 'Auto' -and $d2.TempDays -eq 7 -and (@($d2.MaintSteps) -join ',') -eq 'Dns') 'ignora valores no validos'
    Set-Content -LiteralPath $sp -Value 'esto no es json'
    Assert ((Get-AppSettings -Path $sp).Theme -eq 'Auto') 'archivo corrupto: usa valores por defecto'

    Write-Host 'Analizador de espacio'
    $sd = Join-Path $base 'space'
    New-Item -ItemType Directory -Path (Join-Path $sd 'grande\sub') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $sd 'chica') -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $sd 'grande\sub\a.bin'), (New-Object byte[] 50000))
    [IO.File]::WriteAllBytes((Join-Path $sd 'grande\b.bin'), (New-Object byte[] 30000))
    [IO.File]::WriteAllBytes((Join-Path $sd 'chica\c.txt'), (New-Object byte[] 1000))
    [IO.File]::WriteAllBytes((Join-Path $sd 'suelto.dat'), (New-Object byte[] 5000))
    $tgt = Join-Path $base 'space-target'
    New-Item -ItemType Directory -Path $tgt -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $tgt 'enorme.bin'), (New-Object byte[] 900000))
    if ($onWindows) { New-Item -ItemType Junction -Path (Join-Path $sd 'enlace') -Target $tgt | Out-Null }
    else { New-Item -ItemType SymbolicLink -Path (Join-Path $sd 'enlace') -Target $tgt | Out-Null }
    $prog = [hashtable]::Synchronized(@{ Count = 0 })
    $rep = Get-SpaceReport -Path $sd -TopFiles 2 -Progress $prog
    Assert ($rep.TotalBytes -eq 86000) ('total correcto sin seguir enlaces (' + $rep.TotalBytes + ')')
    Assert ($rep.Carpetas[0].Nombre -eq 'grande' -and $rep.Carpetas[0].Bytes -eq 80000 -and $rep.Carpetas[0].Archivos -eq 2) 'carpeta mayor primero con su tamano recursivo'
    Assert (@($rep.Carpetas | Where-Object { $_.Nombre -eq '(archivos sueltos)' }).Count -eq 1) 'cuenta los archivos sueltos'
    Assert (@($rep.Carpetas | Where-Object { $_.Nombre -eq 'enlace' }).Count -eq 0) 'ignora el enlace'
    Assert ($rep.ArchivosGrandes.Count -eq 2 -and $rep.ArchivosGrandes[0].Nombre -eq 'a.bin') 'top de archivos ordenado y limitado'
    Assert ($prog.Count -eq 4) ('progreso cuenta archivos (' + $prog.Count + ')')
    Assert (Test-Path -LiteralPath (Join-Path $sd 'grande\sub\a.bin')) 'no borra nada'
    $threw = $false
    try { Get-SpaceReport -Path (Join-Path $base 'no-existe') } catch { $threw = $true }
    Assert $threw 'rechaza carpeta inexistente'

    Write-Host 'Uso de procesos'
    $u1 = Get-ProcessUsage
    Start-Sleep -Milliseconds 300
    $u2 = Get-ProcessUsage -Previous $u1.Sample
    Assert (@($u2.Rows).Count -gt 3) 'lista procesos'
    Assert (@($u2.Rows | Where-Object { $_.Id -eq $PID }).Count -eq 1) 'incluye este proceso'
    Assert ($u2.CpuTotal -ge 0 -and $u2.CpuTotal -le 100) ('CPU total en rango (' + $u2.CpuTotal + ')')

    # ------------------------------------------------------------------ varios
    Write-Host 'Varios'
    $keys = @(Get-StepList | ForEach-Object { $_.Key })
    Assert ($keys.Count -eq @($keys | Select-Object -Unique).Count) 'las claves de paso son unicas'
    $missingFn = @(Get-StepList | Where-Object { -not (Get-Command $_.Action -ErrorAction SilentlyContinue) })
    Assert ($missingFn.Count -eq 0) 'todas las acciones de paso existen'
    Assert ((Format-Size 1048576) -like '1*MB') 'Format-Size'
    Assert (@(Split-List @('a,b', 'c')).Count -eq 3) 'Split-List separa por comas'
}
finally {
    Remove-Item -LiteralPath $base -Recurse -Force -ErrorAction SilentlyContinue
}

Write-Host ''
if ($script:Failures -gt 0) { Write-Host ("$($script:Failures) prueba(s) fallaron."); exit 1 }
Write-Host 'Todas las pruebas pasaron.'
exit 0
