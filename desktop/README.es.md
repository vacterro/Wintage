# Wintage para aplicaciones de escritorio

El userscript tematiza la web. Esto tematiza los programas que la rodean, con las mismas paletas, para que el navegador y las apps dejen de discutir sobre qué significa "dark golden".

Hay una regla detrás de cada decisión: **las aplicaciones se actualizan solas, y una actualización no debe romper nada en silencio.** Donde un objetivo tiene un lugar en tu propio perfil, el tema va allí y sobrevive a las actualizaciones. Donde no lo tiene, el instalador está pensado para re-ejecutarse — y lo dice, en lugar de fingir que persistió.

## La GUI

Haz doble clic en **`Wintage Installer.vbs`** en la raíz del repositorio para abrirla sin ventana de consola, o ejecuta esto directamente para diagnósticos:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Lista de temas con chips de color, los objetivos encontrados en esta máquina, una vista previa Win95 en vivo, y los veintiún tokens de color como muestras editables. Editar cualquier muestra bifurca la paleta en **Custom** en lugar de cambiar un tema distribuido por debajo de ti. El panel de la derecha muestra en vivo el contraste WCAG de los tres tokens que llevan texto — una paleta que FAIL ahí la rechaza igualmente el build gate, así que es mejor verlo antes de Apply que después.

Los objetivos se dividen en dos listas accesibles por teclado: **MY APPS** contiene las herramientas portátiles/árbol-fuente CodeNomad, WorkBuddy; **POPULAR APPS** contiene Windows, OBS, terminales, editores y el otro software instalado. ALL/NONE y Apply/Revert operan sobre ambas listas sin cambiar su agrupación.

La ventana lleva la paleta que está a punto de instalar. Es la vista previa más rápida disponible, y mantiene la herramienta honesta: una paleta que vuelve ilegible esta ventana es visiblemente ilegible.

Apply delega en `install.ps1`. Hay exactamente una ruta de código que instala un tema, así que la GUI no puede alejarse de la línea de comandos.

## La línea de comandos

```powershell
.\desktop\install.ps1                                  # qué hay, qué está temado, con qué paleta
.\desktop\install.ps1 -Target freebuff -Palette klite  # una app, una paleta
.\desktop\install.ps1 -Target all -Palette goldendefault # todo
.\desktop\install.ps1 -Target all -WhatIf              # decir qué cambiaría, no tocar nada
.\desktop\install.ps1 -Target freebuff -Revert         # deshacer una
```

`-Palette` por defecto es `goldendefault` (**Golden Default**). La GUI se abre con la misma paleta y comprueba cada objetivo disponible. Repintar una app ya temada funciona mientras se ejecuta; una primera instalación no, porque el archivo está en uso.

## Cuánto puede tematizarse cada objetivo

| objetivo | mecanismo | sobrevive a una actualización de la app |
|---|---|---|
| `windows` | `.theme` de usuario: modo sistema/app oscuro, roles de color de acento y clásicos | sí — instalado en tu carpeta local de temas de Windows |
| `browsers` | detecta perfiles Chromium instalados + portátiles, prepara el tema chrome elegido y abre las páginas de confirmación propias de Tampermonkey/tema del navegador | sí — tras un **Load unpacked** por perfil |
| `terminal` | esquema de Windows Terminal + valores por defecto de todos los perfiles, Consolas 12 con alias | sí — los ajustes están en tu perfil |
| `conhost` | valores por defecto de `HKCU\Console` + cada perfil cmd/PowerShell existente | sí — instantánea exacta de los valores tocados |
| `obs` | variante OBS 30.2+ `.ovt` + ID de tema activo en `user.ini` | sí — vive en tu perfil |
| `qbittorrent` | tema de interfaz Qt desempaquetado (`config.json` + `stylesheet.qss`) + las dos claves de tema en `qBittorrent.ini` | sí — vive en tu perfil |
| `antigravity`, `vscode` | extensión de tema de color en `~/.antigravity/extensions` / `~/.vscode/extensions` | **sí** — vive en tu perfil |
| `freebuff`, `antigravity-app`, `codenomad` | shim de Electron, ver abajo | no — re-ejecuta el instalador |
| `claude` | shim de Electron, parcheado en el lugar — ver abajo | no — una actualización crea una carpeta `app-<version>` nueva |
| `mpchc` | registro, solo tema oscuro + tipografía OSD | no — MPC-HC reescribe sus ajustes al salir |
| `obsidian` | tema de comunidad por vault, todas las paletas instaladas a la vez | **sí** — vive en tu vault |
| `discord` | CSS depositado en la propia carpeta de temas de BetterDiscord | sí |
| `totalcmd`, `totalcmd2` | claves `[Colors]` de `wincmd.ini`; los filtros de archivos recientes existentes usan el color de enlace de la paleta | sí — es tu ini |

