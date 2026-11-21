## Maintenance Tool 4.0

Aplicación de mantenimiento para agilizar equipos con Windows 10/11. Tiene interfaz gráfica, tareas programadas recurrentes y un modo consola para usuarios avanzados.

No hay que instalar nada: usa Windows PowerShell 5.1 y WPF, que vienen con Windows.

### Archivos

| Archivo | Para qué sirve |
|---------|----------------|
| `MaintenanceApp.bat` | **Abre la aplicación con interfaz gráfica.** Pide permisos de administrador. |
| `MaintenanceScript.bat` | Versión de consola con menú (y línea de comandos). |
| `MaintenanceApp.ps1` | Interfaz gráfica. |
| `Maintenance.ps1` | Motor: toda la lógica de limpieza, diagnóstico, arranque y tareas programadas. |

**Los cuatro archivos deben estar en la misma carpeta.** Descarga el proyecto completo (botón *Code → Download ZIP* en GitHub), descomprímelo y haz doble clic en `MaintenanceApp.bat`.

### Secciones de la aplicación

**Inicio.** Estado del equipo de un vistazo: espacio libre, memoria en uso, días sin reiniciar, salud de los discos, último mantenimiento y próxima tarea programada. Muestra avisos (poco espacio, disco con mala salud, reinicio pendiente) y tiene botones de acción rápida:
- *Limpieza rápida* (2-5 min): temporales antiguos, caché de navegadores y DNS.
- *Mantenimiento completo*: todos los pasos recomendados.
- *Simular*: muestra qué haría, sin cambiar nada.

**Mantenimiento.** Elige los pasos, activa o no la simulación y pulsa *Ejecutar*. Se ve el progreso en vivo, el estado de cada paso, el registro completo y, al final, el espacio liberado y los avisos.

**Arranque de Windows.** Lista de programas que se abren al iniciar sesión, con botones para desactivarlos o volver a activarlos. Usa el mismo interruptor que el Administrador de tareas: no se borra nada.

**Tareas programadas.** Crea mantenimientos recurrentes (diario, semanal, cada 2 o cada 4 semanas, con día y hora) eligiendo qué pasos hacer. Se pueden pausar, reanudar, ejecutar al momento o eliminar. Se guardan en la carpeta `\MaintenanceTool\` del Programador de tareas de Windows y se ejecutan en segundo plano mientras tu sesión está iniciada; si el equipo estaba apagado, se ejecutan en cuanto se pueda.

**Historial.** Todas las ejecuciones (manuales y programadas) con su registro completo.

**Herramientas.** Cambio de plan de energía (Equilibrado / Alto rendimiento) y accesos directos a Administrador de tareas, Monitor de recursos, Liberador de espacio, Optimizar unidades, Sensor de almacenamiento, Windows Update, aplicaciones instaladas, Restaurar sistema, Visor de eventos, Servicios, etc.

### Pasos de mantenimiento

| Paso | Clave | Recomendado | Detalle |
|------|-------|:-----------:|---------|
| Punto de restauración | `Restore` | sí | Se crea antes de tocar nada, si Protección del sistema está activa. |
| Diagnóstico | `Diagnostico` | sí | Espacio, salud de discos, RAM, programas de inicio, errores del sistema de 7 días, reinicio pendiente. Solo lectura. |
| Liberar espacio | `Disco` | sí | `cleanmgr` solo con categorías seguras. No toca Papelera ni Descargas. |
| Reparar Windows | `Reparar` | sí | `DISM /RestoreHealth` y después `sfc /scannow` (30-60 min). |
| Windows Update | `Update` | sí | Lanza la búsqueda de actualizaciones. |
| Microsoft Store | `Store` | no | `wsreset`. |
| Temporales | `Temporales` | sí | Solo archivos con más de N días (7 por defecto) en `%TEMP%` y `C:\Windows\Temp`. |
| Caché de aplicaciones | `Caches` | sí | Chrome, Edge, Brave, Vivaldi, Opera, Opera GX, Firefox y Teams: **solo caché**. Si la aplicación está abierta, se omite. |
| Optimizar unidad | `Optimizar` | sí | `defrag /O`: TRIM en SSD, desfragmentar en HDD. |
| Actualizar programas | `Apps` | no | `winget upgrade --all`. |
| DNS | `Dns` | sí | `ipconfig /flushdns` |
| Batería | `Bateria` | sí | `battery-report.html` |
| Procesos | `Procesos` | sí | `tasklist.txt` |
| Mantenimiento automático | `AutoMant` | no | `MSchedExe Start` |

Los registros se guardan en `Escritorio\Maintenance\<fecha>`.

### Consola y línea de comandos

```bat
MaintenanceScript.bat
MaintenanceScript.bat -DryRun
MaintenanceScript.bat -Unattended -Steps Temporales,Caches,Dns
MaintenanceScript.bat -Unattended -Skip Reparar,Optimizar
MaintenanceScript.bat -DiagnosticOnly
MaintenanceScript.bat -TempDays 14
```

### Qué NO hace (a propósito)

- No borra perfiles de navegador: marcadores, contraseñas, historial y extensiones quedan intactos.
- No borra `*.tmp` por todo el disco ni vacía la carpeta de temporales completa.
- No sigue ni borra enlaces o junctions, y rechaza carpetas protegidas (`C:\`, `C:\Windows`, el perfil de usuario...).
- No cierra programas a la fuerza.
- No desinstala nada ni toca el registro fuera de la configuración del liberador de espacio y del interruptor de arranque.

### Pruebas automáticas

Cada cambio se prueba en Windows con GitHub Actions (`.github/workflows/test.yml`):

- Sintaxis de todos los scripts con Windows PowerShell 5.1.
- Borrado seguro sobre carpetas falsas: solo borra lo antiguo, no sigue enlaces, rechaza carpetas protegidas y conserva marcadores, contraseñas, extensiones e historial.
- Arranque: desactiva y reactiva un programa de prueba sin borrar su entrada.
- Tareas programadas: crea, modifica, pausa, reanuda y elimina una tarea, y rechaza datos no válidos.
- **Interfaz gráfica**: abre la ventana, recorre todas las secciones y ejecuta una simulación real a través de ella.
- Simulación completa y ejecución real de los pasos seguros desde la consola.

Lo que **no** se prueba automáticamente porque necesita un escritorio real o tarda demasiado: `cleanmgr`, `DISM /RestoreHealth` + `sfc`, `wsreset`, `defrag`, `winget`, el punto de restauración, el aviso de administrador (UAC) y que una tarea programada se dispare sola a su hora.

### Por qué la versión 1.x rompía el equipo

- `del C:\*.tmp /s /q /f` borraba archivos `.tmp` de **todo el disco**, incluidos los de programas instalados y en uso.
- La "limpieza de caché" borraba la carpeta `User Data` completa de Chrome (el perfil entero) y todos los `*.sqlite` de Firefox (marcadores, historial, cookies).
- `%DataDir%` se usaba dentro de bloques `if ( ... )`, donde cmd lo expande antes de asignarlo: cada navegador borraba la ruta del navegador **anterior** o una ruta vacía.
- Se vaciaba `%TEMP%` entero con programas e instaladores abiertos.
- `cleanmgr /VERYLOWDISK` limpia todo sin preguntar.
- SFC y DISM corrían sin salida en pantalla durante 30-60 minutos; parecía colgado y cerrarlo a medias deja la reparación incompleta.
