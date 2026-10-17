#!/bin/bash
# build.sh <DLY> - compila el banco con DLY etapas de registro a 54 MHz entre cpu_dout y ram_din
# (0 = antes del commit e402652, 1 = el core, mas = sondeo del margen). Deja tb_dly<DLY>.vvp en el directorio de trabajo.
set -e
D=$(cd "$(dirname "$0")" && pwd)
R=$(cd "$D/../.." && pwd)
W=${T80MEM_WORK:-$HOME/t80mem_work}
[ -n "$1" ] || { echo "uso: build.sh <DLY>"; exit 1; }
mkdir -p "$W"
if [ ! -f "$W/g80a_rtl.v" ] || [ -n "$(find "$R/fpga/G80A" -name '*.vhd' -newer "$W/g80a_rtl.v")" ]; then
    bash "$D/gen_t80.sh"
fi
rm -f "$W/tb_dly$1.vvp"
iverilog -g2005 -Ptb_t80mem.DLY="$1" -o "$W/tb_dly$1.vvp" "$D/tb_t80mem.v" "$W/g80a_rtl.v" \
    "$R/fpga/src/memory.v" "$R/tools/sdr16_tb/w9825_model.v" "$R/fpga/src/wondertang/pinfilter.v" 2>&1 \
    | grep -v "sorry: constant selects" | head -20
[ -s "$W/tb_dly$1.vvp" ] || { echo "build.sh: no se ha compilado tb_dly$1.vvp"; exit 1; }
echo "tb_dly$1.vvp compilado"