### Eliminación de anuncios de FreeBuff

FreeBuff (la app de escritorio del asistente de IA) trae su propia red publicitaria: el bundle del renderer (`resources/orchestrator/ui/assets/index-*.js`) renderiza una tarjeta `sponsored-ad` y un banner de hilo, y el orquestador (`resources/orchestrator/orchestrator.js`) expone rutas `/api/ad/slot|impression|click` que llaman a la subasta de anuncios remota. El shim solo tematiza la app; no toca esos archivos.

`desktop/patch-freebuff-ads.js` corta los anuncios a nivel de byte:

- renderer: los puntos de llamada de la tarjeta/banner publicitario se convierten en `null`, y los métodos cliente de API `adSlot` / `adImpression` / `adClick` se vuelven no-ops — nada se renderiza, y ninguna petición `/api/ad/*` sale jamás del renderer;
- orquestador: las tres rutas `/api/ad/*` dejan de llamar a la red publicitaria, y la petición de anuncio en línea de un turno en vivo (`maybeRequestAd`) se cortocircuita.

El nombre del bundle lleva un hash de build, así que el parche descubre el bundle actual desde `index.html` en lugar de enviar un payload bloqueado por versión — eso es lo que hace que sobreviva a las actualizaciones. Los originales se respaldan en `_orig-backup-<timestamp>/` en el directorio de instalación; `--revert` restaura el más reciente.

**Las versiones futuras se manejan en dos capas independientes:**

1. **Parche de bytes con fallbacks de regex.** Cada objetivo tiene una cadena exacta para el build actual *y* un fallback de expresión regular anclado en lo que un minificador no puede renombrar — los literales de ruta `/api/ad/*`, el discriminador de protocolo `case"ad":`, la clase `sponsored-ad`, y las ubicaciones `variant:"banner"` / `variant:"card"`. El orquestador no está minificado (nombres legibles como `maybeRequestAd` y `app.ads.slotAd`), así que sus cadenas exactas aguantan mucho tiempo; el bundle del renderer está minificado, así que sus fallbacks de regex toman el control en el momento en que el siguiente build renombre sus identificadores.
2. **Bloqueo a nivel de shim (`targets/electron/shim.cjs`).** Totalmente independiente del bundle: cualquier fetch/XHR a una URL `/api/ad/` se rechaza dentro de la página, y cualquier elemento cuya clase contenga `sponsored-ad` se oculta en el momento en que aparece. Ni siquiera un bundle flamante que este script aún no ha aprendido puede sacar un anuncio.

```powershell
node .\desktop\patch-freebuff-ads.js           # parchear (respaldar primero)
node .\desktop\patch-freebuff-ads.js --sound "C:\...\my.mp3"   # parchear + sonido de finalización personalizado (wav/mp3/ogg/flac/m4a/aac)
node .\desktop\patch-freebuff-ads.js --scan    # ¿qué marcadores de anuncio lleva ESTE build?
node .\desktop\patch-freebuff-ads.js --verify
node .\desktop\patch-freebuff-ads.js --revert
```

Se ejecuta automáticamente como parte de `install.ps1 -Target freebuff`, y debe re-ejecutarse tras cada actualización de FreeBuff (las actualizaciones restauran los archivos originales). Si un build cambia de forma, el script nombra el objetivo que ya no coincidió — ejecuta `--scan` para ver qué sigue llevando el nuevo build y refresca las cadenas allí.

