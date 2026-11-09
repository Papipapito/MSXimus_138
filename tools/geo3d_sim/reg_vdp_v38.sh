#!/bin/bash
# ============================================================================
# reg_vdp_v38.sh -- regresion del vdp.v con ext_cmd_* (geo3d) contra la V3.8: cada banco de tools/v9968_sim que
# instancia vdp se compila y se corre (iverilog, con sus valores por defecto) DOS veces, con el arbol de esta rama (sus tb_*.sv
# con ext_cmd_* atados a 0) y con un arbol V3.8 (sus tb_*.sv y su vdp.v), y se compara la salida: el texto que
# imprime (sin rutas ni numeros de linea de los .sv, que cambian por la linea del atado) y cada fichero que deja.
#
# Uso (WSL): bash reg_vdp_v38.sh <arbol V3.8> [banco ...]      (sin bancos: todos los que instancian vdp)
#   TO=600   tope de segundos por simulacion (timeout); si los dos cortan, se compara el prefijo comun de la salida
#   JOBS=12  simulaciones a la vez
#   OUT=~/reg_vdp_v38   directorio de trabajo (uno por banco y arbol); KEEP=0 lo borra al acabar
#   HRA_SRC  src del V9968_Cartridge de HRA (tb_screen5b usa su ip_sdram y el modelo Micron)
# Fuera: tb_geo3d_* (no existen en la V3.8) y tb_t2cpuread (no elabora tampoco en la V3.8: u_glue.wr_start).
# Resultado por banco: IGUAL (los dos acaban) / IGUAL_PREFIJO(n lineas) (los dos cortados por TO) / DISTINTO /
# NO_COMPILA, mas las lineas que imprime la rama y sus palabras PASS/FAIL/OK/ERROR/TIMEOUT.
# ============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
V="$(realpath "$1")"; shift
S="$(cd "$(dirname "$0")" && pwd)"
G="$(cd "$S/../.." && pwd)"
TO=${TO:-600}; JOBS=${JOBS:-12}; OUT=${OUT:-$HOME/reg_vdp_v38}
HRA_SRC=${HRA_SRC:-/mnt/c/Users/alber/proyectosAI/msx/V9968_Cartridge/fpga/V9968_Cartridge_TangNano20K/src}
[ -f "$V/fpga/v9968/vdp.v" ] || { echo "no es un arbol del 138K: $V"; exit 2; }
mkdir -p "$OUT"
if [ $# -gt 0 ]; then TBS="$*"; else
    TBS=$(cd "$G/tools/v9968_sim" && grep -l -E '^\s*vdp\s+(#\s*\(.*\)\s*)?\w+\s*\(' tb_*.sv | sed 's/\.sv$//' \
          | grep -v -E '^tb_geo3d_|^tb_t2cpuread$')
fi

ficheros() {   # <arbol> <banco>: la receta de iverilog (la de sus scripts)
    local R=$1 tb=$2
    case $tb in
        tb_sc8cmd_full|tb_screen8_full)
            echo "$R/fpga/src/v9968_vram_shim.v $R/fpga/src/v9968_sdram_bridge.v $R/fpga/src/memory.v $R/tools/sdr16_tb/w9825_model.v $R/fpga/v9968/*.v";;
        tb_screen5b)
            echo "$R/fpga/v9968/*.v $HRA_SRC/sdram/ip_sdram_tangnano20k_c.v $HRA_SRC/test_top_SCREEN5_HMMV/MT48LC2M32B2.v";;
        *)  echo "$R/fpga/v9968/*.v $R/fpga/src/v9968_vram_shim.v $R/fpga/src/v9968_cpu_glue.v";;
    esac
}
plusargs() {   # <arbol> <banco>: los que no corren sin estimulo
    case $2 in
        tb_bootreplay) echo "+stim=$1/tools/v9968_sim/fleet_ops_w12.txt";;
    esac
}
uno() {        # <etiqueta g|v> <banco>
    local t=$1 tb=$2 R; [ $t = g ] && R=$G || R=$V
    local d="$OUT/$tb/$t"; rm -rf "$d"; mkdir -p "$d"; cd "$d"
    if ! iverilog -g2012 -I"$R/tools/v9968_sim" -o "$OUT/$tb/$t.vvp" -s $tb "$R/tools/v9968_sim/$tb.sv" $(ficheros $R $tb) \
            > "$OUT/$tb/$t.build" 2>&1; then echo NO_COMPILA > "$OUT/$tb/$t.rc"; return; fi
    local t0=$(date +%s)
    timeout $TO stdbuf -oL vvp -n "$OUT/$tb/$t.vvp" $(plusargs $R $tb) > "$OUT/$tb/$t.log" 2>&1
    echo "$? $(( $(date +%s) - t0 ))" > "$OUT/$tb/$t.rc"
    sed -E -e "s#$R#<R>#g" -e 's#([A-Za-z0-9_]+\.s?v):[0-9]+#\1:N#g' "$OUT/$tb/$t.log" > "$OUT/$tb/$t.norm"
}
export -f uno ficheros plusargs; export G V TO OUT HRA_SRC
t0=$(date +%s)
for tb in $TBS; do echo "g $tb"; echo "v $tb"; done | xargs -P $JOBS -n 2 bash -c 'uno "$0" "$1"'
echo "simulaciones: $(( $(date +%s) - t0 )) s, TO=$TO s"

