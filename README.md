# My Lazy Plugins for Noctalia

Colección de tres plugins para **Noctalia Shell** en el compositor de ventanas **Niri**.  
Desarrollados por **RosariosTijeras** · Licencia MIT

---

## Instalación rápida

```bash
bash plugins-install.sh
```

O directamente desde el repositorio:

```bash
curl -fsSL https://raw.githubusercontent.com/mikuri12/My-lazy-plugins-for-Noctalia/main/plugins-install.sh | bash
```

El script pregunta qué plugins instalar y los copia a `~/.config/noctalia/plugins/`, actualizando también el `plugins.json` de Noctalia.

---

## Diferencia clave entre `animated-gifs` y `animated-wallpaper`

Aunque ambos muestran imágenes animadas, son conceptualmente distintos:

| | GIF Widget (`animated-gifs`) | Animated Wallpaper (`animated-wallpaper`) |
|---|---|---|
| **¿Dónde se muestra?** | Sobre el escritorio, como un widget flotante | Detrás de todo, como fondo de pantalla |
| **¿Qué muestra?** | Solo archivos `.gif` | Vídeos (`.mp4`, `.webm`, `.mkv`, `.mov`) y `.gif` |
| **¿Se puede mover?** | Sí, es arrastrable y redimensionable | No, cubre toda la pantalla |
| **¿Cuántos a la vez?** | Puedes poner varios widgets en distintas posiciones | Uno solo por pantalla |
| **¿Cómo se añade el contenido?** | Pegando una URL, se descarga automáticamente | Seleccionando un archivo o carpeta local |
| **Capa en el sistema** | Widget de escritorio (`DesktopWidget`) | Capa `Background` de Wayland (la más baja) |

**En resumen:** `animated-gifs` son decoraciones encima del escritorio; `animated-wallpaper` reemplaza el fondo de pantalla estático por un vídeo.

---

## Plugins

### 1. GIF Widget (`animated-gifs`)

> **Versión:** 1.0.0 · **Noctalia mínimo:** 3.6.0

Muestra GIFs animados directamente **sobre el escritorio** como widgets flotantes e independientes. Cada widget que añadas al escritorio puede mostrar un GIF distinto.

#### Cómo funciona

1. En los ajustes del plugin, introduces el **nombre** y la **URL directa** del GIF (terminada en `.gif`).
2. Noctalia ejecuta `curl` en segundo plano y descarga el archivo dentro del directorio del plugin (`/gifs/<id>.gif`).
3. Una vez descargado, el GIF aparece en la lista con estado `DESCARGANDO...` → `activo/inactivo`.
4. Activas los GIFs que quieras con el checkbox.
5. Añades uno o varios **widgets al escritorio** desde Noctalia. Cada widget usa su propio índice (`widgetIndex`) para elegir qué GIF mostrar rotando por los activos: widget 0 → GIF 0, widget 1 → GIF 1, etc.
6. Los widgets son arrastrables, redimensionables y no tienen fondo visible.

#### Estados del widget

- **Sin GIFs activos** — muestra un mensaje "No hay GIFs activos".
- **Cargando** — muestra "Cargando GIF..." mientras `AnimatedImage` lee el archivo.
- **Error** — si el archivo está corrupto o falta, muestra "Error al cargar".
- **Modo edición** — al editar el escritorio, muestra el número de widget y el nombre del GIF asignado.

#### Ajustes disponibles
- Añadir GIF por nombre + URL.
- Activar / desactivar GIFs sin borrarlos.
- Vista previa en miniatura en la lista de ajustes.
- Eliminar GIF (borra también el archivo descargado).

**Archivos clave:**
- `DesktopWidget.qml` — Widget arrastrable que renderiza el GIF con `AnimatedImage`.
- `Settings.qml` — Gestión completa: añadir, activar, previsualizar y eliminar GIFs.

---

### 2. Animated Wallpaper (`animated-wallpaper`)

> **Versión:** 1.5.0 · **Noctalia mínimo:** 1.0.0

Reemplaza el fondo de pantalla estático por un **vídeo o GIF reproducido en bucle** usando `QtMultimedia`. Se renderiza en la capa `Background` de Wayland, por debajo de cualquier ventana o widget.

#### Cómo funciona

Utiliza un `PanelWindow` con `WlrLayershell.layer: WlrLayer.Background` y `exclusiveZone: -1`, lo que hace que ocupe toda la pantalla sin interferir con ventanas ni atajos de teclado. Internamente usa `MediaPlayer` + `VideoOutput` de Qt para la reproducción.

