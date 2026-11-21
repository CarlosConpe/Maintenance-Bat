## MaintenanceBat 2.0

Script `.bat` para dar mantenimiento a un equipo con Windows 10/11.

### Uso

1. Guarda tu trabajo y cierra los navegadores.
2. Doble clic en `MaintenanceScript.bat` y acepta el aviso de administrador.
3. Elige **[1] Completo recomendado** o **[2] Personalizado**.
4. Al terminar se abre la carpeta de registros en `Escritorio\Maintenance\<fecha>`.

### Qué hace

| # | Paso | Detalle |
|---|------|---------|
| 0 | Punto de restauración | Se crea antes de tocar nada (si Protección del sistema está activa). |
| 1 | Liberar espacio | `cleanmgr` solo con categorías seguras. No toca Papelera ni Descargas. |
| 2 | Reparar Windows | `DISM /RestoreHealth` y después `sfc /scannow`, con progreso visible. |
| 3 | Windows Update | Lanza la búsqueda de actualizaciones. |
| 4 | Microsoft Store | `wsreset` (solo en modo personalizado). |
| 5 | Temporales | Solo archivos con más de 7 días en `%TEMP%` y `C:\Windows\Temp`. |
| 6 | Caché de navegadores | Chrome, Edge y Firefox: **solo caché**. Si el navegador está abierto, se omite. |
| 7 | DNS | `ipconfig /flushdns` |
| 8 | Batería | `battery-report.html` en la carpeta de registros. |
| 9 | Procesos | `tasklist.txt` |
| 10 | Mantenimiento automático | `MSchedExe Start` (solo en modo personalizado). |

### Qué NO hace (a propósito)

- No borra perfiles de navegador: marcadores, contraseñas, historial y extensiones quedan intactos.
- No borra `*.tmp` por todo el disco.
- No vacía la carpeta de temporales completa mientras hay programas usándola.
- No cierra programas a la fuerza.

### Por qué la versión 1.x rompía el equipo

- `del C:\*.tmp /s /q /f` borraba archivos `.tmp` de **todo el disco**, incluidos los de programas instalados y en uso.
- La "limpieza de caché" borraba la carpeta `User Data` completa de Chrome (el perfil entero) y todos los `*.sqlite` de Firefox (marcadores, historial, cookies).
- `%DataDir%` se usaba dentro de bloques `if ( ... )`, donde cmd lo expande antes de asignarlo: cada navegador borraba la ruta del navegador **anterior** o una ruta vacía.
- Se vaciaba `%TEMP%` entero con programas e instaladores abiertos.
- `cleanmgr /VERYLOWDISK` limpia todo sin preguntar.
- SFC y DISM corrían sin salida en pantalla durante 30-60 minutos; parecía colgado y cerrarlo a medias deja la reparación incompleta.
- `>null` en vez de `>nul`, rutas sin comillas, fecha tecleada a mano sin validar y una fecha fija (`19-12-2021`) en el informe de batería.
