#!/bin/bash
# run_geo_abort.sh - la fila de geo3d como HMMV de una fila (HRA 3d55af4) debe dejar los registros que ve la CPU
# EXACTAMENTE como la LINE equivalente cuando la CPU la aborta o la pisa: STOP, R#40/41 y R#42/43 a mitad de fila (enteros
# o de una sola mitad), otro R#46 durante la fila o el vaciado de la cache, arranque sin esperar, cambio de modo.
#   tb_geo_abort   vdp_command + cache: cada escenario, LINE frente a fila rapida (registros al acabar y VRAM tras una LINE
#                  posterior que reutiliza NX/NY), con VRAM sin esperas, con esperas y en modo rapido de comandos.
# Uso (WSL): bash run_geo_abort.sh [raiz del repo]      (por defecto, este repo; otra raiz = A/B contra el RTL anterior)
set -e
S="$(cd "$(dirname "$0")" && pwd)"
R="${1:-$(cd "$S/../.." && pwd)}"
B=/tmp/geo_abort_$$
rm -rf "$B" && mkdir -p "$B"
fallo=0

cd "$B"
verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH --top-module tb_geo_abort \
    "$S/tb_geo_abort.sv" "$R/fpga/v9968/vdp_command.v" "$R/fpga/v9968/vdp_command_cache.v" \
    > verilate.log 2>&1 || { grep -E '%Error' verilate.log | head -12; exit 1; }
./obj_dir/Vtb_geo_abort > out.log 2>&1 || fallo=1
grep -cE '^PASS esc' out.log | sed 's/^/tb_geo_abort: escenarios PASS = /' || true
grep -E '^FAIL' out.log | head -12 || true
tail -2 out.log
grep -qE '^PASS all geo abort tests' out.log || fallo=1

if [ $fallo = 0 ]; then echo "RESULTADO: PASS (tb_geo_abort)"; cd /; rm -rf "$B"; else echo "RESULTADO: FAIL (logs en $B)"; exit 1; fi
