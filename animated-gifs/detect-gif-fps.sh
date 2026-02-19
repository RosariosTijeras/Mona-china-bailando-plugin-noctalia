#!/usr/bin/env bash
# Detecta FPS de un archivo GIF usando ffprobe

if [ $# -lt 1 ]; then
    echo "ERROR: Se requiere ruta del archivo GIF"
    exit 1
fi

GIF_PATH="$1"

if [ ! -f "$GIF_PATH" ]; then
    echo "ERROR: Archivo no encontrado: $GIF_PATH"
    exit 1
fi

# Detectar FPS usando ffprobe
# El campo "r_frame_rate" o "avg_frame_rate" contiene el FPS
FPS=$(ffprobe -v error -select_streams v:0 -show_entries stream=r_frame_rate -of default=noprint_wrappers=1:nokey=1 "$GIF_PATH" 2>/dev/null)

if [ -z "$FPS" ]; then
    echo "ERROR: No se pudo detectar FPS"
    exit 1
fi

# Convertir fracción a decimal (ej: "30/1" -> 30.0)
if [[ "$FPS" == *"/"* ]]; then
    IFS='/' read -r NUM DEN <<< "$FPS"
    FPS=$(awk "BEGIN {printf \"%.2f\", $NUM/$DEN}")
fi

# Validar que sea un número razonable (entre 10 y 60 FPS)
if (( $(awk "BEGIN {print ($FPS < 10 || $FPS > 60)}") )); then
    echo "20.0"  # Fallback conservador
else
    echo "$FPS"
fi
