#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# detect-bpm.sh — Detección local de BPM via PipeWire + aubio
#
# Captura audio del sistema y calcula BPM.
# Funciona con CUALQUIER fuente: Spotify, YouTube, VLC, etc.
#
# Dependencias: pipewire + pw-record, aubio, pactl
# Uso:   ./detect-bpm.sh [segundos]
# Sale:  un número (BPM) en stdout
# ─────────────────────────────────────────────────────────────────────────────

DURATION="${1:-4}"
TMPFILE="/tmp/noctalia-bpm-$$.wav"

cleanup() { rm -f "$TMPFILE" 2>/dev/null; }
trap cleanup EXIT

# ── Verificar dependencias ─────────────────────────────────────────────────
if ! command -v aubio &>/dev/null; then
    echo "ERROR: aubio no instalado" >&2
    exit 1
fi

# ── Obtener la fuente de audio (monitor del sink) ──────────────────────────
MONITOR=""

if command -v pactl &>/dev/null; then
    # 1. Intentar EasyEffects monitor (más limpio, post-procesado)
    MONITOR=$(pactl list short sources 2>/dev/null | grep -i "easyeffects.*monitor" | head -1 | awk '{print $2}')
    
    # 2. Monitor del sink por defecto
    if [ -z "$MONITOR" ]; then
        DEFAULT_SINK=$(pactl get-default-sink 2>/dev/null)
        if [ -n "$DEFAULT_SINK" ]; then
            MONITOR="${DEFAULT_SINK}.monitor"
        fi
    fi
    
    # 3. Cualquier monitor disponible
    if [ -z "$MONITOR" ]; then
        MONITOR=$(pactl list short sources 2>/dev/null | grep "monitor" | head -1 | awk '{print $2}')
    fi
fi

if [ -z "$MONITOR" ]; then
    echo "ERROR: No se encontró monitor de audio" >&2
    exit 1
fi

echo "DEBUG: Capturando ${DURATION}s desde ${MONITOR}" >&2

# ── Grabar audio del sistema ───────────────────────────────────────────────
# Usar --signal=INT para que pw-record cierre limpiamente y escriba headers WAV
if command -v pw-record &>/dev/null; then
    timeout --signal=INT "$((DURATION + 1))" pw-record \
        --target="$MONITOR" \
        --channels=1 \
        --format=s16 \
        --rate=44100 \
        "$TMPFILE" 2>/dev/null
elif command -v parecord &>/dev/null; then
    timeout --signal=INT "$((DURATION + 1))" parecord \
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
    echo "ERROR: Archivo de audio vacío" >&2
    exit 1
fi

FILESIZE=$(stat -c%s "$TMPFILE" 2>/dev/null || echo "0")
echo "DEBUG: Archivo grabado: ${FILESIZE} bytes" >&2

if [ "$FILESIZE" -lt 1000 ]; then
    echo "ERROR: Archivo de audio muy pequeño (${FILESIZE} bytes)" >&2
    exit 1
fi

# ── Detectar BPM con aubio ─────────────────────────────────────────────────
BPM_RAW=$(aubio tempo -i "$TMPFILE" 2>/dev/null)

if [ -z "$BPM_RAW" ]; then
    echo "ERROR: aubio no devolvió resultado" >&2
    exit 1
fi

echo "DEBUG: aubio output: ${BPM_RAW}" >&2

# Extraer BPM y normalizar al rango musical 60-200
echo "$BPM_RAW" | awk '{
    bpm = $1 + 0
    if (bpm > 0) {
        # Normalizar: traer BPM al rango 60-200
        while (bpm > 200) bpm = bpm / 2
        while (bpm < 60) bpm = bpm * 2
        printf "%.1f\n", bpm
    }
}'
