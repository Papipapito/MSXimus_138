#!/bin/bash
# Simulacion del motor PCM OPL4 + opl4_pcm.v en Icarus (WSL Ubuntu-24.04).
# 15/10/2026: la seccion 1b prueba que NEW2 se apaga con 105h bit 1 = 0. Control negativo: pasar como argumento el motor anterior
# (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v): debe FALLAR la 1b en las dos pasadas.
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_sim.sh [motor.v]
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
# Dos pasadas: NEW2 con el dato por C7h (VGMPlay, MBWave) y por C5h (los drivers WAVEDRVR de Moonsoft, 13/10/2026).
for def in "" "-DNEW2_POR_C5"; do
    iverilog -g2012 $def -s tb_opl4pcm -o /tmp/tb_opl4pcm.out \
        tb_opl4pcm.v \
        ../../fpga/src/opl4_pcm.v \
        "$MOTOR"
    vvp /tmp/tb_opl4pcm.out
done
