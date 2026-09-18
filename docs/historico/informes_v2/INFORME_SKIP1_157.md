# skip1 — Caza en simulación del "+1" del puerto de lectura de VRAM (V9968 / MSXimus 60K)

**Bug de placa**: VRAMSOK2 (SETRD + INs secuenciales por 0x98, ~35+ T-states,
pantalla de texto activa) devuelve esporádicamente el byte de **dir+1**
(0,13% DDR3 / 0,34% SDRAM; nunca dir−1; releer recolocando el puntero SIEMPRE
acierta; wq=0; los drops de pfq no correlacionan).

**VEREDICTO: REPRODUCIDO, LOCALIZADO y con FIX VERIFICADO EN BANCO.
La causa está en `fpga/v9968/vdp_vram_interface.v` (el router de respuestas
por rtag, parche MSXimus), no en el shim ni en el buffer de pre-lectura _149.**
Árbol analizado: `C:\Users\alber\proyectosAI\msx\MSX_up_th9958`, rama th9958,
HEAD `ff33f99` (copias intactas en `src/`; nada committeado — repos solo lectura).

---

## 1. La causa raíz (defecto S1: el strobe que no se limpia)

`vdp_vram_interface.v`, bloque de enrutado de respuestas (líneas 310–332):

```verilog
else if( vram_rdata_en ) begin
    case( vram_rtag[4:2] )
    c_cpu:     begin ff_cpu_vram_rdata <= w_rdata8; ff_cpu_vram_rdata_en <= 1'b1; end
    ...
    endcase
end
else begin
    ff_cpu_vram_rdata_en     <= 1'b0;   // <-- SOLO se limpia si NO hay respuesta
    ff_command_vram_rdata_en <= 1'b0;
end
```

`ff_cpu_vram_rdata_en` solo vuelve a 0 en un ciclo **sin** respuesta del shim.
Si el shim emite **dos respuestas en ciclos consecutivos** — primero la de CPU
(camino `late_v`: la completación de backend espera un hueco de salida) y en el
ciclo inmediato una de bg (`pipe[6]`, el contrato de 8 ciclos del display) — el
strobe de CPU queda **ALTO 2 CICLOS**. La salida del shim encadena ambas sin
hueco (`v9968_vram_shim.v` 976–987): un grant de `late_v` aterrizando en el
ciclo anterior al slot de salida de una respuesta bg de la tubería produce la
adyacencia. El orden inverso (bg→CPU) es inocuo.

### Efecto en `vdp_cpu_interface.v` (el buffer de pre-lectura _149)

Con `cpu_vram_rdata_en` alto 2 ciclos el core hace dos cosas fatales:

1. **Doble autoincremento** (líneas 432–433 y 510–534): `if (vram_rdata_en)
   ff_vram_address_inc <= 1'b1;` se re-arma en el 2.º ciclo y la dirección
   incrementa DOS veces → el puntero **salta una dirección**. La siguiente
   pre-lectura rellena el buffer con el byte de dir+1 respecto a lo que la CPU
   espera → **todas las lecturas siguientes van corridas +1** hasta recolocar
   el puntero (por eso la relectura con R#14+par SIEMPRE acierta y "cura", y
   por eso el corrimiento nunca es −1).
2. **Re-publicación al bus** (líneas 874–882): en el 1.er ciclo `ff_pf_inflight`
   baja; en el 2.º la condición `vram_rdata_en && !ff_pf_inflight` es cierta y
   el dato del refill sale como `bus_rdata_en` → el glue
   (`v9968_cpu_glue.v` 77–79, sin wait-states) **machaca `cdi_r`**. Si el Z80
   aún no había muestreado su IN (muestrea ~2,5 T ≈ 700 ns tras bajar csr_n y
   el refill completa 300–900 ns tras arrancar el IN), se lleva el byte de
   dir+1 en ese mismo IN.

En el banco domina el sabor (1): el ERROR aparece 2–3 INs después del evento
(dt_leak ≈ 22–25 µs en los logs), exactamente como lo ve VRAMSOK2.

