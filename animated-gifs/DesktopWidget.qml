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

    // Lo inyecta Noctalia al montar el widget
    property var pluginApi: null

    // Tamaño por defecto, el usuario puede redimensionar
    implicitWidth: Math.round(300 * widgetScale)
    implicitHeight: Math.round(300 * widgetScale)

    // Sin fondo
    showBackground: false

    // ── Carpeta de GIFs ────────────────────────────────────────────────────
    // Ruta donde están los GIFs descargados
    readonly property string gifsFolder: {
        try {
            if (!pluginApi || !pluginApi.pluginDir) return ""
            return pluginApi.pluginDir + "/gifs"
        } catch(e) { return "" }
    }

    // Escanea la carpeta en tiempo real — cualquier .gif que aparezca se carga solo
    FolderListModel {
        id: gifFolderModel
        folder: root.gifsFolder ? ("file://" + root.gifsFolder) : ""
        nameFilters: ["*.gif", "*.GIF"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name

        // Cada vez que aparece un archivo nuevo en la carpeta (independientemente
        // de si el panel de configuración está abierto o no), lo procesamos.
        // Solo el widget #0 lo hace para no lanzar el script varias veces.
        onCountChanged: {
            if (widgetIndex === 0 && root.pluginApi) {
                root.queueMissingMetadataDetection()
            }
        }
    }

    // Cola de GIFs pendientes de detectar metadatos
    property var _detectQueue: []
    property bool _detecting: false

    // Proceso que detecta fps/frames/duration de un GIF concreto
    Process {
        id: autoDetectProc
        running: false
        property string targetFilename: ""
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split("|")
                var fps      = parseFloat(parts[0])
                var frames   = parts.length > 1 ? parseInt(parts[1])   : 0
                var duration = parts.length > 2 ? parseFloat(parts[2]) : 0
                if (fps > 0) {
                    try {
                        if (!pluginApi.pluginSettings.gifsMetadata)
                            pluginApi.pluginSettings.gifsMetadata = {}
                        pluginApi.pluginSettings.gifsMetadata[autoDetectProc.targetFilename] = {
                            fps:      fps,
                            frames:   frames   > 0 ? frames   : undefined,
                            duration: duration > 0 ? duration : undefined
                        }
                        pluginApi.saveSettings()
                        console.log("GIF Widget: metadatos guardados →",
                            autoDetectProc.targetFilename,
                            fps.toFixed(2) + " FPS",
                            frames > 0   ? "· " + frames + " frames" : "",
                            duration > 0 ? "· " + duration.toFixed(2) + "s" : "")
                    } catch(e) {}
                }
            }
        }
        onExited: function() {
            root._detecting = false
            // Procesar el siguiente de la cola si hay
            root.processDetectQueue()
        }
    }

    // Encola todos los GIFs sin metadatos y arranca la cola
    function queueMissingMetadataDetection() {
        Qt.callLater(function() {
            if (!pluginApi || !pluginApi.pluginSettings) return
            var metadata = pluginApi.pluginSettings.gifsMetadata || {}
            for (var i = 0; i < gifFolderModel.count; i++) {
                var fp = gifFolderModel.get(i, "filePath")
                if (!fp) continue
                var filename = fp.split("/").pop()
                // Solo encolar si no tiene metadatos y no está ya en la cola
                if (!metadata[filename] && _detectQueue.indexOf(filename) === -1) {
                    var queue = _detectQueue.slice()
                    queue.push(filename)
                    _detectQueue = queue
                    console.log("GIF Widget: encolado para detectar →", filename)
                }
            }
            processDetectQueue()
        })
    }

    // Saca el siguiente de la cola y lanza la detección
    function processDetectQueue() {
        if (_detecting || _detectQueue.length === 0) return
        var queue = _detectQueue.slice()
        var filename = queue.shift()
        _detectQueue = queue
        _detecting = true

        var scriptPath = pluginApi?.pluginDir + "/detect-gif-fps.sh"
        var gifPath    = pluginApi?.pluginDir + "/gifs/" + filename
        autoDetectProc.targetFilename = filename
        autoDetectProc.command = ["bash", scriptPath, gifPath]
        autoDetectProc.running = true
        console.log("GIF Widget: detectando metadatos de →", filename)
    }

    // Rutas absolutas de todos los GIFs que hay en la carpeta
    property var folderGifPaths: {
        var paths = []
        for (var i = 0; i < gifFolderModel.count; i++) {
            var fp = gifFolderModel.get(i, "filePath")
            if (fp) paths.push(fp)
        }
        return paths
    }

    // El GIF que le toca a este widget (viene de widgetData o del JSON)
    // Cada widget tiene el suyo, se pueden poner GIFs distintos en cada uno
    property string _assignedGifFilename: ""
    property bool _configLoaded: false  // Para saber si ya terminó de leer la config
    
    // Carga el archivo JSON con la config guardada de los widgets
    Process {
        id: loadConfigProc
        running: false
        stdout: SplitParser {
            onRead: function(line) {
                try {
                    var config = JSON.parse(line)
                    if (config && config.widgets) {
                        // Buscar la entrada de este widget en el JSON
                        for (var i = 0; i < config.widgets.length; i++) {
                            var w = config.widgets[i]
                            if (w.index === widgetIndex && w.gifFilename) {
                                _assignedGifFilename = w.gifFilename
                                console.log("GIF Widget [" + widgetIndex + "]: ✓ Config cargada desde JSON →", w.gifFilename)
                                _configLoaded = true
                                return
                            }
                        }
                        // Este widget no tiene entrada en el JSON, tiro de widgetData
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
    
    // Guarda el GIF asignado en el JSON de persistencia
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
    
    // Si widgetData cambia desde afuera, actualizo el GIF asignado
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
    
    // Al arrancar, cargo la config y pongo todo en marcha
    Component.onCompleted: {
        // Me aseguro de que widgetData sea un objeto
        if (!widgetData) {
            widgetData = {}
        }
        
        // Primero intento leer del JSON (es la fuente fiable)
        var configPath = pluginApi?.pluginDir + "/widgets-config.json"
        if (configPath && pluginApi?.pluginDir) {
            loadConfigProc.command = ["cat", configPath]
            loadConfigProc.running = true
            
            // Si en 300ms no llegó nada, uso widgetData de todos modos
            configLoadTimeoutTimer.start()
        } else {
            // No tengo ruta del plugin, tiro de widgetData directamente
            var fromWidgetData = widgetData?.gifFilename ?? ""
            if (fromWidgetData) {
                _assignedGifFilename = fromWidgetData
                console.log("GIF Widget [" + widgetIndex + "]: Sin ruta de config, usando widgetData →", fromWidgetData)
            }
            _configLoaded = true
        }
        
        console.log("GIF Widget [" + widgetIndex + "]: Inicializado")
        
        // Solo el widget 0 hace estas tareas de fondo
        if (widgetIndex === 0) {
            startBpmRealtime()
            // Detectar metadatos de GIFs que no los tengan aún
            queueMissingMetadataDetection()
        }
    }
    
    // Si el JSON tarda más de 300ms, bajo a widgetData y sigo
    Timer {
        id: configLoadTimeoutTimer
        interval: 300
        repeat: false
        onTriggered: {
            if (!_configLoaded && !_assignedGifFilename) {
                // Se acabó el tiempo, uso widgetData y listo
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
            // Si tiene un GIF configurado, verifico que el archivo siga existiendo
            if (_assignedGifFilename !== "") {
                for (var i = 0; i < folderGifPaths.length; i++) {
                    if (folderGifPaths[i].endsWith("/" + _assignedGifFilename)) {
                        return { filename: _assignedGifFilename, name: _assignedGifFilename.replace(/\.gif$/i, "") }
                    }
                }
                // Ya no está el archivo, probablemente lo borraron
                console.log("GIF Widget: Archivo asignado no encontrado:", _assignedGifFilename)
            }
            // Sin GIF asignado → en modo edición aparece el selector
            return null
        } catch(e) { return null }
    }

    // Asigna un GIF a este widget y lo guarda
    function assignGif(filename) {
        console.log("GIF Widget [" + widgetIndex + "]: assignGif() llamado con →", filename)
        
        _assignedGifFilename = filename
        
        // Lo meto también en widgetData por si acaso
        var newData = {}
        if (widgetData) {
            for (var key in widgetData) {
                newData[key] = widgetData[key]
            }
        }
        newData.gifFilename = filename
        widgetData = newData
        
        // Y lo persisto en el JSON para que no se pierda al reiniciar
        var scriptPath = pluginApi?.pluginDir + "/save-widget-config.sh"
        if (scriptPath && pluginApi?.pluginDir) {
            saveConfigProc.command = ["bash", scriptPath, widgetIndex.toString(), filename]
            saveConfigProc.running = true
        }
        
        console.log("GIF Widget [" + widgetIndex + "]: GIF asignado →", filename)
    }

    // URL completa del GIF para pasarle al AnimatedImage
    property string gifUrl: {
        try {
            if (!currentGif) return ""
            if (!pluginApi || !pluginApi.pluginDir) return ""
            var filename = currentGif.filename || currentGif.name + ".gif"
            return "file://" + pluginApi.pluginDir + "/gifs/" + filename
        } catch(e) { return "" }
    }

    // El GIF cargó bien y hay uno asignado
    property bool gifReady: gifDisplay.status === AnimatedImage.Ready && currentGif !== null

    // Hay GIFs en la carpeta pero este widget no tiene ninguno asignado
    property bool needsGifSelection: folderGifPaths.length > 0 && currentGif === null

    // Valores escalados según el zoom del widget
    readonly property int scaledRadius: Math.round(Style.radiusM * widgetScale)
    readonly property int scaledMargin: Math.round(16 * widgetScale)
    readonly property int scaledIconSize: Math.round(48 * widgetScale)

    // ══════════════════════════════════════════════════════════════════════
    // Sincronización BPM
    //
    // La velocidad del GIF depende del BPM de la canción:
    //   frameInterval = 1000 / (gifBaseFPS * playbackRate)
    //   playbackRate  = effectiveBPM / gifBaseBPM
    //
    // Igual que cat-jam: calculamos en qué momento cae el siguiente beat
    // y reseteamos el GIF al frame 0 justo en ese momento.
    // ══════════════════════════════════════════════════════════════════════

    readonly property real gifBaseFPS: {
        try {
            // Uso el FPS que detectó ffprobe para este GIF concreto
            if (currentGif && pluginApi?.pluginSettings?.gifsMetadata) {
                var filename = currentGif.filename || (_assignedGifFilename || "")
                var metadata = pluginApi.pluginSettings.gifsMetadata[filename]
                if (metadata && metadata.fps > 0) {
                    console.log("GIF Widget [" + widgetIndex + "]: Usando FPS detectado →", metadata.fps, "para", filename)
                    return metadata.fps
                }
            }
            // Si no hay metadatos, 20 FPS es un valor seguro para la mayoría de GIFs
            return 20.0
        } catch(e) { return 20.0 }
    }

    // BPM al que el GIF va a velocidad 1×. Con 100 BPM en la canción —> playbackRate = 1.0
    // Si la canción va a 150 BPM el GIF irá a 1.5×
    readonly property real gifBaseBPM: {
        try { return pluginApi?.pluginSettings?.gifBPM ?? 100.0 } catch(e) { return 100.0 }
    }

    readonly property real manualBPM: {
        try { return pluginApi?.pluginSettings?.manualBPM ?? -1 } catch(e) { return -1 }
    }

    // ── BPM en tiempo real desde bpm-realtime.py ───────────────────────────────────
    // El script Python está corriendo en segundo plano todo el tiempo.
    // Captura el audio del sistema (PipeWire/PulseAudio + aubio) y va
    // mandando "BPM:XXX.X" por stdout en cada beat que detecta.
    // Funciona con Spotify, YouTube, VLC, lo que sea.
    property real realtimeBPM: -1   // BPM que está mandando el script ahora mismo
    property real detectedBPM: -1   // BPM de playerctl (por si acaso)
    property bool _bpmProcessReady: false  // El script terminó de arrancar y está escuchando

    // Interpolación suave entre BPMs para que no haya saltos bruscos
    property real _currentBPM: 100.0  // BPM en el que estamos ahora mismo
    property real _targetBPM: 100.0   // BPM al que queremos llegar
    property real _previousBPM: 100.0 // El BPM anterior para interpolar desde ahí
    property real _transitionProgress: 1.0  // 0 = acaba de empezar, 1 = ya llegó

    // Buffer para el filtro de mediana rodante.
    // Aubio con audio orquestal manda valores muy irregulares (e.g. 93 → 176 → 92).
    // Guardamos las últimas 7 lecturas y usamos la mediana — los spikes desaparecen solos.
    property var _bpmBuffer: []
    property int _bpmBufferSize: 7

    // Aplica corrección de doblado y devuelve la mediana del buffer.
    function processBpm(rawBpm) {
        // Corrección de doblado: aubio a veces detecta 2× el tempo real.
        // Si el valor nuevo es ~2× el BPM suavizado actual, lo dividimos.
        var ref = (_currentBPM > 0) ? _currentBPM : 100.0
        if (rawBpm > ref * 1.75 && rawBpm < ref * 2.25) {
            rawBpm = rawBpm / 2.0
        }

        // Meter en el buffer y recortarlo al tamaño máximo
        var buf = _bpmBuffer.slice()
        buf.push(rawBpm)
        if (buf.length > _bpmBufferSize) buf.shift()
        _bpmBuffer = buf

        // Calcular mediana
        var sorted = buf.slice().sort(function(a, b) { return a - b })
        var mid = Math.floor(sorted.length / 2)
        return (sorted.length % 2 === 0)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }

    // BPM sacado de los metadatos MPRIS (raro que esté, pero por si acaso)
    readonly property real mprisBPM: {
        try {
            var meta = MediaService.currentPlayer?.metadata
            if (!meta) return -1
            var bpm = meta["xesam:audioBPM"] ?? meta["xesam:bpm"] ?? -1
            var n = Number(bpm)
            return (n > 0) ? n : -1
        } catch(e) { return -1 }
    }

    // El BPM que se usa en realidad: MPRIS > tiempo real > playerctl > manual > por defecto
    readonly property real effectiveBPM: {
        if (mprisBPM     > 0) return mprisBPM
        if (realtimeBPM  > 0) return _currentBPM   // BPM interpolado suavemente
        if (detectedBPM  > 0) return detectedBPM
        if (manualBPM    > 0) return manualBPM
        return _currentBPM  // Ritmo medio si no hay detección
    }

    // Cuando cambia el BPM, reinicio el timer para que se aplique ya
    onEffectiveBPMChanged: {
        if (effectiveBPM > 0 && isMusicPlaying && gifReady) {
            frameTicker.restart()
        }
    }

    // playbackRate: qué tan rápido va el GIF respecto a su velocidad normal
    // Ej: canción a 150 BPM con base 100 BPM —> 1.5× de velocidad
    // Con BPM en tiempo real activo uso un rango más amplio (0.25×–2.8×) para
    // que el usuario realmente note la diferencia entre canciones lentas y rápidas.
    // Sin detección en tiempo real, rango conservador (0.4×–2.0×).
    readonly property real playbackRate: {
        if (effectiveBPM > 0) {
            var rate = effectiveBPM / gifBaseBPM
            if (realtimeBPM > 0) {
                // Rango ampliado cuando el BPM viene del script Python
                return Math.max(0.25, Math.min(rate, 2.8))
            }
            return Math.max(0.4, Math.min(rate, 2.0))
        }
        return 1.0
    }

    // Cuántos ms entre frame y frame
    readonly property int frameInterval: Math.max(8, Math.round(1000.0 / (gifBaseFPS * playbackRate)))

    // ── El timer que avanza los frames del GIF ────────────────────────────────────
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
    // DETECIÓN BPM EN TIEMPO REAL
    // ════════════════════════════════════════════════════════════════════
    // bpm-realtime.py corre sin parar, captura el audio y manda beats por stdout.
    // No hay archivos WAV, no hay procesos intermedios, simplemente funciona.

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
                        // Filtrar con mediana y corregir doblado antes de aplicar
                        var smoothed = root.processBpm(bpm)
                        root._previousBPM = root._currentBPM
                        root._targetBPM = smoothed
                        root._transitionProgress = 0.0
                        root.realtimeBPM = smoothed
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
            // Si se cayó con error y sigue la música, lo reinicio en 3s
            if (root.isMusicPlaying && code !== 0) {
                bpmRestartTimer.start()
            }
        }
    }

    // Si el proceso Python muere, lo levanto de nuevo después de 3s
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
        // Solo el widget 0 hace esto, aquí los demás no hacen nada
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

    // ── Transición suave entre BPMs ───────────────────────────────────────────────
    Timer {
        id: bpmTransitionTimer
        interval: 33  // ~30 fps de interpolación
        repeat: true
        running: root._transitionProgress < 1.0 && root.isMusicPlaying
        onTriggered: {
            // 3% por tick → ~1s para completar la transición
            // Más lento que antes (5%) para que los saltos de aubio no sean bruscos
            root._transitionProgress = Math.min(1.0, root._transitionProgress + 0.03)
            root._currentBPM = root._previousBPM + (root._targetBPM - root._previousBPM) * root._transitionProgress
        }
    }

    // ── playerctl --follow: escucha cambios de pista, trae BPM si lo tiene ─────────────
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

    // ── Reacciones a eventos de MediaService ───────────────────────────────────────
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
                // No paro el Python — es liviano y cuando vuelva la música ya está listo
            }
        }
        function onTrackTitleChanged() {
            console.log("GIF Widget [" + widgetIndex + "]: Canción nueva →",
                        MediaService.trackTitle ?? "unknown",
                        "|", MediaService.trackArtist ?? "unknown")
            root.detectedBPM = -1
            // Vuelvo al ritmo por defecto al cambiar de canción
            root._currentBPM = 100.0
            root._targetBPM = 100.0
            root._previousBPM = 100.0
            root._transitionProgress = 1.0
            // Limpiar el buffer de mediana para que la canción nueva empiece sin historial
            root._bpmBuffer = []
            // El script Python detectará el nuevo BPM en ~1-2s, no hay que hacer nada más
        }
    }

    // ══════════════════════════════════════════════════════════════════════
    // Zona visual
    // ══════════════════════════════════════════════════════════════════════

    AnimatedImage {
        id: gifDisplay
        anchors.fill: parent
        source: root.gifUrl
        fillMode: AnimatedImage.PreserveAspectFit
        // frameTicker lleva el control, no dejo que Qt lo mueva solo
        // Si no hay música el GIF queda quieto (se ve atenuado al 40%)
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
                // Si no hay metadatos de FPS, tiro una estimación rápida
                var calculatedFPS = root.gifBaseFPS
                if (frameCount > 0 && currentGif) {
                    // La mayoría de GIFs van a 30fps, sirve como base
                    try {
                        if (!pluginApi?.pluginSettings?.gifsMetadata || !pluginApi.pluginSettings.gifsMetadata[currentGif.filename]) {
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

    // Fondo oscuro que aparece cuando no hay GIF o hay un error de carga
    Rectangle {
        anchors.fill: parent
        visible: currentGif === null || gifDisplay.status === AnimatedImage.Error
        color: Qt.rgba(0.1, 0.1, 0.15, 0.95)

        ColumnLayout {
            anchors.centerIn: parent
            anchors.margins: scaledMargin
            spacing: Math.round(12 * widgetScale)
            width: Math.min(parent.width - scaledMargin * 2, Math.round(280 * widgetScale))

            // Icono
            NIcon {
                icon: "photo"
                color: Color.mPrimary
                Layout.alignment: Qt.AlignHCenter
                width: scaledIconSize
                height: scaledIconSize
            }

            // Título del widget
            NText {
                Layout.fillWidth: true
                text: "Widget #" + (widgetIndex + 1)
                color: Color.mOnSurface
                opacity: 0.9
                pointSize: Math.round(Style.fontSizeM * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                font.weight: Font.DemiBold
            }

            // ── Selector de GIF (solo cuando el widget no tiene ninguno asignado) ──────
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

            // Aviso de que no hay GIFs descargados todavía
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

            // Mensaje de error si el archivo no cargó bien
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

    // Spinner de carga mientras el GIF todavía no ha terminado de cargarse
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
