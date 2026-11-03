#!/bin/bash
# run_pll_init_orden.sh - banco del orden de arranque de la cadena de PLL del HDMI (v3.8.4b), con los .v reales de fpga/pll138.
# Uso (WSL): bash tools/pll_init_tb/run_pll_init_orden.sh        (Icarus, ~1 min)
S="$(cd "$(dirname "$0")" && pwd)"
R="$S/../../fpga/pll138"
B=/tmp/pllinit_$$; mkdir -p "$B"
# los wrappers con el primitivo PLL simulado: fuera los defparam de PLL_inst salvo MDIV_SEL (el modelo lo usa)
for f in pll_27 pll_hdmiref pll_74 pll_86; do
    sed -E '/defparam PLL_inst\./{/defparam PLL_inst\.MDIV_SEL /!d}' "$R/$f.v" | tr -d '\r' > "$B/$f.v"
done
iverilog -g2012 -o "$B/sim" -s tb_pll_init_orden \
    "$S/tb_pll_init_orden.sv" "$S/tb_pll_stub.sv" "$R/pll_init.v" "$B/pll_27.v" "$B/pll_hdmiref.v" "$B/pll_74.v" "$B/pll_86.v" || exit 1
vvp "$B/sim" | grep -v "^VCD"
E=${PIPESTATUS[0]}
rm -rf "$B"
exit $E
