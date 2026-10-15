#!/bin/bash
# run_lforst.sh — bit de reset del LFO (68h+slot, bit 5) del motor PCM OPL4 (15/10/2026), tb_lforst.v con el motor entero:
#   sin reset (control: ningun LFO parado), reset en un slot (0, 5, 6, 11, 17, 18, 23: incluye el salto 23 -> 0), en dos (0 y 23),
#   la salida pcm_l de un slot solo (con reset: pico plano; sin reset: baja por el tremolo) y con la CPU releyendo sin parar 50h
#   (roba el puerto de la BSRAM de slot: tolera 1 tick) o 03h (no toca nada). Cada caso mira DENTRO del motor
#   el DATA del LFO, el ALFO y el PHASE de los 24 slots. Con ALL=1 barre los 24 slots (un caso por slot).
# Control negativo: pasar como argumento el motor anterior (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v);
# debe FALLAR todo caso con reset (el reset caia en el slot k+6).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_lforst.sh [motor.v]
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_lforst -o /tmp/tb_lforst.out \
    tb_lforst.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
CASOS="none k=0 k=5 k=6 k=11 k=17 k=18 k=23 k=0,k2=23 solo=3,k=3 solo=9,k=3 solo=21,k=3 solo=0,k=18 solo=18,k=18 solo=3 k=5,rd=50 k=5,rd=03"
if [ -n "$ALL" ]; then CASOS="none $(for k in $(seq 0 23); do echo -n "k=$k "; done)"; fi
LOGS=""
for c in $CASOS; do
    f=/tmp/tb_lforst_${c//[=,]/_}.log
    args=""; [ "$c" != none ] && args=$(echo "$c" | tr ',' '\n' | sed 's/^/+/' | tr '\n' ' ')
    vvp -n /tmp/tb_lforst.out $args > $f 2>&1 &
    LOGS="$LOGS $f"
done
wait
for f in $LOGS; do
    echo "##### ${f#/tmp/tb_lforst_}"
    grep -v '\$finish' $f
done
! grep -L "TODOS LOS TESTS PASAN" $LOGS | grep -q .
