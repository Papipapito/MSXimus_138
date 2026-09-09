#!/bin/bash
# Banco del sd_reader (V3.5 / V3.5c multibloque) contra el modelo de tarjeta SD,
# mas el banco del sdc_ioport (puertos de E/S).
# Uso (desde Windows):
#   wsl.exe -d Ubuntu-24.04 bash -lc "cd /mnt/c/Users/alber/proyectosAI/msx/MSX_up_v3/tools/sd_tb && bash run.sh"
# Corre tres variantes: 6,75 MHz con TOD=14 ns (spec), 6,75 MHz con TOD=60 ns
# (tarjeta lenta + pista larga) y los 2,25 MHz de siempre como referencia.
set -e
cd "$(dirname "$0")"
SRC=../../fpga/src/wondertang
run_one () {
    local fd=$1 tod=$2
    iverilog -g2012 -o tb_sd_${fd}_${tod}.vvp -P tb_sd.FASTDIV=$fd -P tb_sd.TOD=$tod \
        tb_sd.sv sd_card_model.sv $SRC/sd_reader.sv $SRC/sdcmd_ctrl.sv $SRC/crc16.v
    vvp -n tb_sd_${fd}_${tod}.vvp | tee log_${fd}_${tod}.txt | grep -v -E '^\s*$'
}
run_one 0 14
run_one 0 60
run_one 4 14
echo "---- sdc_ioport ----"
iverilog -g2012 -o tb_sdio.vvp tb_sdio.sv $SRC/sdc_ioport.sv
vvp -n tb_sdio.vvp | tee log_sdio.txt | grep -v -E '^\s*$'
echo "---- cronometro de ms ----"
iverilog -g2012 -o tb_mstimer.vvp tb_mstimer.sv $SRC/sdc_ioport.sv
vvp -n tb_mstimer.vvp | tee log_mstimer.txt | grep -v -E '^\s*$'
echo "---- pegamento bus/puertos/ventana ----"
iverilog -g2012 -o tb_glue.vvp tb_glue.sv $SRC/sdc_ioport.sv
vvp -n tb_glue.vvp | tee log_glue.txt | grep -v -E '^\s*$'
echo "---- Game Master 2 en el slot 1 ----"
iverilog -g2012 -o tb_gm2.vvp tb_gm2.sv ../../fpga/src/gm2_slot1.v
vvp -n tb_gm2.vvp | tee log_gm2.txt | grep -v -E '^\s*$'
echo "---- resumen ----"
grep -h -E '^=== tb_sd .*(TODO OK|FALLOS)' log_[0-9]*.txt
grep -h -E '^=== tb_sdio:' log_sdio.txt
grep -h -E '^=== tb_mstimer:' log_mstimer.txt
grep -h -E '^=== tb_glue:' log_glue.txt
grep -h -E '^=== tb_gm2:' log_gm2.txt
