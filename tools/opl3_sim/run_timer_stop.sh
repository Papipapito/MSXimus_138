#!/bin/bash
# Banco del temporizador del OPL3 parado en el ciclo critico (Verilator), traido de MoonTANG.
# Uso (WSL Ubuntu-24.04):  bash tools/opl3_sim/run_timer_stop.sh [negativo]
#   negativo: con el timer.sv anterior al arreglo (el de a39424f): TIENE que fallar (5 de 9).
set -e
cd "$(dirname "$0")"
FPGA=../../fpga
B=obj_timer_stop
rm -rf $B && mkdir -p $B/src
cp $FPGA/opl3/*.sv $FPGA/opl3/*.v $FPGA/src/opl4fm.v $B/src/
if [ "$1" = "negativo" ]; then
    git -C $FPGA show a39424f:fpga/opl3/timer.sv > $B/src/timer.sv
    echo "(control negativo: timer.sv sin el arreglo)"
fi
FILES="$B/src/opl3_pkg.sv $(ls $B/src/*.sv $B/src/*.v | grep -v opl3_pkg.sv | grep -v opl4fm.v | tr '\n' ' ') $B/src/opl4fm.v"
verilator --cc --exe --build -j 4 -Wno-fatal --public-flat-rw --Mdir $B/obj --top-module opl4fm -CFLAGS "-O2" \
    $FILES $PWD/tb_timer_stop.cpp > $B/verilator.log 2>&1 || { tail -40 $B/verilator.log; exit 1; }
./$B/obj/Vopl4fm "${1:-actual}"
