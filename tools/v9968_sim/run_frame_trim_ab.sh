#!/bin/bash
# run_frame_trim_ab.sh - A/B de PIXELES del recorte de v3.8.6: tb_sprite_yjk_vdp.sv (G7 + sprites en SCREEN 8 / 10-11 / 12, un cuadro volcado de la paleta
# con el VDP completo) compilado con y sin -DFRAME_TRIM_OFF. El recorte solo salta ciclos de una media linea de blanking, asi que los volcados
# (transiciones de color por linea, por numero de pixel) tienen que ser IDENTICOS byte a byte.
# Uso (WSL): bash run_frame_trim_ab.sh [dir con fpga/v9968]      Verilator: ~2 min (2 compilaciones + 6 simulaciones en paralelo).
S="$(cd "$(dirname "$0")" && pwd)"
R="${1:-$S/../../fpga/v9968}"
B=/tmp/frmab_$$; mkdir -p "$B"
cd "$B"
for v in on off; do
    D=""; [ "$v" = off ] && D="-DFRAME_TRIM_OFF"
    ( verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH $D --top-module tb_sprite_yjk_vdp -Mdir obj_$v \
        "$S/tb_sprite_yjk_vdp.sv" "$R"/*.v > verilate_$v.log 2>&1 || { grep -E '%Error' verilate_$v.log | head -12; echo "FALLA la compilacion ($v)"; } ) &
done
wait
[ -x obj_on/Vtb_sprite_yjk_vdp ] && [ -x obj_off/Vtb_sprite_yjk_vdp ] || { echo "TB_FAIL: sin binarios"; exit 1; }
for v in on off; do
    for m in 8 11 12; do
        mkdir -p run_${v}_$m
        ( cd run_${v}_$m && ../obj_$v/Vtb_sprite_yjk_vdp +MODE=$m | grep -E "FRAME|TIMEOUT|FIN" ) &
    done
done
wait
E=0
for m in 8 11 12; do
    a=run_on_$m/sprite_$m.txt; b=run_off_$m/sprite_$m.txt
    if [ ! -s "$a" ] || [ ! -s "$b" ]; then echo "FALLO modo $m: falta el volcado"; E=1; continue; fi
    if cmp -s "$a" "$b"; then echo "ok    modo $m: $(grep -c '^L ' $a) lineas, $(wc -l < $a) renglones, IDENTICOS con y sin recorte"
    else echo "FALLO modo $m: los volcados difieren"; diff "$a" "$b" | head -6; E=1; fi
done
[ $E = 0 ] && echo TB_OK || echo TB_FAIL
cd /
if [ -n "$KEEP" ]; then echo "volcados en $B"; else rm -rf "$B"; fi
exit $E
