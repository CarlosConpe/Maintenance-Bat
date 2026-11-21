[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Unattended,
    [switch]$DiagnosticOnly,
    [string[]]$Steps,
    [string[]]$Skip,
    [int]$TempDays = 7,
    [string]$LogRoot,
    [string]$InvokedBy,
    [switch]$InstallTask,
    [switch]$RemoveTask,
    [switch]$NoPause,
    [switch]$GuiMode
)

# ============================================================================
#  Maintenance Tool 4.0  (compatible con Windows PowerShell 5.1)
#
#  Reglas de seguridad:
#   - Solo se borra dentro de carpetas de cache / temporales conocidas.
#   - Nunca se siguen ni se borran enlaces o junctions.
#   - Nunca se tocan perfiles (marcadores, claves, extensiones, sesiones).
#   - Los temporales solo se borran si llevan mas de TempDays dias sin cambios.
#   - Una aplicacion abierta se salta; nunca se cierra a la fuerza.
#   - Con -DryRun no se modifica nada: solo se mide y se informa.
#
#  Este archivo debe mantenerse en ASCII puro (PowerShell 5.1 lo lee como ANSI).
# ============================================================================

$script:TaskName = 'MaintenanceTool'
$script:TaskPath = '\MaintenanceTool\'
$script:GuiMode = [bool]$GuiMode
if ($script:GuiMode) { try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { } }
$script:SageId = 64
$script:CacheLeafNames = @('Cache', 'Code Cache', 'GPUCache', 'cache2', 'startupCache')
$script:Simulate = $false
$script:Results = New-Object System.Collections.ArrayList
$script:Warnings = New-Object System.Collections.ArrayList
$script:Detail = ''
$script:LogDir = $null
$script:MainLog = $null

# ----------------------------------------------------------------------------
#  Utilidades
# ----------------------------------------------------------------------------

function Write-Note {
    param([string]$Text)
    Write-Host ('    ' + $Text)
    if ($script:MainLog) {
        try { Add-Content -LiteralPath $script:MainLog -Value ('    ' + $Text) -ErrorAction Stop } catch { }
    }
}

function Write-Marker {
    # Lineas que la interfaz grafica interpreta para mostrar el progreso.
    param([string]$Text)
    if ($script:GuiMode) { Write-Host ('##' + $Text) }
}

function Add-Warning {
    param([string]$Text)
    [void]$script:Warnings.Add($Text)
    Write-Marker ('WARN|' + $Text)
    Write-Note ('AVISO: ' + $Text)
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    return ('{0:N0} KB' -f ($Bytes / 1KB))
}

function Test-IsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $p = New-Object Security.Principal.WindowsPrincipal($id)
        return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Invoke-Native {
    # Ejecuta un programa en esta misma consola (se ve su progreso) y devuelve
    # su codigo de salida.
    param([string]$File, [string]$Arguments)
    if ($Arguments) {
        $p = Start-Process -FilePath $File -ArgumentList $Arguments -NoNewWindow -Wait -PassThru
    } else {
        $p = Start-Process -FilePath $File -NoNewWindow -Wait -PassThru
    }
    return $p.ExitCode
}

function Get-FreeBytes {
    try {
        $d = New-Object System.IO.DriveInfo($env:SystemDrive)
        return [double]$d.AvailableFreeSpace
    } catch { return [double]0 }
}

# ----------------------------------------------------------------------------
#  Nucleo de borrado seguro (probado en tests\Test-Maintenance.ps1)
# ----------------------------------------------------------------------------

