#!/bin/bash
# Simulacion del motor PCM OPL4 + opl4_pcm.v en Icarus (WSL Ubuntu-24.04).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_sim.sh
set -e
cd "$(dirname "$0")"
# Dos pasadas: NEW2 con el dato por C7h (VGMPlay, MBWave) y por C5h (los drivers WAVEDRVR de Moonsoft, 13/10/2026).
for def in "" "-DNEW2_POR_C5"; do
    iverilog -g2012 $def -s tb_opl4pcm -o /tmp/tb_opl4pcm.out \
        tb_opl4pcm.v \
        ../../fpga/src/opl4_pcm.v \
        ../../fpga/opl4wave/ymf278b_gowin.v
    vvp /tmp/tb_opl4pcm.out
done
