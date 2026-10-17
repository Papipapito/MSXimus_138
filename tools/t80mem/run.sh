#!/bin/bash
# run.sh [paralelos] - la matriz minima del banco t80mem (README.md): el registro cpu_dout_ram del core (DLY=1) a 3,58 y
# a 5,37 MHz, en dos fases de reloj cada uno, tiene que pasar; el control negativo (DLY=10 a 5,37 y DLY=13 a 3,58) tiene
# que fallar. Unos 2 minutos con 6 en paralelo. Desde Windows (Git Bash):
#   MSYS_NO_PATHCONV=1 wsl.exe -d Ubuntu-24.04 bash -lc "cd /mnt/c/Users/alber/proyectosAI/msx/MSXimus_138/tools/t80mem && bash run.sh"
set -e
D=$(cd "$(dirname "$0")" && pwd)
W=${T80MEM_WORK:-$HOME/t80mem_work}
bash "$D/matrix.sh" "$D/jobs_min.txt" "${1:-6}"
mal=0
for e in d1_t0_a:PASS d1_t0_b:PASS d1_t1_a:PASS d1_t1_b:PASS d10_t1_b:FAIL d13_t0_a:FAIL; do
    et=${e%%:*}
    esp=${e##*:}
    r=$(grep -h 'RESULTADO:' "$W/res/$et.txt" | awk '{print $2}')
    if [ "$r" != "$esp" ]; then
        echo "MAL: $et da '${r:-nada}' y tenia que dar $esp"
        mal=1
    fi
done
if [ $mal = 0 ]; then
    echo "BANCO t80mem: TODO OK (DLY=1: 4 PASS a 3,58 y 5,37 MHz; control negativo: 2 FAIL)"
else
    echo "BANCO t80mem: MAL"
    exit 1
fi