**Sonido de finalización de FreeBuff.** El renderer reproduce `chime-<hash>.mp3` cuando termina un turno. El parche lo encuentra igual que encuentra el bundle (el nombre lleva un hash de build), así que `--sound <file>` instala tu propio audio (wav/mp3/ogg/flac/m4a/aac) encima y guarda el archivo original como `chime-*.mp3.bak`; `--revert` lo restaura. `--verify` informa cuál está activo.

### Botón de sonido de FreeBuff (GUI)

`WintageInstaller.ps1` tiene un pequeño botón **FB SOUND** debajo de la pila APPLY / REVERT. Solo almacena una *preferencia*; `install.ps1 -Target freebuff` lee el mismo archivo y se lo pasa al parche como `--sound`, así que los anuncios y el sonido se aplican en una sola pasada:

- **Clic izquierdo** — elegir un archivo de audio (OpenFileDialog, wav/mp3/ogg/flac/m4a/aac) y oírlo reproducido de inmediato: PCM WAV mediante System.Media.SoundPlayer, cualquier otro formato mediante un MediaPlayer de WPF (Media Foundation, asíncrono, así la ventana nunca se congela). La elección se recuerda en `%APPDATA%\Wintage\freebuff-sound.txt` (por máquina, fuera del checkout de git, igual que las carpetas recordadas del árbol fuente).
- **Clic derecho** — limpiar la preferencia y volver al chime original de FreeBuff (también detiene cualquier vista previa que siga sonando).
- **COPY** — copia el audio elegido al propio repositorio (`sounds\freebuff.<ext>`, conservando la extensión de origen) y reapunta la preferencia a esa copia, así el sonido sobrevive a que el archivo original se borre o se mueva. Habilitado solo mientras hay un sonido personalizado configurado; volver a copiar simplemente sobrescribe la copia del repo. La carpeta `sounds/` es contenido normal rastreable por git, así que commitearlo hace que el sonido sobreviva también a los re-clones.

Solo se previsualizan contenedores de audio reconocidos — primero se olfatea la cabecera, así que una selección no-audio se anuncia en lugar de reproducir silenciosamente nada.

El botón muestra `ON` mientras hay un sonido personalizado configurado; al pasar el cursor muestra la ruta. Aplica después el objetivo `freebuff` (marca FreeBuff + APPLY, o ejecuta `install.ps1 -Target freebuff` desde un terminal) para que surta efecto.

### Terminales

`terminal` escribe un esquema de colores `Wintage` en cada archivo de ajustes de Windows Terminal estable, Preview o sin empaquetar detectado y lo selecciona mediante `profiles.defaults`, junto con Consolas 12 seguro para consola y texto con alias. El archivo original se conserva byte por byte junto a él y `-Revert` lo restaura.

`conhost` cubre el clásico `cmd.exe`, Windows PowerShell, los perfiles de consola de Git CMD/Bash y otros hijos `HKCU\Console` existentes. Escribe la tabla completa de 16 colores de la paleta tanto en los valores por defecto raíz como en cada override existente, y luego restaura solo los valores que tocó. Aplica Consolas también allí, porque la Verdana proporcional choca dentro de la cuadrícula de celdas de ancho fijo que usan ambos hosts de terminal.

### Navegadores y Tampermonkey

`browsers` encuentra perfiles de Chrome, Edge, Brave, Cent, Vivaldi y Opera desde ubicaciones instaladas y desde la raíz portátil a la que apuntes (`-PortableRoot`, o la entrada `portable` recordada en `paths.json`). Su estado muestra tanto el número de perfiles como cuántos contienen Tampermonkey. Apply copia el tema de chrome elegido a la carpeta estable `%LOCALAPPDATA%\Wintage\browser-theme`, pone esa ruta en el portapapeles, y abre cada perfil exacto en `chrome://extensions` más la página de Instalación/Actualización del userscript de Wintage. Los perfiles sin Tampermonkey reciben también su página de Chrome Web Store.

Chromium prohíbe deliberadamente la instalación silenciosa de extensiones fuera de la tienda en una máquina Windows no administrada. La primera instalación del tema de navegador requiere por tanto una confirmación de **Developer mode → Load unpacked** por perfil. Elige la ruta copiada; después, Wintage sigue reemplazando la misma carpeta estable cuando cambian las paletas. Confirma también **Install/Update** en Tampermonkey. Ningún `Preferences` del navegador, Secure Preferences ni archivo LevelDB de Tampermonkey se edita a espaldas del navegador. Si Tampermonkey no estaba presente, instálalo desde la pestaña de la tienda abierta y refresca la pestaña ya abierta de `wintage.user.js` para obtener la pantalla de instalación.