### Por qué la tasa crece con la latencia del backend

El grant de `late_v` solo existe para los refills de CPU que **fallan la
sc-cache** y van al backend — 1 de cada 4 lecturas secuenciales (una por
palabra de 32 bits; medido en banco: `resp_cpu_desde_backend=126` para 500
lecturas). La colisión exige que la completación aterrice en la fase exacta
(1 ciclo antes de una respuesta bg, que sale en fase fija mod 16): con
latencia corta y jitter estrecho las completaciones quedan **casi bloqueadas
en fase** y pueden esquivar sistemáticamente la ventana; con más latencia y
jitter (colas, refresh de la DRAM real) las completaciones barren todas las
fases y la ventana se pisa a tasa baja y constante. De ahí DDR3 (rápida,
191 ns de media pero con picos de 757 ns) 0,13% < SDRAM (300–500 ns) 0,34%.
Reproducido en el barrido (§3).

### Y las "rayas" del renderizador (ru66/DEVCON)

El MISMO defecto existe para `ff_command_vram_rdata_en` (tag 4): una respuesta
de comando por `late_v` seguida de bg produce doble `rdata_en` al motor de
comandos → sus lecturas (SRCH, point, LMMM origen…) se desincronizan una
posición. Candidato directo a los gráficos rotos residuales. El fix de §4
cubre ambos consumidores; vale la pena re-pasar tb_devcon/tb_sprite3 con él.

## 2. El banco (`tb_skip1.sv`)

End-to-end REAL: `v9968_cpu_glue` (sin wait-states) + `vdp` completo (TEXT2
W80 dibujando, mismo setup que `tb_t2cpuread`) + `v9968_vram_shim` + backend
de dos canales con latencia configurable (`+LATMIN`/`+LATRND` en ciclos de
85,9 MHz) y semilla (`+SEED`). Patrón VRAMSOK2 (`dir^(dir>>8)^A5h` + bits de
banco) precargado en 256 KB; lazo de lectura SETRD + INs secuenciales a
35–42 T-states de Z80 3,58 MHz, muestreo del dato a los 2,5 T como el T80; al
fallar clasifica (+1/−1/otro), recoloca el puntero, relee la misma dirección
(verifica que sana) y continúa — el protocolo de VRAMSOK2.

Sondas (lección de la campaña: actividad>0 verificada en cada corrida —
`w_read≈500`, `resp_bg≈40k`, `resp_cpu≈510`, refills late ≈ NRD/4):

- `en2`: `ff_cpu_vram_rdata_en` alto ≥2 ciclos (el defecto S1 en el interface)
- `leak_pre`: respuesta CPU seguida de otra respuesta en el ciclo inmediato (salida del shim)
- `dbl_inc`: doble pulso de `ff_vram_address_inc` (el salto del puntero)
- `blocked_in`/`phantom`: IN llegando con el puerto ocupado / 2.ª ejecución del mismo IN (defecto S2, §5)

Relanzar (WSL Ubuntu-24.04, Icarus):
```
bash run_skip1.sh      [NRD] [SEED]   # RTL tal cual (src/)
bash run_skip1_fix.sh  [NRD] [SEED]   # RTL con el fix (src_fix/)
```
Cada llamada compila y corre 3 latencias en paralelo (~5–8 min con NRD=500).

## 3. Resultados

RTL en `ff33f99` (build BUG) y con el fix de §4 (build FIX).

| build | backend (ns/op) | lecturas | errores | firma | en2 | dbl_inc | relectura sana |
|---|---|---|---|---|---|---|---|
| BUG | 93–140 (DDR3 sin jitter) | 1000 (s1+s2) | 0 | — | 0 | 0 | — |
| BUG | 93–465 (DDR3 con colas/refresh) | 500 (s3) | **3 (0,6%)** | **+1=3**, −1=0, otro=0 | 3 | 3 | 3/3 |
| BUG | 300–510 (SDRAM medida) | 1000 (s1+s2) | **14 (1,4%)** | **+1=14**, −1=0, otro=0 | 14 | 14 | 14/14 |
| BUG | 582–815 (fuera de presupuesto) | 1000 (s1+s2) | 1 y 285(*) | (*) | 0–1 | 0–1 | (*) |
| FIX | las tres primeras | 1500 (s1) | **0** | — | **0** | **0** | — |