ndis=0
printf "%-20s %-22s %-10s %-10s %-6s %s\n" banco resultado "rc/s rama" "rc/s V3.8" lineas "palabras clave (rama)"
for tb in $TBS; do
    d="$OUT/$tb"; rg=$(cat $d/g.rc); rv=$(cat $d/v.rc); res=""
    if [ "$rg" = NO_COMPILA ] || [ "$rv" = NO_COMPILA ]; then res=NO_COMPILA
    else
        if [ "${rg%% *}" != 124 ] && [ "${rv%% *}" != 124 ] && cmp -s $d/g.norm $d/v.norm; then res=IGUAL
        elif [ "${rg%% *}" = 124 ] && [ "${rv%% *}" = 124 ]; then
            n=$(( $(wc -l < $d/g.norm) < $(wc -l < $d/v.norm) ? $(wc -l < $d/g.norm) : $(wc -l < $d/v.norm) ))
            n=$(( n > 0 ? n - 1 : 0 ))   # la ultima linea puede ir a medias
            if cmp -s <(head -n $n $d/g.norm) <(head -n $n $d/v.norm); then res="IGUAL_PREFIJO($n)"; else res=DISTINTO; fi
        else res=DISTINTO; fi
        # los ficheros que deja cada simulacion
        for f in $(cd $d/g && ls); do
            [ -f $d/v/$f ] || { res="$res,falta_v:$f"; continue; }
            if [ "${rg%% *}" = 124 ] || [ "${rv%% *}" = 124 ]; then
                m=$(( $(wc -l < $d/g/$f) < $(wc -l < $d/v/$f) ? $(wc -l < $d/g/$f) : $(wc -l < $d/v/$f) ))
                m=$(( m > 0 ? m - 1 : 0 ))
                cmp -s <(head -n $m $d/g/$f) <(head -n $m $d/v/$f) || res="$res,distinto:$f"
            else cmp -s $d/g/$f $d/v/$f || res="$res,distinto:$f"; fi
        done
        for f in $(cd $d/v && ls); do [ -f $d/g/$f ] || res="$res,falta_g:$f"; done
    fi
    case $res in IGUAL|IGUAL_PREFIJO*) case $res in *,*) ndis=$((ndis+1));; esac;; *) ndis=$((ndis+1));; esac
    kw=$(grep -hoiE "PASS|FAIL|FALLO|OK\b|ERROR|TIMEOUT|DIFFS?=[0-9]+|diffs [0-9]+|mismatch|errores?[ =:]+[0-9]+" $d/g.log 2>/dev/null | sort | uniq -c | awk '{printf "%s:%s ", $2, $1}')
    printf "%-20s %-22s %-10s %-10s %-6s %s\n" $tb "$res" "${rg// //}" "${rv// //}" "$(wc -l < $d/g.log 2>/dev/null)" "$kw"
done
echo "bancos: $(echo $TBS | wc -w), con diferencias o sin compilar: $ndis"
[ "${KEEP:-1}" = 1 ] || rm -rf "$OUT"
[ "$ndis" = 0 ]
