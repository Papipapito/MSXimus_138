#!/bin/bash
# run_damp.sh — DAMP y pseudo-reverb (PRVB) del motor PCM OPL4 (14/10/2026), tb_damp.v con el motor entero:
#   fases 1-3: KEY OFF con DAMP y RR=2 -> EVOL llega a -12 / -48 / -96 dB en 5,8 / 8,0 / 10,9 ms, con OCT/RC extremos (DAMP
#              ignora la correccion de tasa); fases 4-5: KEY OFF sin DAMP -> la cola sigue como siempre (con su correccion);
#   fase 11: KEY ON + DAMP (la tecla sigue pulsada) y fase 12: el ataque no ve el DAMP, la nota cae al acabarlo;
#   fases 6-10: PRVB -> al cruzar -18 dB la tasa pasa a 20 (D2R, D1R, RR y con correccion de tasa); la 7 es el control sin PRVB.
# Las doce fases (tb_damp.v +fase=N) corren en paralelo (un par de minutos).
# Control negativo: pasar como argumento el motor anterior (git show f6ad042:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v);
# deben FALLAR las fases 1-3, 6, 8-12 y pasar las 4, 5 y 7.
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_damp.sh [motor.v]
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_damp -o /tmp/tb_damp.out \
    tb_damp.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
for f in 1 2 3 4 5 6 7 8 9 10 11 12; do
    vvp -n /tmp/tb_damp.out +fase=$f > /tmp/tb_damp_$f.log 2>&1 &
done
wait
for f in 1 2 3 4 5 6 7 8 9 10 11 12; do
    grep -v '\$finish' /tmp/tb_damp_$f.log
done
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_damp_{1,2,3,4,5,6,7,8,9,10,11,12}.log | grep -q .
