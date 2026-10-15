#!/bin/bash
# run_memmode.sh — modo de acceso a memoria del motor PCM OPL4 (15/10/2026), tb_memmode.v con el motor entero:
#   pasada 1 (control): el mismo trafico de OUT 03h-06h SIN modo memoria -> la musica sigue;
#   pasada 2: OUT 02h = 11h, 1024 bytes a la RAM de ondas, OUT 02h = 10h -> durante la carga pcm_l vale 0 EXACTO;
#   pasada 3: pulso corto (02h = 11h y 02h = 10h seguidos, ~12 us).
# Despues compara las tres muestra a muestra: toda muestra de las pasadas 2 y 3 es 0 o IGUAL a la del control en el mismo indice (ni DC ni
# datos rancios, la musica reanuda donde toca), las muestras mudas son las del modo mas 2, y mide el salto de entrada y el de salida.
# Control negativo: pasar como argumento un motor anterior al 15/10 (p. ej. git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v,
# que tambien lleva la suma de 11 bits: tb_memmode no la ejercita); la pasada 2
# debe FALLAR (continuo de ~1700 durante la carga) y la comparacion tambien.
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_memmode.sh [motor.v]   (unos 3 minutos)
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_memmode -o /tmp/tb_memmode.out \
    tb_memmode.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
vvp -n /tmp/tb_memmode.out +mode=1 +dump=/tmp/mm_ctrl.txt  > /tmp/mm_1.log 2>&1 < /dev/null &
vvp -n /tmp/tb_memmode.out +mode=2 +dump=/tmp/mm_mem.txt   > /tmp/mm_2.log 2>&1 < /dev/null &
vvp -n /tmp/tb_memmode.out +mode=3 +dump=/tmp/mm_pulso.txt > /tmp/mm_3.log 2>&1 < /dev/null &
wait
for f in 1 2 3; do
    echo "######## pasada $f"
    grep -v '\$finish' /tmp/mm_$f.log
done
python3 - /tmp/mm_ctrl.txt /tmp/mm_mem.txt /tmp/mm_pulso.txt <<'PY'
import sys

def load(p):
    ent = sal = None
    v = []
    for l in open(p):
        if l.startswith('#'):
            f = dict(x.split('=') for x in l[1:].split())
            ent, sal = int(f['ent']), int(f['sal'])
        else:
            x = l.split()[1]
            v.append(int(x) if x not in ('x', 'z') else 0)   # la primera muestra puede ser X antes de la primera salida del motor
    return ent, sal, v

ce, cs, c = load(sys.argv[1])
ok = True
LAT = 12      # muestras de retraso maximo del FIFO de salida del pegamento (~8 de colchon mas jitter)

def compara(nombre, p, largo):
    global ok
    ent, sal, m = load(p)
    # modo largo: las muestras del modo (sal-ent) mas las 2 de despues (con margen por el reloj); pulso: de 1 a 6
    esperadas_min, esperadas_max = (sal - ent - 2, sal - ent + 8) if largo else (1, 6)
    n = min(len(c), len(m))
    malas = [k for k in range(n) if m[k] != 0 and m[k] != c[k]]
    mudas = [k for k in range(n) if m[k] == 0 and c[k] != 0]
    print("== %s: %d muestras comparadas con el control" % (nombre, n))
    print("   muestras distintas del control y no nulas (continuo o datos rancios): %d%s" % (
        len(malas), (" (primera en %d: %d en vez de %d)" % (malas[0], m[malas[0]], c[malas[0]])) if malas else ""))
    if malas:
        ok = False
    if not mudas:
        print("   FALLO: ninguna muestra muda")
        ok = False
        return
    f, l = mudas[0], mudas[-1]
    print("   muestras mudas (0 donde el control no es 0): %d, de la %d a la %d; el modo empieza en la %d y acaba en la %d" % (len(mudas), f, l, ent, sal))
    # el FIFO del pegamento (opl4_pcm.v) retrasa ~9 muestras lo que el motor saca: los indices mudos van desplazados
    if f < ent or l > sal + 3 + LAT:
        print("   FALLO: hay muestras mudas fuera del modo (+3 tras soltarlo, +%d de FIFO)" % LAT)
        ok = False
    if len(mudas) < esperadas_min or len(mudas) > esperadas_max:
        print("   FALLO: se esperaban entre %d y %d muestras mudas" % (esperadas_min, esperadas_max))
        ok = False
    huecos = [k for k in range(f, l + 1) if m[k] != 0]
    if huecos:
        print("   FALLO: la salida no es 0 en todo el tramo mudo (muestras %s...)" % huecos[:5])
        ok = False
    salto_ent = abs(m[f - 1] - m[f]) if f > 0 else 0
    salto_sal = abs(m[l + 1] - m[l]) if l + 1 < n else 0
    nat = max(abs(c[k + 1] - c[k]) for k in range(ent - 200, ent))
    print("   salto de entrada (ultima muestra audible -> 0) = %d; salto de salida (0 -> primera audible) = %d; mayor salto entre muestras seguidas de la musica = %d" % (salto_ent, salto_sal, nat))
    print("   tras el modo la salida es otra vez la del control desde la muestra %d (%d muestras despues de soltarlo)" % (l + 1, l + 1 - sal))

compara("pasada 2: modo memoria", sys.argv[2], True)
compara("pasada 3: pulso corto", sys.argv[3], False)
print("RESULTADO MODO MEMORIA:", "OK" if ok else "FALLO")
raise SystemExit(0 if ok else 1)
PY
! grep -L "TODOS LOS TESTS PASAN" /tmp/mm_1.log /tmp/mm_2.log /tmp/mm_3.log | grep -q .
