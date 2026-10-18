#!/bin/bash
# ============================================================================
# run_alex_ce.sh -- los bancos de RTL de Alex (geo3d/sim: tb_geo3d, tb_phase1_on_engine, tb_engine, tb_bus)
# contra el geo3d del 138K (fpga/geo3d), con y sin GEO3D_CE. WSL, iverilog + python3.
#
# Uso: bash run_alex_ce.sh <carpeta geo3d de un clon de alexmoncks/V9968_Cartridge> [<rtl de referencia>]
#   <rtl de referencia>: carpeta con geo3d_core.v, geo3d_engine.v y geo3d_bus.v SIN CE (por ejemplo el
#   fpga/geo3d de la Zynq). Si falta, la referencia es <clon>/rtl.
#   KEEP=1 deja el directorio de trabajo ($WDIR/g3ce_*, por defecto /tmp) con todos los registros.
#
# Variantes:
#   REF  el RTL de referencia, bancos de Alex tal cual
#   A    fpga/geo3d del 138K sin GEO3D_CE, bancos tal cual           -> got y registro IGUALES a REF (ciclo a ciclo)
#   B    GEO3D_CE (geo3d_ce.v), ce = 1 fijo (g3w.v, G3MODE=1)          -> got y registro IGUALES a A (ciclo a ciclo)
#   C2   GEO3D_CE, motor a reloj doble y ce 1/2, fase A (G3MODE=2)    -> got igual y SECUENCIA (num, dato) igual a A
#   C3   igual, fase B (G3MODE=3)                                     -> got igual y SECUENCIA (num, dato) igual a A
#   En tb_bus, C2/C3 es el enganche real del 138K: clk_eng = clk y ce_eng alterno (las dos fases).
# El registro (g3mon.v) es cada cmd_wr que ve el modelo del V9968 del banco: <ciclo> <num> <dato>.
# tb_bus va con las tres familias de escenas (Alex solo lo pasa con las de alambre).
# ============================================================================
set -e
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
G="$(realpath "$1")"
S="$(cd "$(dirname "$0")" && pwd)"
R="$(cd "$S/../.." && pwd)"
REF="$(realpath "${2:-$G/rtl}")"
[ -f "$G/sim/tb_engine.v" ] && [ -f "$G/rtl/geo3d_z80if.v" ] || { echo "no es la carpeta geo3d de Alex: $G"; exit 2; }
W=${WDIR:-/tmp}/g3ce_$$
rm -rf "$W"; mkdir -p "$W"; cp -r "$G/sim" "$W/sim"; cd "$W/sim"
echo "clon de Alex: $G"; echo "referencia:   $REF"; echo "138K:         $R/fpga/geo3d"; echo "trabajo:      $W"

python3 gen_vectors.py 500 vectors.hex > gen.log 2>&1
python3 gen_scenes.py 24 >> gen.log 2>&1
python3 gen_face_scenes.py 16 >> gen.log 2>&1
python3 gen_tex_scenes.py 12 >> gen.log 2>&1
STIMS="scenes face tex"

# copias de los bancos con los envoltorios de g3w.v
sed 's/^\(\s*\)geo3d_engine dut (/\1g3w_engine dut (/' tb_engine.v           > tbw_engine.v
sed 's/^\(\s*\)geo3d_engine dut (/\1g3w_engine dut (/' tb_phase1_on_engine.v > tbw_phase1_on_engine.v
sed 's/^\(\s*\)geo3d_bus dut (/\1g3w_bus dut (/'       tb_bus.v              > tbw_bus.v
sed 's/^\(\s*\)geo3d_core u_core (/\1g3w_core u_core (/' "$G/rtl/geo3d_z80if.v" > z80if_w.v
for f in tbw_engine.v tbw_phase1_on_engine.v tbw_bus.v z80if_w.v; do
    grep -q 'g3w_' $f || { echo "sed no ha cambiado $f"; exit 2; }
done