function Test-SafeTarget {
    # Una carpeta solo se acepta como objetivo si existe, no es un enlace, no es
    # la raiz de una unidad y no es una carpeta protegida del sistema o usuario.
    param([string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path)) { return $false }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/') } catch { return $false }
    if ($full.Length -lt 10) { return $false }
    if (-not (Test-Path -LiteralPath $full -PathType Container)) { return $false }
    $root = [IO.Path]::GetPathRoot($full)
    if ($root -and ($full -eq $root.TrimEnd('\', '/'))) { return $false }
    try {
        $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) { return $false }
    } catch { return $false }
    $protected = @(
        $env:SystemDrive, $env:SystemRoot, $env:ProgramFiles, ${env:ProgramFiles(x86)},
        $env:ProgramData, $env:USERPROFILE, $env:APPDATA, $env:LOCALAPPDATA, $env:PUBLIC, $env:HOME,
        $(if ($env:SystemRoot) { Join-Path $env:SystemRoot 'System32' }),
        $(if ($env:USERPROFILE) { Split-Path -Parent $env:USERPROFILE })
    )
    foreach ($p in $protected) {
        if ([string]::IsNullOrWhiteSpace($p)) { continue }
        if ($full -ieq $p.TrimEnd('\', '/')) { return $false }
    }
    return $true
}

function Invoke-CleanWalk {
    param([string]$Dir, $Limit, [bool]$Simulate, $Stat)
    $items = @(Get-ChildItem -LiteralPath $Dir -Force -ErrorAction SilentlyContinue)
    foreach ($i in $items) {
        # Enlaces y junctions: ni se siguen ni se borran.
        if ($i.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
        if ($i.PSIsContainer) {
            Invoke-CleanWalk -Dir $i.FullName -Limit $Limit -Simulate $Simulate -Stat $Stat
            if (-not $Simulate -and (($null -eq $Limit) -or ($i.LastWriteTime -lt $Limit))) {
                # Borrado NO recursivo: solo tiene exito si quedo vacia.
                try { [IO.Directory]::Delete($i.FullName, $false) } catch { }
            }
            continue
        }
        if (($null -ne $Limit) -and ($i.LastWriteTime -ge $Limit)) { continue }
        $len = [long]$i.Length
        if ($Simulate) {
            $Stat.Files++
            $Stat.Bytes += $len
            continue
        }
        try {
            if ($i.IsReadOnly) { $i.IsReadOnly = $false }
            [IO.File]::Delete($i.FullName)
            $Stat.Files++
            $Stat.Bytes += $len
        } catch {
            $Stat.Failed++
        }
    }
}

function Invoke-SafeClean {
    # Borra el CONTENIDO de $Path (nunca la carpeta en si). Con -OlderThanDays
    # solo lo que lleve mas de esos dias sin modificarse. Con -Simulate solo mide.
    param(
        [string]$Path,
        [int]$OlderThanDays = -1,
        [bool]$Simulate = $false
    )
    $stat = New-Object psobject -Property @{ Files = 0; Bytes = [long]0; Failed = 0; Valid = $false }
    if (-not (Test-SafeTarget $Path)) { return $stat }
    $stat.Valid = $true
    $limit = $null
    if ($OlderThanDays -ge 0) { $limit = (Get-Date).AddDays(-$OlderThanDays) }
    Invoke-CleanWalk -Dir ([IO.Path]::GetFullPath($Path)) -Limit $limit -Simulate $Simulate -Stat $stat
    return $stat
}

function Clear-CacheFolder {
    # Unico punto que vacia carpetas de cache. Exige que el nombre final de la
    # ruta sea uno de los nombres de cache conocidos.
    param([string]$Path, [bool]$Simulate = $false)
    $empty = New-Object psobject -Property @{ Files = 0; Bytes = [long]0; Failed = 0; Valid = $false }
    if ([string]::IsNullOrWhiteSpace($Path)) { return $empty }
    $leaf = Split-Path -Leaf $Path
    if ($script:CacheLeafNames -notcontains $leaf) { return $empty }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { return $empty }
    return (Invoke-SafeClean -Path $Path -Simulate $Simulate)
}

function Get-ProfileDirs {
    # Devuelve las carpetas de perfil existentes para un patron dado.
    param([string]$Root, [string[]]$Patterns)
    $out = @()
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return $out }
    foreach ($pat in $Patterns) {
        if ($pat -eq '.') { $out += $Root; continue }
        $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -Force -Filter $pat -ErrorAction SilentlyContinue)
        foreach ($d in $dirs) {
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            $out += $d.FullName
        }
    }
    return $out
}

function Clear-AppCache {
    # $App: hashtable con Name, Process, Root, Profiles (patrones), Caches (nombres)
    param([hashtable]$App, [bool]$Simulate = $false, [bool]$IgnoreRunning = $false)
    $r = New-Object psobject -Property @{ Name = $App.Name; State = 'NoInstalado'; Files = 0; Bytes = [long]0 }
    if (-not (Test-Path -LiteralPath $App.Root -PathType Container)) { return $r }
    if (-not $IgnoreRunning -and $App.Process) {
        if (@(Get-Process -Name $App.Process -ErrorAction SilentlyContinue).Count -gt 0) {
            $r.State = 'Abierto'
            return $r
        }
    }
    foreach ($prof in (Get-ProfileDirs -Root $App.Root -Patterns $App.Profiles)) {
        foreach ($c in $App.Caches) {
            $s = Clear-CacheFolder -Path (Join-Path $prof $c) -Simulate $Simulate
            $r.Files += $s.Files
            $r.Bytes += $s.Bytes
        }
    }
    $r.State = 'Limpio'
    return $r
}

function Get-AppCacheList {
    $chromium = @('Cache', 'Code Cache', 'GPUCache')
    $prof = @('Default', 'Profile *')
    $la = $env:LOCALAPPDATA
    $ra = $env:APPDATA
    return @(
        @{ Name = 'Chrome';   Process = 'chrome';   Root = "$la\Google\Chrome\User Data";                Profiles = $prof; Caches = $chromium },
        @{ Name = 'Edge';     Process = 'msedge';   Root = "$la\Microsoft\Edge\User Data";               Profiles = $prof; Caches = $chromium },
        @{ Name = 'Brave';    Process = 'brave';    Root = "$la\BraveSoftware\Brave-Browser\User Data";  Profiles = $prof; Caches = $chromium },
        @{ Name = 'Vivaldi';  Process = 'vivaldi';  Root = "$la\Vivaldi\User Data";                      Profiles = $prof; Caches = $chromium },
        @{ Name = 'Opera';    Process = 'opera';    Root = "$la\Opera Software\Opera Stable";            Profiles = @('.', 'Default'); Caches = $chromium },
        @{ Name = 'Opera GX'; Process = 'opera';    Root = "$la\Opera Software\Opera GX Stable";         Profiles = @('.', 'Default'); Caches = $chromium },
        @{ Name = 'Firefox';  Process = 'firefox';  Root = "$la\Mozilla\Firefox\Profiles";               Profiles = @('*'); Caches = @('cache2', 'startupCache') },
        @{ Name = 'Teams clasico'; Process = 'Teams'; Root = "$ra\Microsoft\Teams";                      Profiles = @('.'); Caches = $chromium },
        @{ Name = 'Teams nuevo'; Process = 'ms-teams'; Root = "$la\Packages\MSTeams_8wekyb3d8bbwe\LocalCache\Microsoft\MSTeams\EBWebView"; Profiles = $prof; Caches = $chromium }
    )
}

# ----------------------------------------------------------------------------
#  Pasos
# ----------------------------------------------------------------------------

function Step-Restore {
    if ($script:Simulate) { Write-Note 'Simulacion: se crearia un punto de restauracion.'; return }
    try {
        Checkpoint-Computer -Description 'Maintenance Tool' -RestorePointType MODIFY_SETTINGS -ErrorAction Stop -WarningAction SilentlyContinue
        Write-Note 'Punto de restauracion creado.'
        $script:Detail = 'Creado'
    } catch {
        # Windows solo permite uno cada 24 h y exige Proteccion del sistema activa.
        Add-Warning ('No se pudo crear el punto de restauracion: ' + $_.Exception.Message)
        $script:Detail = 'No creado'
    }
}

function Step-Diagnostico {
    $out = New-Object System.Collections.ArrayList
    $nl = { param($t) [void]$out.Add($t) }

    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $up = (Get-Date) - $os.LastBootUpTime
        & $nl ('Sistema : ' + $os.Caption + ' ' + $os.Version)
        & $nl ('Encendido desde hace: {0:N1} dias' -f $up.TotalDays)
        & $nl ('RAM     : {0:N1} GB libres de {1:N1} GB' -f ($os.FreePhysicalMemory / 1MB), ($os.TotalVisibleMemorySize / 1MB))
        if ($up.TotalDays -gt 14) { Add-Warning ('El equipo lleva {0:N0} dias sin reiniciarse.' -f $up.TotalDays) }
    } catch { & $nl ('Sistema : no disponible - ' + $_.Exception.Message) }

    & $nl ''
    & $nl 'UNIDADES'
    try {
        foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
            if (-not $v.Size) { continue }
            $pct = 100 * $v.FreeSpace / $v.Size
            & $nl ('  {0}  {1} libres de {2}  ({3:N0}%)' -f $v.DeviceID, (Format-Size $v.FreeSpace), (Format-Size $v.Size), $pct)
            if ($pct -lt 15) { Add-Warning ('Unidad {0} con poco espacio libre: {1:N0}%.' -f $v.DeviceID, $pct) }
        }
    } catch { & $nl ('  no disponible - ' + $_.Exception.Message) }

    & $nl ''
    & $nl 'DISCOS FISICOS'
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            & $nl ('  {0}  [{1}]  {2}  salud: {3}' -f $d.FriendlyName, $d.MediaType, (Format-Size $d.Size), $d.HealthStatus)
            if ("$($d.HealthStatus)" -ne 'Healthy') { Add-Warning ('Disco {0} con estado de salud: {1}. Haz copia de seguridad.' -f $d.FriendlyName, $d.HealthStatus) }
        }
    } catch { & $nl ('  no disponible - ' + $_.Exception.Message) }

    & $nl ''
    & $nl 'PROGRAMAS DE INICIO'
    try {
        $st = @(Get-CimInstance Win32_StartupCommand -ErrorAction Stop)
        foreach ($s in $st) { & $nl ('  {0}  <-  {1}' -f $s.Name, $s.Location) }
        & $nl ('  Total: ' + $st.Count)
        if ($st.Count -gt 15) { Add-Warning ('Hay {0} programas de inicio; revisa cuales necesitas.' -f $st.Count) }
    } catch { & $nl ('  no disponible - ' + $_.Exception.Message) }

    & $nl ''
    & $nl 'ERRORES DEL SISTEMA - ULTIMOS 7 DIAS (los 10 mas repetidos)'
    try {
        $ev = @(Get-WinEvent -FilterHashtable @{ LogName = 'System'; Level = 1, 2; StartTime = (Get-Date).AddDays(-7) } -MaxEvents 1000 -ErrorAction SilentlyContinue)
        if ($ev.Count -eq 0) { & $nl '  Ninguno.' }
        $groups = $ev | Group-Object ProviderName, Id | Sort-Object Count -Descending | Select-Object -First 10
        foreach ($g in $groups) { & $nl ('  {0,4} x  {1}' -f $g.Count, $g.Name) }
    } catch { & $nl ('  no disponible - ' + $_.Exception.Message) }

    & $nl ''
    $pending = $false
    foreach ($k in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $k) { $pending = $true }
    }
    if ($pending) { Add-Warning 'Hay un reinicio pendiente de Windows.' }
    & $nl ('Reinicio pendiente: ' + $(if ($pending) { 'SI' } else { 'no' }))

    $file = Join-Path $script:LogDir 'diagnostico.txt'
    $out | Out-File -LiteralPath $file -Encoding UTF8
    foreach ($l in $out) { Write-Host ('    ' + $l) }
    $script:Detail = 'diagnostico.txt'
}

