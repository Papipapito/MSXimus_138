#!/bin/bash
# Megaram V3.5 (4 MB + NEO) contra la V3.1 como oraculo.
# megaram_old.v se regenera desde git: git show V3.1:fpga/src/megaram.v | sed 's/^module megaram_scc(/module megaram_scc_old(/'
# Uso: wsl.exe -d Ubuntu-24.04 bash -lc "cd /mnt/c/Users/alber/proyectosAI/msx/MSX_up_v3/tools/megaram_tb && bash run.sh"
set -e
cd "$(dirname "$0")"
iverilog -g2012 -o tb_megaram.vvp tb_megaram.sv megaram_old.v ../../fpga/src/megaram.v
vvp -n tb_megaram.vvp | grep -v -E '^\s*$'