RTL_REF="$REF/geo3d_core.v $REF/geo3d_engine.v $REF/geo3d_bus.v"
RTL_A="$R/fpga/geo3d/geo3d_core.v $R/fpga/geo3d/geo3d_engine.v $R/fpga/geo3d/geo3d_bus.v"
RTL_CE="-I$R/fpga $R/fpga/geo3d/geo3d_ce.v $S/g3w.v"
MON="$S/g3mon.v"

# compila y corre una variante: <var> <modo g3w o 0>
variante() {
    local v=$1 m=$2 d="$W/$1"; mkdir -p "$d"; cd "$W/sim"
    if [ "$m" = 0 ]; then
        local rtl; [ "$v" = REF ] && rtl="$RTL_REF" || rtl="$RTL_A"
        iverilog -g2005 -o $d/tb.vvp  -s tb_geo3d tb_geo3d.v "$G/rtl/geo3d_z80if.v" $rtl
        iverilog -g2005 -o $d/p1.vvp  -s tb_geo3d tb_phase1_on_engine.v $rtl
        iverilog -g2005 -o $d/tbe.vvp -s tb_engine -s g3mon -DG3TB=tb_engine tb_engine.v $rtl $MON
        iverilog -g2005 -o $d/tbb.vvp -s tb_bus -s g3mon -DG3TB=tb_bus tb_bus.v $rtl $MON
    else
        iverilog -g2005 -o $d/tb.vvp  -s tb_geo3d -DG3MODE=$m -DG3Q=5.82 tb_geo3d.v z80if_w.v $RTL_CE
        iverilog -g2005 -o $d/p1.vvp  -s tb_geo3d -DG3MODE=$m -DG3Q=5.82 tbw_phase1_on_engine.v $RTL_CE
        iverilog -g2005 -o $d/tbe.vvp -s tb_engine -s g3mon -DG3TB=tb_engine -DG3MODE=$m -DG3Q=2.91 tbw_engine.v $RTL_CE $MON
        iverilog -g2005 -o $d/tbb.vvp -s tb_bus -s g3mon -DG3TB=tb_bus -DG3MODE=$m tbw_bus.v $RTL_CE $MON
    fi
    vvp -n $d/tb.vvp | grep -E "Resultado|PASS|FAIL" > $d/fase1_core.txt || true
    vvp -n $d/p1.vvp | grep -E "Resultado|PASS|FAIL" > $d/fase1_engine.txt || true
    for k in $STIMS; do
        vvp -n $d/tbe.vvp +stim=${k}_stim.txt +got=$d/eng_${k}_got.txt +seq=$d/eng_${k}_seq.txt | head -1 > $d/eng_${k}.txt &
        vvp -n $d/tbb.vvp +stim=${k}_stim.txt +got=$d/bus_${k}_got.txt +seq=$d/bus_${k}_seq.txt | head -1 > $d/bus_${k}.txt &
    done
    wait
}
t0=$(date +%s)
variante REF 0 & variante A 0 & variante B 1 & variante C2 2 & variante C3 3 &
wait
echo "simulaciones: $(( $(date +%s) - t0 )) s"

set +e
fallos=0
mal() { echo "  FALLO: $*"; fallos=$((fallos + 1)); }
# desfase <registro A> <registro B>: cuantas escrituras caen en otro ciclo y el desfase minimo y maximo
desfase() { paste -d' ' <(cut -d' ' -f1 "$1") <(cut -d' ' -f1 "$2") | awk '{d=$2-$1; if(NR==1||d<mn)mn=d; if(NR==1||d>mx)mx=d; if(d!=0)nd++}
    END{printf "%d de %d desplazadas, desfase %+d..%+d ciclos", nd, NR, mn, mx}'; }
cd "$W"
echo "== fase 1 (geo3d_core por geo3d_z80if de Alex, y por geo3d_engine)"
for v in REF A B C2 C3; do
    printf "  %-3s z80if: %s | engine: %s\n" $v "$(tr '\n' ' ' < $v/fase1_core.txt)" "$(tr '\n' ' ' < $v/fase1_engine.txt)"
    grep -q '^PASS' $v/fase1_core.txt   || mal "$v fase 1 (z80if)"
    grep -q '^PASS' $v/fase1_engine.txt || mal "$v fase 1 (engine)"
    case $v in A|B)   # resultado y latencia medida, iguales; en C2/C3 la latencia se mide en ciclos del banco
        cmp -s REF/fase1_core.txt $v/fase1_core.txt     || mal "$v fase 1 (z80if) distinta de REF"
        cmp -s REF/fase1_engine.txt $v/fase1_engine.txt || mal "$v fase 1 (engine) distinta de REF";;
    esac
