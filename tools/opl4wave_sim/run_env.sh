#!/bin/bash
# run_env.sh — envolvente del motor PCM OPL4 (13/10/2026): tb_envfn (EffRateCalc, EnvStep y EnvInc contra openMSX/libvgm
# para todas las combinaciones) y tb_env con el motor entero (nota con OCT=-4/RC=0/D2R=1 que no se apaga; ataque con
# AR=9 de ~24 ms). Los tres bancos corren en paralelo (unos 50 s).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_env.sh
set -e
cd "$(dirname "$0")"
iverilog -g2012 -s tb_envfn -o /tmp/tb_envfn.out \
    tb_envfn.v \
    ../../fpga/opl4wave/ymf278b_gowin.v
# 138K: el motor va a 36 MHz (medio periodo 13,889 ns), no a 37,5
iverilog -g2012 -Ptb_env.ENG_HALF=13.889 -s tb_env -o /tmp/tb_env.out \
    tb_env.v \
    ../../fpga/src/opl4_pcm.v \
    ../../fpga/opl4wave/ymf278b_gowin.v
vvp -n /tmp/tb_envfn.out > /tmp/tb_envfn.log 2>&1 &
vvp -n /tmp/tb_env.out +fase=1 > /tmp/tb_env_1.log 2>&1 &
vvp -n /tmp/tb_env.out +fase=2 > /tmp/tb_env_2.log 2>&1 &
wait
cat /tmp/tb_envfn.log /tmp/tb_env_1.log /tmp/tb_env_2.log | grep -v '\$finish'
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_envfn.log /tmp/tb_env_1.log /tmp/tb_env_2.log | grep -q .
