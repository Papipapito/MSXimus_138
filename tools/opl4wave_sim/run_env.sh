#!/bin/bash
# run_env.sh — envolvente del motor PCM OPL4 (13/10/2026): tb_envfn (EffRateCalc, EnvStep y EnvInc contra openMSX/libvgm
# para todas las combinaciones) y tb_env con el motor entero (nota con OCT=-4/RC=0/D2R=1 que no se apaga; ataque con
# AR=9 de ~24 ms); 15/10/2026: fases 3-6 de tb_env (DL a 3 dB por paso con >=: codo a 080h con DL=4, a 3E0h con DL=15,
# DL escrito en caliente por debajo del EVOL y DL=0). Los siete bancos corren en paralelo (unos 80 s).
# Control negativo: pasar como argumento el motor anterior (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v):
# deben FALLAR las fases 3, 4 y 5 de tb_env y pasar el resto.
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_env.sh [motor.v]
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_envfn -o /tmp/tb_envfn.out \
    tb_envfn.v \
    "$MOTOR"
# 138K: el motor va a 36 MHz (medio periodo 13,889 ns), no a 37,5
iverilog -g2012 -Ptb_env.ENG_HALF=13.889 -s tb_env -o /tmp/tb_env.out \
    tb_env.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
vvp -n /tmp/tb_envfn.out > /tmp/tb_envfn.log 2>&1 &
for f in 1 2 3 4 5 6; do
    vvp -n /tmp/tb_env.out +fase=$f > /tmp/tb_env_$f.log 2>&1 &
done
wait
cat /tmp/tb_envfn.log /tmp/tb_env_{1,2,3,4,5,6}.log | grep -v '\$finish'
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_envfn.log /tmp/tb_env_{1,2,3,4,5,6}.log | grep -q .