Tiene **dos modos de funcionamiento**:

**Modo manual**
- Seleccionas un único archivo de vídeo desde el selector de archivos.
- Se reproduce ese vídeo en bucle indefinidamente mientras el plugin esté activo.

**Modo automático (Random)**
- Apuntas a una **carpeta** con vídeos.
- El plugin carga todos los archivos compatibles con `FolderListModel` y elige uno aleatoriamente al arrancar.
- Un `Timer` cambia a otro vídeo aleatorio de la carpeta cada `X` segundos/minutos/horas.
- También puedes hacer clic sobre el fondo para cambiar de vídeo manualmente en modo automático.

#### Ajustes disponibles
- **Activar/desactivar** el wallpaper con un toggle.
- **Modo manual o automático** desde un desplegable.
- **Intervalo de cambio** (solo en modo auto): botones predefinidos (`5s`, `10s`, `15s`, `30s`, `45s`, `1m`, `1h 30m`, `2h`) o intervalos personalizados en formato `5s` / `10m` / `2h`. Los personalizados se pueden eliminar con el botón `−`.
- **Selector de vídeo** — abre un explorador de archivos para elegir un vídeo concreto.
- **Selector de carpeta** — abre un explorador de directorios para el modo automático.
- **Modo de relleno**: `Crop` (recorta para llenar, recomendado), `Fit` (ajusta con barras) o `Stretch` (estira).
- **Volumen** — deslizador de 0 % a 100 % (por defecto silenciado).
- **Bucle** — toggle para repetir el vídeo indefinidamente.

**Archivos clave:**
- `Main.qml` — Lógica de reproducción, cambio automático aleatorio y ventana de fondo de Wayland.
- `Settings.qml` — Todos los controles de configuración.
- `VideoPickerPanel.qml` — Panel explorador para elegir un vídeo concreto.
- `FolderPickerPanel.qml` — Panel explorador para elegir una carpeta.

---

### 3. Media Panel (`media-panel`)

> **Versión:** 1.0.0 · **Noctalia mínimo:** 1.0.0

Plugin de reproductor de música que se integra con el servicio de medios de Noctalia (`MediaService`) para mostrar la pista en reproducción y permitir controlarla. Tiene dos puntos de entrada: un **panel completo** y un **widget en la barra**.

#### Panel completo (`Panel.qml`)

Se abre como panel de Noctalia (700 × 280 px escalable). Está dividido en tres columnas:

1. **Portada del álbum** — muestra la imagen de la portada si el reproductor la expone vía MPRIS, o un icono de disco como fallback. El borde cambia de color cuando hay reproducción activa.
2. **Información y controles** — muestra:
   - Título de la canción (en color primario).
   - Nombre del artista.
   - Botones **anterior / play·pausa / siguiente** (habilitados según lo que permita el reproductor actual).
   - **Barra de progreso interactiva**: puedes hacer clic o arrastrar para saltar a cualquier punto. Al pasar el ratón aparece un tooltip con el tiempo exacto y un indicador de previsualización semitransparente.
   - Tiempo actual y duración total.
3. **GIF decorativo** — un GIF animado a la derecha del panel. Solo se anima cuando hay música reproduciéndose; se vuelve semitransparente al pausar. Se configura desde los ajustes del plugin introduciendo una URL, que se descarga localmente como `custom-media-gif.gif` usando `curl`.

#### Widget de barra (`BarWidget.qml`)

Widget compacto que vive en **la barra de estado de Noctalia**. Muestra el título de la pista en curso como una cápsula. Al pasar el ratón aparecen los botones de anterior / play·pausa / siguiente sin abrir el panel. Se adapta a barras **horizontales y verticales**, y su tamaño escala con `barLineSize`.

#### Ajustes (`Settings.qml`)

Solo tiene una opción: introducir la **URL del GIF decorativo** del panel. Al guardar, descarga el GIF con `curl` y lo almacena como `custom-media-gif.gif` dentro del directorio del plugin. Un botón "Recargar GIF" fuerza la recarga si el archivo ya existía.

**Archivos clave:**
- `Panel.qml` — Panel completo con portada, controles, barra de progreso y GIF decorativo.
- `BarWidget.qml` — Widget compacto para la barra de estado.
- `Settings.qml` — Configuración del GIF decorativo.