function Step-Disco {
    $cats = @('Temporary Files', 'Temporary Setup Files', 'Internet Cache Files', 'Thumbnail Cache',
        'Old ChkDsk Files', 'Windows Error Reporting Files', 'Delivery Optimization Files',
        'D3D Shader Cache', 'Update Cleanup')
    if ($script:Simulate) {
        Write-Note ('Simulacion: se ejecutaria cleanmgr con: ' + ($cats -join ', '))
        Write-Note 'Quedan fuera: Papelera, Descargas e instalaciones anteriores de Windows.'
        return
    }
    $vc = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    $flag = 'StateFlags{0:D4}' -f $script:SageId
    foreach ($k in @(Get-ChildItem -LiteralPath $vc -ErrorAction SilentlyContinue)) {
        Remove-ItemProperty -LiteralPath $k.PSPath -Name $flag -ErrorAction SilentlyContinue
    }
    foreach ($c in $cats) {
        $key = Join-Path $vc $c
        if (Test-Path -LiteralPath $key) {
            New-ItemProperty -LiteralPath $key -Name $flag -PropertyType DWord -Value 2 -Force -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Write-Note 'Ejecutando cleanmgr, puede tardar varios minutos...'
    Start-Process -FilePath 'cleanmgr.exe' -ArgumentList ('/sagerun:' + $script:SageId) -Wait
    Write-Note 'Hecho.'
}

function Step-Reparar {
    if ($script:Simulate) {
        Write-Note 'Simulacion: solo se comprueba el estado con DISM /CheckHealth.'
        $c = Invoke-Native 'dism.exe' '/Online /Cleanup-Image /CheckHealth'
        $script:Detail = 'CheckHealth codigo ' + $c
        return
    }
    Write-Host ''
    Write-Host '    NO cierres esta ventana ni apagues el equipo durante este paso.'
    Write-Host ''
    Write-Host '    --- DISM /RestoreHealth ---'
    $d = Invoke-Native 'dism.exe' '/Online /Cleanup-Image /RestoreHealth'
    Write-Host ''
    Write-Host '    --- SFC /scannow ---'
    $s = Invoke-Native 'sfc.exe' '/scannow'
    $script:Detail = ('DISM codigo {0}, SFC codigo {1}' -f $d, $s)
    Write-Note $script:Detail
    if ($d -ne 0) { Add-Warning ('DISM termino con codigo {0}; revisa dism.log.' -f $d) }
    Copy-Item -LiteralPath (Join-Path $env:SystemRoot 'Logs\DISM\dism.log') -Destination (Join-Path $script:LogDir 'dism.log') -ErrorAction SilentlyContinue
    try {
        Select-String -LiteralPath (Join-Path $env:SystemRoot 'Logs\CBS\CBS.log') -SimpleMatch '[SR]' -ErrorAction Stop |
            ForEach-Object { $_.Line } | Out-File -LiteralPath (Join-Path $script:LogDir 'sfc-detalle.log') -Encoding UTF8
    } catch { }
}

function Step-Update {
    if ($script:Simulate) { Write-Note 'Simulacion: se pediria a Windows Update buscar actualizaciones.'; return }
    $uso = Join-Path $env:SystemRoot 'System32\UsoClient.exe'
    if (Test-Path -LiteralPath $uso) {
        Start-Process -FilePath $uso -ArgumentList 'StartInteractiveScan' -WindowStyle Hidden
        Write-Note 'Busqueda iniciada. Revisa Configuracion - Windows Update.'
    } else {
        Write-Note 'UsoClient no encontrado; abre Windows Update manualmente.'
    }
}

function Step-Store {
    if ($script:Simulate) { Write-Note 'Simulacion: se ejecutaria wsreset.'; return }
    Write-Note 'Se abrira la Tienda al terminar; puedes cerrarla.'
    Start-Process -FilePath 'wsreset.exe' -Wait
    Write-Note 'Hecho.'
}

function Step-Temporales {
    $total = [long]0
    $files = 0
    foreach ($t in @($env:TEMP, (Join-Path $env:SystemRoot 'Temp')) | Select-Object -Unique) {
        $s = Invoke-SafeClean -Path $t -OlderThanDays $script:TempDays -Simulate $script:Simulate
        if (-not $s.Valid) { Write-Note ($t + ': ruta no valida, se omite.'); continue }
        Write-Note ('{0}: {1} archivos, {2}{3}' -f $t, $s.Files, (Format-Size $s.Bytes), $(if ($s.Failed) { ", $($s.Failed) en uso" } else { '' }))
        $total += $s.Bytes
        $files += $s.Files
    }
    $script:Detail = ('{0} archivos, {1}' -f $files, (Format-Size $total))
}

function Step-Caches {
    $total = [long]0
    foreach ($app in (Get-AppCacheList)) {
        $r = Clear-AppCache -App $app -Simulate $script:Simulate
        switch ($r.State) {
            'NoInstalado' { }
            'Abierto' { Write-Note ($r.Name + ': esta abierto, se omite. Cierralo y vuelve a ejecutar.') }
            default {
                Write-Note ('{0}: {1} archivos, {2}' -f $r.Name, $r.Files, (Format-Size $r.Bytes))
                $total += $r.Bytes
            }
        }
    }
    $script:Detail = Format-Size $total
}

function Step-Optimizar {
    if ($script:Simulate) { Write-Note 'Simulacion: se optimizaria la unidad del sistema (TRIM en SSD, desfragmentar en HDD).'; return }
    $c = Invoke-Native 'defrag.exe' ($env:SystemDrive + ' /O')
    $script:Detail = 'codigo ' + $c
}

function Step-Apps {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        Write-Note 'winget no esta disponible en este equipo; se omite.'
        $script:Detail = 'winget no disponible'
        return
    }
    $log = Join-Path $script:LogDir 'winget.log'
    if ($script:Simulate) {
        Write-Note 'Simulacion: solo se listan las actualizaciones disponibles.'
        & winget.exe upgrade --accept-source-agreements --disable-interactivity 2>&1 | Tee-Object -FilePath $log | Out-Host
        return
    }
    & winget.exe upgrade --all --silent --accept-source-agreements --accept-package-agreements --disable-interactivity 2>&1 | Tee-Object -FilePath $log | Out-Host
    $script:Detail = 'codigo ' + $LASTEXITCODE
}

function Step-Dns {
    if ($script:Simulate) { Write-Note 'Simulacion: se vaciaria la cache DNS.'; return }
    & ipconfig.exe /flushdns 2>&1 | Out-File -LiteralPath (Join-Path $script:LogDir 'flush-dns.log') -Encoding UTF8
    Write-Note 'Hecho.'
}

function Step-Bateria {
    $file = Join-Path $script:LogDir 'battery-report.html'
    & powercfg.exe /batteryreport /output $file 2>&1 | Out-File -LiteralPath (Join-Path $script:LogDir 'battery-report.log') -Encoding UTF8
    if (Test-Path -LiteralPath $file) { Write-Note 'battery-report.html generado.'; $script:Detail = 'Generado' }
    else { Write-Note 'Sin informe - normal en equipos sin bateria.'; $script:Detail = 'Sin bateria' }
}

function Step-Procesos {
    & tasklist.exe /v 2>&1 | Out-File -LiteralPath (Join-Path $script:LogDir 'tasklist.txt') -Encoding UTF8
    Write-Note 'tasklist.txt generado.'
}

function Step-AutoMant {
    if ($script:Simulate) { Write-Note 'Simulacion: se lanzaria el mantenimiento automatico de Windows.'; return }
    Start-Process -FilePath 'MSchedExe.exe' -ArgumentList 'Start' -WindowStyle Hidden
    Write-Note 'Iniciado en segundo plano.'
}

function Get-StepList {
    # Changes = el paso modifica el equipo (en simulacion se marca "Simulado").
    return @(
        @{ Key = 'Restore';     Title = 'Punto de restauracion';              Rec = $true;  Changes = $true;  Action = 'Step-Restore' },
        @{ Key = 'Diagnostico'; Title = 'Diagnostico del equipo';             Rec = $true;  Changes = $false; Action = 'Step-Diagnostico' },
        @{ Key = 'Disco';       Title = 'Liberar espacio en disco';           Rec = $true;  Changes = $true;  Action = 'Step-Disco' },
        @{ Key = 'Reparar';     Title = 'Reparar Windows (DISM + SFC, 30-60 min)'; Rec = $true; Changes = $true; Action = 'Step-Reparar' },
        @{ Key = 'Update';      Title = 'Buscar actualizaciones de Windows';  Rec = $true;  Changes = $true;  Action = 'Step-Update' },
        @{ Key = 'Store';       Title = 'Restablecer cache de Microsoft Store'; Rec = $false; Changes = $true; Action = 'Step-Store' },
        @{ Key = 'Temporales';  Title = 'Borrar temporales antiguos';         Rec = $true;  Changes = $true;  Action = 'Step-Temporales' },
        @{ Key = 'Caches';      Title = 'Cache de navegadores y Teams';       Rec = $true;  Changes = $true;  Action = 'Step-Caches' },
        @{ Key = 'Optimizar';   Title = 'Optimizar unidad (TRIM / desfragmentar)'; Rec = $true; Changes = $true; Action = 'Step-Optimizar' },
        @{ Key = 'Apps';        Title = 'Actualizar programas con winget';    Rec = $false; Changes = $true;  Action = 'Step-Apps' },
        @{ Key = 'Dns';         Title = 'Vaciar cache DNS';                   Rec = $true;  Changes = $true;  Action = 'Step-Dns' },
        @{ Key = 'Bateria';     Title = 'Informe de bateria';                 Rec = $true;  Changes = $false; Action = 'Step-Bateria' },
        @{ Key = 'Procesos';    Title = 'Lista de procesos';                  Rec = $true;  Changes = $false; Action = 'Step-Procesos' },
        @{ Key = 'AutoMant';    Title = 'Mantenimiento automatico de Windows'; Rec = $false; Changes = $true; Action = 'Step-AutoMant' }
    )
}

function Invoke-Step {
    param([hashtable]$Step, [int]$Number, [bool]$Selected)
    Write-Host ''
    Write-Host (' {0}. {1}' -f $Number, $Step.Title)
    Write-Host ' -----------------------------'
    if ($script:MainLog) { Add-Content -LiteralPath $script:MainLog -Value ('[{0}] {1}' -f (Get-Date -Format 'HH:mm:ss'), $Step.Title) -ErrorAction SilentlyContinue }
    $script:Detail = ''
    $status = 'Omitido'
    $sw = [Diagnostics.Stopwatch]::StartNew()
    if (-not $Selected) {
        Write-Note 'Omitido.'
    } else {
        Write-Marker ('STEP|' + $Step.Key)
        try {
            & $Step.Action | Out-Host
            if ($script:Simulate -and $Step.Changes) { $status = 'Simulado' } else { $status = 'OK' }
        } catch {
            $status = 'Error'
            $script:Detail = $_.Exception.Message
            Write-Note ('ERROR: ' + $_.Exception.Message)
        }
    }
    $sw.Stop()
    if ($Selected) { Write-Marker ('DONE|{0}|{1}|{2}|{3}' -f $Step.Key, $status, [int]$sw.Elapsed.TotalSeconds, ("$($script:Detail)" -replace '[\r\n|]', ' ')) }
    [void]$script:Results.Add((New-Object psobject -Property @{
                Paso = $Step.Title; Estado = $status; Detalle = $script:Detail; Segundos = [int]$sw.Elapsed.TotalSeconds
            }))
}

# ----------------------------------------------------------------------------
#  Tarea programada
# ----------------------------------------------------------------------------

function Install-MaintenanceTask {
    $bat = Join-Path $PSScriptRoot 'MaintenanceScript.bat'
    if (-not (Test-Path -LiteralPath $bat)) { throw 'No se encuentra MaintenanceScript.bat junto a Maintenance.ps1.' }
    $action = New-ScheduledTaskAction -Execute $bat -Argument '-Unattended'
    $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek Saturday -At '12:00'
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $script:TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host ''
    Write-Host ('  Tarea "{0}" creada: sabados a las 12:00, cada 4 semanas.' -f $script:TaskName)
    Write-Host '  Se ejecuta sin preguntas con el modo recomendado. No muevas esta carpeta.'
}

function Remove-MaintenanceTask {
    if (Get-ScheduledTask -TaskName $script:TaskName -ErrorAction SilentlyContinue) {
        Unregister-ScheduledTask -TaskName $script:TaskName -Confirm:$false
        Write-Host ('  Tarea "{0}" eliminada.' -f $script:TaskName)
    } else {
        Write-Host '  No habia ninguna tarea programada.'
    }
}

# ----------------------------------------------------------------------------
#  Datos para la interfaz grafica
# ----------------------------------------------------------------------------

function Get-DefaultLogRoot {
    $desktop = [Environment]::GetFolderPath('Desktop')
    if (-not $desktop -or -not (Test-Path -LiteralPath $desktop)) { $desktop = $env:USERPROFILE }
    return (Join-Path $desktop 'Maintenance')
}

function Get-QuickStatus {
    # Estado rapido del equipo (solo lectura) para el panel de inicio.
    $st = @{ Os = ''; UptimeDays = 0.0; RamTotalGB = 0.0; RamFreeGB = 0.0; Volumes = @(); Disks = @(); PendingReboot = $false }
    try {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction Stop
        $st.Os = ("$($os.Caption) $($os.Version)").Trim()
        $st.UptimeDays = ((Get-Date) - $os.LastBootUpTime).TotalDays
        $st.RamTotalGB = $os.TotalVisibleMemorySize / 1MB
        $st.RamFreeGB = $os.FreePhysicalMemory / 1MB
    } catch { }
    try {
        foreach ($v in @(Get-CimInstance Win32_LogicalDisk -Filter 'DriveType=3' -ErrorAction Stop)) {
            if (-not $v.Size) { continue }
            $st.Volumes += New-Object psobject -Property @{ Id = $v.DeviceID; FreeBytes = [double]$v.FreeSpace; SizeBytes = [double]$v.Size; FreePct = 100 * $v.FreeSpace / $v.Size }
        }
    } catch { }
    try {
        foreach ($d in @(Get-PhysicalDisk -ErrorAction Stop)) {
            $st.Disks += New-Object psobject -Property @{ Name = "$($d.FriendlyName)"; Media = "$($d.MediaType)"; Health = "$($d.HealthStatus)" }
        }
    } catch { }
    foreach ($k in @(
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
            'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired')) {
        if (Test-Path $k) { $st.PendingReboot = $true }
    }
    return $st
}

function Get-RunHistory {
    # Ejecuciones anteriores, de la mas reciente a la mas antigua.
    param([string]$Root)
    $out = @()
    if (-not $Root -or -not (Test-Path -LiteralPath $Root -PathType Container)) { return $out }
    $dirs = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Sort-Object Name -Descending)
    foreach ($d in $dirs) {
        $log = Join-Path $d.FullName 'resumen.log'
        if (-not (Test-Path -LiteralPath $log)) { continue }
        $first = "$(Get-Content -LiteralPath $log -TotalCount 1 -ErrorAction SilentlyContinue)"
        $mode = $(if ($first -match 'SIMULACION') { 'Simulacion' } else { 'Real' })
        $when = $d.Name
        try { $when = [datetime]::ParseExact($d.Name, 'yyyy-MM-dd_HH-mm-ss', $null).ToString('dd/MM/yyyy HH:mm') } catch { }
        $out += New-Object psobject -Property @{ Fecha = $when; Modo = $mode; Path = $d.FullName; Log = $log }
    }
    return $out
}

