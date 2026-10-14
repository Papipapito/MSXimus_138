#!/bin/bash
# run_pan.sh — _116: valida la POLARIDAD del fix de pan de srg320 (5379b34).
# Canon: pan=+3 atenua IZQUIERDA; pan=13 (-3) la deja plena; pan=0 centro.
# 13/10/2026: ademas mide la LEY. El chip baja 3 dB por paso (pan_left/pan_right de openMSX); el motor bajaba 12 dB
# (pan 3 => 1/64). Con pan 3 el cociente L/R debe ser 0,375 (-8,5 dB), con pan 13 el R/L, y con pan 0 las dos salidas
# iguales; el canal que no se atenua no cambia. Falla (codigo != 0) si no.
set -e
cd "$(dirname "$0")"
iverilog -g2012 -s tb_yrw801 -o /tmp/typan.out tb_yrw801.v \
    ../../fpga/src/opl4_pcm.v ../../fpga/opl4wave/ymf278b_gowin.v
for p in 0 3 13; do
    vvp /tmp/typan.out +wave=384 +fmt8=1 +nsamp=3000 +pan=$p +dumpr > /dev/null 2>&1 || true
    mv pcm_dump.txt pan_$p.txt
    mv pcm_dump_r.txt panr_$p.txt
done
echo "runs completos"
python3 - <<'PY'
def suma(f): return sum(abs(int(x)) for x in open(f).read().split() if x != 'x')
L = {p: suma('pan_%d.txt' % p) for p in (0, 3, 13)}
R = {p: suma('panr_%d.txt' % p) for p in (0, 3, 13)}
ok = True
def chk(nombre, valor, esperado, tol):
    global ok
    bien = abs(valor - esperado) <= tol
    ok = ok and bien
    print("  %-34s %.4f (esperado %.3f +-%.3f)  %s" % (nombre, valor, esperado, tol, "ok" if bien else "FALLO"))
chk("pan 0:  L/R", L[0] / R[0], 1.0, 0.002)
chk("pan 3:  L/R (izquierda atenuada)", L[3] / R[3], 0.375, 0.01)
chk("pan 3:  R igual que con pan 0", R[3] / R[0], 1.0, 0.002)
chk("pan 13: R/L (derecha atenuada)", R[13] / L[13], 0.375, 0.01)
chk("pan 13: L igual que con pan 0", L[13] / L[0], 1.0, 0.002)
print("RESULTADO PAN:", "OK" if ok else "FALLO")
raise SystemExit(0 if ok else 1)
PY
