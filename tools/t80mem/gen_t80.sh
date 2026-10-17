#!/bin/bash
# gen_t80.sh - traduce el T80 del core (fpga/G80A, el G80a de top.v) a Verilog con la sintesis de GHDL 4.1 y lo deja
# en el directorio de trabajo como g80a_rtl.v (900 KB; no va en el repositorio, lo rehace build.sh si falta o si
# cambia algun .vhd). GHDL: el de $GHDL; si no, el de ~/ghdl_local (ghdl-mcode 4.1.0 de Ubuntu 24.04 extraido sin
# instalar); si no, el del PATH (apt install ghdl).
set -e
D=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$D/../.." && pwd)
W=${T80MEM_WORK:-$HOME/t80mem_work}
SRC=$R/fpga/G80A
GOPT=()
if [ -n "$GHDL" ]; then
    G=$GHDL
elif [ -x "$HOME/ghdl_local/root/usr/bin/ghdl-mcode" ]; then
    G=$HOME/ghdl_local/root/usr/bin/ghdl-mcode
    GOPT=(--PREFIX="$HOME/ghdl_local/root/usr/lib/ghdl/mcode/vhdl")
elif command -v ghdl > /dev/null; then
    G=ghdl
else
    echo "gen_t80.sh: no encuentro GHDL (apt install ghdl, o GHDL=/ruta/a/ghdl)"; exit 1
fi
mkdir -p "$W/ghdl"
cd "$W/ghdl"
rm -f ./*.cf g80a_ghdl.v ghdl.log
falla() { cat ghdl.log; echo "gen_t80.sh: GHDL ha fallado (arriba, su salida)"; exit 1; }
for f in t80_pack t80_alu t80_mcode t80_reg t80 g80a; do
    "$G" -a "${GOPT[@]}" --std=93c "$SRC/$f.vhd" 2>> ghdl.log || falla
done
"$G" --synth "${GOPT[@]}" --std=93c --out=verilog g80a > g80a_ghdl.v 2>> ghdl.log || falla
python3 "$D/fix_ghdl_v.py" g80a_ghdl.v "$W/g80a_rtl.v"
echo "g80a_rtl.v: $(wc -l < "$W/g80a_rtl.v") lineas, en $W (avisos de GHDL en $W/ghdl/ghdl.log)"