---

## Estructura del repositorio

```
animated-gifs/
├── DesktopWidget.qml
├── Settings.qml
├── manifest.json
└── settings.json

animated-wallpaper/
├── Main.qml
├── Settings.qml
├── VideoPickerPanel.qml
├── FolderPickerPanel.qml
├── manifest.json
└── settings.json

media-panel/
├── Panel.qml
├── BarWidget.qml
├── Settings.qml
├── manifest.json
└── settings.json

plugins-install.sh
```

---

## Instalación rápida

```bash
bash plugins-install.sh
```

O directamente desde el repositorio:

```bash
curl -fsSL https://raw.githubusercontent.com/mikuri12/My-lazy-plugins-for-Noctalia/main/plugins-install.sh | bash
```

El script te pregunta qué plugins instalar y los copia al directorio `~/.config/noctalia/plugins/`.

---

## Plugins

### 1. GIF Widget (`animated-gifs`)

> **Versión:** 1.0.0 · **Noctalia mínimo:** 3.6.0

Muestra GIFs animados directamente sobre el escritorio como widgets arrastrables.

**Características:**
- Añade GIFs desde cualquier URL (los descarga con `curl` en segundo plano).
- Cada widget en el escritorio muestra un GIF distinto según su índice.
- Los GIFs se pueden activar o desactivar individualmente sin borrarlos.
- El widget es redimensionable y no tiene fondo visible.
- Si no hay GIFs activos, muestra un estado vacío con mensaje.

**Archivos clave:**
- `DesktopWidget.qml` — Widget arrastrable que renderiza el GIF.
- `Settings.qml` — Gestor de GIFs: añadir por URL, activar/desactivar y eliminar.

---

### 2. Animated Wallpaper (`animated-wallpaper`)

> **Versión:** 1.5.0 · **Noctalia mínimo:** 1.0.0

Reproduce un vídeo o GIF como fondo de pantalla animado mediante `QtMultimedia`.

**Características:**
- **Modo manual:** selecciona un archivo de vídeo concreto.
- **Modo automático:** apunta a una carpeta y cambia de vídeo aleatoriamente cada cierto tiempo.
- Formatos soportados: `.mp4`, `.webm`, `.mkv`, `.mov`, `.gif`.
- Ajuste de modo de relleno (`PreserveAspectCrop`, `Stretch`, etc.).
- Volumen configurable (por defecto silenciado) y opción de bucle.
- Intervalos de cambio predefinidos o personalizados (formato `5s`, `10m`, `2h`).

**Archivos clave:**
- `Main.qml` — Lógica de reproducción y cambio automático de vídeo.
- `Settings.qml` — Selector de archivo/carpeta, modo, intervalo, relleno y volumen.
- `VideoPickerPanel.qml` — Panel para elegir un vídeo concreto.
- `FolderPickerPanel.qml` — Panel para elegir una carpeta.

---

### 3. Media Panel (`media-panel`)

> **Versión:** 1.0.0 · **Noctalia mínimo:** 1.0.0

Panel y widget de barra para controlar la reproducción de música, con un GIF decorativo personalizable.

**Características:**
- Muestra título de la canción, artista, álbum y duración.
- Controles de reproducción: anterior, play/pausa y siguiente.
- Barra de progreso interactiva.
- GIF animado en el panel configurable desde ajustes (URL remota, se descarga localmente).
- **Widget de barra:** muestra el título de la pista en la barra de Noctalia con botones de control al pasar el ratón, adaptable a barras verticales y horizontales.

**Archivos clave:**
- `Panel.qml` — Panel completo con info de la pista, GIF decorativo y controles.
- `BarWidget.qml` — Widget compacto para la barra de estado.
- `Settings.qml` — Campo para introducir la URL del GIF decorativo y descargarlo.

---

## Estructura del repositorio

```
animated-gifs/
├── DesktopWidget.qml
├── Settings.qml
├── manifest.json
└── settings.json

animated-wallpaper/
├── Main.qml
├── Settings.qml
├── VideoPickerPanel.qml
├── FolderPickerPanel.qml
├── manifest.json
└── settings.json

media-panel/
├── Panel.qml
├── BarWidget.qml
├── Settings.qml
├── manifest.json
└── settings.json

plugins-install.sh
```

---

## Créditos

GIFs animados obtenidos mediante [Giphy](https://giphy.com) · Powered by Giphy