# ----------------------------------------------------------------------------
#  Programas de inicio (mismo mecanismo que el Administrador de tareas:
#  se marca como desactivado en StartupApproved, no se borra nada)
# ----------------------------------------------------------------------------

function Get-StartupSources {
    $run = 'Software\Microsoft\Windows\CurrentVersion\Run'
    $ok = 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved'
    return @(
        @{ Label = 'Usuario';      Kind = 'Reg';    Path = "HKCU:\$run";                    Approved = "HKCU:\$ok\Run" },
        @{ Label = 'Equipo';       Kind = 'Reg';    Path = "HKLM:\$run";                    Approved = "HKLM:\$ok\Run" },
        @{ Label = 'Equipo (32)';  Kind = 'Reg';    Path = 'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\$ok\Run32" },
        @{ Label = 'Carpeta Inicio'; Kind = 'Folder'; Path = [Environment]::GetFolderPath('Startup');       Approved = "HKCU:\$ok\StartupFolder" },
        @{ Label = 'Carpeta Inicio comun'; Kind = 'Folder'; Path = [Environment]::GetFolderPath('CommonStartup'); Approved = "HKLM:\$ok\StartupFolder" }
    )
}

function Test-StartupApproved {
    # Sin valor = activado. Primer byte par = activado, impar = desactivado.
    param([string]$ApprovedKey, [string]$ValueName)
    try {
        $v = (Get-ItemProperty -LiteralPath $ApprovedKey -Name $ValueName -ErrorAction Stop).$ValueName
        if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 0) }
    } catch { }
    return $true
}

