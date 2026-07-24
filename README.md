# amon — Developer OS workspace CLI

`amon` es el CLI del workspace: descubre proyectos desde
`manifests/projects.yaml`, diagnostica runtimes y dependencias, informa puertos y
gestiona los procesos de desarrollo que él mismo inicia. Está escrito en Bash y
no depende de Node ni Python para arrancar.

## `amon` y `amon-agents`

Son dos CLIs distintos:

- `amon` es la capa *porcelain* del Developer OS. Conoce el manifiesto, las rutas,
  los runtimes, los puertos y los procesos del workspace.
- `amon-agents` es el orquestador TypeScript de agentes IA (`run`, `audit`,
  `scan`, `push`) y vive en su propio repositorio.

No se fusionan. `amon` resuelve el proyecto en el manifiesto y delega el trabajo
de IA al proceso externo `amon-agents`; no importa ni copia su código.

## Contrato porcelain/plumbing

| Comando `amon` | Delega a `amon-agents` | Notas |
|---|---|---|
| `amon audit <slug>` | `amon-agents audit --repo <path>` | Auditoría del proyecto resuelto |
| `amon scan <slug>` | `amon-agents scan --repo <path>` | Escaneo del proyecto resuelto |
| `amon agents:status` | `amon-agents status` | Estado global del motor de agentes |
| `amon agents:doctor` | `amon-agents doctor` | Diagnóstico del entorno de agentes IA |

El proyecto plumbing `amon-agents` también se resuelve desde el manifiesto. La
delegación valida su bin declarado, usa su runtime mediante mise y ejecuta
`npm exec --offline -- amon-agents` con un PATH Linux saneado. Esto evita tomar
por accidente un binario homónimo instalado en Windows bajo `/mnt/c`.

Los namespaces son deliberados:

- `amon doctor` diagnostica el workspace, sus runtimes y proyectos.
- `amon agents:doctor` diagnostica proveedores y dependencias de agentes IA.
- `amon status` muestra procesos de desarrollo gestionados por `amon`.
- `amon agents:status` muestra el estado global de `amon-agents`.

## Dependencia YAML

Bash no parsea YAML. La dependencia elegida es `yq` v4, un binario estático
escrito en Go, administrado por mise:

```bash
mise use -g yq
```

Esta decisión no agrega una dependencia de Node o Python. `amon doctor` comprueba
explícitamente que `yq` esté en el `PATH` y falla con una instrucción clara si
falta.

## Instalación en el PATH

El entrypoint es `bin/amon`. Para la sesión actual:

```bash
export PATH="$HOME/amon-dev/_infrastructure/bin:$PATH"
```

Para hacerlo persistente, agrega la misma línea a `~/.bashrc`. Este repositorio
no modifica automáticamente la configuración del shell.

También se puede invocar sin cambiar el `PATH`:

```bash
"$HOME/amon-dev/_infrastructure/bin/amon" help
```

## Manifiesto

Por defecto se usa `<raíz-del-repo>/manifests/projects.yaml`. La variable
`AMON_MANIFEST` permite seleccionar otro archivo:

```bash
AMON_MANIFEST=/ruta/al/projects.yaml amon ls
```

Formato:

```yaml
machine: nombre-del-entorno
root: /ruta/a/los/repos

projects:
  mi-proyecto:
    path: /ruta/a/los/repos/mi-proyecto
    runtime: node@20
    manager: npm
    start: npm run dev
    doctor: npm run lint
    ports: [3000]
    env_required: [DATABASE_URL]
    status: ready
```

Las rutas y los comandos de proyecto salen del manifiesto. `amon` no inventa
comandos. El campo `doctor` queda disponible para evolución del contrato, pero
este ticket ejecuta únicamente los chequeos de workspace definidos para
`amon doctor`.

## Comandos

Listar los proyectos:

```bash
amon ls
```

Diagnosticar el workspace o sumar un proyecto:

```bash
amon doctor
amon doctor bracketflow
```

Preparar un proyecto sin arrancarlo:

```bash
amon open amon-agents
```

Arrancar el comando `start` declarado, desde su ruta y mediante el runtime de
mise; el PID y el log se guardan bajo `~/.amon/`:

```bash
amon start bracketflow
```

Detener uno o todos los procesos gestionados:

```bash
amon stop bracketflow
amon stop --all
```

Inspeccionar conflictos y ocupación de puertos:

```bash
amon ports
```

Ver procesos gestionados que siguen vivos:

```bash
amon status
```

Auditar un proyecto mediante `amon-agents`:

```bash
amon audit bracketflow
```

Escanear un proyecto, independientemente de su runtime:

```bash
amon scan amon_erp
```

Consultar el estado global del motor de agentes:

```bash
amon agents:status
```

Diagnosticar el entorno de agentes IA:

```bash
amon agents:doctor
```

Pausar el entorno de desarrollo para jugar:

```bash
amon gaming
```

`gaming` guarda en `~/.amon/pre-gaming-snapshot.json` los slugs de los proyectos
gestionados que estaban corriendo, libera los modelos cargados por Ollama y
detiene esos procesos. El snapshot siempre se escribe, incluso cuando está vacío.
No toca juegos, Windows ni servicios del sistema.

Restaurar el último estado previo a `gaming`:

```bash
amon dev
```

`dev` vuelve a ejecutar `cmd_start` para cada proyecto del snapshot, incluyendo
sus chequeos de `doctor`. Continúa si alguno falla y muestra un resumen. Si todos
arrancan, mueve el snapshot a `.consumed`, por lo que un segundo `amon dev` no
repite el arranque accidentalmente.

El ciclo completo es:

```text
amon gaming  →  recuerda y pausa
amon dev     →  restaura y consume el snapshot
```

Mostrar ayuda:

```bash
amon help
```

## Estado local y seguridad

- PIDs: `~/.amon/run/<proyecto>.pid`
- Logs: `~/.amon/log/<proyecto>.log`
- Eventos append-only: `~/.amon/events.jsonl`
- Snapshot pre-gaming: `~/.amon/pre-gaming-snapshot.json`
- Las delegaciones registran `agents:<comando>`, slug y resultado en el mismo
  archivo de eventos.
- `AMON_STATE_DIR` permite usar otra ubicación de estado.
- Los chequeos de entorno solo comprueban la existencia de `.env` o `.env.local`.
  No leen ni imprimen su contenido ni valores de credenciales.
- Ollama es informativo en `doctor`: que no esté disponible no bloquea otros
  comandos.
