#!/bin/bash
# run_frame_trim.sh - tb_frame_trim.sv: periodo del cuadro del VDP completo con el recorte de v3.8.6 y sin el (-DFRAME_TRIM_OFF).
# Esperado (ciclos de clk 85,909 MHz):  60 Hz con recorte 1.431.824 (1.237.505 px del HDMI = 59,99976 Hz);  60 Hz sin recorte 1.433.664;
# En todos los casos 524 flancos HS por cuadro y 480 lineas con display_en.
# Con recorte, una linea corta por cuadro de 896 ciclos (2736 - 1840), siempre en el mismo sitio; sin recorte, ninguna.
# El bit NT de R#9 (50 Hz) se IGNORA en este VDP (vdp_cpu_interface.v, MSXimus _125: NTSC-only, el puente HDMI es 60 Hz fijo): R#9 con NT = 1
# da exactamente lo mismo que sin el. Por eso el recorte esta siempre activo y la guarda !reg_50hz_mode es solo prevision (no se puede ejercitar por el bus).
# Uso (WSL): bash run_frame_trim.sh [dir con fpga/v9968]      Verilator: ~1 min por compilacion.
S="$(cd "$(dirname "$0")" && pwd)"
R="${1:-$S/../../fpga/v9968}"
B=/tmp/frmtrim_$$; mkdir -p "$B"
cd "$B"
for v in on off; do
    D=""; [ "$v" = off ] && D="-DFRAME_TRIM_OFF"
    ( verilator --binary --timing -j 8 -Wno-fatal -Wno-BLKANDNBLK -Wno-WIDTH $D --top-module tb_frame_trim -Mdir obj_$v \
        "$S/tb_frame_trim.sv" "$R"/*.v > verilate_$v.log 2>&1 || { grep -E '%Error' verilate_$v.log | head -12; echo "FALLA la compilacion ($v)"; } ) &
done
wait
[ -x obj_on/Vtb_frame_trim ] && [ -x obj_off/Vtb_frame_trim ] || { echo "TB_FAIL: sin binarios"; exit 1; }
# R#9: 0 = 192 lineas; 128 = 212; 8 = entrelazado 192; 136 = entrelazado 212; 2 y 130 = lo mismo con NT = 1 (ignorado)
for v in on off; do
    for r in 0 128 8 136 2 130; do
        ./obj_$v/Vtb_frame_trim +R9=$r > out_${v}_$r.log 2>&1 &
    done
done
wait
python3 - <<'EOF'
import re, sys, glob
def get(v, r):
    t = open('out_%s_%d.log' % (v, r)).read()
    m = re.search(r'RESULT (.*)', t)
    if not m:
        return None
    return {k: int(x) for k, x in re.findall(r'(\w+)=(-?\d+)', m.group(1))}, m.group(1)
bad = 0
for r, name in ((0, '192'), (128, '212'), (8, '192 IL'), (136, '212 IL'), (2, '192 NT=1'), (130, '212 NT=1')):
    for v in ('on', 'off'):
        g = get(v, r)
        if g is None:
            print('FALLO %-14s %-3s sin RESULT' % (name, v)); bad += 1; continue
        d, raw = g
        if v == 'on':
            exp_p, exp_hs, exp_short = 524 * 2736 - 1840, 524, 1
        else:
            exp_p, exp_hs, exp_short = 524 * 2736, 524, 0
        ok = (d['period_min'] == exp_p and d['period_max'] == exp_p and d['hs_min'] == exp_hs and d['hs_max'] == exp_hs
              and d['en_min'] == 480 and d['en_max'] == 480 and d['other_lines'] == 0
              and (d['short_lines'] == 0 if exp_short == 0 else d['frames'] <= d['short_lines'] <= d['frames'] + 2))
        if v == 'on':
            ok = ok and d['short_len'] == 2736 - 1840 and d['short_per_frame_max'] == 1 and d['short_pos_min'] == d['short_pos_max']
        print('%s %-14s %-3s periodo=%d (esperado %d) hs=%d..%d en=%d..%d cortas=%d %s' % (
            'ok   ' if ok else 'FALLO', name, v, d['period_min'], exp_p, d['hs_min'], d['hs_max'], d['en_min'], d['en_max'],
            d['short_lines'], ('len=%d pos=%d' % (d['short_len'], d['short_pos_min'])) if d['short_lines'] else ''))
        if not ok:
            bad += 1
            print('      ' + raw)
print('TB_OK' if bad == 0 else 'TB_FAIL (%d)' % bad)
sys.exit(1 if bad else 0)
EOF
E=$?
cd /
if [ -n "$KEEP" ]; then echo "volcados en $B"; else rm -rf "$B"; fi
exit $E
