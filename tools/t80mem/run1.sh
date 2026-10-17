#!/bin/bash
# run1.sh <DLY> <turbo> <ideal> <p27> <vph> <rph> <etiqueta> [plusargs] - una ejecucion de tb_dly<DLY>.vvp (build.sh antes).
# El informe sale por la salida estandar; la imagen 8000h-8FFFh, en img_<etiqueta>.hex del directorio de trabajo.
W=${T80MEM_WORK:-$HOME/t80mem_work}
D=$(cd "$(dirname "$0")" && pwd)
cd "$W" || exit 1
cp "$D/prog.hex" "prog.hex.$$" && mv -f "prog.hex.$$" prog.hex     # atomico: matrix.sh lanza varios a la vez
/usr/bin/time -f "tiempo_real=%es" vvp -n "tb_dly$1.vvp" +turbo="$2" +ideal="$3" +p27="$4" +vph="$5" +rph="$6" \
    +dump="img_$7.hex" $8 2>&1 | grep -v "^VCD\|WARNING: .*tb_t80mem.v:.*readmemh"