### Windows

`windows` instala y activa inmediatamente un `%LOCALAPPDATA%\Microsoft\Windows\Themes\Wintage-<hash>.theme` direccionado por contenido. Parte del tema activo y reemplaza solo las secciones documentadas de color, cursor y estilo visual. Fondo de pantalla, sonidos e iconos del escritorio permanecen sin cambios; los cursores cambian intencionadamente al esquema `___CURRENT___` instalado. El primer tema activo se guarda byte por byte como `Wintage.original.theme`; los cambios de paleta conservan esa línea base, y `-Revert` la reactiva. Los controles modernos de Windows siguen viniendo del estilo visual Aero firmado — Wintage cambia sus entradas admitidas de modo oscuro, acento y colores de sistema clásicos en lugar de reemplazar archivos `.msstyles` protegidos. Las leyendas activas e inactivas comparten el color de superficie elevada atenuado de la paleta; el resaltado brillante queda reservado para los bordes de texto/selección. El acento anterior de leyenda inactiva se captura por separado y `-Revert` lo restaura exactamente. El hash de contenido da a Windows un nuevo objetivo de asociación de archivo cuando se reconstruye la misma paleta, así que re-aplicar una paleta actualizada no se confunde con un no-op; el archivo de Wintage sustituido se elimina después de que Windows confirme el nuevo como activo.

### OBS Studio

`obs` genera una variante OBS 30.2+ sobre la base mantenida de Yami Classic, la instala en `%APPDATA%\obs-studio\themes`, y escribe su ID de tema estable en `user.ini`, así la paleta de Wintage elegida ya está seleccionada en el siguiente arranque. Cierra OBS antes de Apply o Revert: OBS reescribe `user.ini` al salir. El primer apply respalda tanto la selección anterior como cualquier tema homónimo byte por byte.

### qBittorrent

`qbittorrent` escribe un tema de interfaz Qt **desempaquetado** en `%APPDATA%\qBittorrent\themes\wintage` — un `config.json` (los roles `Palette.*` más los colores de contexto propios de qBittorrent: estados de la lista de transferencias, gravedades del registro) y un `stylesheet.qss` junto a él (los biseles de 2px, las esquinas rectas y Verdana, que una paleta no puede expresar) — y luego apunta `General\CustomUIThemePath` a ese `config.json` y establece `General\UseCustomUITheme=true`.
Desempaquetado en lugar de un paquete `.qbtheme`, a propósito: un `.qbtheme` es un archivo Qt Resource Collection y necesitaría un binario `rcc` de versión mayor coincidente en la máquina para producirlo, es decir, una dependencia de compilador para dos archivos de texto. qBittorrent lee la forma de carpeta de forma nativa (`FolderThemeSource`).
Cierra qBittorrent antes de Apply o Revert: reescribe todo `qBittorrent.ini` al salir, así que una edición hecha mientras se ejecuta se descarta al cerrar — el objetivo se niega a ejecutarse en ese estado en lugar de informar de un éxito que el siguiente cierre borra. `-Revert` devuelve las dos claves del INI a sus valores exactos anteriores a Wintage (o las elimina si no estaban) y repone cualquier carpeta de tema con el mismo nombre byte a byte; las ediciones no relacionadas de `qBittorrent.ini` hechas después de Apply sobreviven.
No alcanzable: los iconos de la barra de herramientas y de la bandeja proceden del propio paquete de recursos compilado de qBittorrent, así que conservan sus colores originales.

### Tipografías: con nombre, nunca instaladas

