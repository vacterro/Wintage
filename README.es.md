# Wintage

**Tema vintage « Win95 Dark Golden » para toda la web.** Un userscript de Tampermonkey que reestiliza cada sitio como una aplicación Windows 95 de dorado-marrón oscuro: biseles 3D nítidos a píxel, cero esquinas redondeadas, cero animaciones, sin destellos al pasar el cursor, Verdana en todas partes.

[🤍 Apoyar al desarrollador](https://buymeacoffee.com/vacuum34)

[EN](README.md) | [RU](README.ru.md) | [ET](README.et.md) | [Дед](README.ded.md)

_La web moderna optimiza la estética a expensas de la usabilidad. Las esquinas redondeadas reemplazan la jerarquía visual, las animaciones reemplazan la retroalimentación, las sombras reemplazan la estructura, y el minimalismo suele eliminar justo las señales en las que se apoya nuestro cerebro para entender una interfaz._

_Los usuarios no deberían adivinar si algo es un botón, una etiqueta, una tarjeta o texto plano. Wintage devuelve un lenguaje visual explícito: botones en relieve, campos de entrada hundidos, límites nítidos, tipografía consistente, cero distracciones y cambios de estado inmediatos._

_Cada elemento comunica su propósito de un vistazo, reduce la carga cognitiva y vuelve a hacer de la web un instrumento preciso en lugar de una colección de burbujas decorativas._

[Registro de cambios](CHANGELOG.md)

## Instalación

1. Instala [Tampermonkey](https://www.tampermonkey.net/) (Chrome, Edge, Firefox, Opera, Safari).
2. Haz clic en **[Instalar Wintage](https://raw.githubusercontent.com/vacterro/Wintage/main/wintage.user.js)** — Tampermonkey abre automáticamente su página de instalación.
3. Listo. Cada sitio que visites ahora corre Windows 95, edición Dark Golden.

## Actualización

- **Automática:** el script lleva `@updateURL`/`@downloadURL` apuntando a este repositorio, así que Tampermonkey recoge las versiones nuevas en sus comprobaciones periódicas.
- **Actualización manual:** Tampermonkey → **Utilities → Check for userscript updates**, o simplemente vuelve a hacer clic en el enlace de instalación — reemplaza la versión anterior en el sitio, sin necesidad de desinstalar.
- **Faltan filas de temas: script viejo:** el menú se genera a partir del registro de temas integrado y la prueba de release exige exactamente una fila de menú por cada paleta integrada. Si el menú es más corto que la lista de paletas de abajo, haz clic de nuevo en **Install Wintage** y confirma **Update** en Tampermonkey.

## Dieciséis paletas y un interruptor

Wintage ya no es una sola paleta. Seis son la estructura propia de UI.md girada a otra familia de tonos (Dark Golden, Claude Code, Antigravity, K-Lite, FreeBuff, CodeNomad); Custom se puede editar y guardar desde el instalador de escritorio, y nueve se importan de [FastPrompter](https://github.com/vacterro) (Default, Golden Vintage, Golden Default, Vintage Dark, Vintage Classic, Dark 2 OLED, Dracula, Nord, Solarized Dark). Todas superan WCAG AA en los tres tokens que llevan texto — el build gate rechaza cualquier paleta que no lo haga.

Elige una en el **menú de Tampermonkey** en cualquier página; la elección se guarda por usuario, no por sitio, así que se mantiene en todos los dominios.

Las paletas viven en `themes/*.json`, fuera del script, por una razón: Tampermonkey re-descarga `wintage.user.js` en cada actualización, así que una paleta editada a mano desaparecería. Reaplícalas sobre un build fresco con:

```powershell
.\install-themes.ps1 -Latest
```

## Más allá del navegador

Las mismas paletas se instalan en aplicaciones de escritorio — VS Code y Antigravity como temas de color, apps Electron (Freebuff, la app agente Antigravity) mediante un shim que inyecta exactamente la hoja de estilo que usa este userscript. Hay una pequeña GUI para ello:

Haz doble clic en **`Wintage Installer.vbs`** en la raíz del repositorio. Abre la GUI sin ventana de consola. El lanzador `.cmd` heredado redirige al mismo host oculto; `desktop\WintageInstaller.ps1` sigue ejecutable directamente para diagnósticos.

Lo que cada objetivo puede y no puede alcanzar — incluidas las dos apps soldadas o con colores compilados — está escrito en **[desktop/README.md](desktop/README.md)**.

## Funcionalidades

- **Paleta Golden Default** — lienzo marrón-negro profundo `#1A1810`, texto dorado `#D4C89A`, relieves dorados `#F0D060`. Solo superficies planas sólidas: sin degradados, sin desenfoque, sin efectos de transparencia.
- **Biseles 3D clásicos** — botones en relieve, campos hundidos, botones presionados que se hunden (con el auténtico desplazamiento de 1px de la etiqueta). Las barras de desplazamiento son de 16px completos estilo Win95, con pulgar y botones biselados.
- **Asesino de radios** — `border-radius: 0` aplicado en todas partes, incluidas las variables CSS de los frameworks (Bootstrap, Material, YouTube, Reddit).
- **Movimiento prohibido** — todas las transiciones y animaciones quedan a cero. Los cambios de estado son instantáneos, como en una interfaz real de 1995.
- **Resaltado al pasar el cursor completamente desactivado** — sin filas que destellen en blanco, sin bloques de tinte gris:
  - las propiedades de pintura se eliminan quirúrgicamente de cada regla `:hover` legible (las propiedades funcionales como `display`/`visibility`/`opacity` se conservan, así que los menús que se abren al pasar el cursor siguen funcionando);
  - las hojas de estilo cross-origin ilegibles se neutralizan con un respaldo de congelación de transiciones.
  Solo los controles reales (botones, enlaces, campos) conservan una respuesta biselada inmediata y temada.
- **Verdana forzado 100 % en todas partes** — incluidos campos y textareas, con el suavizado de fuente desactivado. Las fuentes de iconos quedan excluidas para que los glifos no se conviertan en letras. Si tienes una fuente personalizada instalada con el nombre `Verdana_m1` (p. ej. un parche Verdana des-antialiasado), se usa automáticamente; de lo contrario, Verdana normal.
- **Repintador adaptativo** — un barrido JS ligero convierte las superficies claras tipo "flashbang" y los grises del modo oscuro sin temar en la escala marrón vintage, y arregla el texto de bajo contraste (oscuro-sobre-oscuro) hacia dorado, con umbrales conscientes del WCAG. Las imágenes, videos, canvases y reproductores nunca se tocan.
- **Perforación del Shadow DOM** — tema también los web components (YouTube, Reddit y compañía) mediante un hook `attachShadow`.
- **Los popups se portan bien** — menús, diálogos, tooltips y hovercards solo se recoloran; el script nunca fuerza `opacity`/`z-index`/`visibility`, así que la UI oculta del sitio sigue oculta.
- **Protector de seguridad** — el script se desactiva solo en páginas de OAuth, captcha, banca y pagos para que los flujos críticos nunca se reestilicen.

## Paleta

La tabla siguiente muestra 10 de los 21 tokens de la paleta Golden Default. Cada paleta distribuida define los 21; los 11 restantes cubren la estructura de biseles, el texto secundario, los colores semánticos (éxito/advertencia/peligro), la selección y las particularidades por objetivo.

| Token | Hex | Se usa para |
|---|---|---|
| background | `#1A1810` | fondo más externo |
| backgroundSoft | `#232018` | fondo del body / del contenido |
| surface | `#332E22` | cabeceras, navegación, paneles |
| surfaceRaised | `#3D372A` | botones, popups, pulgar de scrollbar |
| surfaceAlt | `#453D30` | hover de botón |
| borderHighlight | `#F0D060` | bordes 3D superior-izquierda |
| borderDark | `#100E08` | bordes 3D inferior-derecha |
| textPrimary | `#D4C89A` | texto dorado principal |
| textMuted | `#6E674E` | placeholders, deshabilitado |
| link | `#F0D060` | enlaces, foco |

## Tema de navegador a juego

El objetivo `browsers` del instalador de escritorio detecta los perfiles Chromium instalados y portátiles, informa de la cobertura de Tampermonkey, prepara el tema de navegador seleccionado y abre las páginas correctas de instalación/actualización para cada perfil. Chromium exige una confirmación **Developer mode → Load unpacked** por perfil; el instalador copia la ruta estable del tema al portapapeles. Los cambios de paleta posteriores reutilizan esa ruta.

## Comportamientos conocidos

- Los sitios que construyen efectos de hover en JavaScript (alternando clases) en lugar de CSS `:hover` pueden seguir mostrando su propio resaltado.
- En los raros sitios cuyo CSS es cross-origin, hacer clic en un elemento no enfocable puede retrasar su cambio de estado visual hasta que el ratón lo abandone (actúa el respaldo de congelación de hover). Los botones y enlaces reales están exentos.
- El script es estático por diseño: sin panel de opciones, sin interruptores por sitio. Haz un fork y edita los tokens de arriba si quieres otro sabor.

## Publicar una nueva versión (mantenedores)

Primero añade una entrada `## [x.y.z] - date` al principio de `CHANGELOG.md` — `release.ps1` se niega a ejecutarse sin ella. Luego:

```powershell
.\release.ps1 -Message "qué cambió"
```

Incrementa el número de parche de `@version` (la cabecera de Tampermonkey y el sello `W95_VERSION` se mueven juntos), reconstruye los temas de escritorio generados, ejecuta toda la suite de compuertas de release, y hace commit, tag y push — los clientes de Tampermonkey recogen la actualización automáticamente. Pasa `-Bump minor` o `-Bump major` para releases mayores.

## Licencia

[MIT](LICENSE)

<!-- source-digest: README.md sha256:886c5e27060e7b30 -->
