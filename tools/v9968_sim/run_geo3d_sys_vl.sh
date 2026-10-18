#!/bin/bash
# run_geo3d_sys_vl.sh — tb_geo3d_sys (glue + geo3d_bus + vdp completo, lado Z80 entero) con Verilator --timing.
# Uso: bash run_geo3d_sys_vl.sh <sys.txt> <expect.txt> <frames.hex>
#   sys.txt y (con check_demo.py de Alex) expect.txt salen de tools/geo3d_demo/run_kanon_rom.py de la Zynq; frames.hex
#   son las paginas mostradas (212 x 128 bytes en hex, una por D) para frames_to_png.py.
# 138K (18/10/2026), como run_geo3d_int_vl.sh: GEO3D_CE=1 compila la variante con clock enable por fpga/geo3d/geo3d_ce.v
#   (el camino de build.tcl) y el banco con el generador de CE de top.v; GEO3D_CE_FASE_B=1 arranca ese CE en la otra
#   fase. Sin GEO3D_CE, los tres fuentes de Alex tal cual y el motor a clk_43 (el enganche de la Zynq). MAXPOLL = tope
#   de sondeos de RUN (400000). GEO3D_SYS_BUILD = directorio del verilado (se reutiliza si ya esta; uno por variante).
#   Si falla, el registro obtenido se queda en el directorio del verilado (no se copia al repo).
set -e
S="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$S/../.." && pwd)"
STIM="$(realpath "$1")"; EXP="$(realpath "$2")"; FR="$(realpath -m "$3")"
if [ "${GEO3D_CE:-0}" = 1 ]; then
    GEO="+define+GEO3D_CE -I$R/fpga $R/fpga/geo3d/geo3d_ce.v"; VAR="GEO3D_CE (motor a clk con CE 1/2)"
    if [ "${GEO3D_CE_FASE_B:-0}" = 1 ]; then GEO="+define+GEO3D_CE_FASE_B $GEO"; VAR="$VAR, fase B"; fi
else
    GEO="$R/fpga/geo3d/geo3d_core.v $R/fpga/geo3d/geo3d_engine.v $R/fpga/geo3d/geo3d_bus.v"; VAR="sin CE (motor a clk_43)"
fi
B=${GEO3D_SYS_BUILD:-/tmp/vgeo3dsys_$$}
mkdir -p "$B" && cd "$B"
if [ ! -x obj_dir/Vtb_geo3d_sys ]; then
    verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo3d_sys \
        "$S/tb_geo3d_sys.sv" $GEO "$R/fpga/src/v9968_cpu_glue.v" "$R"/fpga/v9968/*.v > verilate.log 2>&1 \
        || { grep -E '%Error' verilate.log | head -12; exit 1; }
    echo "$VAR" > variante.txt
fi
[ "$(cat variante.txt 2>/dev/null)" = "$VAR" ] || { echo "GEO3D_SYS_BUILD=$B esta verilado con otra variante: $(cat variante.txt)"; exit 1; }
echo "variante: $VAR"
./obj_dir/Vtb_geo3d_sys +stim="$STIM" +got="$B/got.txt" +frames="$FR" +maxpoll=${MAXPOLL:-400000} 2>&1 \
    | grep -viE "^VCD|dumpfile" | tail -40
if diff -q "$EXP" "$B/got.txt" > /dev/null; then
    echo "PASS: registro de comandos IDENTICO al modelo de geo3d ($(grep -c '^L\|^M' "$B/got.txt") comandos)"
else
    echo "FAIL: el registro difiere del modelo (obtenido en $B/got.txt):"; diff "$EXP" "$B/got.txt" | head -10
    exit 1
fi
[ -n "$GEO3D_SYS_BUILD" ] || rm -rf "$B"
