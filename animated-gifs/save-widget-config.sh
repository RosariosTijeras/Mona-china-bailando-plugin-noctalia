#!/bin/bash
# Script para guardar configuración de un widget
# Uso: ./save-widget-config.sh <widget_index> <gif_filename>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/widgets-config.json"
WIDGET_INDEX="$1"
GIF_FILENAME="$2"

# Crear archivo si no existe
if [ ! -f "$CONFIG_FILE" ]; then
    echo '{"_comment":"Configuración persistente de widgets - NO BORRAR","widgets":[]}' > "$CONFIG_FILE"
fi

# Usar jq para actualizar (si está disponible)
if command -v jq &>/dev/null; then
    # Leer config actual
    CONFIG=$(cat "$CONFIG_FILE")
    
    # Actualizar o agregar widget
    UPDATED=$(echo "$CONFIG" | jq --arg idx "$WIDGET_INDEX" --arg gif "$GIF_FILENAME" '
        .widgets |= 
        if any(.[]; .index == ($idx | tonumber)) then
            map(if .index == ($idx | tonumber) then .gifFilename = $gif else . end)
        else
            . + [{"index": ($idx | tonumber), "gifFilename": $gif}]
        end
    ')
    
    echo "$UPDATED" > "$CONFIG_FILE"
else
    # Fallback simple sin jq (menos robusto pero funcional)
    python3 -c "
import json
import sys

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

# Buscar widget existente
found = False
for w in config.get('widgets', []):
    if w.get('index') == $WIDGET_INDEX:
        w['gifFilename'] = '$GIF_FILENAME'
        found = True
        break

# Si no existe, agregarlo
if not found:
    if 'widgets' not in config:
        config['widgets'] = []
    config['widgets'].append({'index': $WIDGET_INDEX, 'gifFilename': '$GIF_FILENAME'})

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
fi

echo "Widget $WIDGET_INDEX configurado con $GIF_FILENAME"