- **Correlación 1:1**: cada error de los regímenes realistas va precedido del
  trío `LEAK_PRE`+`LEAK_EN2`+`DBL_INC` (mismo instante) y aparece 2–3 INs
  después (`dt_leak` ≈ 22–25 µs) — el corrimiento persistente que el re-point
  corta. `blocked_in=0`, `phantom=0` en TODOS los regímenes realistas.
- **La adyacencia de respuestas es normal**: en el build FIX `leak_pre` sigue
  ocurriendo (7 veces en lat26/s1) pero ya no produce `en2` ni `dbl_inc` ni
  errores → la cadena causal queda demostrada de punta a punta.
- La tasa CRECE con latencia+jitter (0 → 0,6% → 1,4%), como en placa
  (0,13% DDR3 < 0,34% SDRAM). La tasa absoluta del banco es mayor que la de
  placa (fase del lazo, densidad de bg del TEXT2 del banco, distribución de
  latencias sintética) — el orden y la firma son lo reproducido.

(*) **lat50 es OTRO régimen, no el bug de campo**: 582–815 ns/op supera el
presupuesto del glue sin wait-states (muestreo a ~700 ns) cuando una lectura
cae bloqueante; el Z80 se lleva el dato RANCIO (firma −1/otro), el manejador
de error escribe con el puerto aún ocupado, engancha la re-captura S2
(`PHANTOM_RD`) y el estado queda corrupto en cascada (285/500 con TODAS las
relecturas malas — "esto NO pasa en placa", lo marca el propio TB). Es la
familia conocida del "rastro del cursor" (documentada en tb_t2cpuread),
amplificada; MUY sensible a la semilla (1/500 vs 285/500). Confirma por
contraste que los backends reales nunca operan en ese régimen: en placa la
relectura siempre acierta.

## 4. El fix propuesto (mínimo, verificado en banco)

`fpga/v9968/vdp_vram_interface.v` — re-evaluar los strobes en CADA ciclo con
respuesta (aplicado en `src_fix/v9968/vdp_vram_interface.v`, NO committeado):

```verilog
else if( vram_rdata_en ) begin
    ff_cpu_vram_rdata_en     <= (vram_rtag[4:2] == c_cpu);
    ff_command_vram_rdata_en <= (vram_rtag[4:2] == c_command);
    case( vram_rtag[4:2] )
    c_bg:      begin ff_screen_mode_vram_rdata <= vram_rdata; end
    c_sprite:  begin ff_sprite_vram_rdata      <= vram_rdata; ff_sprite_vram_rdata8 <= w_rdata8; end
    c_cpu:     begin ff_cpu_vram_rdata         <= w_rdata8;   end
    c_command: begin ff_command_vram_rdata     <= vram_rdata; end
    endcase
end
```

Coste: 2 comparadores de 3 bits que ya existían dentro del case — cero FF
nuevos, cero impacto en el contrato de 8 ciclos del display. Resultado A/B con
la misma semilla: 9→0 errores (lat26), 3→0 (DDR3 con jitter), en2 14→0.

## 5. Otras ventanas examinadas (y su estado)

