#!/bin/bash
# run_rdnoise.sh — una nota sonando no puede cambiar porque la CPU lea un registro por 7Fh (15/10/2026), tb_rdnoise.v:
#   caso real: la demo "Dutch Moonsound Veterans" relee 68h-7Fh (KEY/PAN) por 7Fh mientras suena la musica; se barren
#   ademas 03h, 05h, 06h (MEMDAT, un cargador que verifique la RAM), 50h, 70h y 98h. Se vuelca pcm_l una vez por muestra y se
#   compara con la referencia: IDENTICO.
#   Los registros de las RAM de FNUM/LFO (20h, 38h, 80h: el FNUM de OTRO slot) se imprimen pero no puntuan: comparten el puerto
#   de lectura con el motor mientras dura REG_RD (limitacion conocida del diseno).
# Control negativo: pasar como argumento el motor anterior (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v);
# deben FALLAR 03h, 05h, 06h, 50h, 70h y 98h (la nota se llena de saltos de fase: ruido).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_rdnoise.sh [motor.v]   (unos 2 minutos)
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_rdnoise -o /tmp/tb_rdnoise.out \
    tb_rdnoise.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
vvp -n /tmp/tb_rdnoise.out +modo=0 +out=/tmp/rdnoise_ref.txt > /tmp/tb_rdnoise_ref.log 2>&1 &
for r in 03 05 06 50 70 98 20 38 80; do
    vvp -n /tmp/tb_rdnoise.out +modo=1 +reg=$r +out=/tmp/rdnoise_$r.txt > /tmp/tb_rdnoise_$r.log 2>&1 &
done
wait
for r in ref 03 05 06 50 70 98 20 38 80; do grep -v '\$finish' /tmp/tb_rdnoise_$r.log; done
python3 - <<'PY'
import sys
def carga(f):
    d = {}
    for ln in open(f):
        i, v = ln.split()
        d[int(i)] = int(v)
    return d
ref = carga('/tmp/rdnoise_ref.txt')
print("referencia: %d muestras, |pcm| max %d" % (len(ref), max(abs(v) for v in ref.values())))
mal = False
for r, puntua in (('03', 1), ('05', 1), ('06', 1), ('50', 1), ('70', 1), ('98', 1), ('20', 0), ('38', 0), ('80', 0)):
    d = carga('/tmp/rdnoise_%s.txt' % r)
    comunes = [i for i in ref if i in d]
    dif = [i for i in comunes if ref[i] != d[i]]
    rms = (sum((ref[i] - d[i]) ** 2 for i in dif) / max(1, len(comunes))) ** 0.5
    mx = max([abs(ref[i] - d[i]) for i in dif] or [0])
    ok = (len(dif) == 0 and len(comunes) > 400)
    print("  lectura de %sh: %4d de %4d muestras distintas de la referencia (error max %5d, rms %7.1f)  %s" %
          (r, len(dif), len(comunes), mx, rms, ("ok" if ok else ("FALLO" if puntua else "(informativo)"))))
    if puntua and not ok: mal = True
print("RESULTADO RDNOISE:", "FALLO" if mal else "OK")
sys.exit(1 if mal else 0)
PY
