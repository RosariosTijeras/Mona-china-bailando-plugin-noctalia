import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import qs.Commons
import qs.Widgets
import qs.Services.UI

ColumnLayout {
    id: root
    spacing: Style.marginL

    property var pluginApi: null

    // ── Carpeta de GIFs ────────────────────────────────────────────────────
    readonly property string gifsFolder: {
        try {
            if (!pluginApi || !pluginApi.pluginDir) return ""
            return pluginApi.pluginDir + "/gifs"
        } catch(e) { return "" }
    }

    // Recarga sola cuando cambia algo en la carpeta
    FolderListModel {
        id: gifFolderModel
        folder: root.gifsFolder ? ("file://" + root.gifsFolder) : ""
        nameFilters: ["*.gif", "*.GIF"]
        showDirs: false
        showDotAndDotDot: false
        showHidden: false
        sortField: FolderListModel.Name
    }

    // Solo los nombres, no las rutas completas
    property var folderFiles: {
        var files = []
        for (var i = 0; i < gifFolderModel.count; i++) {
            var fp = gifFolderModel.get(i, "filePath")
            if (fp) files.push(fp.split("/").pop())
        }
        return files
    }

    function deleteGif(filename) {
        // Borra el archivo y avisa al usuario
        deleteProc.command = ["rm", "-f", gifsFolder + "/" + filename]
        deleteProc.running = true
        ToastService.showNotice(filename + " eliminado")
    }

    Process {
        id: mkdirProc
        running: false
    }

    Process {
        id: deleteProc
        running: false
    }

    // Copia el GIF a la carpeta. La detección de metadatos la hace DesktopWidget
    // automáticamente al detectar el archivo nuevo via FolderListModel.onCountChanged
    Process {
        id: copyProc
        property string targetFilename: ""
        running: false
        onExited: function(code) {
            if (code === 0) {
                ToastService.showNotice("GIF agregado: " + targetFilename + " — detectando metadatos...")
            } else {
                ToastService.showNotice("Error al copiar archivo")
            }
        }
    }

    // Para abrir dolphin
    Process {
        id: openFolderProc
        running: false
    }

    function addGifFromPath(srcPath) {
        if (srcPath === "" || (!srcPath.toLowerCase().endsWith(".gif"))) {
            ToastService.showNotice("El archivo debe ser .gif")
            return false
        }

        var filename = srcPath.split("/").pop()
        var destPath = root.gifsFolder + "/" + filename

        copyProc.targetFilename = filename
        copyProc.command = ["cp", srcPath, destPath]
        copyProc.running = true
        // DesktopWidget detectará el GIF nuevo via onCountChanged y detectará sus metadatos
        return true
    }

    Component.onCompleted: {
        // Valores por defecto si no están ya guardados
        if (!pluginApi.pluginSettings.gifFPS) {
            pluginApi.pluginSettings.gifFPS = 33.33
        }
        if (!pluginApi.pluginSettings.gifBPM) {
            pluginApi.pluginSettings.gifBPM = 120.0
        }
        if (pluginApi.pluginSettings.manualBPM === undefined) {
            pluginApi.pluginSettings.manualBPM = -1
        }
        if (pluginApi.pluginSettings.bpmCaptureSecs === undefined) {
            pluginApi.pluginSettings.bpmCaptureSecs = 5
        }
        if (!pluginApi.pluginSettings.gifsMetadata) {
            pluginApi.pluginSettings.gifsMetadata = {}
        }
        // Creo la carpeta gifs/ si no existe
        mkdirProc.command = ["mkdir", "-p", pluginApi.pluginDir + "/gifs"]
        mkdirProc.running = true
    }

    // ══════════════════════════════════════════════════════════════════════
    // Interfaz
    // ══════════════════════════════════════════════════════════════════════

    NText {
        text: "GIF Widget"
        pointSize: Style.fontSizeL
        font.weight: Font.Bold
        color: Color.mOnSurface
    }

    NText {
        text: "Agrega GIFs aquí, luego en cada widget (modo edición) elige qué GIF mostrar. Los widgets SIEMPRE recordarán su GIF asignado."
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
 opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    NDivider { Layout.fillWidth: true }

    // ── BPM Sync ──────────────────────────────────────────────────────────
    NText {
        text: "Sincronización BPM"
        pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
    }

    NText {
        text: "El BPM se detecta automáticamente del audio del sistema via PipeWire + aubio. Funciona con cualquier fuente (Spotify, YouTube, VLC, etc). Requiere el paquete 'aubio' instalado."
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
        opacity: 0.7
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
    }

    NTextInput {
        Layout.fillWidth: true
        label: "Segundos de captura"
        description: "Cuántos segundos de audio analizar para detectar BPM (menos = más rápido)"
        placeholderText: "5"
        text: (pluginApi?.pluginSettings?.bpmCaptureSecs ?? 5).toString()
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onTextChanged: {
            var v = parseInt(text)
            if (v >= 3 && v <= 30) {
                pluginApi.pluginSettings.bpmCaptureSecs = v
                pluginApi.saveSettings()
            }
        }
    }

    NTextInput {
        Layout.fillWidth: true
        label: "FPS del GIF"
        description: "Consúltalo con: ffprobe tu.gif"
        placeholderText: "33.33"
        text: (pluginApi?.pluginSettings?.gifFPS ?? 33.33).toString()
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onTextChanged: {
            var v = parseFloat(text)
            if (v > 0) {
                pluginApi.pluginSettings.gifFPS = v
                pluginApi.saveSettings()
            }
        }
    }

    NTextInput {
        Layout.fillWidth: true
        label: "BPM base del GIF"
        description: "A qué BPM va el GIF a velocidad 1×"
        placeholderText: "120"
        text: (pluginApi?.pluginSettings?.gifBPM ?? 120).toString()
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onTextChanged: {
            var v = parseFloat(text)
            if (v > 0) {
                pluginApi.pluginSettings.gifBPM = v
                pluginApi.saveSettings()
            }
        }
    }

    NTextInput {
        Layout.fillWidth: true
        label: "BPM manual de la canción"
        description: "Déjalo en -1 para que lo detecte automáticamente"
        placeholderText: "-1"
        text: (pluginApi?.pluginSettings?.manualBPM ?? -1).toString()
        inputMethodHints: Qt.ImhFormattedNumbersOnly
        onTextChanged: {
            var v = parseFloat(text)
            pluginApi.pluginSettings.manualBPM = v
            pluginApi.saveSettings()
        }
    }

    NDivider { Layout.fillWidth: true }

    // ── Ruta de la carpeta ────────────────────────────────────────────────
    NText {
        text: "Carpeta de GIFs"
        pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
    }

    NText {
        text: root.gifsFolder || "(no disponible)"
        pointSize: Style.fontSizeS
        color: Color.mPrimary
        wrapMode: Text.WrapAnywhere
        Layout.fillWidth: true
    }

    NText {
        text: "Método 1: Pega la ruta completa del archivo"
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
        opacity: 0.7
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: Style.marginM

        NTextInput {
            id: manualPathInput
            Layout.fillWidth: true
            placeholderText: "/ruta/completa/al/archivo.gif o ~/Downloads/catjam.gif"
        }

        NButton {
            text: "Agregar"
            enabled: manualPathInput.text.trim() !== ""
            onClicked: {
                var srcPath = manualPathInput.text.trim()
                // Expandir ~ usando variable de ambiente HOME
                if (srcPath.startsWith("~/")) {
                    var homeDir = Quickshell.env("HOME") || "/home"
                    srcPath = homeDir + srcPath.substring(1)
                }
                if (root.addGifFromPath(srcPath)) {
                    manualPathInput.text = ""
                }
            }
        }
    }

    NText {
        text: "Método 2: Copia el archivo directamente a la carpeta"
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
        opacity: 0.7
    }

    Rectangle {
        Layout.fillWidth: true
        height: Math.round(80)
        color: Qt.rgba(1, 1, 1, 0.05)
        radius: Style.radiusM
        border.color: Color.mPrimary
        border.width: 2

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 8

            NIcon {
                icon: "folder-open"
                color: Color.mPrimary
                Layout.alignment: Qt.AlignHCenter
            }

            NText {
                text: root.gifsFolder
                pointSize: Style.fontSizeXS
                color: Color.mOnSurface
                opacity: 0.7
                Layout.alignment: Qt.AlignHCenter
            }

            NButton {
                text: "Abrir carpeta"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    // Uso dolphin directamente porque xdg-open abre kitty en este sistema
                    // Si no está dolphin, prueba con gio open, nautilus, thunar o nemo
                    openFolderProc.command = ["bash", "-c",
                        'dolphin "' + root.gifsFolder + '" 2>/dev/null || ' +
                        'gio open "' + root.gifsFolder + '" 2>/dev/null || ' +
                        'nautilus "' + root.gifsFolder + '" 2>/dev/null || ' +
                        'thunar "' + root.gifsFolder + '" 2>/dev/null || ' +
                        'nemo "' + root.gifsFolder + '" 2>/dev/null'
                    ]
                    openFolderProc.running = true
                }
            }
        }
    }

    NDivider { Layout.fillWidth: true }

    // ── Lista de GIFs detectados ──────────────────────────────────────────
    NText {
        text: "GIFs disponibles (" + root.folderFiles.length + ")"
        pointSize: Style.fontSizeM
        font.weight: Font.DemiBold
        color: Color.mOnSurface
    }

    NText {
        visible: root.folderFiles.length === 0
        text: "No hay GIFs en la carpeta"
        pointSize: Style.fontSizeS
        color: Color.mOnSurface
        opacity: 0.4
    }

    Repeater {
        model: root.folderFiles

        ColumnLayout {
            required property int index
            property string filename: root.folderFiles[index]

            Layout.fillWidth: true
            spacing: Style.marginS

            RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginM

                // Preview thumbnail
                Rectangle {
                    width: 64
                    height: 48
                    radius: Style.radiusS
                    color: Qt.rgba(0, 0, 0, 0.25)
                    clip: true

                    AnimatedImage {
                        anchors.fill: parent
                        source: "file://" + root.gifsFolder + "/" + filename
                        fillMode: Image.PreserveAspectCrop
                        playing: true
                        smooth: true
                        cache: false
                        visible: status === AnimatedImage.Ready
                    }

                    NIcon {
                        anchors.centerIn: parent
                        icon: "photo"
                        color: Color.mOnSurface
                        opacity: 0.35
                        visible: parent.children[0].status !== AnimatedImage.Ready
                    }
                }

                // Nombre del archivo
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    NText {
                        Layout.fillWidth: true
                        text: filename.replace(/\.gif$/i, "")
                        pointSize: Style.fontSizeS
                        color: Color.mOnSurface
                        elide: Text.ElideRight
                    }

                    NText {
                        text: filename
                        pointSize: Style.fontSizeXS
                        color: Color.mOnSurface
                        opacity: 0.5
                        elide: Text.ElideRight
                    }
                }

                // Campo FPS
                NTextInput {
                    Layout.preferredWidth: 80
                    label: "FPS"
                    placeholderText: "30"
                    text: {
                        try {
                            var metadata = pluginApi?.pluginSettings?.gifsMetadata
                            if (metadata && metadata[filename] && metadata[filename].fps) {
                                return metadata[filename].fps.toString()
                            }
                        } catch(e) {}
                        return ""
                    }
                    inputMethodHints: Qt.ImhFormattedNumbersOnly
                    onTextChanged: {
                        var fps = parseFloat(text)
                        if (fps > 0 && fps <= 200) {
                            if (!pluginApi.pluginSettings.gifsMetadata) {
                                pluginApi.pluginSettings.gifsMetadata = {}
                            }
                            if (!pluginApi.pluginSettings.gifsMetadata[filename]) {
                                pluginApi.pluginSettings.gifsMetadata[filename] = {}
                            }
                            pluginApi.pluginSettings.gifsMetadata[filename].fps = fps
                            pluginApi.saveSettings()
                        }
                    }
                }

                // Eliminar
                NButton {
                    text: "Eliminar"
                    onClicked: root.deleteGif(filename)
                }
            }

            // Separador entre GIFs
            Rectangle {
                Layout.fillWidth: true
                height: 1
                color: Color.mOnSurface
                opacity: 0.1
            }
        }
    }

    Item { Layout.fillHeight: true }
}
