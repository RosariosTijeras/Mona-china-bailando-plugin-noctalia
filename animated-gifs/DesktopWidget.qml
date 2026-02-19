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

    // GIF asignado a este widget específico (desde widgetData o JSON)
    // Cada widget puede tener un GIF diferente configurado independientemente
    property string _assignedGifFilename: ""
    property bool _configLoaded: false  // Flag para saber si ya cargó la config
    
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
                                console.log("GIF Widget [" + widgetIndex + "]: ✓ Config cargada desde JSON →", w.gifFilename)
                                _configLoaded = true
                                return
                            }
                        }
                        // No hay config para este widget en el JSON, usar widgetData
                        console.log("GIF Widget [" + widgetIndex + "]: Sin config en JSON para este widget")
                    }
                } catch(e) {
                    console.log("GIF Widget [" + widgetIndex + "]: Error parseando config:", e)
                }
                _configLoaded = true
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                console.log("GIF Widget [" + widgetIndex + "]: No se pudo leer widgets-config.json (code", code, "), usando widgetData")
            }
            _configLoaded = true
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
    
    // Inicializar widget
    Component.onCompleted: {
        // Preparar widgetData
        if (!widgetData) {
            widgetData = {}
        }
        
        // Intentar cargar desde JSON primero
        var configPath = pluginApi?.pluginDir + "/widgets-config.json"
        if (configPath && pluginApi?.pluginDir) {
            loadConfigProc.command = ["cat", configPath]
            loadConfigProc.running = true
            
            // Timeout: si no carga en 300ms, usar widgetData
            configLoadTimeoutTimer.start()
        } else {
            // No hay ruta de config, usar widgetData inmediatamente
            var fromWidgetData = widgetData?.gifFilename ?? ""
            if (fromWidgetData) {
                _assignedGifFilename = fromWidgetData
                console.log("GIF Widget [" + widgetIndex + "]: Sin ruta de config, usando widgetData →", fromWidgetData)
            }
            _configLoaded = true
        }
        
        console.log("GIF Widget [" + widgetIndex + "]: Inicializado")
        
        // Iniciar detección BPM en tiempo real (solo widget #0)
        if (widgetIndex === 0) {
            startBpmRealtime()
        }
    }
    
    // Timer para fallback si la carga JSON tarda mucho
    Timer {
        id: configLoadTimeoutTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!_configLoaded && !_assignedGifFilename) {
                // Timeout alcanzado, usar widgetData como fallback
                var fromWidgetData = widgetData?.gifFilename ?? ""
                if (fromWidgetData) {
                    _assignedGifFilename = fromWidgetData
                    console.log("GIF Widget [" + widgetIndex + "]: Timeout, usando widgetData →", fromWidgetData)
                }
                _configLoaded = true
            }
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
            // Intentar obtener FPS específico del GIF actual desde metadatos
            if (currentGif && pluginApi?.pluginSettings?.gifsMetadata) {
                var filename = currentGif.filename || (_assignedGifFilename || "")
                var metadata = pluginApi.pluginSettings.gifsMetadata[filename]
                if (metadata && metadata.fps > 0) {
                    console.log("GIF Widget [" + widgetIndex + "]: Usando FPS detectado →", metadata.fps, "para", filename)
                    return metadata.fps
                }
            }
            // Fallback conservador: 20 FPS (el más bajo de tus GIFs)
            return 20.0
        } catch(e) { return 20.0 }
    }

    // gifBaseBPM: BPM al que el GIF fue diseñado para ir a velocidad 1×
    // 100 BPM = velocidad natural. Si la canción tiene 150 BPM, el GIF irá a 1.5×
    readonly property real gifBaseBPM: {
        try { return pluginApi?.pluginSettings?.gifBPM ?? 100.0 } catch(e) { return 100.0 }
    }

    readonly property real manualBPM: {
        try { return pluginApi?.pluginSettings?.manualBPM ?? -1 } catch(e) { return -1 }
    }

    // ── BPM detectado en tiempo real via bpm-realtime.py ─────────────────
    // El script Python corre como proceso persistente, captura audio del
    // sistema via PipeWire/PulseAudio + aubio.tempo y emite "BPM:XXX.X"
    // por stdout en cada beat detectado. Funciona con CUALQUIER fuente:
    // Spotify, YouTube, VLC, Firefox, etc.
    property real realtimeBPM: -1   // BPM del proceso Python en tiempo real
    property real detectedBPM: -1   // BPM de playerctl (fallback)
    property bool _bpmProcessReady: false  // Script listo para detectar

    // Sistema de interpolación suave de BPM
    property real _currentBPM: 100.0  // BPM actual interpolado (ritmo medio)
    property real _targetBPM: 100.0   // BPM objetivo al que interpolar
    property real _previousBPM: 100.0 // BPM anterior para transición
    property real _transitionProgress: 1.0  // 0.0 = inicio, 1.0 = completo

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

    // BPM efectivo: MPRIS → tiempo real → playerctl → manual → BPM interpolado
    readonly property real effectiveBPM: {
        if (mprisBPM     > 0) return mprisBPM
        if (realtimeBPM  > 0) return _currentBPM   // BPM interpolado suavemente
        if (detectedBPM  > 0) return detectedBPM
        if (manualBPM    > 0) return manualBPM
        return _currentBPM  // Ritmo medio si no hay detección
    }

    // Cuando cambia el BPM efectivo, ajustar velocidad del GIF
    onEffectiveBPMChanged: {
        if (effectiveBPM > 0 && isMusicPlaying && gifReady) {
            frameTicker.restart()
        }
    }

    // playbackRate: qué tan rápido va el GIF respecto a su velocidad nativa
    // Formula: trackBPM / gifBaseBPM. Si canción=150 y base=100, rate=1.5×
    // Rango: 0.4× (canción lenta) a 2.0× (canción rápida)
    readonly property real playbackRate: {
        if (effectiveBPM > 0) {
            var rate = effectiveBPM / gifBaseBPM
            return Math.max(0.4, Math.min(rate, 2.0))
        }
        return 1.0
    }

    // Intervalo del timer de frames
    readonly property int frameInterval: Math.max(8, Math.round(1000.0 / (gifBaseFPS * playbackRate)))

    // ── Timer principal: avanza frames a la velocidad correcta ────────────
    Timer {
        id: frameTicker
        interval: root.frameInterval
        repeat: true
        running: root.gifReady && root.isMusicPlaying
        onTriggered: {
            if (gifDisplay.frameCount > 0)
                gifDisplay.currentFrame = (gifDisplay.currentFrame + 1) % gifDisplay.frameCount
        }
        onIntervalChanged: { if (running) restart() }
    }

    // ── Estado de reproducción de música ──────────────────────────────────
    readonly property bool isMusicPlaying: MediaService.isPlaying

    onIsMusicPlayingChanged: {
        console.log("GIF Widget [" + widgetIndex + "]: isMusicPlaying →", isMusicPlaying,
                    "| Player:", MediaService.currentPlayer?.playerName ?? "none")
        if (isMusicPlaying) {
            frameTicker.restart()
        } else {
            console.log("GIF Widget [" + widgetIndex + "]: Música pausada")
            frameTicker.stop()
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // DETECCIÓN BPM EN TIEMPO REAL — Proceso Python persistente
    // ══════════════════════════════════════════════════════════════════════
    // bpm-realtime.py corre continuamente, captura audio del sistema y
    // emite líneas "BPM:XXX.X" por stdout en cada beat. No necesita
    // grabar archivos WAV ni lanzar procesos periódicos.

    readonly property string bpmRealtimeScript: {
        try {
            if (!pluginApi || !pluginApi.pluginDir) return ""
            return pluginApi.pluginDir + "/bpm-realtime.py"
        } catch(e) { return "" }
    }

    Process {
        id: bpmRealtimeProc
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                var trimmed = line.trim()

                // Parsear mensajes del script
                if (trimmed.startsWith("BPM:")) {
                    var bpmStr = trimmed.substring(4)
                    var bpm = parseFloat(bpmStr)
                    if (bpm > 0 && bpm < 300) {
                        // Iniciar transición suave al nuevo BPM
                        root._previousBPM = root._currentBPM
                        root._targetBPM = bpm
                        root._transitionProgress = 0.0
                        root.realtimeBPM = bpm
                    }
                } else if (trimmed === "READY") {
                    root._bpmProcessReady = true
                    console.log("GIF Widget [" + widgetIndex + "]: ✓ BPM realtime → LISTO")
                } else if (trimmed.startsWith("DEVICE:")) {
                    console.log("GIF Widget [" + widgetIndex + "]: Audio device →", trimmed.substring(7))
                } else if (trimmed.startsWith("ERROR:")) {
                    console.log("GIF Widget [" + widgetIndex + "]: BPM error →", trimmed)
                }
            }
        }
        onExited: function(code) {
            console.log("GIF Widget [" + widgetIndex + "]: bpm-realtime.py terminó (code", code, ")")
            root._bpmProcessReady = false
            // Auto-reiniciar si se cayó inesperadamente y sigue reproduciéndose música
            if (root.isMusicPlaying && code !== 0) {
                bpmRestartTimer.start()
            }
        }
    }

    // Timer para reiniciar el proceso Python si se cae
    Timer {
        id: bpmRestartTimer
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.isMusicPlaying && !bpmRealtimeProc.running) {
                console.log("GIF Widget [" + widgetIndex + "]: Reiniciando bpm-realtime.py...")
                root.startBpmRealtime()
            }
        }
    }

    function startBpmRealtime() {
        if (bpmRealtimeScript === "") return
        // Solo el widget #0 lanza la detección (evita múltiples procesos)
        if (typeof widgetIndex !== "undefined" && widgetIndex !== 0) return
        if (bpmRealtimeProc.running) return

        console.log("GIF Widget [" + widgetIndex + "]: Iniciando bpm-realtime.py")
        bpmRealtimeProc.command = ["python3", bpmRealtimeScript]
        bpmRealtimeProc.running = true
    }

    function stopBpmRealtime() {
        if (bpmRealtimeProc.running) {
            console.log("GIF Widget [" + widgetIndex + "]: Deteniendo bpm-realtime.py")
            bpmRealtimeProc.running = false
        }
    }

    // ── Interpolación suave entre BPMs (transición gradual) ───────────────────
    Timer {
        id: bpmTransitionTimer
        interval: 33  // ~30 FPS de interpolación
        repeat: true
        running: root._transitionProgress < 1.0 && root.isMusicPlaying
        onTriggered: {
            root._transitionProgress = Math.min(1.0, root._transitionProgress + 0.05)
            root._currentBPM = root._previousBPM + (root._targetBPM - root._previousBPM) * root._transitionProgress
        }
    }

    // ── playerctl --follow: escucha cambios de pista (fallback) ───────────
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
                }
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                frameTicker.restart()
            }
        }
        onExited: function(code) {
            if (code !== 0) {
                root._playerctlAvailable = false
                console.log("GIF Widget: playerctl no disponible (code " + code + ")")
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
            if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
            if (root.isMusicPlaying) {
                frameTicker.restart()
            }
        }
        function onIsPlayingChanged() {
            if (MediaService.isPlaying) {
                console.log("GIF Widget [" + widgetIndex + "]: Reproducción iniciada")
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                frameTicker.restart()
                // Iniciar detección BPM en tiempo real
                root.startBpmRealtime()
            } else {
                console.log("GIF Widget [" + widgetIndex + "]: Reproducción pausada")
                frameTicker.stop()
                // No detener el proceso Python — es ligero y se recupera solo
            }
        }
        function onTrackTitleChanged() {
            console.log("GIF Widget [" + widgetIndex + "]: Canción nueva →",
                        MediaService.trackTitle ?? "unknown",
                        "|", MediaService.trackArtist ?? "unknown")
            root.detectedBPM = -1
            // Resetear a ritmo medio al cambiar canción
            root._currentBPM = 100.0
            root._targetBPM = 100.0
            root._previousBPM = 100.0
            root._transitionProgress = 1.0
            // El proceso Python detectará el nuevo BPM automáticamente en ~1-2s
        }
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