- **S2 — re-captura del glue** (`v9968_cpu_glue.v` 51–74 + `vdp_cpu_interface.v`
  296–325): el glue retiene `bus_valid` hasta ver `bus_ready`
  (= `ff_bus_ready & ~ff_busy & ~ff_pf_inflight`) pero el interface latchea con
  el `ff_bus_ready` INTERNO → si una transacción llega con el puerto bloqueado
  se re-latchea cada 2 ciclos ("re-capturas… visto en traza", ya lo documenta
  `tb_cpu_bulk.sv`). Trazado a mano: existe una secuencia (completación del
  refill en ciclo de latch + el branch de `ff_vram_address_inc` comiéndose el
  `ff_pf_req`) en la que el MISMO IN se ejecuta DOS veces y la 2.ª es una
  lectura fantasma de dir+1. **Exonerado como causa de campo**: exige llegar
  con `ff_busy|ff_pf_inflight` y a ~35 T (9,8 µs) el refill (≤1 µs) siempre
  terminó — `blocked_in=0`/`phantom=0` en todos los regímenes realistas; solo
  aparece en el régimen fuera de presupuesto (lat50). Endurecimiento sugerido
  si algún día se toca: latchear solo con
  `bus_valid && ff_bus_ready && !ff_busy && !ff_pf_inflight`.
- **S3 — pre-lectura lanzada en el mismo ciclo que el commit de R#14**
  (`vdp_cpu_interface.v` 482–494): el guard `!w_set_vram_address` no cubre la
  escritura de R#14 (su `w_pf_invalidate` llega 1 ciclo tarde vía
  `ff_register_write`): una pre-lectura puede salir con el banco VIEJO y su
  completación incrementa el puntero NUEVO; si ese incremento espurio acarrea
  a bit 14, el par de dirección posterior no lo repara (solo reescribe [13:0]).
  Firma sería rancio/"otro" y solo en recolocaciones — no es el bug medido;
  latente, prioridad baja.
- **V4 — falso-accept de `cpu_vram_ready`** (`vdp_vram_interface.v` 277): el
  ready es un SUPERconjunto de la aceptación real (no comprueba bg/sprite ni
  `ff_vram_valid`). Cerrado por construcción HOY: verificado que TODOS los
  valids de bg (`vdp_timing_control_screen_mode.v` 353–366) y de sprites
  (`vdp_sprite_select_visible_planes.v` 180–222,
  `vdp_sprite_info_collect.v` 244+) pulsan solo con `w_sub_phase==0`
  (→ slot A, h%16==1) y nunca en el slot B de la CPU. Frágil ante futuros
  cambios de fase.
- **V5 — drop de rq con cola llena** (`v9968_vram_shim.v` 1181): una lectura
  CPU/cmd con `rq_full` se pierde en silencio → cuelgue del puerto. Protegido
  por la reserva de 3 plazas (bg/sprite paran en 12); no observado.
- El **shim** (colas rq/wq/pfq, eco de tags, pf_dirty, victim buffer) sale
  LIMPIO para este bug: el tag se ecoa bien, no hay respuestas duplicadas ni
  fuera de orden indebido; su única contribución es legítima (encadenar
  pipe+late sin hueco, que es válido según su contrato).

## 6. Ficheros

- `INFORME.md` — este documento
- `tb_skip1.sv` — el banco (sondas + clasificación +1/−1/otro + verificación de actividad)
- `run_skip1.sh` / `run_skip1_fix.sh` — compilación y barrido (iverilog, WSL Ubuntu-24.04)
- `src/` — copia intacta de `fpga/v9968/*.v` + `v9968_vram_shim.v` + `v9968_cpu_glue.v` (HEAD ff33f99)
- `src_fix/` — ídem con el fix de §4 en `v9968/vdp_vram_interface.v`
- `logs/` — corridas: `skip1_lat{8,26,50}_s{1,2}.log`, `skip1_lat8j32_s3.log`,
  `skip1fix_lat{8,26,50}_s1.log`, `parcial_fix_lat50_NRD3000_muerta.log`

## 7. Siguientes pasos sugeridos (fuera de este encargo)

1. Aplicar el fix de §4 al árbol real y correr VRAMSOK2 en placa (DDR3 y
   SDRAM): la tasa debe caer a 0.
2. Re-pasar tb_devcon / tb_sprite3 / la ru66 con el fix: mirar si el residuo
   de gráficos rotos baja (el strobe de COMANDO sufría el mismo defecto).
3. Opcional: endurecer S2 y S3 (parches indicados en §5) y añadir al banco de
   regresión un chequeo permanente de `en2==0`.
