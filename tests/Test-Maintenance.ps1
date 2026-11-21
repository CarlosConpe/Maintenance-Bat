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
