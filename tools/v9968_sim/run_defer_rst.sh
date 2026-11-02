#!/bin/bash
# run_defer_rst.sh - tb_defer_rst.sv (diferidor del reinicio del HDMI _136 + punto de aterrizaje del reinicio) con el cuadro de siempre del VDP
# (2736*524 = 1.433.664 ciclos de clk_86) y con el cuadro recortado de v3.8.6 (1.431.824).
# Esperado: los dos "TODO OK". Con el cuadro de siempre el reinicio aterriza en cy = 720, cx ~1595 (dentro de las data islands: el diferidor engancha,
# defers > 0). Con el recortado, en cy = 720 con cx de unos pocos px: fuera de la ventana de las islands (defers = 0) y nunca en una linea activa.
# Uso (WSL): bash run_defer_rst.sh      Icarus: ~2-3 min.
S="$(cd "$(dirname "$0")" && pwd)"
B=/tmp/deferrst_$$; mkdir -p "$B"
cd "$B"
iverilog -g2012 -o t.vvp "$S/tb_defer_rst.sv" || exit 1
vvp -n t.vvp > viejo.log 2>&1 &
vvp -n t.vvp +FRAME86=1431824 > recortado.log 2>&1 &
wait
E=0
for f in viejo recortado; do
    echo "== cuadro $f"
    grep -E "CUADRO|ATERRIZAJE|RESULTADO|DEFER_RST|FALLO" $f.log
    grep -q "TODO OK" $f.log || E=1
done
[ $E = 0 ] && echo TB_OK || echo TB_FAIL
cd /
if [ -n "$KEEP" ]; then echo "volcados en $B"; else rm -rf "$B"; fi
exit $E
