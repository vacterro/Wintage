# Wintage para aplicaciones de escritorio

El userscript tematiza la web. Esto tematiza los programas que la rodean, con las mismas paletas, para que el navegador y las apps dejen de discutir sobre qué significa "dark golden".

Hay una regla detrás de cada decisión: **las aplicaciones se actualizan solas, y una actualización no debe romper nada en silencio.** Donde un objetivo tiene un lugar en tu propio perfil, el tema va allí y sobrevive a las actualizaciones. Donde no lo tiene, el instalador está pensado para re-ejecutarse — y lo dice, en lugar de fingir que persistió.

## La GUI

Haz doble clic en **`Wintage Installer.vbs`** en la raíz del repositorio para abrirla sin ventana de consola, o ejecuta esto directamente para diagnósticos:

```powershell
powershell -File desktop\WintageInstaller.ps1
```

Lista de temas con chips de color, los objetivos encontrados en esta máquina, una vista previa Win95 en vivo, y los veintiún tokens de color como muestras editables. Editar cualquier muestra bifurca la paleta en **Custom** en lugar de cambiar un tema distribuido por debajo de ti. El panel de la derecha muestra en vivo el contraste WCAG de los tres tokens que llevan texto — una paleta que FAIL ahí la rechaza igualmente el build gate, así que es mejor verlo antes de Apply que después.

Los objetivos se dividen en dos listas accesibles por teclado: **MY APPS** contiene las herramientas portátiles/árbol-fuente CodeNomad, SAIPENVIEW, SmartVac y WildRift; **POPULAR APPS** contiene Windows, OBS, terminales, editores y el otro software instalado. ALL/NONE y Apply/Revert operan sobre ambas listas sin cambiar su agrupación.

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

| target | mecanismo | sobrevive a una actualización de la app |
|---|---|---|
| `windows` | `.theme` de usuario: modo sistema/app oscuro, roles de color de acento y clásicos | sí — instalado en tu carpeta local de temas de Windows |
| `browsers` | detecta perfiles Chromium instalados + portátiles, prepara el tema chrome elegido y abre las páginas de confirmación propias de Tampermonkey/tema del navegador | sí — tras un **Load unpacked** por perfil |
| `terminal` | esquema de Windows Terminal + valores por defecto de todos los perfiles, Consolas 12 con alias | sí — los ajustes están en tu perfil |
| `conhost` | valores por defecto de `HKCU\Console` + cada perfil cmd/PowerShell existente | sí — instantánea exacta de los valores tocados |
| `obs` | variante OBS 30.2+ `.ovt` + ID de tema activo en `user.ini` | sí — vive en tu perfil |
| `antigravity`, `vscode` | extensión de tema de color en `~/.antigravity/extensions` / `~/.vscode/extensions` | **sí** — vive en tu perfil |
| `freebuff`, `antigravity-app`, `codenomad` | shim de Electron, ver abajo | no — re-ejecuta el instalador |
| `claude` | shim de Electron, parcheado en el lugar — ver abajo | no — una actualización crea una carpeta `app-<version>` nueva |
| `mpchc` | registro, solo tema oscuro + tipografía OSD | no — MPC-HC reescribe sus ajustes al salir |
| `obsidian` | tema de comunidad por vault, todas las paletas instaladas a la vez | **sí** — vive en tu vault |
| `saipenview` | reescribe sus propios valores de token `:root` en `style.css` | no — un archivo fuente; re-ejecutar tras un pull |
| `discord` | CSS depositado en la propia carpeta de temas de BetterDiscord | sí |
| `totalcmd`, `totalcmd2` | claves `[Colors]` de `wincmd.ini`; los filtros de archivos recientes existentes usan el color de enlace de la paleta | sí — es tu ini |
| `smartvac`, `wildrift` | tabla de tokens reescrita en el propio código fuente de la app | no — un archivo fuente; re-ejecutar tras un pull |

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

### SAIPENVIEW

Su frontend ya declara los nombres de tokens de Wintage en su propio `:root`, así que este parche reescribe **solo los valores de tokens** — nunca un selector, una fuente, un ancho de borde o un padding. Nada que afecte al box model cambia, así que el texto no puede desplazarse. Eso es deliberado: el enfoque anterior anexaba toda la hoja de estilo del navegador encima, y `wintage.css` está escrita para páginas web arbitrarias — selectores universales que fuerzan la fuente, la escala de tamaños, bordes de 2px y alturas de controles. En una app que ya tiene su propio layout, eso mueve todo.

Verificado enmascarando cada hex y comparando con el respaldo: estructuralmente idéntico, solo difieren los literales de color. `--link` se informa como no declarado allí (sus enlaces markdown leen `--accentTeal`, que esto sí define) en lugar de inyectarse — añadir una variable que la app nunca lee sería peso muerto.

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

<!-- source-digest: desktop/README.md sha256:1b166ae6a7cf8a5c -->
