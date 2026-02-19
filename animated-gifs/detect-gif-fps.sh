#!/usr/bin/env bash
# Detecta FPS, número de frames y duración de un GIF usando ffprobe.
# Salida: fps|frames|duration  (ej: 10.00|43|4.30)

if [ $# -lt 1 ]; then
    echo "ERROR: Se requiere ruta del archivo GIF"
    exit 1
fi

GIF_PATH="$1"

if [ ! -f "$GIF_PATH" ]; then
    echo "ERROR: Archivo no encontrado: $GIF_PATH"
    exit 1
fi

# Leer fps, duración y frames de una sola pasada
# ffprobe devuelve: r_frame_rate, duration, nb_frames (en ese orden)
read -r FPS DURATION NB_FRAMES < <(ffprobe -v error \
    -select_streams v:0 \
    -show_entries stream=r_frame_rate,duration,nb_frames \
    -of csv=p=0 \
    "$GIF_PATH" 2>/dev/null | tr ',' ' ')

if [ -z "$FPS" ]; then
    echo "ERROR: No se pudo detectar FPS"
    exit 1
fi

# Convertir fracción a decimal (ej: "10/1" -> 10.00)
if [[ "$FPS" == *"/"* ]]; then
    IFS='/' read -r NUM DEN <<< "$FPS"
    FPS=$(awk "BEGIN {printf \"%.2f\", $NUM/$DEN}")
fi

# Fallback si ffprobe no dio frames/duration (algunos GIFs raros)
NB_FRAMES="${NB_FRAMES:-0}"
DURATION="${DURATION:-0}"

# Convertir a decimal limpio
DURATION=$(awk "BEGIN {printf \"%.2f\", $DURATION+0}")
NB_FRAMES=$(awk "BEGIN {printf \"%d\", $NB_FRAMES+0}")

# Si FPS fuera de rango razonable, usar 20 como fallback
if (( $(awk "BEGIN {print ($FPS < 1 || $FPS > 120)}") )); then
    FPS="20.00"
fi

echo "${FPS}|${NB_FRAMES}|${DURATION}"
