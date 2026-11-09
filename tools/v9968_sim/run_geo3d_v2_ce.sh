#!/bin/bash
# run_geo3d_v2_ce.sh — geo3d v2.0 + HMMV rapido (HRA 3d55af4) en el 138K: el VDP completo con geo3d SIN y CON GEO3D_CE sobre
# las escenas de Alex (geo3d/sim: gen_scenes.py, gen_face_scenes.py, gen_tex_scenes.py), en SCREEN 5 (las filas rellenas
# van por LINE) y en SCREEN 8 (+sc8: las filas planas van por el HMMV de una fila).
#   - SCREEN 5: el registro de comandos de las dos variantes tiene que ser IDENTICO al modelo de Alex.
#   - SCREEN 8: el registro de comandos tambien (es lo que geo3d_bus entrega al VDP) y la VRAM final (65536 palabras) de
#     la variante con CE tiene que ser identica a la de sin CE.
# Compila el banco dos veces (una por variante) y corre las tres familias de escenas con cada binario.
# Uso (WSL): bash run_geo3d_v2_ce.sh <carpeta con scenes_*, face_*, tex_*  (la sim/ de Alex tras correr los gen_*.py)>
#   MAXPOLL=N para el tope de sondeos de RUN por cuadro (por defecto lo que traiga el banco).
set -e
S="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$S/../.." && pwd)"
D="$(realpath "$1")"
for f in scenes face tex; do
    [ -f "$D/${f}_stim.txt" ] && [ -f "$D/${f}_expect.txt" ] || { echo "falta ${f}_stim.txt / ${f}_expect.txt en $D"; exit 2; }
done
B=/tmp/g3v2ce_$$
rm -rf "$B" && mkdir -p "$B/noce" "$B/ce"
fallo=0

compila() {   # <dir> <define o vacio> <fuentes del motor>
    ( cd "$1" && verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo3d_int $2 \
        "$S/tb_geo3d_int.sv" $3 "$R/fpga/src/v9968_cpu_glue.v" "$R"/fpga/v9968/*.v > verilate.log 2>&1 ) \
        || { grep -E '%Error' "$1/verilate.log" | head -12; exit 1; }
}
compila "$B/noce" "" "$R/fpga/geo3d/geo3d_core.v $R/fpga/geo3d/geo3d_engine.v $R/fpga/geo3d/geo3d_bus.v"
compila "$B/ce"   "+define+GEO3D_CE -I$R/fpga" "$R/fpga/geo3d/geo3d_ce.v"

corre() {     # <variante> <familia> <modo: sc5|sc8>
    local v=$1 f=$2 m=$3 extra=""
    [ "$m" = sc8 ] && extra="+sc8 +vdump=$B/$v/${f}_$m.vram"
    ( cd "$B/$v" && ./obj_dir/Vtb_geo3d_int +stim="$D/${f}_stim.txt" +got="$B/$v/${f}_$m.got" \
        +maxpoll=${MAXPOLL:-4000000} $extra > "${f}_$m.log" 2>&1 ) || { echo "FAIL $v $f $m: la simulacion acabo con error"; tail -5 "$B/$v/${f}_$m.log"; return 1; }
    grep -q "SIN VIOLACIONES" "$B/$v/${f}_$m.log" && ! grep -qE "RUN no acaba|NO RESPONDE" "$B/$v/${f}_$m.log" \
        || { echo "FAIL $v $f $m: escrituras con CE=1, RUN sin acabar o geo3d sin responder"; tail -8 "$B/$v/${f}_$m.log"; return 1; }
}

for f in scenes face tex; do
    for m in sc5 sc8; do
        for v in noce ce; do corre $v $f $m || fallo=1; done
        n=$(grep -c '^[LM]' "$B/ce/${f}_$m.got" || true)
        if diff -q "$D/${f}_expect.txt" "$B/noce/${f}_$m.got" >/dev/null; then a="sin CE = modelo"; else a="sin CE DIFIERE del modelo"; fallo=1; fi
        if diff -q "$D/${f}_expect.txt" "$B/ce/${f}_$m.got" >/dev/null; then b="con CE = modelo"; else b="con CE DIFIERE del modelo"; fallo=1; fi
        if [ "$m" = sc8 ]; then
            if cmp -s "$B/noce/${f}_$m.vram" "$B/ce/${f}_$m.vram"; then c="VRAM igual"; else c="VRAM DISTINTA"; fallo=1; fi
        else c="-"; fi
        echo "$f $m: $n comandos; $a; $b; $c"
    done
done
if [ $fallo = 0 ]; then echo "RESULTADO: PASS (geo3d v2.0 sin y con CE, SCREEN 5 y SCREEN 8)"; rm -rf "$B"; else echo "RESULTADO: FAIL (logs en $B)"; exit 1; fi
