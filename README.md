## MaintenanceBat 3.0

Herramienta de mantenimiento para equipos con Windows 10/11.

`MaintenanceScript.bat` es el lanzador (pide permisos de administrador) y `Maintenance.ps1` contiene la lógica. **Los dos archivos deben estar en la misma carpeta.**

### Uso

1. Descarga el proyecto completo.
2. Guarda tu trabajo y cierra los navegadores.
3. Doble clic en `MaintenanceScript.bat` y acepta el aviso de administrador.
4. Elige una opción del menú:

| Opción | Qué hace |
|--------|----------|
| 1 | Mantenimiento completo recomendado |
| 2 | Personalizado: pregunta paso a paso |
| 3 | **Simulación**: muestra qué haría y cuánto espacio liberaría, sin cambiar nada |
| 4 | Solo diagnóstico (no modifica nada) |
| 5 | Programar la ejecución automática cada 4 semanas |
| 6 | Quitar la tarea programada |

Al terminar se muestra un resumen (estado de cada paso, espacio liberado y avisos) y se abre la carpeta de registros en `Escritorio\Maintenance\<fecha>`.

> La primera vez, usa la opción **3 (Simulación)** para ver qué haría en tu equipo.

### Pasos

| Paso | Clave | Recomendado | Detalle |
|------|-------|:-----------:|---------|
| Punto de restauración | `Restore` | sí | Se crea antes de tocar nada, si Protección del sistema está activa. |
| Diagnóstico | `Diagnostico` | sí | Espacio libre, salud de los discos (SMART), RAM, programas de inicio, errores del sistema de los últimos 7 días, reinicio pendiente. Solo lectura. |
| Liberar espacio | `Disco` | sí | `cleanmgr` solo con categorías seguras. No toca Papelera ni Descargas. |
| Reparar Windows | `Reparar` | sí | `DISM /RestoreHealth` y después `sfc /scannow`, con progreso visible. |
| Windows Update | `Update` | sí | Lanza la búsqueda de actualizaciones. |
| Microsoft Store | `Store` | no | `wsreset`. |
| Temporales | `Temporales` | sí | Solo archivos con más de 7 días en `%TEMP%` y `C:\Windows\Temp`. |
| Caché de aplicaciones | `Caches` | sí | Chrome, Edge, Brave, Vivaldi, Opera, Opera GX, Firefox y Teams: **solo caché**. Si la aplicación está abierta, se omite. |
| Optimizar unidad | `Optimizar` | sí | `defrag /O`: TRIM en SSD, desfragmentar en HDD. |
| Actualizar programas | `Apps` | no | `winget upgrade --all`. |
| DNS | `Dns` | sí | `ipconfig /flushdns` |
| Batería | `Bateria` | sí | `battery-report.html` |
| Procesos | `Procesos` | sí | `tasklist.txt` |
| Mantenimiento automático | `AutoMant` | no | `MSchedExe Start` |

### Línea de comandos

```bat
MaintenanceScript.bat -DryRun
MaintenanceScript.bat -Unattended
MaintenanceScript.bat -Unattended -Steps Temporales,Caches,Dns
MaintenanceScript.bat -Unattended -Skip Reparar,Optimizar
MaintenanceScript.bat -DiagnosticOnly
MaintenanceScript.bat -TempDays 14
MaintenanceScript.bat -InstallTask
MaintenanceScript.bat -RemoveTask
```

- `-Unattended`: sin preguntas ni pausas, con los pasos recomendados.
- `-Steps` / `-Skip`: lista de claves de la tabla anterior.
- `-InstallTask`: crea la tarea `MaintenanceTool` (sábados 12:00, cada 4 semanas). Si mueves la carpeta, vuelve a crearla.

### Qué NO hace (a propósito)

- No borra perfiles de navegador: marcadores, contraseñas, historial y extensiones quedan intactos.
- No borra `*.tmp` por todo el disco.
- No vacía la carpeta de temporales completa mientras hay programas usándola.
- No sigue ni borra enlaces o junctions.
- No cierra programas a la fuerza.

### Pruebas

Cada cambio se prueba automáticamente en Windows con GitHub Actions (`.github/workflows/test.yml`): sintaxis, pruebas del borrado seguro sobre carpetas falsas (`tests\Test-Maintenance.ps1`), una simulación completa y una ejecución real de los pasos seguros.

Lo que **no** se prueba automáticamente porque necesita un escritorio real o tarda demasiado: `cleanmgr`, `DISM /RestoreHealth` + `sfc`, `wsreset`, `defrag`, `winget`, el punto de restauración, la tarea programada y el aviso de elevación (UAC).

### Por qué la versión 1.x rompía el equipo

- `del C:\*.tmp /s /q /f` borraba archivos `.tmp` de **todo el disco**, incluidos los de programas instalados y en uso.
- La "limpieza de caché" borraba la carpeta `User Data` completa de Chrome (el perfil entero) y todos los `*.sqlite` de Firefox (marcadores, historial, cookies).
- `%DataDir%` se usaba dentro de bloques `if ( ... )`, donde cmd lo expande antes de asignarlo: cada navegador borraba la ruta del navegador **anterior** o una ruta vacía.
- Se vaciaba `%TEMP%` entero con programas e instaladores abiertos.
- `cleanmgr /VERYLOWDISK` limpia todo sin preguntar.
- SFC y DISM corrían sin salida en pantalla durante 30-60 minutos; parecía colgado y cerrarlo a medias deja la reparación incompleta.
- `>null` en vez de `>nul`, rutas sin comillas, fecha tecleada a mano sin validar y una fecha fija (`19-12-2021`) en el informe de batería.
