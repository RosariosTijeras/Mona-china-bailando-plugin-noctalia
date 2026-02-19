#!/usr/bin/env bash
# Script para detectar FPS de todos los GIFs en la carpeta
# y generar el archivo de metadatos

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GIFS_DIR="$SCRIPT_DIR/gifs"
METADATA_FILE="$SCRIPT_DIR/gifs-metadata.json"

echo "🔍 Detectando FPS de todos los GIFs..."
echo ""

# Inicializar JSON
echo "{" > "$METADATA_FILE"
echo '  "_comment": "Metadatos auto-generados. NO editar manualmente.",' >> "$METADATA_FILE"

FIRST=true

# Iterar sobre todos los GIFs
for gif_file in "$GIFS_DIR"/*.gif; do
    # Verificar que el archivo exista (por si no hay GIFs)
    [ -e "$gif_file" ] || continue
    
    FILENAME=$(basename "$gif_file")
    
    # Detectar FPS
    FPS=$("$SCRIPT_DIR/detect-gif-fps.sh" "$gif_file")
    
    if [ $? -eq 0 ]; then
        echo "✓ $FILENAME → ${FPS} FPS"
        
        # Agregar coma si no es el primer elemento
        if [ "$FIRST" = false ]; then
            echo "," >> "$METADATA_FILE"
        fi
        FIRST=false
        
        # Agregar entrada al JSON (sin salto de línea al final)
        echo -n "  \"$FILENAME\": {\"fps\": $FPS}" >> "$METADATA_FILE"
    else
        echo "✗ $FILENAME → ERROR al detectar FPS"
    fi
done

# Cerrar JSON
echo "" >> "$METADATA_FILE"
echo "}" >> "$METADATA_FILE"

echo ""
echo "✅ Metadatos guardados en: $METADATA_FILE"