function Get-StartupApps {
    $out = @()
    foreach ($src in (Get-StartupSources)) {
        if (-not $src.Path) { continue }
        if ($src.Kind -eq 'Reg') {
            if (-not (Test-Path -LiteralPath $src.Path)) { continue }
            $key = Get-Item -LiteralPath $src.Path -ErrorAction SilentlyContinue
            if (-not $key) { continue }
            foreach ($name in $key.GetValueNames()) {
                if (-not $name) { continue }
                $out += New-Object psobject -Property @{
                    Nombre = $name; Comando = "$($key.GetValue($name))"; Origen = $src.Label
                    ApprovedKey = $src.Approved; ValueName = $name
                    Activo = (Test-StartupApproved $src.Approved $name)
                }
            }
        } else {
            if (-not (Test-Path -LiteralPath $src.Path -PathType Container)) { continue }
            foreach ($f in @(Get-ChildItem -LiteralPath $src.Path -File -ErrorAction SilentlyContinue)) {
                if ($f.Name -ieq 'desktop.ini') { continue }
                $out += New-Object psobject -Property @{
                    Nombre = $f.BaseName; Comando = $f.FullName; Origen = $src.Label
                    ApprovedKey = $src.Approved; ValueName = $f.Name
                    Activo = (Test-StartupApproved $src.Approved $f.Name)
                }
            }
        }
    }
    foreach ($o in $out) { $o | Add-Member -NotePropertyName Estado -NotePropertyValue $(if ($o.Activo) { 'Activado' } else { 'Desactivado' }) }
    return @($out | Sort-Object Nombre)
}

