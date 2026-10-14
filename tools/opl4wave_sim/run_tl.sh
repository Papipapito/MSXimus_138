#!/bin/bash
# run_tl.sh — TL con LD=0 del motor PCM OPL4 (13/10/2026): fundido 0->24 en ~15 ms y sin el patron de 3 muestras,
# subida 24->0 en ~7 ms y TL=7Fh = silencio. Las tres fases (tb_tl.v +fase=N) corren en paralelo (unos 3 minutos).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_tl.sh
set -e
cd "$(dirname "$0")"
# 138K: el motor va a 36 MHz (medio periodo 13,889 ns), no a 37,5
iverilog -g2012 -Ptb_tl.ENG_HALF=13.889 -s tb_tl -o /tmp/tb_tl.out \
    tb_tl.v \
    ../../fpga/src/opl4_pcm.v \
    ../../fpga/opl4wave/ymf278b_gowin.v
for f in 1 2 3; do
    vvp -n /tmp/tb_tl.out +fase=$f > /tmp/tb_tl_$f.log 2>&1 &
done
wait
cat /tmp/tb_tl_1.log /tmp/tb_tl_2.log /tmp/tb_tl_3.log | grep -v '\$finish'
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_tl_1.log /tmp/tb_tl_2.log /tmp/tb_tl_3.log | grep -q .
