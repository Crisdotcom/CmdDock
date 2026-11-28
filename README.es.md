# CmdDock

<p align="center">
  <img src="docs/demo/cmddock-demo.gif" alt="Demo de CmdDock: pulsa ⌥⌘K, busca un comando y ejecútalo en tu terminal" width="800">
</p>

**Un lanzador tipo Spotlight para los comandos de terminal que usas a diario.** Pulsa un atajo, elige un comando y CmdDock lo ejecuta en tu terminal —Warp, Terminal, iTerm2 o Ghostty— en una pestaña nueva, una ventana nueva o la actual. Se acabó copiar comandos desde una nota.

## Funciones

- **Atajo global** (por defecto `⌥⌘K`, personalizable) que abre un panel flotante con búsqueda y navegación por teclado.
- **Ejecuta en la terminal que elijas**, en nueva pestaña, nueva ventana o la actual. Se puede sobrescribir por comando y fijar una carpeta de trabajo.
- **Variables**: escribe `ssh {{usuario:root}}@{{host}}` y CmdDock te pide los valores antes de ejecutar o copiar (con valores por defecto y recordando los últimos usados).
- **Grupos en pestañas**, reordenar arrastrando el asa ⠿ y soltar una fila sobre una pestaña para cambiarla de grupo.
- **Clics configurables**: un clic copia, doble clic ejecuta (o editar / nada).
- **Análisis del historial (sin IA)**: al abrirlo por primera vez ofrece analizar tu historial de Warp, zsh, bash y fish y proponerte grupos. Se puede omitir y todo es local.
- **Fijar el panel**, **importar** una lista pegada desde Notas, abrir al iniciar sesión.
- **CLI**: `cmddock scan`, `cmddock scan --apply`, `cmddock --version`.

## Instalación

```bash
brew tap crisdotcom/tap
brew trust --cask crisdotcom/tap/cmddock   # Homebrew 7+ pide confiar en casks de terceros
brew install --cask crisdotcom/tap/cmddock
```

CmdDock se abre al terminar la instalación y te pregunta si quieres analizar tu historial (puedes omitirlo). Puedes hacerlo más tarde desde **Ajustes → Analizar historial**, el icono de la barra de menú o con:

```bash
cmddock scan          # muestra la propuesta sin cambiar nada
cmddock scan --apply  # la añade a CmdDock (pide confirmación)
```

Desde el código: `git clone https://github.com/Crisdotcom/CmdDock.git && cd CmdDock && ./build.sh install` (macOS 14+, Xcode 15+).

## Variables

Usa `{{nombre}}` o `{{nombre:valor por defecto}}` en cualquier parte del comando:

```bash
gcloud compute ssh {{vm}} -- -N -L {{puerto:8080}}:localhost:{{puerto}}
```

<p align="center">
  <img src="docs/demo/cmddock-variables.gif" alt="Completando las variables {{user}} y {{host}} de un comando ssh antes de que CmdDock lo ejecute" width="800">
</p>

Al ejecutarlo o copiarlo aparece un formulario con un campo por variable (si se repite, se pide una vez), una vista previa en vivo y los últimos valores que usaste. Los valores se insertan tal cual: si necesitas comillas, ponlas en el comando (`git commit -m "{{mensaje}}"`).

## Permisos

- **Accesibilidad**: Warp y Ghostty no tienen API de scripting, así que CmdDock abre la pestaña con `⌘T` y pega el comando.
- **Automatización**: para Terminal, iTerm2 y System Events. macOS lo pide la primera vez.

Las versiones están firmadas ad-hoc (sin notarizar), así que tras actualizar puede que macOS pida de nuevo el permiso de Accesibilidad.

## Contribuir

Los PR son bienvenidos: mira [CONTRIBUTING.md](CONTRIBUTING.md).

## Licencia

[MIT](LICENSE)
