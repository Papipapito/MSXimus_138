#!/bin/bash
# run_amwrap.sh — suma LEVEL + TL + ALFO del motor PCM OPL4 (15/10/2026), tb_amwrap.v con el motor entero:
#   fase 1: slot ocioso (EVOL=3FFh) con AM y TL=7Fh mientras otro slot suena -> su salida es 0 exacto (antes: ~5700, ruido de banda
#           ancha en el fundido de la demo de MBWave); fase 2: KEY ON con TL=7Fh y EVOL en ataque -> silencio;
#   fase 3: EVOL entre 3C0h y 3FFh con TL=0 -> silencio, y LevelAddTLALFO exhaustiva contra min(LEVEL+TL+ALFO,3FFh);
#   fase 4: nota normal con y sin AM (el tremolo sigue funcionando) + CHECKSUM, que debe ser el mismo con el motor anterior.
# Las cuatro fases (tb_amwrap.v +fase=N) corren en paralelo (un par de minutos).
# Control negativo: pasar como argumento el motor anterior (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v);
# deben FALLAR la fase 1 (pico ~5700 con TL=7Fh, 211 muestras con suma > 7FFh) y la 3 (la comprobacion exhaustiva de la funcion:
# 8671 combinaciones distintas de min()); la 2 y la 4 pasan, la 4 con el mismo CHECKSUM (con TL=0 nada cambia).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_amwrap.sh [motor.v]
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_amwrap -o /tmp/tb_amwrap.out \
    tb_amwrap.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
for f in 1 2 3 4; do
    vvp -n /tmp/tb_amwrap.out +fase=$f > /tmp/tb_amwrap_$f.log 2>&1 < /dev/null &
done
wait
for f in 1 2 3 4; do
    echo "######## fase $f"
    grep -v '\$finish' /tmp/tb_amwrap_$f.log
done
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_amwrap_{1,2,3,4}.log | grep -q .
