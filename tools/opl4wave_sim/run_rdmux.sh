#!/bin/bash
# run_rdmux.sh — la lectura por 7Fh de un registro no puede tocar las RAM de otros (15/10/2026), tb_rdmux.v con el motor entero:
#   sin lecturas (control) y con la CPU releyendo sin parar 02h, 03h, 06h, 50h y 70h (registros que NO son de las RAM de
#   FNUM/LFO: 03h, 50h y 70h dejaban las 12 colas con PRVB en 471..560 en vez de 199) y 21h, 38h y 81h (de las RAM de FNUM/LFO,
#   pero del mismo slot o de uno con el mismo valor: tampoco cambian nada). Aceptacion: las 12 colas entre 196 y 203.
#   +info=1 (ultima linea, no puntua): 39h, el FNUM alto de un slot SIN PRVB, que comparte el puerto con el motor mientras dura
#   REG_RD y sigue quitando el PRVB (limitacion conocida del diseno: una sola RAM de FNUM para el motor y la CPU).
# Control negativo: pasar como argumento el motor anterior (git show 82eb524:fpga/opl4wave/ymf278b_gowin.v > /tmp/viejo.v);
# deben FALLAR 03h, 21h, 50h, 70h y 81h (02h, 06h y 38h pasan por casualidad: la direccion que roban cae en un slot con PRVB).
# Uso: wsl -d Ubuntu-24.04 -- bash tools/opl4wave_sim/run_rdmux.sh [motor.v]   (unos 3 minutos)
set -e
cd "$(dirname "$0")"
MOTOR=${1:-../../fpga/opl4wave/ymf278b_gowin.v}
iverilog -g2012 -s tb_rdmux -o /tmp/tb_rdmux.out \
    tb_rdmux.v \
    ../../fpga/src/opl4_pcm.v \
    "$MOTOR"
vvp -n /tmp/tb_rdmux.out +modo=0 > /tmp/tb_rdmux_ref.log 2>&1 &
for r in 02 03 06 21 38 50 70 81; do
    vvp -n /tmp/tb_rdmux.out +modo=1 +reg=$r > /tmp/tb_rdmux_$r.log 2>&1 &
done
vvp -n /tmp/tb_rdmux.out +modo=1 +reg=39 +info=1 > /tmp/tb_rdmux_39.log 2>&1 &
wait
for f in ref 02 03 06 21 38 50 70 81 39; do
    grep -v '\$finish' /tmp/tb_rdmux_$f.log | grep -v '^0:'
done
! grep -L "TODOS LOS TESTS PASAN" /tmp/tb_rdmux_{ref,02,03,06,21,38,50,70,81}.log | grep -q .