function Set-StartupAppEnabled {
    param([string]$ApprovedKey, [string]$ValueName, [bool]$Enabled)
    if (-not $ApprovedKey -or -not $ValueName) { throw 'Entrada de inicio no valida.' }
    if ($ApprovedKey -notmatch '\\Explorer\\StartupApproved\\(Run|Run32|StartupFolder)$') { throw 'Clave no permitida.' }
    if (-not (Test-Path -LiteralPath $ApprovedKey)) { New-Item -Path $ApprovedKey -Force -ErrorAction Stop | Out-Null }
    $bytes = New-Object byte[] 12
    if ($Enabled) { $bytes[0] = 2 }
    else {
        $bytes[0] = 3
        [Array]::Copy([BitConverter]::GetBytes((Get-Date).ToFileTime()), 0, $bytes, 4, 8)
    }
    New-ItemProperty -LiteralPath $ApprovedKey -Name $ValueName -PropertyType Binary -Value $bytes -Force -ErrorAction Stop | Out-Null
}

# ----------------------------------------------------------------------------
#  Tareas programadas recurrentes (carpeta \MaintenanceTool\ del Programador)
# ----------------------------------------------------------------------------

function Get-FrequencyList {
    return @(
        @{ Key = 'Diaria';       Label = 'Cada dia' },
        @{ Key = 'Semanal';      Label = 'Cada semana' },
        @{ Key = 'Cada2Semanas'; Label = 'Cada 2 semanas' },
        @{ Key = 'Cada4Semanas'; Label = 'Cada 4 semanas' }
    )
}

