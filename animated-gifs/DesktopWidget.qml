import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Widgets
import qs.Modules.DesktopWidgets
import qs.Services.Media

DraggableDesktopWidget {
    id: root

    // Injected by Noctalia
    property var pluginApi: null

    // Default size - user can resize
    implicitWidth: Math.round(300 * widgetScale)
    implicitHeight: Math.round(300 * widgetScale)

    // No background
    showBackground: false

    // ── Carpeta de GIFs ────────────────────────────────────────────────────
    // Ruta de la carpeta donde se guardan los GIFs descargados
    readonly property string gifsFolder: {
        try {
            if (!pluginApi || !pluginApi.pluginDir) return ""
            return pluginApi.pluginDir + "/gifs"
        } catch(e) { return "" }
    }

    // FolderListModel: escanea la carpeta en tiempo real.
    // Cualquier .gif que esté ahí aparece automáticamente como candidato.
    FolderListModel {
        id: gifFolderModel
        folder: root.gifsFolder ? ("file://" + root.gifsFolder) : ""
        nameFilters: ["*.gif", "*.GIF"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Lista de rutas absolutas de todos los GIFs en la carpeta
    property var folderGifPaths: {
        var paths = []
        for (var i = 0; i < gifFolderModel.count; i++) {
            var fp = gifFolderModel.get(i, "filePath")
            if (fp) paths.push(fp)
        }
        return paths
    }

    // GIF asignado a este widget específico (desde widgetData)
    // Cada widget puede tener un GIF diferente configurado independientemente
    property string _assignedGifFilename: ""
    
    // Proceso para cargar configuración del archivo JSON
    Process {
        id: loadConfigProc
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var config = JSON.parse(line)
                    if (config && config.widgets) {
                        // Buscar configuración de este widget
                        for (var i = 0; i < config.widgets.length; i++) {
                            var w = config.widgets[i]
                            if (w.index === widgetIndex && w.gifFilename) {
                                _assignedGifFilename = w.gifFilename
                                console.log("GIF Widget [" + widgetIndex + "]: Configuración cargada desde archivo →", w.gifFilename)
                                break
                            }
                        }
                    }
                } catch(e) {
                    console.log("GIF Widget: Error parseando config:", e)
                }
            }
        }
    }
    
    // Proceso para guardar configuración en archivo JSON
    Process {
        id: saveConfigProc
        running: false
        onExited: function(code) {
            if (code === 0) {
                console.log("GIF Widget [" + widgetIndex + "]: Configuración guardada exitosamente")
            } else {
                console.log("GIF Widget [" + widgetIndex + "]: Error guardando configuración (code", code, ")")
            }
        }
    }
    
    // Watcher para sincronizar con widgetData
    Connections {
        target: root
        function onWidgetDataChanged() {
            var filename = widgetData?.gifFilename ?? ""
            if (_assignedGifFilename !== filename) {
                _assignedGifFilename = filename
                console.log("GIF Widget [" + widgetIndex + "]: widgetData cambió →", filename)
            }
        }
    }
    
    // Inicializar desde widgetData
    Component.onCompleted: {
        // Intentar cargar desde archivo JSON (más confiable que widgetData)
        var configPath = pluginApi?.pluginDir + "/widgets-config.json"
        if (configPath && pluginApi?.pluginDir) {
            loadConfigProc.command = ["cat", configPath]
            loadConfigProc.running = true
        }
        
        // Fallback: intentar desde widgetData
        if (!widgetData) {
            widgetData = {}
        }
        var fromWidgetData = widgetData?.gifFilename ?? ""
        if (fromWidgetData && !_assignedGifFilename) {
            _assignedGifFilename = fromWidgetData
        }
        
        // Log de inicio
        console.log("GIF Widget [" + widgetIndex + "]: Inicializando...",
                    "| GIF asignado:", _assignedGifFilename || "(ninguno)")
        
        // Si ya hay música reproduciéndose, iniciar detección de BPM
        if (isMusicPlaying && widgetIndex === 0) {
            console.log("GIF Widget: Música detectada al iniciar, lanzando análisis BPM...")
            bpmDelayTimer.restart()
        }
    }
    
    property var currentGif: {
        try {
            // Si el widget tiene un GIF específico configurado, usarlo
            if (_assignedGifFilename !== "") {
                // Verificar que el archivo existe en la carpeta
                for (var i = 0; i < folderGifPaths.length; i++) {
                    if (folderGifPaths[i].endsWith("/" + _assignedGifFilename)) {
                        return { filename: _assignedGifFilename, name: _assignedGifFilename.replace(/\.gif$/i, "") }
                    }
                }
                // El archivo asignado ya no existe
                console.log("GIF Widget: Archivo asignado no encontrado:", _assignedGifFilename)
            }
            // Sin GIF asignado → mostrar selector en edit mode
            return null
        } catch(e) { return null }
    }

    // Función para asignar un GIF a este widget
    function assignGif(filename) {
        console.log("GIF Widget [" + widgetIndex + "]: assignGif() llamado con →", filename)
        
        _assignedGifFilename = filename
        
        // Guardar en widgetData (backup)
        var newData = {}
        if (widgetData) {
            for (var key in widgetData) {
                newData[key] = widgetData[key]
            }
        }
        newData.gifFilename = filename
        widgetData = newData
        
        // Guardar en archivo JSON (persistencia real)
        var scriptPath = pluginApi?.pluginDir + "/save-widget-config.sh"
        if (scriptPath && pluginApi?.pluginDir) {
            saveConfigProc.command = ["bash", scriptPath, widgetIndex.toString(), filename]
            saveConfigProc.running = true
        }
        
        console.log("GIF Widget [" + widgetIndex + "]: GIF asignado →", filename)
    }

    // URL completa del GIF actual
    property string gifUrl: {
        try {
            if (!currentGif) return ""
            if (!pluginApi || !pluginApi.pluginDir) return ""
            var filename = currentGif.filename || currentGif.name + ".gif"
            return "file://" + pluginApi.pluginDir + "/gifs/" + filename
        } catch(e) { return "" }
    }

    // El GIF está listo para mostrar (también en edit mode si tiene GIF asignado)
    property bool gifReady: gifDisplay.status === AnimatedImage.Ready && currentGif !== null

    // ¿Hay GIFs disponibles pero ninguno asignado a este widget?
    property bool needsGifSelection: folderGifPaths.length > 0 && currentGif === null

    // Scaled values
    readonly property int scaledRadius: Math.round(Style.radiusM * widgetScale)
    readonly property int scaledMargin: Math.round(16 * widgetScale)
    readonly property int scaledIconSize: Math.round(48 * widgetScale)

    // ══════════════════════════════════════════════════════════════════════
    // BPM sync — lógica cat-jam adaptada para QML
    //
    // VELOCIDAD: frameInterval = 1000 / (gifBaseFPS * playbackRate)
    //            playbackRate  = efectiveBPM / gifBaseBPM
    //
    // SINCRONIZACIÓN AL BEAT (como cat-jam hace con currentTime=0):
    //   Calculamos cuándo cae el siguiente beat a partir de
    //   MediaService.currentPosition y el BPM efectivo, y en ese momento
    //   reseteamos al frame 0.
    // ══════════════════════════════════════════════════════════════════════

    readonly property real gifBaseFPS: {
        try {
            // Intentar obtener FPS específico del GIF actual
            if (currentGif && pluginApi?.pluginSettings?.gifsMetadata) {
                var metadata = pluginApi.pluginSettings.gifsMetadata[currentGif.filename]
                if (metadata && metadata.fps > 0) {
                    return metadata.fps
                }
            }
            // Fallback: Estandarizar a 30 FPS (funciona bien para la mayoría de GIFs)
            return 30.0
        } catch(e) { return 30.0 }
    }

    readonly property real gifBaseBPM: {
        try { return pluginApi?.pluginSettings?.gifBPM ?? 120.0 } catch(e) { return 120.0 }
    }

    readonly property real manualBPM: {
        try { return pluginApi?.pluginSettings?.manualBPM ?? -1 } catch(e) { return -1 }
    }

    // API key de GetSongBPM (getsongbpm.com — gratis, 500 req/día)
    // readonly property string bpmApiKey — REMOVIDO: ya no se usan APIs externas

    // BPM detectado localmente via PipeWire + aubio (detect-bpm.sh)
    property real apiBPM: -1
    // BPM recibido de playerctl --follow (cualquier app del escritorio)
    property real detectedBPM: -1

    // BPM desde metadatos MPRIS (raro pero posible)
    readonly property real mprisBPM: {
        try {
            var meta = MediaService.currentPlayer?.metadata
            if (!meta) return -1
            var bpm = meta["xesam:audioBPM"] ?? meta["xesam:bpm"] ?? -1
            var n = Number(bpm)
            return (n > 0) ? n : -1
        } catch(e) { return -1 }
    }

    // BPM efectivo: MPRIS → detección local → playerctl → manual → -1
    readonly property real effectiveBPM: {
        if (mprisBPM    > 0) return mprisBPM
        if (apiBPM      > 0) return apiBPM
        if (detectedBPM > 0) return detectedBPM
        if (manualBPM   > 0) return manualBPM
        return -1
    }

    // Cuando cambia el BPM efectivo, ajustar velocidad del GIF
    onEffectiveBPMChanged: {
        console.log("GIF Widget [" + widgetIndex + "]: BPM cambió →", effectiveBPM,
                    "| gifBaseBPM:", gifBaseBPM,
                    "| rate:", playbackRate.toFixed(2) + "×",
                    "| interval:", frameInterval + "ms")
        if (effectiveBPM > 0 && isMusicPlaying && gifReady) {
            frameTicker.restart()
        }
    }

    // playbackRate: qué tan rápido va el GIF respecto a su velocidad nativa
    // Formula directa como spicetify-cat-jam-synced: trackBPM / videoDefaultBPM
    // IMPORTANTE: Limitado entre 0.5× y 1.5× para evitar velocidades extremas
    readonly property real playbackRate: {
        if (effectiveBPM > 0) {
            var rate = effectiveBPM / gifBaseBPM
            // Limitar a rango razonable para evitar que se rompa
            return Math.max(0.5, Math.min(rate, 1.5))
        }
        // Si no hay BPM detectado, ir a velocidad reducida (0.5×)
        return 0.5
    }

    // Intervalo del timer de frames
    readonly property int frameInterval: Math.max(8, Math.round(1000.0 / (gifBaseFPS * playbackRate)))

    // ── Timer principal: avanza frames a la velocidad correcta ────────────
    Timer {
        id: frameTicker
        interval: root.frameInterval
        repeat: true
        // Permite animar incluso sin BPM detectado (con velocidad reducida)
        running: root.gifReady && root.isMusicPlaying

        onTriggered: {
            if (gifDisplay.frameCount > 0)
                gifDisplay.currentFrame = (gifDisplay.currentFrame + 1) % gifDisplay.frameCount
        }
        onIntervalChanged: { if (running) restart() }
    }

    // ── Detección local de BPM via PipeWire + aubio ─────────────────────
    // Captura el audio del sistema (lo que suena) y analiza el BPM.
    // Funciona con CUALQUIER fuente: Spotify, YouTube, VLC, Firefox, etc.
    // No requiere APIs, claves ni internet.
    property string _bpmDetectBuffer: ""
    property bool _bpmDetecting: false
    // Nombre de la última canción analizada (evita re-analizar la misma)
    property string _lastAnalyzedTrack: ""
    // Timestamp de cuándo se lanzó la detección (para invalidar resultados viejos)
    property real _bpmDetectStartTime: 0
    // BPM anterior para suavizado de transiciones
    property real _previousApiBPM: -1

    // ── Estado de reproducción de música ──────────────────────────────────
    // Usa SOLO MediaService.isPlaying (reproductores MPRIS dedicados: Spotify, VLC, etc.)
    // NO detecta audio del navegador/juegos (evita falsos positivos)
    readonly property bool isMusicPlaying: MediaService.isPlaying

    // Cuando cambia el estado de reproducción
    onIsMusicPlayingChanged: {
        console.log("GIF Widget [" + widgetIndex + "]: isMusicPlaying →", isMusicPlaying,
                    "| Player:", MediaService.currentPlayer?.playerName ?? "none")
        if (isMusicPlaying) {
            // Empezó la música → animar GIF y detectar BPM
            frameTicker.restart()
            if (effectiveBPM <= 0) {
                // No hay BPM detectado → iniciar detección
                bpmDelayTimer.restart()
            }
        } else {
            // Se detuvo la música → pausar inmediatamente
            console.log("GIF Widget [" + widgetIndex + "]: Música pausada")
            frameTicker.stop()
        }
    }

    // Ruta al script de detección
    readonly property string detectBpmScript: {
        try {
            if (!pluginApi || !pluginApi.pluginDir) return ""
            return pluginApi.pluginDir + "/detect-bpm.sh"
        } catch(e) { return "" }
    }

    // Duración de captura en segundos (configurable en settings, default 5s para respuesta rápida)
    readonly property int bpmCaptureSecs: {
        try { return pluginApi?.pluginSettings?.bpmCaptureSecs ?? 5 } catch(e) { return 5 }
    }

    Process {
        id: bpmDetectProc
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                root._bpmDetectBuffer += line.trim()
            }
        }
        onExited: function(code) {
            var startedAt = root._bpmDetectStartTime
            root._bpmDetecting = false

            if (code !== 0 || root._bpmDetectBuffer === "") {
                root._bpmDetectBuffer = ""
                console.log("GIF Widget: detect-bpm.sh no obtuvo BPM (¿no hay audio?)")
                return
            }

            // Si la canción cambió mientras se analizaba, descartar resultado
            var currentTrack = (MediaService.trackTitle ?? "") + "|" + (MediaService.trackArtist ?? "")
            if (currentTrack !== root._lastAnalyzedTrack) {
                root._bpmDetectBuffer = ""
                console.log("GIF Widget: Canción cambió durante análisis, descartando resultado")
                root.fetchBpmFromAudio(false)
                return
            }

            try {
                var bpm = parseFloat(root._bpmDetectBuffer)
                root._bpmDetectBuffer = ""
                if (bpm > 0 && bpm < 300) {
                    // Si el BPM cambió dramáticamente (>30%), resetear suavizado
                    var smoothed = bpm
                    if (root._previousApiBPM > 0) {
                        var change = Math.abs(bpm - root._previousApiBPM) / root._previousApiBPM
                        if (change > 0.3) {
                            // Cambio grande → resetear suavizado
                            console.log("GIF Widget: BPM cambió mucho (" + (change * 100).toFixed(0) + "%), reseteando suavizado")
                            smoothed = bpm
                        } else {
                            // Cambio pequeño → suavizar transición
                            smoothed = Math.round((0.65 * bpm + 0.35 * root._previousApiBPM) * 10) / 10
                        }
                    }
                    root._previousApiBPM = bpm
                    root.apiBPM = smoothed
                    console.log("GIF Widget: BPM detectado:", bpm, "→ suavizado:", smoothed,
                                "| gifBaseBPM:", root.gifBaseBPM,
                                "| playbackRate calculado:", (smoothed / root.gifBaseBPM).toFixed(2) + "×",
                                "| limitado a:", root.playbackRate.toFixed(2) + "×")
                    // El frameTicker ya está corriendo, solo ajustar velocidad
                } else {
                    console.log("GIF Widget: BPM fuera de rango:", bpm)
                }
            } catch(e) {
                root._bpmDetectBuffer = ""
                console.log("GIF Widget: Error parseando BPM:", e)
            }
        }
    }

    function fetchBpmFromAudio(isRefresh) {
        if (root.detectBpmScript === "") return
        // Solo el widget #0 lanza la detección (evita múltiples procesos)
        if (typeof widgetIndex !== "undefined" && widgetIndex !== 0) return

        // Si ya está corriendo, no lanzar otro
        if (root._bpmDetecting) return

        // Solo analizar si hay música reproduciéndose
        if (!root.isMusicPlaying) return

        // Construir clave de canción
        var trackKey = (MediaService.trackTitle ?? "") + "|" + (MediaService.trackArtist ?? "")

        // En modo normal: evitar re-analizar la misma canción si ya tenemos BPM
        // En modo refresh: siempre re-analizar para captar cambios de ritmo
        if (!isRefresh && trackKey === root._lastAnalyzedTrack && root.apiBPM > 0) return
        root._lastAnalyzedTrack = trackKey

        // Captura más corta en modo refresh para respuesta rápida
        var captureSecs = isRefresh
            ? Math.max(3, Math.floor(root.bpmCaptureSecs * 0.6))
            : root.bpmCaptureSecs

        root._bpmDetectBuffer = ""
        root._bpmDetecting = true
        root._bpmDetectStartTime = Date.now()
        bpmDetectProc.command = ["bash", root.detectBpmScript, captureSecs.toString()]
        bpmDetectProc.running = false
        bpmDetectProc.running = true
        console.log("GIF Widget: Analizando audio (" + captureSecs + "s" + (isRefresh ? ", refresh" : "") + ")...")
    }

    // Re-analizar periódicamente si no se tiene BPM (solo cuando hay música)
    Timer {
        id: bpmRetryTimer
        interval: 15000  // reintentar cada 15s si no hay BPM
        repeat: true
        running: root.effectiveBPM <= 0 && root.isMusicPlaying
        onTriggered: {
            if (!root._bpmDetecting) {
                root._lastAnalyzedTrack = ""
                root.fetchBpmFromAudio(false)
            }
        }
    }

    // ── Actualización periódica de BPM mientras suena música ─────────────
    // Re-captura el BPM cada cierto tiempo para seguir cambios de ritmo
    // dentro de la misma canción (drops, breakdowns, cambios de tempo)
    Timer {
        id: bpmRefreshTimer
        interval: 20000  // re-analizar cada 20s para seguir cambios de ritmo
        repeat: true
        running: root.isMusicPlaying && root.effectiveBPM > 0
        onTriggered: {
            if (!root._bpmDetecting) {
                console.log("GIF Widget: Refrescando BPM en tiempo real...")
                root.fetchBpmFromAudio(true)  // true = refresh (captura corta)
            }
        }
    }

    // ── playerctl --follow: escucha cambios de pista en CUALQUIER app ─────
    // Se recupera automáticamente si playerctl no está instalado o falla
    property bool _playerctlAvailable: true

    Process {
        id: playerctlWatcher
        command: ["playerctl", "--player=%any", "--follow", "metadata",
                  "--format", "{{playerName}}|{{xesam:title}}|{{xesam:audioBPM}}"]
        running: root._playerctlAvailable
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split("|")
                if (parts.length < 3) return
                var bpm = parseFloat(parts[2])
                if (bpm > 0) {
                    root.detectedBPM = bpm
                } else {
                    root.detectedBPM = -1
                    // Canción nueva sin BPM en playerctl → analizar audio
                    if (root.isMusicPlaying) root.fetchBpmFromAudio(false)
                }
                // Canción nueva → resetear frame y arrancar animación
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                frameTicker.restart()
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                root._playerctlAvailable = false
                console.log("GIF Widget: playerctl no disponible (code " + code + "), usando solo detección de audio")
            }
        }
    }

    // ── Reaccionar a cambios de MediaService ──────────────────────────────
    Connections {
        target: MediaService
        function onCurrentPlayerChanged() {
            console.log("GIF Widget [" + widgetIndex + "]: Cambio de reproductor →",
                        MediaService.currentPlayer?.playerName ?? "none")
            root.detectedBPM = -1
            root._previousApiBPM = -1
            if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
            if (root.isMusicPlaying) {
                frameTicker.restart()
            }
        }
        function onIsPlayingChanged() {
            if (MediaService.isPlaying) {
                // Música reanudada → arrancar animación
                console.log("GIF Widget [" + widgetIndex + "]: Reproducción iniciada")
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                frameTicker.restart()
                // Si no hay BPM, lanzar detección
                if (root.effectiveBPM <= 0) root.fetchBpmFromAudio(false)
            } else {
                // Música pausada → congelar GIF inmediatamente
                console.log("GIF Widget [" + widgetIndex + "]: Reproducción pausada")
                frameTicker.stop()
            }
        }
        function onTrackTitleChanged() {
            console.log("GIF Widget [" + widgetIndex + "]: Canción nueva →",
                        MediaService.trackTitle ?? "unknown",
                        "|", MediaService.trackArtist ?? "unknown")
            root.detectedBPM = -1
            root.apiBPM = -1
            root._previousApiBPM = -1
            root._lastAnalyzedTrack = ""
            // Canción nueva → analizar audio del sistema
            // Esperar 3s para que la nueva canción empiece a sonar
            bpmDelayTimer.restart()
        }
    }

    // Timer para retrasar el análisis cuando cambia la canción
    // Espera a que la nueva canción empiece a sonar antes de capturar audio
    Timer {
        id: bpmDelayTimer
        interval: 3000  // 3 segundos de espera
        repeat: false
        running: false
        onTriggered: root.fetchBpmFromAudio(false)
    }

    // ══════════════════════════════════════════════════════════════════════
    // Display
    // ══════════════════════════════════════════════════════════════════════

    AnimatedImage {
        id: gifDisplay
        anchors.fill: parent
        source: root.gifUrl
        fillMode: AnimatedImage.PreserveAspectFit
        // SIEMPRE controlado manualmente por frameTicker
        // GIF congelado cuando no hay música — solo se mueve con canciones
        playing: false
        paused: true
        opacity: root.isMusicPlaying ? 1.0 : 0.4
        smooth: true
        cache: false
        asynchronous: true
        visible: root.gifReady

        Behavior on opacity { NumberAnimation { duration: 300 } }

        onStatusChanged: {
            if (status === AnimatedImage.Ready) {
                // Calcular FPS aproximado si no está configurado
                var calculatedFPS = root.gifBaseFPS
                if (frameCount > 0 && currentGif) {
                    // Intentar detectar FPS real observando el GIF
                    // La mayoría de GIFs tienen 30-60 FPS
                    // Si no hay metadatos, estimar basado en frameCount
                    try {
                        if (!pluginApi?.pluginSettings?.gifsMetadata || !pluginApi.pluginSettings.gifsMetadata[currentGif.filename]) {
                            // Estimación simple: la mayoría son 30fps
                            calculatedFPS = 30.0
                            console.log("GIF Widget [" + widgetIndex + "]: FPS no configurado, usando estimación:", calculatedFPS)
                        }
                    } catch(e) {}
                }
                
                console.log("GIF Widget [" + widgetIndex + "]: ✓",
                            currentGif?.name || "", "| frames:", frameCount,
                            "| FPS:", root.gifBaseFPS.toFixed(1),
                            "| BPM efectivo:", root.effectiveBPM,
                            "| gifBaseBPM:", root.gifBaseBPM,
                            "| rate:", root.playbackRate.toFixed(2) + "×",
                            "| interval:", root.frameInterval + "ms")
                currentFrame = 0
                if (root.isMusicPlaying) {
                    frameTicker.restart()
                }
            } else if (status === AnimatedImage.Error) {
                console.log("GIF Widget [" + widgetIndex + "]: ✗ Error al cargar:", root.gifUrl)
            }
        }
    }

    // Overlay - visible SOLO cuando no hay GIF asignado o hay error
    Rectangle {
        anchors.fill: parent
        visible: currentGif === null || gifDisplay.status === AnimatedImage.Error
        color: Qt.rgba(0.1, 0.1, 0.15, 0.95)

        ColumnLayout {
            anchors.centerIn: parent
            anchors.margins: scaledMargin
            spacing: Math.round(12 * widgetScale)
            width: Math.min(parent.width - scaledMargin * 2, Math.round(280 * widgetScale))

            // Icon
            NIcon {
                icon: "photo"
                color: Color.mPrimary
                Layout.alignment: Qt.AlignHCenter
                width: scaledIconSize
                height: scaledIconSize
            }

            // Widget info
            NText {
                Layout.fillWidth: true
                text: "Widget #" + (widgetIndex + 1)
                color: Color.mOnSurface
                opacity: 0.9
                pointSize: Math.round(Style.fontSizeM * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                font.weight: Font.DemiBold
            }

            // ── Selector de GIF (solo cuando NO hay GIF asignado) ──────
            ComboBox {
                id: gifSelector
                visible: currentGif === null && root.folderGifPaths.length > 0
                Layout.fillWidth: true
                Layout.preferredHeight: Math.round(40 * widgetScale)

                model: {
                    var items = ["-- Seleccionar GIF --"]
                    for (var i = 0; i < root.folderGifPaths.length; i++) {
                        var fp = root.folderGifPaths[i]
                        items.push(fp.split("/").pop())
                    }
                    return items
                }

                currentIndex: 0

                onActivated: function(index) {
                    if (index > 0) {
                        var filename = root.folderGifPaths[index - 1].split("/").pop()
                        root.assignGif(filename)
                    }
                }

                background: Rectangle {
                    color: Qt.rgba(1, 1, 1, 0.15)
                    radius: Style.radiusS
                    border.color: Color.mPrimary
                    border.width: 2
                }

                contentItem: NText {
                    text: gifSelector.displayText
                    color: Color.mOnSurface
                    pointSize: Math.round(Style.fontSizeM * widgetScale)
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                    elide: Text.ElideRight
                }
            }

            // No hay GIFs en la carpeta
            NText {
                visible: root.folderGifPaths.length === 0
                Layout.fillWidth: true
                text: "No hay GIFs\nAgrega archivos .gif desde Configuración"
                color: Color.mOnSurface
                opacity: 0.7
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // Error message
            NText {
                visible: currentGif !== null && gifDisplay.status === AnimatedImage.Error
                Layout.fillWidth: true
                text: "Error al cargar\nVerifica el archivo"
                color: "#e05555"
                opacity: 0.9
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }
        }
    }

    // Indicador de carga (cuando GIF está asignado pero aún no ha cargado)
    Rectangle {
        anchors.centerIn: parent
        width: Math.round(120 * widgetScale)
        height: Math.round(80 * widgetScale)
        visible: currentGif !== null && gifDisplay.status === AnimatedImage.Loading
        color: Qt.rgba(0, 0, 0, 0.7)
        radius: Math.round(Style.radiusM * widgetScale)

        ColumnLayout {
            anchors.centerIn: parent
            spacing: Math.round(8 * widgetScale)

            NIcon {
                icon: "hourglass"
                color: Color.mPrimary
                Layout.alignment: Qt.AlignHCenter
                opacity: 0.8
            }

            NText {
                text: "Cargando..."
                color: Color.mOnSurface
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                opacity: 0.8
            }
        }
    }
}
