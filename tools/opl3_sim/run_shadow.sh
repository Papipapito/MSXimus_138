#!/bin/bash
# Banco del shadow de lectura de los registros FM (opl4fm.v, Verilator), 15/10/2026: un solo latch de direccion FM,
# el banco de cada registro lo fija el ULTIMO C4h/C6h y no el puerto de datos (C5h/C7h), y el core OPL3 recibe cada
# dato en el banco correcto.
# Uso (WSL Ubuntu-24.04):  bash tools/opl3_sim/run_shadow.sh [opl4fm.v]
#   opl4fm.v: control negativo con el shadow anterior (git show 82eb524:fpga/src/opl4fm.v > /tmp/viejo_opl4fm.v):
#             TIENE que fallar (S2, S3, S4 y S5).
set -e
cd "$(dirname "$0")"
FPGA=../../fpga
B=$(mktemp -d /tmp/opl3_shadow.XXXXXX)
mkdir -p $B/src
cp $FPGA/opl3/*.sv $FPGA/opl3/*.v $B/src/
cp "${1:-$FPGA/src/opl4fm.v}" $B/src/opl4fm.v
if [ -n "$1" ]; then echo "(control negativo: opl4fm.v de $1)"; fi
FILES="$B/src/opl3_pkg.sv $(ls $B/src/*.sv $B/src/*.v | grep -v opl3_pkg.sv | grep -v opl4fm.v | tr '\n' ' ') $B/src/opl4fm.v"
verilator --cc --exe --build -j 4 -Wno-fatal --public-flat-rw --Mdir $B/obj --top-module opl4fm -CFLAGS "-O2" \
    $FILES $PWD/tb_shadow.cpp > $B/verilator.log 2>&1 || { tail -40 $B/verilator.log; exit 1; }
RC=0
$B/obj/Vopl4fm || RC=$?
rm -rf $B
exit $RC