function New-MaintenanceSchedule {
    param(
        [string]$Name,
        [string]$Frequency = 'Semanal',
        [string]$Day = 'Saturday',
        [string]$Time = '12:00',
        [string[]]$StepKeys
    )
    if ($Name -notmatch '^[A-Za-z0-9 _\-]{1,40}$') { throw 'El nombre solo admite letras, numeros, espacios y guiones (maximo 40).' }
    if ($Time -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { throw 'La hora debe tener el formato HH:mm, por ejemplo 13:30.' }
    if (@(Get-FrequencyList | ForEach-Object { $_.Key }) -notcontains $Frequency) { throw 'Frecuencia no valida.' }
    if (@([Enum]::GetNames([DayOfWeek])) -notcontains $Day) { throw 'Dia no valido.' }
    $valid = @(Get-StepList | ForEach-Object { $_.Key })
    $keys = @(Split-List $StepKeys)
    if ($keys.Count -eq 0) { throw 'Elige al menos un paso.' }
    foreach ($k in $keys) { if ($valid -notcontains $k) { throw ('Paso desconocido: ' + $k) } }

    $engine = Join-Path $PSScriptRoot 'Maintenance.ps1'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arg = '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" -Unattended -Steps {1}' -f $engine, ($keys -join ',')
    $action = New-ScheduledTaskAction -Execute $ps -Argument $arg
    switch ($Frequency) {
        'Diaria'       { $trigger = New-ScheduledTaskTrigger -Daily -At $Time }
        'Semanal'      { $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 1 -DaysOfWeek $Day -At $Time }
        'Cada2Semanas' { $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 2 -DaysOfWeek $Day -At $Time }
        'Cada4Semanas' { $trigger = New-ScheduledTaskTrigger -Weekly -WeeksInterval 4 -DaysOfWeek $Day -At $Time }
    }
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $desc = 'MT|{0}|{1}|{2}|{3}' -f $Frequency, $Day, $Time, ($keys -join ',')
    Register-ScheduledTask -TaskPath $script:TaskPath -TaskName $Name -Description $desc -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null
}

function Get-MaintenanceSchedules {
    $out = @()
    $freq = @{}
    foreach ($f in (Get-FrequencyList)) { $freq[$f.Key] = $f.Label }
    $days = @{ Monday = 'lunes'; Tuesday = 'martes'; Wednesday = 'miercoles'; Thursday = 'jueves'; Friday = 'viernes'; Saturday = 'sabado'; Sunday = 'domingo' }
    foreach ($t in @(Get-ScheduledTask -TaskPath $script:TaskPath -ErrorAction SilentlyContinue)) {
        $p = "$($t.Description)".Split('|')
        $when = ''
        $steps = ''
        if ($p.Count -ge 5 -and $p[0] -eq 'MT') {
            $when = "$($freq[$p[1]])"
            if ($p[1] -ne 'Diaria') { $when += ', ' + $days[$p[2]] }
            $when += ' a las ' + $p[3]
            $steps = $p[4]
        }
        $next = ''
        $last = ''
        try {
            $info = Get-ScheduledTaskInfo -TaskPath $script:TaskPath -TaskName $t.TaskName -ErrorAction Stop
            if ($info.NextRunTime) { $next = $info.NextRunTime.ToString('dd/MM/yyyy HH:mm') }
            if ($info.LastRunTime -and $info.LastRunTime.Year -gt 2000) { $last = $info.LastRunTime.ToString('dd/MM/yyyy HH:mm') }
        } catch { }
        $state = $(if ("$($t.State)" -eq 'Disabled') { 'Pausada' } elseif ("$($t.State)" -eq 'Running') { 'En curso' } else { 'Activa' })
        $out += New-Object psobject -Property @{ Nombre = $t.TaskName; Cuando = $when; Pasos = $steps; Estado = $state; Proxima = $next; Ultima = $last }
    }
    return @($out | Sort-Object Nombre)
}

function Remove-MaintenanceSchedule {
    param([string]$Name)
    Unregister-ScheduledTask -TaskPath $script:TaskPath -TaskName $Name -Confirm:$false -ErrorAction Stop
}

function Set-MaintenanceScheduleEnabled {
    param([string]$Name, [bool]$Enabled)
    if ($Enabled) { Enable-ScheduledTask -TaskPath $script:TaskPath -TaskName $Name -ErrorAction Stop | Out-Null }
    else { Disable-ScheduledTask -TaskPath $script:TaskPath -TaskName $Name -ErrorAction Stop | Out-Null }
}

function Start-MaintenanceSchedule {
    param([string]$Name)
    Start-ScheduledTask -TaskPath $script:TaskPath -TaskName $Name -ErrorAction Stop
}

# ----------------------------------------------------------------------------
#  Programa principal
# ----------------------------------------------------------------------------

function Read-YesNo {
    param([string]$Question, [bool]$Default)
    $hint = $(if ($Default) { '[S/n]' } else { '[s/N]' })
    while ($true) {
        $a = (Read-Host ('  {0} {1}' -f $Question, $hint)).Trim().ToLower()
        if ($a -eq '') { return $Default }
        if ($a -in @('s', 'si', 'y', 'yes')) { return $true }
        if ($a -in @('n', 'no')) { return $false }
    }
}

function Split-List {
    param([string[]]$Values)
    $out = @()
    foreach ($v in $Values) { if ($v) { $out += ($v -split '[,; ]+' | Where-Object { $_ }) } }
    return $out
}

function Wait-Exit {
    param([int]$Code)
    if (-not $Unattended -and -not $NoPause -and -not $script:GuiMode) { Write-Host ''; [void](Read-Host '  Pulsa Enter para salir') }
    exit $Code
}

function Invoke-Main {
    $stepList = Get-StepList
    $selected = @{}
    foreach ($s in $stepList) { $selected[$s.Key] = [bool]$s.Rec }
    $script:Simulate = [bool]$DryRun
    $script:TempDays = $TempDays
    $interactive = -not $Unattended

    if ($InstallTask) { Install-MaintenanceTask; Wait-Exit 0 }
    if ($RemoveTask) { Remove-MaintenanceTask; Wait-Exit 0 }

    $wanted = Split-List $Steps
    $skipped = Split-List $Skip
    $validKeys = @($stepList | ForEach-Object { $_.Key })
    foreach ($k in ($wanted + $skipped)) {
        if ($validKeys -notcontains $k) {
            Write-Host ('  Paso desconocido: {0}. Validos: {1}' -f $k, ($validKeys -join ', '))
            Wait-Exit 2
        }
    }

    Write-Host ''
    Write-Host ' =========================================='
    Write-Host '   Maintenance Tool 4.0'
    Write-Host ' =========================================='
    Write-Host ('   Usuario: ' + $env:USERNAME)

    if ($InvokedBy -and ($InvokedBy -ine $env:USERNAME)) {
        Write-Host ''
        Write-Host ('   ATENCION: lo lanzo "{0}" pero se ejecuta como "{1}".' -f $InvokedBy, $env:USERNAME)
        Write-Host ('   Temporales y cache de navegadores se limpiaran para "{0}".' -f $env:USERNAME)
        if ($interactive -and -not (Read-YesNo 'Continuar de todos modos' $false)) { Wait-Exit 0 }
    }

    if ($DiagnosticOnly) {
        foreach ($k in $validKeys) { $selected[$k] = ($k -in @('Diagnostico', 'Bateria', 'Procesos')) }
    } elseif ($wanted.Count -gt 0) {
        foreach ($k in $validKeys) { $selected[$k] = ($wanted -contains $k) }
    } elseif ($interactive) {
        Write-Host ''
        Write-Host '   Guarda tu trabajo y cierra los navegadores antes de continuar.'
        Write-Host '   NO se borran documentos, descargas, papelera, marcadores,'
        Write-Host '   contrasenas ni extensiones.'
        Write-Host ''
        Write-Host '   [1] Mantenimiento completo recomendado'
        Write-Host '   [2] Personalizado - elegir cada paso'
        Write-Host '   [3] Simulacion - muestra que haria, sin cambiar nada'
        Write-Host '   [4] Solo diagnostico'
        Write-Host '   [5] Programar para que se ejecute solo cada 4 semanas'
        Write-Host '   [6] Quitar la tarea programada'
        Write-Host '   [7] Salir'
        Write-Host ''
        $opt = ''
        while ($opt -notin @('1', '2', '3', '4', '5', '6', '7')) { $opt = (Read-Host '   Elige una opcion [1-7]').Trim() }
        switch ($opt) {
            '2' { Write-Host ''; foreach ($s in $stepList) { $selected[$s.Key] = Read-YesNo $s.Title $s.Rec } }
            '3' { $script:Simulate = $true }
            '4' { foreach ($k in $validKeys) { $selected[$k] = ($k -in @('Diagnostico', 'Bateria', 'Procesos')) } }
            '5' { Install-MaintenanceTask; Wait-Exit 0 }
            '6' { Remove-MaintenanceTask; Wait-Exit 0 }
            '7' { exit 0 }
        }
    }
    foreach ($k in $skipped) { $selected[$k] = $false }

    $needsAdmin = $false
    foreach ($s in $stepList) { if ($selected[$s.Key] -and $s.Changes) { $needsAdmin = $true } }
    if ($needsAdmin -and -not $script:Simulate -and -not (Test-IsAdmin)) {
        Write-Host ''
        Write-Host '  Se necesitan permisos de administrador.'
        Write-Host '  Usa MaintenanceScript.bat, que los pide automaticamente.'
        Wait-Exit 3
    }

    # --- Carpeta de registros ---
    $root = $LogRoot
    if (-not $root) { $root = Get-DefaultLogRoot }
    $script:LogDir = Join-Path $root (Get-Date -Format 'yyyy-MM-dd_HH-mm-ss')
    try { New-Item -ItemType Directory -Path $script:LogDir -Force -ErrorAction Stop | Out-Null }
    catch {
        Write-Host ('  No se pudo crear la carpeta de registros: ' + $script:LogDir)
        Write-Host '  No se hizo ningun cambio.'
        Wait-Exit 4
    }
    $script:MainLog = Join-Path $script:LogDir 'resumen.log'
    $mode = $(if ($script:Simulate) { 'SIMULACION - no se modifica nada' } else { 'REAL' })
    Set-Content -LiteralPath $script:MainLog -Value ('Inicio: {0}   Modo: {1}   Usuario: {2}' -f (Get-Date), $mode, $env:USERNAME)
    Write-Host ('   Registros: ' + $script:LogDir)
    Write-Host ('   Modo: ' + $mode)

    Write-Marker ('PLAN|' + (@($stepList | Where-Object { $selected[$_.Key] } | ForEach-Object { $_.Key }) -join ','))
    $freeBefore = Get-FreeBytes
    $n = 0
    foreach ($s in $stepList) {
        Invoke-Step -Step $s -Number $n -Selected ([bool]$selected[$s.Key])
        $n++
    }
    $freeAfter = Get-FreeBytes

    # --- Resumen ---
    $lines = New-Object System.Collections.ArrayList
    [void]$lines.Add('')
    [void]$lines.Add(' ==========================================')
    [void]$lines.Add('   RESUMEN' + $(if ($script:Simulate) { ' (SIMULACION)' } else { '' }))
    [void]$lines.Add(' ==========================================')
    foreach ($r in $script:Results) {
        [void]$lines.Add(('   {0,-9} {1,-42} {2,5}s  {3}' -f $r.Estado, $r.Paso, $r.Segundos, $r.Detalle))
    }
    [void]$lines.Add('')
    [void]$lines.Add(('   Espacio libre en {0}  antes: {1}   despues: {2}   liberado: {3}' -f $env:SystemDrive,
            (Format-Size $freeBefore), (Format-Size $freeAfter), (Format-Size ([Math]::Max(0, $freeAfter - $freeBefore)))))
    if ($script:Warnings.Count -gt 0) {
        [void]$lines.Add('')
        [void]$lines.Add('   AVISOS:')
        foreach ($w in $script:Warnings) { [void]$lines.Add('    - ' + $w) }
    }
    $errors = @($script:Results | Where-Object { $_.Estado -eq 'Error' }).Count
    [void]$lines.Add('')
    if ($errors -gt 0) { [void]$lines.Add(('   {0} paso(s) con error. Revisa los registros.' -f $errors)) }
    elseif ($selected['Reparar'] -and -not $script:Simulate) { [void]$lines.Add('   Terminado. Se recomienda reiniciar el equipo.') }
    else { [void]$lines.Add('   Terminado.') }
    [void]$lines.Add(('   Registros: ' + $script:LogDir))
    foreach ($l in $lines) { Write-Host $l }
    Add-Content -LiteralPath $script:MainLog -Value $lines -ErrorAction SilentlyContinue

    if ($interactive -and -not $NoPause) {
        try { Start-Process -FilePath 'explorer.exe' -ArgumentList ('"' + $script:LogDir + '"') } catch { }
    }
    Write-Marker ('END|{0}|{1}|{2}|{3}' -f $(if ($errors -gt 0) { 1 } else { 0 }), [long]$freeBefore, [long]$freeAfter, $script:LogDir)
    Wait-Exit $(if ($errors -gt 0) { 1 } else { 0 })
}

# Al cargarse con ". .\Maintenance.ps1" (pruebas) solo se definen las funciones.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-Main
}
