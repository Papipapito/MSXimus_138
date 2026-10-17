#!/bin/bash
# matrix.sh <lista de trabajos> [paralelos] - corre una lista en paralelo (4 por defecto) y resume cada trabajo.
# Cada linea de la lista: "DLY turbo ideal p27 vph rph etiqueta [plusargs]" (ver README.md). Los informes enteros
# quedan en res/<etiqueta>.txt del directorio de trabajo.
set -e
D=$(cd "$(dirname "$0")" && pwd)
W=${T80MEM_WORK:-$HOME/t80mem_work}
L=$1
P=${2:-4}
[ -f "$L" ] || { echo "uso: matrix.sh <lista de trabajos> [paralelos]"; exit 1; }
mkdir -p "$W/res"
LISTA=$W/res/.lista
tr -d '\r' < "$L" | grep -v '^[[:space:]]*$' > "$LISTA"
for d in $(awk '{print $1}' "$LISTA" | sort -un); do
    bash "$D/build.sh" "$d" > /dev/null
done
export D W
xargs -P "$P" -L 1 bash -c 'bash "$D/run1.sh" "$@" > "$W/res/$7.txt" 2>&1' _ < "$LISTA" || true
for l in $(awk '{print $7}' "$LISTA"); do
    f=$W/res/$l.txt
    echo "== $l: $(grep -h 'RESULTADO' "$f") | $(grep -h 'escrituras CPU' "$f")"
    grep -h -e "margen minimo (captura en SdrDat" -e "ultimo cambio de DO" -e "subida de ram_write" -e "retencion" \
         -e "suma B10" -e "tiempo_real" -e "TIMEOUT" "$f" | sed 's/^/     /'
    grep -h "^ERROR" "$f" | head -3 | sed 's/^/     /'
done