done
for tb in eng bus; do
  for k in $STIMS; do
    echo "== $tb / $k"
    for v in REF A B C2 C3; do
        n=$(grep -c -v '^X' $v/${tb}_${k}_seq.txt || true); nx=$(grep -c '^X' $v/${tb}_${k}_seq.txt || true)
        printf "  %-3s %s | escrituras %s, X %s\n" $v "$(cat $v/${tb}_${k}.txt)" "$n" "$nx"
        [ "$nx" = 0 ] || mal "$v $tb $k: $nx escrituras con X"
        grep -q 'violacoes de CE: 0,' $v/${tb}_${k}.txt || mal "$v $tb $k: violaciones de CE"
        diff -q sim/${k}_expect.txt $v/${tb}_${k}_got.txt > /dev/null || mal "$v $tb $k: got distinto del modelo"
        cut -d' ' -f2- $v/${tb}_${k}_seq.txt > $v/${tb}_${k}_nd.txt
    done
    cmp -s REF/${tb}_${k}_got.txt A/${tb}_${k}_got.txt  || mal "A $tb $k: got distinto de REF"
    cmp -s REF/${tb}_${k}_seq.txt A/${tb}_${k}_seq.txt  || mal "A $tb $k: registro distinto de REF (ciclo a ciclo)"
    cmp -s REF/${tb}_${k}.txt A/${tb}_${k}.txt          || mal "A $tb $k: resumen distinto de REF"
    cmp -s A/${tb}_${k}_got.txt B/${tb}_${k}_got.txt    || mal "B $tb $k: got distinto de A"
    if cmp -s A/${tb}_${k}_seq.txt B/${tb}_${k}_seq.txt; then echo "  B  = A ciclo a ciclo"
    elif cmp -s A/${tb}_${k}_nd.txt B/${tb}_${k}_nd.txt; then echo "  B  = A en secuencia (num, dato), no ciclo a ciclo"
         [ $tb = eng ] && mal "B $tb $k: no es ciclo a ciclo"
    else mal "B $tb $k: secuencia distinta de A"; fi
    for v in C2 C3; do
        cmp -s A/${tb}_${k}_got.txt $v/${tb}_${k}_got.txt || mal "$v $tb $k: got distinto de A"
        if cmp -s A/${tb}_${k}_seq.txt $v/${tb}_${k}_seq.txt; then echo "  $v = A ciclo a ciclo"
        elif cmp -s A/${tb}_${k}_nd.txt $v/${tb}_${k}_nd.txt; then
            echo "  $v = A en secuencia (num, dato); instantes distintos ($(desfase A/${tb}_${k}_seq.txt $v/${tb}_${k}_seq.txt))"
        else mal "$v $tb $k: secuencia (num, dato) distinta de A"; diff A/${tb}_${k}_nd.txt $v/${tb}_${k}_nd.txt | head -4; fi
    done
  done
done
if [ "$fallos" = 0 ]; then echo "RESULTADO: PASS"; else echo "RESULTADO: FAIL ($fallos)"; fi
[ "${KEEP:-0}" = 1 ] || rm -rf "$W"
[ "$fallos" = 0 ]