La ley 1 de UI.md pide Verdana **sin suavizado**. Una hoja de estilo Qt no tiene ninguna propiedad para eso, y el `OSDFont` de MPC-HC es un simple nombre de fuente GDI — así que la única palanca es la propia tipografía. El `Verdana_m1.ttf` en la raíz del repositorio es una copia de Verdana con trazos de mapa de bits de 1 bpp prerenderizados de 3 a 30 ppem, que el renderizador prefiere antes que suavizar el contorno.
Las hojas de estilo de `qbittorrent` y `obs` nombran `Verdana_m1, Verdana`, y `mpchc` nombra la que la máquina resuelve de verdad. **El instalador nunca instala ni desinstala una tipografía**, y eso es deliberado, no incompleto:
Una familia tipográfica se resuelve por (familia, estilo). Registra Regular + Bold + Italic y todos los consumidores se resolverán correctamente; si das de baja **un** miembro, todos los consumidores que piden esa familia se reapuntan a un miembro superviviente. En una máquina que asigna `MS Shell Dlg 2` —la tipografía de diálogos de Windows— a esa familia mediante `HKLM\...\FontSubstitutes`, quitar Regular pone **todo el escritorio en cursiva**, incluidos los títulos de ventana que el DWM ya tenía en caché, y hace falta cerrar sesión para recuperarlo. Ninguna cantidad de recuento de referencias lo arregla: el radio de impacto es de toda la máquina y un instalador de temas no tiene nada que hacer ahí.
Así que la tipografía es una acción única y explícita del usuario: clic derecho en `Verdana_m1.ttf` → **Instalar** (por usuario, sin necesidad de administrador) y luego vuelve a aplicar el objetivo. Si la tipografía falta, los objetivos lo dicen una vez, nombran la solución y recurren a la Verdana original: con suavizado, pero sin hacer nada a tu máquina a tus espaldas.

### Apps de Electron

`resources/app.asar` se mueve a `resources/app/app.asar` (su hermano `app.asar.unpacked` se mueve con él — ese emparejamiento es por nombre de archivo, y separarlo rompe cada módulo nativo), y un pequeño `shim.cjs` toma el slot `resources/app` desocupado. El shim inyecta la hoja de estilo y luego carga el archivo original. **Ningún byte de la aplicación se reescribe**, solo se reubica; `-Revert` lo mueve directamente de vuelta.

La hoja de estilo no se escribe para estas apps — se extrae de `wintage.user.js`, así que cada corrección de bisel, scrollbar y escala tipográfica hecha para el navegador aterriza también aquí, sin una segunda copia que se pudra.

Dos notas que vale la pena saber de antemano:

- El enfoque obvio — soltar `resources/app` junto al archivo y confiar en que Electron lo prefiera — **no funciona y falla en silencio**. Electron busca `app.asar` primero. La app arranca perfectamente y el tema nunca corre.
- El shim es `.cjs`, no `.js`, a propósito. Su `package.json` se copia del de la propia app para que la app conserve su nombre y versión (el nombre decide dónde vive userData — un shim que lo renombra mueve la app a un perfil vacío). Si ese manifiesto dice `"type": "module"`, un shim `.js` muere en su primer `require`.

### La app de escritorio de Claude: en el lugar, y el marco donde realmente dibuja

Claude no puede usar la reubicación de arriba, porque `OnlyLoadAppFromAsar` está fundido: Electron carga `resources/app.asar` y nada más, así que un shim en `resources/app` nunca puede ejecutarse. En su lugar se parchea **en el lugar**: el archivo se respalda, su `main` de `package.json` se reescribe a `"../wintage-shim.cjs"` (rellenado a la misma longitud de bytes, para que cada offset del archivo siga siendo válido), y el hash de integridad por archivo se actualiza para que coincida. `-Revert` restaura el respaldo.

El instalador lee los fuses **antes de mover cualquier cosa** y se niega con un motivo cuando lo bloquean — `EnableEmbeddedAsarIntegrityValidation` haría que la reescritura de arriba fallara al arrancar en lugar de al instalar. Comprueba cualquier app tú mismo:

```powershell
node ..\tools\electron-fuses.js "<path to the app's exe>"
```

La segunda mitad fue un problema mucho más silencioso. El `BrowserWindow` de Claude renderiza una carcasa delgada y **toda la aplicación visible es una `WebContentsView`** adjunta a él. El shim solía enganchar `browser-window-created`, así que inyectaba la hoja de estilo en la carcasa, informaba éxito a `wintage-status.txt`, y no cambiaba nada que pudieras ver. Ahora engancha `web-contents-created`, que cubre contenidos de ventana, `WebContentsView`, `BrowserView`, invitados `<webview>` y popups por igual.

