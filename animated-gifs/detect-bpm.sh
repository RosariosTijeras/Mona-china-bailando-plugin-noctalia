#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# detect-bpm.sh — Detección local de BPM via PipeWire + aubio
#
# Captura audio del sistema (lo que suena por los altavoces) y calcula el BPM.
# Funciona con CUALQUIER fuente: Spotify, YouTube, VLC, mpv, Firefox, etc.
#
# Dependencias:
#   - pipewire + pw-record  (obligatorio en Wayland/Niri)
#   - aubio                 (paquete: aubio / python3-aubio / aubio-tools)
#   - pactl                 (viene con pipewire-pulse o pulseaudio-utils)
#
# Uso:   ./detect-bpm.sh [segundos]
# Sale:  un número (BPM) en stdout, o nada si falla
# ─────────────────────────────────────────────────────────────────────────────

DURATION="${1:-8}"
TMPFILE="/tmp/noctalia-bpm-$$.wav"

cleanup() { rm -f "$TMPFILE"; }
trap cleanup EXIT

# ── Verificar dependencias ─────────────────────────────────────────────────
if ! command -v aubio &>/dev/null; then
    echo "ERROR: aubio no instalado. Instálalo con:" >&2
    echo "  Fedora/RHEL:  sudo dnf install aubio" >&2
    echo "  Arch:         sudo pacman -S aubio" >&2
    echo "  Debian/Ubuntu: sudo apt install aubio-tools" >&2
    echo "  openSUSE:     sudo zypper install aubio" >&2
    exit 1
fi

# ── Obtener el monitor del sink por defecto ────────────────────────────────
# El "monitor" es el loopback de la salida de audio: captura lo que suena
MONITOR=""

if command -v pactl &>/dev/null; then
    DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null)
    if [ -n "$DEFAULT_SINK" ]; then
        MONITOR="${DEFAULT_SINK}.monitor"
    fi
fi

# Fallback 1: buscar EasyEffects sink (common en Fedora/Niri)
if [ -z "$MONITOR" ] && command -v pactl &>/dev/null; then
    MONITOR=$(pactl list short sources 2>/dev/null | grep "easyeffects.*monitor" | head -1 | awk '{print $2}')
fi

# Fallback 2: buscar cualquier monitor disponible
if [ -z "$MONITOR" ] && command -v pactl &>/dev/null; then
    MONITOR=$(pactl list short sources 2>/dev/null | grep "monitor" | head -1 | awk '{print $2}')
fi

# Fallback 3: wpctl (WirePlumber, alternativa a pactl)
if [ -z "$MONITOR" ] && command -v wpctl &>/dev/null; then
    # En WirePlumber, el default sink siempre tiene un monitor
    MONITOR="@DEFAULT_AUDIO_SINK@"
fi

if [ -z "$MONITOR" ]; then
    echo "ERROR: No se encontró monitor de audio" >&2
    exit 1
fi

# ── Grabar audio del sistema ───────────────────────────────────────────────
if command -v pw-record &>/dev/null; then
    timeout "$((DURATION + 1))" pw-record \
        --target="$MONITOR" \
        --channels=1 \
        --format=s16 \
        --rate=44100 \
        "$TMPFILE" 2>/dev/null
elif command -v parecord &>/dev/null; then
    timeout "$((DURATION + 1))" parecord \
        --device="$MONITOR" \
        --channels=1 \
        --format=s16le \
        --rate=44100 \
        --file-format=wav \
        "$TMPFILE" 2>/dev/null
else
    echo "ERROR: Ni pw-record ni parecord disponibles" >&2
    exit 1
fi

# ── Verificar que se grabó algo ────────────────────────────────────────────
if [ ! -s "$TMPFILE" ]; then
    exit 1
fi

# ── Detectar BPM con aubio ─────────────────────────────────────────────────
# aubio tempo: imprime "X.XX bpm" directamente
BPM_LINE=$(aubio tempo -i "$TMPFILE" 2>/dev/null)

if [ -z "$BPM_LINE" ]; then
    exit 1
fi

# Extraer solo el número del formato "126.26 bpm"
echo "$BPM_LINE" | awk '{
    bpm = $1 + 0
    if (bpm > 0) {
        # Normalizar: traer BPM al rango 60-180 (rango musical típico)
        # Aubio a veces detecta el doble o mitad del BPM real
        while (bpm > 180) bpm = bpm / 2
        while (bpm < 60) bpm = bpm * 2
        printf "%.1f\n", bpm
    }
}'
