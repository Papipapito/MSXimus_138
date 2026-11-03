#!/bin/bash
# run_geo3d_int_vl.sh — tb_geo3d_int (glue + geo3d_bus + vdp completo) con Verilator --timing.
# Uso (WSL): bash run_geo3d_int_vl.sh <scenes_stim.txt> <scenes_expect.txt>
#   (los genera sim/gen_scenes.py del repo geo3d de alexmoncks: python3 gen_scenes.py 24; tambien valen
#    face_* de gen_face_scenes.py y tex_* de gen_tex_scenes.py)
# 138K (17/10/2026): GEO3D_CE=1 bash run_geo3d_int_vl.sh ... compila la variante con clock enable por el
#   envoltorio fpga/geo3d/geo3d_ce.v (el mismo camino que build.tcl) y el banco con el generador de CE de top.v.
#   Sin GEO3D_CE, los tres fuentes de Alex tal cual y el motor a clk_43 (el enganche de la Zynq).
#   Los dos tienen que dar el MISMO registro de comandos que el modelo.
#   MAXPOLL=4000000 para face_*/tex_*: sus cuadros pasan de los 400000 sondeos de RUN por defecto (tambien
#   sin CE: es el tope del banco, no el motor).
set -e
S="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$S/../.." && pwd)"
STIM="$(realpath "$1")"; EXP="$(realpath "$2")"
if [ "${GEO3D_CE:-0}" = 1 ]; then
    GEO="+define+GEO3D_CE -I$R/fpga $R/fpga/geo3d/geo3d_ce.v"; VAR="GEO3D_CE (motor a clk con CE 1/2)"
else
    GEO="$R/fpga/geo3d/geo3d_core.v $R/fpga/geo3d/geo3d_engine.v $R/fpga/geo3d/geo3d_bus.v"; VAR="sin CE (motor a clk_43)"
fi
B=/tmp/vgeo3d_$$
rm -rf "$B" && mkdir -p "$B" && cd "$B"
verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo3d_int \
    "$S/tb_geo3d_int.sv" $GEO "$R/fpga/src/v9968_cpu_glue.v" "$R"/fpga/v9968/*.v > verilate.log 2>&1 \
    || { grep -E '%Error' verilate.log | head -12; exit 1; }
echo "variante: $VAR"
./obj_dir/Vtb_geo3d_int +stim="$STIM" +got="$B/got.txt" +maxpoll=${MAXPOLL:-400000} > sim.log 2>&1 \
    || { tail -12 sim.log; echo "FAIL: la simulacion acabo con error"; exit 1; }
grep -viE "^VCD|dumpfile" sim.log | tail -12
# el banco solo IMPRIME estos fallos (y sale con 0): el veredicto los cuenta aqui, no solo el diff
if ! grep -q "SIN VIOLACIONES" sim.log || grep -qE "RUN no acaba|NO RESPONDE" sim.log; then
    echo "FAIL: escrituras con CE=1, S#2 raros, RUN sin acabar o geo3d sin responder (ver arriba)"
    cp "$B/got.txt" "$S/geo3d_int_got.txt" 2>/dev/null; exit 1
fi
if diff -q "$EXP" "$B/got.txt" > /dev/null; then
    echo "PASS: registro de comandos IDENTICO al modelo de geo3d ($(grep -c '^L\|^M' "$B/got.txt") comandos)"
else
    echo "FAIL: el registro difiere del modelo:"; diff "$EXP" "$B/got.txt" | head -10
    cp "$B/got.txt" "$S/geo3d_int_got.txt"; exit 1
fi
rm -rf "$B"
