#!/bin/bash
# run_geo3d_hmmv.sh - bancos de HRA del HMMV rapido de geo3d (v0.92, issue #9 de HRA / muhanpong) sobre NUESTRO RTL:
#   tb_geo3d_hmmv      vdp_command + geo3d_bus/engine: LINE de la CPU frente a la fila de geo3d (VRAM, parametros y estado
#                      identicos), SCREEN 5-8, YJK, LOP, cambios de modo a mitad de fila, caras planas/texturadas/alambre.
#   tb_geo3d_vdp_modes vdp completo: el modo de R#0/R#25 decide si la fila se optimiza (solo SCREEN 8, no SCREEN 10/11/12).
# 138K: los tres fuentes de Alex SIN GEO3D_CE (el motor a clk con ce fijo a 1: lo de la CE lo cubre run_alex_ce.sh).
# Uso (WSL): bash run_geo3d_hmmv.sh [raiz del repo]      (por defecto, este repo; pasar otra raiz para el A/B)
set -e
S="$(cd "$(dirname "$0")" && pwd)"
R="${1:-$(cd "$S/../.." && pwd)}"
B=/tmp/geo3d_hmmv_$$
rm -rf "$B" && mkdir -p "$B/a" "$B/b"
fallo=0

cd "$B/a"
verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo3d_hmmv \
    "$S/tb_geo3d_hmmv.sv" "$R/fpga/v9968/vdp_command.v" "$R/fpga/v9968/vdp_command_cache.v" "$R/fpga/geo3d/geo3d_core.v" "$R/fpga/geo3d/geo3d_engine.v" "$R/fpga/geo3d/geo3d_bus.v" \
    > verilate.log 2>&1 || { grep -E '%Error' verilate.log | head -12; exit 1; }
./obj_dir/Vtb_geo3d_hmmv > out.log 2>&1 || fallo=1
grep -cE '^PASS' out.log | sed 's/^/tb_geo3d_hmmv: lineas PASS = /'
tail -3 out.log
grep -qE '^PASS all Geo3D HMMV tests' out.log || fallo=1

cd "$B/b"
verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo3d_vdp_modes \
    "$S/tb_geo3d_vdp_modes.sv" "$R"/fpga/v9968/*.v > verilate.log 2>&1 \
    || { grep -E '%Error' verilate.log | head -12; exit 1; }
./obj_dir/Vtb_geo3d_vdp_modes > out.log 2>&1 || fallo=1
cat out.log | grep -vE '^-' | tail -12
grep -qE '^PASS VDP mode integration' out.log || fallo=1

if [ $fallo = 0 ]; then echo "RESULTADO: PASS (tb_geo3d_hmmv + tb_geo3d_vdp_modes)"; rm -rf "$B"; else echo "RESULTADO: FAIL (logs en $B)"; exit 1; fi