### Obsidian

Se escribe un tema de comunidad en el `.obsidian/themes/` de cada vault — las dieciséis paletas a la vez, exactamente como el objetivo de VS Code, así que cambias entre ellas en **Settings → Appearance** sin re-ejecutar nada. La plantilla se derivó del tema hecho a mano `VintageWin95` ya presente en el vault, cada color reemplazado por el token al que equivalía. `-Palette <slug>` fija cuál está activa en la instalación; `appearance.json` se respalda primero, y `-Revert` elimina solo los temas `Wintage *` y restaura tu elección anterior — un tema hecho a mano en el mismo vault nunca se toca.


### MPC-HC (K-Lite)

Win32 nativo, sin hoja de estilo ni punto de inyección, y los colores de su tema oscuro están compilados en el programa — ningún valor de registro los expone. Así que este objetivo **no puede llevar una paleta**. Lo que hace: activa el tema oscuro y aplica las reglas de tipografía de UI.md al OSD, que es la única superficie que MPC-HC deja controlar al usuario. Los ajustes anteriores se exportan primero a `desktop/backup/mpc-hc-settings.reg`.

Cierra MPC-HC antes de aplicar: reescribe sus ajustes al salir.

## Reconstrucción

Todo lo que hay bajo `desktop/out/` se genera a partir de `themes/*.json`. No está en git (T-160), así que un clon fresco debe construir una vez antes de instalar:

```powershell
node ..\tools\build-desktop.js          # reconstruir todos los objetivos
node ..\tools\build-desktop.js --check  # exit 1 si algo está obsoleto
```

`release.ps1` ejecuta el build y cada compuerta, así que una release no puede enviar una salida que se haya alejado de las paletas.

<!-- T-311 target/section coverage supplement -->
## Cobertura de objetivos y secciones (T-311)

Esta sección refleja la cobertura de Process Explorer, Notepad++, Cinema 4D y las
fuentes de terminal del README actual en inglés, para que esta versión en tu idioma
no se quede obsoleta en silencio. Los literales de código (ids de objetivo, rutas de
registro, nombres de archivo) no se traducen por diseño; el texto que los rodea ya
está escrito en este idioma.

### Qué se puede tematizar de verdad en cada objetivo (objetivos añadidos)

| objetivo | mecanismo | sobrevive a una actualización de la app |
|---|---|---|
| `notepadplusplus` | XML de tema + alias en la carpeta `themes` de Notepad++ del usuario | sí — vive en tu perfil |
| `cinema4d` | esquema de color depositado en la carpeta `schemes` de Cinema 4D del usuario | sí — vive en tu perfil |
| `processexplorer` | `HKCU\Software\Sysinternals\Process Explorer`: colores de resaltado de fila y fondos de gráfico, ver abajo | no — Process Explorer reescribe sus ajustes al salir; ciérralo y vuelve a ejecutar |

### Process Explorer (Sysinternals)

Process Explorer guarda sus colores en `HKCU\Software\Sysinternals\Process Explorer`
y reescribe esa clave al salir, así que el objetivo **se niega mientras `procexp`,
`procexp64` o `procexp64a` esté en marcha** — ciérralo y ejecútalo otra vez. Tematiza
estas categorías de color configurables:

- **alcanzable**: los colores de resaltado de fila del proceso (`ColorOwn`,
  `ColorServices`, `ColorRelocatedDlls`, `ColorImmersive`, `ColorPacked`,
  `ColorJobs`, `ColorNet`, `ColorProtected`, `ColorNewProc`, `ColorDelProc`,
  `ColorSuspend`) en su variante clara y en su variante `*Dark`, más los fondos de
  gráfico (`ColorGraphBk`, `ColorGraphBkDark`) — 24 valores en total. Cada variante
  se mezcla hacia el polo correspondiente de la paleta activa (su tono más claro
  para el relleno claro, su tono más oscuro para `*Dark`), de modo que los rellenos
  de fila se quedan en el tono propio de la paleta en vez de aclararse hacia un
  blanco casi puro;
