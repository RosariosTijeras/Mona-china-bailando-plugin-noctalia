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

    // Initialize widgetData
    Component.onCompleted: {
        if (!widgetData) {
            widgetData = {}
        }
    }

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

    // Compatibilidad con Settings.qml: GIFs marcados como activos en settings
    // Si settings tiene GIFs activos solo se muestran esos (en orden).
    // Si settings está vacío o sin activos, se muestran TODOS los de la carpeta.
    property var activeGifs: {
        try {
            var fromSettings = []
            var allS = pluginApi?.pluginSettings?.gifs ?? []
            for (var i = 0; i < allS.length; i++) {
                var g = allS[i]
                if (g && g.active) fromSettings.push(g)
            }
            if (fromSettings.length > 0) return fromSettings
            // Fallback: usar todos los archivos de la carpeta
            var fromFolder = []
            for (var j = 0; j < folderGifPaths.length; j++) {
                var fp = folderGifPaths[j]
                var fname = fp.split("/").pop()
                fromFolder.push({ filename: fname, name: fname.replace(".gif","").replace(".GIF","") })
            }
            return fromFolder
        } catch(e) {
            console.log("GIF Widget: Error en activeGifs:", e)
            return []
        }
    }

    // GIF asignado a este widget según su índice
    property var currentGif: {
        try {
            if (activeGifs.length === 0) return null
            var index = widgetIndex % activeGifs.length
            return activeGifs[index]
        } catch(e) { return null }
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

    // El GIF está listo para mostrar
    property bool gifReady: gifDisplay.status === AnimatedImage.Ready && !root.isEditing && currentGif !== null

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
        try { return pluginApi?.pluginSettings?.gifFPS ?? 33.33 } catch(e) { return 33.33 }
    }

    readonly property real gifBaseBPM: {
        try { return pluginApi?.pluginSettings?.gifBPM ?? 120.0 } catch(e) { return 120.0 }
    }

    readonly property real manualBPM: {
        try { return pluginApi?.pluginSettings?.manualBPM ?? -1 } catch(e) { return -1 }
    }

    // API key de GetSongBPM (getsongbpm.com — gratis, 500 req/día)
    readonly property string bpmApiKey: {
        try { return pluginApi?.pluginSettings?.bpmApiKey ?? "" } catch(e) { return "" }
    }

    // BPM recibido de la API de GetSongBPM
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

    // BPM efectivo: MPRIS → API → playerctl → manual → -1
    readonly property real effectiveBPM: {
        if (mprisBPM    > 0) return mprisBPM
        if (apiBPM      > 0) return apiBPM
        if (detectedBPM > 0) return detectedBPM
        if (manualBPM   > 0) return manualBPM
        return -1
    }

    // playbackRate: qué tan rápido va el GIF respecto a su velocidad nativa
    readonly property real playbackRate: {
        if (effectiveBPM > 0) return Math.max(0.25, Math.min(effectiveBPM / gifBaseBPM, 4.0))
        return 1.0
    }

    // Duración de un beat en ms según el BPM efectivo
    readonly property real beatMs: effectiveBPM > 0 ? (60000.0 / effectiveBPM) : -1

    // Intervalo del timer de frames
    readonly property int frameInterval: Math.max(8, Math.round(1000.0 / (gifBaseFPS * playbackRate)))

    // ── Timer principal: avanza frames a la velocidad correcta ────────────
    Timer {
        id: frameTicker
        interval: root.frameInterval
        repeat: true
        running: root.gifReady && MediaService.isPlaying

        onTriggered: {
            if (gifDisplay.frameCount > 0)
                gifDisplay.currentFrame = (gifDisplay.currentFrame + 1) % gifDisplay.frameCount
        }
        onIntervalChanged: { if (running) restart() }
    }

    // ── Timer de sincronización al beat (como cat-jam: currentTime=0) ─────
    // Calcula la distancia al siguiente beat y resetea el GIF al frame 0
    // exactamente en ese momento, manteniendo el GIF en fase con la música.
    Timer {
        id: beatSyncTimer
        repeat: false
        running: false

        function schedule() {
            if (root.beatMs <= 0 || !MediaService.isPlaying) return
            // Posición actual en ms
            var posMs = (MediaService.currentPosition ?? 0) * 1000
            // Cuántos beats han pasado desde el inicio
            var beatsPassed = posMs / root.beatMs
            // Tiempo hasta el siguiente beat
            var msToNextBeat = root.beatMs * (Math.ceil(beatsPassed + 0.01) - beatsPassed)
            // Mínimo 10ms para no disparar inmediatamente
            interval = Math.max(10, Math.round(msToNextBeat))
            restart()
        }
    }

    // Cuando el beatSyncTimer dispara: resetear frame y programar el siguiente beat
    Connections {
        target: beatSyncTimer
        function onTriggered() {
            if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
            beatSyncTimer.schedule()
        }
    }

    // ── GetSongBPM API ────────────────────────────────────────────────────
    // Llama a https://api.getsong.co/search/ con título + artista.
    // Respuesta JSON: { "search": [ { "tempo": 128, "title": "...", ... } ] }
    property string _bpmApiBuffer: ""

    Process {
        id: bpmApiProc
        running: false
        // El comando se asigna dinámicamente antes de running = true
        stdout: SplitParser {
            onRead: function(line) {
                root._bpmApiBuffer += line
            }
        }
        onExited: function(code) {
            if (code !== 0 || root._bpmApiBuffer === "") {
                root._bpmApiBuffer = ""
                return
            }
            try {
                var data = JSON.parse(root._bpmApiBuffer)
                root._bpmApiBuffer = ""
                var results = data["search"]
                if (!results || results.length === 0) {
                    console.log("GIF Widget: GetSongBPM no encontró resultados")
                    return
                }
                var tempo = parseFloat(results[0]["tempo"])
                if (tempo > 0) {
                    root.apiBPM = tempo
                    console.log("GIF Widget: BPM obtenido de API:", tempo,
                                "para:", results[0]["title"] || "")
                    beatSyncTimer.schedule()
                    frameTicker.restart()
                }
            } catch(e) {
                root._bpmApiBuffer = ""
                console.log("GIF Widget: Error parseando respuesta API:", e)
            }
        }
    }

    function fetchBpmFromApi() {
        if (root.bpmApiKey === "") return
        var title  = MediaService.trackTitle  ?? ""
        var artist = MediaService.trackArtist ?? ""
        if (title === "") return
        root.apiBPM = -1
        root._bpmApiBuffer = ""
        // Formato "both" con prefijos song:/artist: para mayor precisión
        var lookup
        if (artist !== "") {
            lookup = encodeURIComponent("song:" + title + " artist:" + artist)
        } else {
            lookup = encodeURIComponent("song:" + title)
        }
        var url = "https://api.getsong.co/search/?api_key=" + root.bpmApiKey
                  + "&type=both&lookup=" + lookup
        bpmApiProc.command = ["curl", "-s", "--max-time", "8", url]
        bpmApiProc.running = false
        bpmApiProc.running = true
        console.log("GIF Widget: Consultando BPM para:", title, "-", artist)
    }

    // ── playerctl --follow: escucha cambios de pista en CUALQUIER app ─────
    Process {
        id: playerctlWatcher
        command: ["playerctl", "--player=%any", "--follow", "metadata",
                  "--format", "{{playerName}}|{{xesam:title}}|{{xesam:audioBPM}}"]
        running: true
        stdout: SplitParser {
            onRead: function(line) {
                var parts = line.trim().split("|")
                if (parts.length < 3) return
                var bpm = parseFloat(parts[2])
                if (bpm > 0) {
                    root.detectedBPM = bpm
                } else {
                    root.detectedBPM = -1
                    // Canción nueva sin BPM en playerctl → consultar API
                    root.fetchBpmFromApi()
                }
                // Canción nueva → resetear frame y replanificar beat
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                beatSyncTimer.schedule()
                frameTicker.restart()
            }
        }
    }

    // ── Reaccionar a cambios de MediaService ──────────────────────────────
    Connections {
        target: MediaService
        function onCurrentPlayerChanged() {
            root.detectedBPM = -1
            if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
            beatSyncTimer.schedule()
            frameTicker.restart()
        }
        function onIsPlayingChanged() {
            if (MediaService.isPlaying) {
                if (gifDisplay.frameCount > 0) gifDisplay.currentFrame = 0
                beatSyncTimer.schedule()
                frameTicker.restart()
            }
        }
        function onTrackTitleChanged() {
            root.detectedBPM = -1
            root.apiBPM = -1
            // Consultar API con el nuevo título
            root.fetchBpmFromApi()
            beatSyncTimer.schedule()
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
        playing: false   // controlado manualmente por frameTicker
        paused: true
        opacity: MediaService.isPlaying ? 1.0 : 0.4
        smooth: true
        cache: false
        asynchronous: true
        visible: root.gifReady

        Behavior on opacity { NumberAnimation { duration: 300 } }

        onStatusChanged: {
            if (status === AnimatedImage.Ready) {
                console.log("GIF Widget [" + widgetIndex + "]: ✓",
                            currentGif?.name || "", "| frames:", frameCount,
                            "| BPM efectivo:", root.effectiveBPM,
                            "| rate:", root.playbackRate.toFixed(2) + "×",
                            "| interval:", root.frameInterval + "ms")
                currentFrame = 0
                if (MediaService.isPlaying) {
                    frameTicker.restart()
                    beatSyncTimer.schedule()
                }
            } else if (status === AnimatedImage.Error) {
                console.log("GIF Widget [" + widgetIndex + "]: ✗ Error al cargar:", root.gifUrl)
            }
        }
    }

    // Overlay - SOLO visible cuando el GIF NO está listo
    Rectangle {
        anchors.fill: parent
        visible: !root.gifReady
        color: Qt.rgba(0.1, 0.1, 0.15, 0.95)
        radius: scaledRadius

        ColumnLayout {
            anchors.centerIn: parent
            anchors.margins: scaledMargin
            spacing: Math.round(12 * widgetScale)
            width: Math.min(parent.width - scaledMargin * 2, Math.round(300 * widgetScale))

            // Icon
            NIcon {
                icon: "photo"
                color: Color.mPrimary
                Layout.alignment: Qt.AlignHCenter
                width: scaledIconSize
                height: scaledIconSize
            }

            // Widget info (only in edit mode)
            NText {
                visible: root.isEditing && currentGif !== null
                Layout.fillWidth: true
                text: "Widget #" + (widgetIndex + 1) + "\n" + (currentGif?.name || "")
                color: Color.mOnSurface
                opacity: 0.9
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                font.weight: Font.DemiBold
            }

            // No active GIFs message
            NText {
                visible: root.activeGifs.length === 0
                Layout.fillWidth: true
                text: "No hay GIFs activos\nActiva GIFs en Configuración"
                color: Color.mOnSurface
                opacity: 0.7
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            // Loading message
            NText {
                visible: !root.isEditing && currentGif !== null && gifDisplay.status === AnimatedImage.Loading
                Layout.fillWidth: true
                text: "Cargando GIF..."
                color: Color.mOnSurface
                opacity: 0.6
                pointSize: Math.round(Style.fontSizeS * widgetScale)
                horizontalAlignment: Text.AlignHCenter
            }

            // Error message
            NText {
                visible: !root.isEditing && currentGif !== null && gifDisplay.status === AnimatedImage.Error
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
}
