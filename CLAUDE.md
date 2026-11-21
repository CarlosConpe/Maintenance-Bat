# Maintenance-Bat

Script `.bat` de mantenimiento para Windows (`MaintenanceScript.bat`). No hay build ni tests: solo se puede probar ejecutándolo en una PC con Windows, así que cualquier cambio debe decirse como "no probado" hasta que el usuario lo corra.

## Panel de Proyectos

El estado de este proyecto (siguiente paso, tareas, plan, flujo, archivos) vive en un artifact con base de datos:

https://claude.ai/artifact/UjrvkjbZGP5vK9TnGDuvMx

Se lee y escribe con la herramienta `ArtifactData` usando esa URL. No republicar la página para cambiar datos.

- **Al empezar una sesión:** leer `projects/maintenance-bat` y las tareas con `proyecto == "maintenance-bat"` en la colección `tasks`. Si el usuario pregunta "¿qué sigue?", responder desde ahí.
- **Al terminar un trabajo:** mover las tareas tocadas (`estado`: `pendiente` | `en_curso` | `hecho`), crear las nuevas que hayan salido, y actualizar `siguiente`, `plan`, `diagrama`, `archivos` y `notas` del proyecto si cambiaron.

Campos de una tarea: `proyecto`, `titulo`, `detalle`, `estado`, `prioridad` (`alta` | `media` | `baja`), `orden`, y `origen: "claude"` cuando la propone Claude y no el usuario.

El usuario prefiere respuestas en español y una vista visual antes que archivos de texto o herramientas de terminal.