- **no alcanzable**: la barra de título, la barra de menús, la barra de herramientas,
  el fondo de la vista de lista y los colores de texto, además de los colores de las
  líneas del gráfico — todo eso está compilado dentro de `procexp.exe` y ninguna
  opción de ajustes lo expone. El objetivo tematiza los resaltados de fila y el
  fondo de gráfico que de verdad posee, y no reclama nada más.

Cada valor que Apply puede modificar se guarda en una instantánea antes de
modificarlo (recuperación de primer contacto en
`%APPDATA%\Wintage\recovery\processexplorer\`) y `-Revert` lo restaura exactamente,
incluido si el valor no estaba y si el marcador estaba presente pero vacío. Una
carpeta portátil fuera de los directorios habituales de Sysinternals se recuerda
mediante la clave canónica `processexplorer` de `paths.json` (argumento de CLI
`-ProcessExplorerPath`; la GUI también puede elegirlo).

### Fuentes de terminal (`fonts/terminal/`)

Los dos objetivos de terminal leen UNA única preferencia tipográfica canónica desde
`%APPDATA%\Wintage\terminal-font.json` (`schema`, `fontSlug`, `family`, `size`,
`renderingMode`). Cuando el archivo no existe, los objetivos conservan el valor
predeterminado incluido (Terminus (TTF) para Windows, 12 pt, aliased), así que las
máquinas existentes no cambian. Una preferencia mal formada falla de forma segura:
no se sobrescribe nada y el objetivo se niega.

`fonts/terminal/catalog.json` es el único catálogo de fuentes: 20 familias
monoespaciadas de código abierto incluidas más las dos fuentes del sistema que
Wintage nombra pero nunca distribuye (Terminus (TTF) para Windows, Consolas). Cada
entrada incluida lleva su fuente original, la revisión fijada, el id de licencia, el
archivo de licencia y el SHA-256. Los archivos exactos están vendorizados bajo
`fonts/terminal/files/` con sus textos de licencia bajo `licenses/`; Wintage en
funcionamiento trabaja totalmente sin conexión y nunca descarga una fuente.

`tools/sync-terminal-fonts.ps1` es el descargador, solo para quien mantiene el
proyecto. Lee `fonts/terminal/sources.json` (un artefacto inmutable por familia),
verifica cada SHA-256 y se niega ante cualquier discrepancia. `-VerifyOnly` (por
defecto) revisa el árbol del disco sin tocar la red; `-Fetch -Write` vuelve a
vendorizar. Los bytes de fuente descargados se tratan como recursos binarios no
confiables: se hashean y se escriben, nunca se ejecutan. Hay una sustitución
registrada: **Fantasque Sans Mono** sustituye a Liberation Mono, que no publica
ninguna versión binaria fijada (solo `.sfd` de código fuente).

El instalador **explora fuentes, no las instala.** La pestaña TERMINAL FONTS carga
una fuente incluida en un `PrivateFontCollection` local al proceso para tener una
vista previa en vivo, lo que supone **cero** registros de fuentes en el sistema.
Elegir fuente, tamaño (7–24 pt) o modo de renderizado (aliased/grayscale/cleartype)
solo actualiza la vista previa y la preferencia. Instalar una fuente es una acción
explícita de **INSTALL SELECTED** que abre el propio instalador de fuentes de
Windows; tras la confirmación de Windows, el usuario vuelve a sondear con Refresh.
Los cambios reales en la terminal ocurren solo con un
**APPLY TERMINAL / APPLY CONHOST / APPLY BOTH** explícito.

Windows Terminal se aplica a la familia instalada seleccionada con el tamaño
seleccionado, y el modo de renderizado se mapea a
`profiles.defaults.antialiasingMode`. El conhost clásico es más estricto: renderiza
sobre una rejilla de celdas fija, así que una fuente seleccionada se rechaza antes
de cualquier cambio en el registro a menos que Windows la resuelva (la fuente
predeterminada y el respaldo de Consolas quedan exentos). Health y Reapply validan
la fuente, el tamaño y el suavizado configurados contra la preferencia, así que
cambiar la preferencia después de un Apply se informa como desviación y no como
"sano". El ciclo de vida de los colores de terminal queda intacto: Revert restaura
exactamente los valores que eran propiedad de Wintage antes y nunca quita una
fuente de la máquina.
<!-- source-digest: desktop/README.md sha256:15c96dac8494ab84 -->
