# Implementación _159 — ADPCM-B del Y8950 con 256 KB de muestras en la SDRAM

**Fecha**: 2026-07-28 · **Base**: `MSX_up` @ `6d15c0b` (v2.0.2 BORDES) · **Repos SOLO LECTURA**
**Diseño de partida**: `files/20260726/INFORME_ADPCM_256K.md` (§5 escalón "b")
**Estado**: parche propuesto, **validado en simulación**, sin sintetizar (horneada en curso).

---

## 0. Qué se entrega

| Fichero | Qué es |
|---|---|
| `01_adpcm_sdram.patch` | El cambio de memoria completo. `git apply` limpio sobre `6d15c0b`. |
| `02_mixer_balance.patch` | Solo el reequilibrado del mixer (`>>>1` → `>>>3`). Aplica sobre el HEAD **o** sobre HEAD+01. |
| `INFORME_IMPL.md` | Este documento. |
| `sim/` | Banco completo (Verilator), reproducible con `./run.sh` en ~2,5 min. |
| `sim/adpcm_256k_SDRAM_PARCHE.wav` | Salida del **RTL parcheado** (13,1 s, 49.716 Hz). |
| `sim/adpcm_32k_ACTUAL_V.wav` | La misma batería sobre el RTL actual, para A/B. |
| `sim/adpcm_256k_SDRAM_LAT900.wav` / `_LAT6000.wav` | El parche con latencia de puerto ×22 y ×150. |
| `check/` | Copia del árbol `fpga/` del HEAD con los dos parches ya aplicados (lo que se verificó). |

**Verificación de aplicabilidad** (hecha sobre una copia, y repetida en solo-lectura contra el repo real):

```
--- 01 sobre HEAD limpio ---   OK
--- 02 sobre HEAD limpio ---   OK
--- 02 sobre HEAD+01 ---       OK
01 sobre MSX_up (git apply --check): OK
```

---

## 1. Resumen de un vistazo

- El array de **32 KB en BSRAM se retira** de `y8950_adpcm.v` (−16 bloques).
- Las muestras pasan a los **256 KB completos del Y8950** en la SDRAM del dock, por el
  puerto **wv2** de `memory.v`, a través de un shim nuevo `adpcm_sdram.v` calcado del
  lado HOST de `wave_sdram.v` (toggle + 3FF + FSM de 4 fases).
- El módulo se queda con **una caché de 2 palabras + prefetch de +1** y el motor va
  **gateado** por el acierto: sin dato no se decodifica, se pierde un tick.
- La familia `wv2`/`wv3` se muda a las **filas 5120+**, lo que además cierra el bug #3
  del `INFORME_NIQUELADO` en la línea de respaldo _137.
- En simulación: **131.072 de 131.072 bytes** del bloque llegan a la RAM, el segmento
  que ya cabía sale **bit a bit idéntico**, y los tres que se clavaban en el raíl dejan
  de hacerlo. Con la latencia del puerto multiplicada por 22, la salida sigue siendo
  **bit a bit la misma, sólo retrasada 3-5 muestras**.

---

## 2. Qué cambia cada fichero, y por qué

### 2.1 `fpga/src/y8950_adpcm.v` (+238 / −24 líneas)

**a) Puerto de memoria nuevo (toggle).** Seis señales más `mem_diag`. El contrato es el
del host de `wave_sdram.v`: `mem_req_t` *cambia de valor* = nueva operación, el payload
viaja con él y no se toca hasta ver `mem_done_t`. La respuesta es la **palabra alineada**
(`memory.v` ya devuelve 16 bits). No se inventa protocolo: ése lleva validado desde la _104.

**b) Se retira la guarda de 32 KB.**

```verilog
-wire rd_oob = (rd_byte_addr[17:15] != 3'b000) | rom_bank;
+wire rd_oob = rom_bank;
```

La máscara `is64k` **no se toca**: es la del chip real (openMSX `addrMask = 64K ?
(1<<16)-1 : (1<<18)-1`) y con 256 KB reales pasa a ser correcta en vez de decorativa.
El camino de direcciones ya era de 256 KB desde el _80 — lo único que topaba era el array.

**c) Caché de 2 palabras con reemplazo round-robin.** El puntero de reproducción avanza
monótono nibble a nibble: dos entradas (la palabra en curso + la que trae el prefetch)
cubren el patrón entero sin fallar en régimen, y el round-robin es correcto *justo por*
esa monotonía — cuando el prefetch de T+1 aterriza en la entrada libre, la siguiente
víctima es la de T, ya consumida.

El **tag es la dirección física de palabra ya enmascarada**, así que la caché es coherente
por construcción frente a saltos (START/REPEAT), a `is64k` y a `rom_bank`: si la dirección
cambia, el tag no casa y hay miss. **Lo único que hay que invalidar a mano son las
escrituras de la CPU**, y se hace en el mismo ciclo del encolado. (Esto simplifica bastante
lo que esbozaba §5.4 del informe de diseño, que preveía invalidaciones explícitas.)

**d) Gate del motor.**

```verilog
wire mem_rdy = !mode_mem || rd_oob || word_hit;
wire engine  = cen_fs && playing && !dec_clr && mem_rdy;
```

Fail-safe: sin dato se pierde un tick de 20 µs (inaudible) en vez de meterle al deltaT un
nibble inventado, que envenena `step` y el acumulador durante **toda la nota** — que es
exactamente el mecanismo del raíl diagnosticado en el informe anterior.

**e) FSM del puerto**, una operación en vuelo, prioridad **escritura > miss > prefetch**.
La escritura va primero porque es la única con control de flujo visible (BUF_RDY) y la
única que puede perder información; el prefetch es especulativo y puede esperar.

Sólo alimentan la caché los modos que **leen** memoria (`0xA0` reproducción y `0x20`
RAM→CPU). En `0x60` (subida) el puerto es todo para las escrituras: emitir misses ahí
sería tráfico inútil compitiendo con la propia subida.

**f) Cola de escritura de 4 plazas con freno anticipado a 2.** Esto **no** estaba en el
diseño y es el hallazgo de la implementación:

> Con una cola de 2 plazas y `BUF_RDY = buf_rdy & ~full`, el banco **perdía uno de cada
> dos bytes de la subida** (4.097 escrituras de 8.192). Causa: entre que el software lee
> BUF_RDY y llega su `OUT` pasan ciclos, y en ese hueco puede haber colado otra escritura.
> El byte se perdía **en silencio**.

Con capacidad 4 y el freno declarado a 2 caben las dos escrituras "en vuelo" del peor caso.
Medido después del arreglo: **131.072 de 131.072**, `wq_lost = 0`. El contador `wq_lost`
queda en `mem_diag[7:4]` para que el imposible, si ocurre, se vea.

**g) BUF_RDY efectivo.** El flag significa "puedo aceptar / ya tengo el byte". Con la RAM
fuera del chip eso deja de ser instantáneo, así que se le añade la condición real:

```verilog
wire buf_rdy_eff = (mode == 8'h60) ? (buf_rdy & ~wq_full)     :   // hay sitio
                   (mode == 8'h20) ? (buf_rdy &  rd_byte_rdy) :   // el byte está
                                      buf_rdy;
```

Es **más fiel al chip real** que darlo siempre listo (openMSX lo hace porque su RAM es un
array de C++), y le da al bucle `in a,(C0) / and 8 / jr z` de VGMPlay el control de flujo
que ya estaba esperando. El resto de modos, sin tocar.

**h) Watchdog del handshake** (lección _95 del OPL4): si un toggle se pierde, `busy`
quedaría clavado y el ADPCM **mudo para siempre**. A ~150 µs se libera a la fuerza y
`wd_hits` (en `mem_diag[3:0]`) lo delata.

### 2.2 `fpga/src/adpcm_sdram.v` (fichero nuevo, 187 líneas)

Shim entre el módulo (clk_54m) y el puerto wv2 (clk_108m). Copia deliberada del lado HOST
de `wave_sdram.v`: 3FF en las dos direcciones, FSM `ST_IDLE/ST_REQ/ST_DROP` de 4 fases, el
payload asentado ≥3 ciclos antes de que se consuma (regla _96), y el `ST_DROP` de guarda
para que el `inflight` de `memory.v` vea `req=0` antes de poder reconceder.

`wv_addr = {4'd0, addr[17:0]}` ⇒ con el mapa nuevo, **filas 5120-5183** del W9825:
físicamente fuera del alcance de la CPU (filas 0-2047), del VDP (banco D, 0-2047) y de la
wave del OPL4 (4096-5119).

**Parámetro `FALLBACK_BSRAM`.** Con `=1`, la misma interfaz se implementa con los 32 KB de
siempre en BSRAM (dos bancos de 16K×8, pares/impares, para escribir de byte y leer de
palabra sin byte-enables). Sirve a la **línea de respaldo _137**, donde la VRAM del V9968
ocupa wv2/wv3 y no hay puerto libre. Así `y8950_adpcm.v` se queda con **un solo camino de
datos** y la variante vive aislada en un fichero pequeño. Verificado: la rama de respaldo
da **0/650.000 muestras distintas** frente al RTL actual.

### 2.3 `fpga/src/memory.v` (+22 / −3)

Una constante en un mux:

```verilog
-(wv2_req == 1 && wv2_inflight == 0) ? { 1'b1, 2'b00, wv2_addr[21:12] } :
-                                      { 1'b1, 2'b00, wv3_addr[21:12] };
+(wv2_req == 1 && wv2_inflight == 0) ? { 1'b1, 2'b01, wv2_addr[21:12] } :
+                                      { 1'b1, 2'b01, wv3_addr[21:12] };
```

**wv2 y wv3 se mueven JUNTOS** — y esto corrige el diseño de partida, que hablaba sólo de
"la familia wv2". En la línea _137 wv2 y wv3 son los **dos canales del mismo shim** y
direccionan la **misma VRAM**: moviendo sólo wv2, cada palabra de 32 bits acabaría partida
entre dos filas distintas y esa línea quedaría rota.

El resto del cambio son comentarios (la cabecera del puerto wv2 decía "filas 4096+", que
con esto pasa a ser falso).

### 2.4 `fpga/top.v` (+79 / −2)

**a) El define es DERIVADO, no manual.** Meter el ADPCM en wv2 sólo es legal si wv2 está
libre; dejar un `define` a mano invita a la combinación mala (dos drivers del mismo bus).

```verilog
`ifdef ENABLE_Y8950_ADPCM
 `ifndef ENABLE_V9968_VDP
  `define ENABLE_ADPCM_SDRAM
 `else
  `ifdef ENABLE_VRAM_DDR3
   `define ENABLE_ADPCM_SDRAM
  `endif
 `endif
`endif
```

Comprobado con el preprocesador en las tres configuraciones que existen:

| configuración | tie-off wv2 | tie-off wv3 | shim |
|---|---|---|---|
| (a) HEAD actual (V9968 apagado) | no (lo conduce el shim) | sí | `FALLBACK_BSRAM(0)` |
| (b) V9968 + VRAM en DDR3 (línea principal _138) | no (lo conduce el shim) | sí | `FALLBACK_BSRAM(0)` |
| (c) V9968 sin DDR3 (respaldo _137) | no (lo conduce el bridge) | no (idem) | `FALLBACK_BSRAM(1)` |

**b)** Los tie-offs de wv2 se envuelven en `ifndef ENABLE_ADPCM_SDRAM`; los de wv3 quedan
como estaban.
**c)** El puerto nuevo del `y8950_adpcm` y la instancia del shim, en las dos variantes.

### 2.5 `fpga/build.tcl` (+2)

`add_file src/adpcm_sdram.v` junto al resto de la familia ADPCM.

> ⚠️ **A mano**: `fpga/opl4_20k_est/build_est_y8950.tcl` (el tcl de estimación para TN20K)
> también lista `y8950_adpcm.v`, pero **ese directorio está UNTRACKED** en el repo, así que
> queda fuera del parche. Si se usa esa estimación, hay que añadirle
> `add_file $SRC/src/adpcm_sdram.v` a mano.

---

## 3. Coste estimado

**No se ha sintetizado** (había una horneada de Gowin ocupando la máquina). Esto es un
recuento analítico, no una medición — trátese como tal.

### Biestables (contados uno a uno sobre el RTL final)

| Bloque | FF |
|---|---:|
| Puerto (`mem_req_t/we/addr/wdata`) | 28 |
| Caché: `cw0/cw1` + `ctag0/ctag1` + `cv0/cv1` | 68 |
| FSM: `busy/op_kind/op_tag/fill_sel/done_seen` | 22 |
| Cola de escritura (4×26) + punteros + `wq_lost` | 115 |
| Watchdog (`wd`, `wd_hits`) | 17 |
| **`y8950_adpcm` (menos el `ram_q` que desaparece)** | **+242** |
| `adpcm_sdram`: 3FF ida + FSM + payload + 3FF vuelta | +75 |
| **Total** | **≈ +317** |

### Lógica

| Concepto | LUT (est.) |
|---|---:|
| 6 comparadores de tag de 17 bits (rd×2, pf×2, wr×2) | ~70 |
| Sumador `+1` de 17 bits (prefetch) | ~17 |
| Mux de la cola (4 entradas × 26 bits) | ~78 |
| Muxes de emisión (`mem_addr` 18b × 3 fuentes, `mem_wdata`) | ~45 |
| Mux `hit_word` + selección de byte | ~24 |
| Control (FSM, gates, `buf_rdy_eff`) | ~30 |
| `adpcm_sdram` (FSM + muxes de payload) | ~50 |
| **Total** | **≈ 280 … 400** |

A la densidad de empaquetado medida del proyecto (~1,53 logic/CLS): **≈ +185 … 260 CLS**.

| BSRAM | |
|---|---:|
| Array `sram[0:32767]` retirado | **−16 bloques** |
| Caché / cola / shim (todo en FF) | 0 |
| **Neto** | **−16** |

**La partida más cara es la cola de 4 plazas** (115 FF + ~78 LUT del mux). Si el PnR
aprieta, se puede bajar a 3 plazas (freno a 2 igual, 1 sola de reserva) por ~30 FF y
~26 LUT menos. **Bajar a 2 NO** — es exactamente la configuración que perdía bytes.

---

## 4. Validación en simulación (hecha)

Banco en `sim/`, portado a **Verilator** (el de Icarus tardaba ~30 min por corrida; éste
hace las cinco en 2 min 38 s). Mismo estímulo que `tb_adpcm128k.v`: bloque DELTA-T **real**
de 128 KB del VGZ *Psycho Soldier*, protocolo de VGMPlay 1.4 desensamblado (reg 08
enmascarado con `0xC4`, direcciones ×8, stop `|7`), los mismos 4 segmentos y las mismas
650.000 muestras.

**Novedades respecto al banco viejo**, que es lo que pedía §7.1 del informe de diseño:

- Camino **completo**: `y8950_adpcm` → `adpcm_sdram` → modelo del puerto wv2.
- **Dos relojes de verdad** (54 y 108 en fase, como el PLLA) ⇒ el CDC 3FF se ejercita.
- Modelo del puerto con **latencia aleatoria pero determinista** (LFSR), que además vigila
  el contrato: ninguna dirección fuera de los 256 KB, y no reconcede hasta ver `req=0`.
- La subida usa el **handshake BUF_RDY**, como VGMPlay.
- El banco corre con `cen3m6 = 1` (×15 acelerado): eso hace la prueba **más dura** que la
  realidad, no menos — el ADPCM corre 15× más rápido contra un puerto con la misma latencia.

### 4.1 Criterios de aceptación de §7.1 del informe de diseño

| # | Criterio | Resultado |
|---|---|---|
| 1 | bytes del bloque presentes en la RAM = 131.072 | **131.072 / 131.072** ✅ (el RTL actual: 32.830) |
| 2 | Segmento #1 **bit a bit idéntico** al RTL actual | **0 de 150.000 muestras distintas** ✅ |
| 3 | #4/#9/#16: `\|media\|` < 2.000 y RMS < 15.000 | #4 ✅ (−394 / 2.402) · #9 ✅ (+618 / 7.801) · #16 **parcial** (−9.205 / 10.884) |
| 4 | Ningún tramo > 1.000 muestras pegado a ±32.639 | **máximos 0 / 22 / 2** ✅ (el RTL actual: 70.328 / 184.168 / 127.296) |
| 5 | (añadido) latencia inyectada sin cambiar el dato | ✅ ver 4.3 |

**Honestidad sobre el #16**: su continua de −9.205 **no** es un fallo del parche — el WAV
`adpcm_256k_PROPUESTO.wav` del informe anterior da exactamente lo mismo (−9.204,9). El
criterio "<2.000" era optimista: ese segmento tiene offset propio en el material. Lo que
importa es que pasa de **+29.284 a −9.205** de continua y que la parte de señal (RMS_ac)
sube de 8.960 a… bueno, baja a 5.808 porque antes el "RMS" era casi todo continua. Y el
tramo pegado al raíl cae de 127.296 muestras a **2**.

### 4.2 Tabla completa (las cuatro versiones sobre los cuatro segmentos)

| Segmento | versión | DC | RMS | RMS_ac | pico | raíl máx |
|---|---|---:|---:|---:|---:|---:|
| #1 `0x00000-0x027FF` | ACTUAL | −302,8 | 3.564,2 | 3.551,3 | 22.041 | 0 |
| | **PARCHE** | **−302,8** | **3.564,2** | **3.551,3** | **22.041** | **0** |
| #4 `0x07000-0x097FF` | ACTUAL | **+16.725,1** | 23.142,1 | 15.994,7 | 32.639 | **70.328** |
| | **PARCHE** | **−394,4** | **2.401,6** | 2.369,0 | 18.647 | **0** |
| #9 `0x12000-0x157FF` | ACTUAL | **+31.244,5** | 31.722,6 | 5.487,1 | 32.639 | **184.168** |
| | **PARCHE** | **+618,1** | **7.801,4** | 7.776,8 | 32.640 | **22** |
| #16 `0x1D800-0x1FFFF` | ACTUAL | **+29.284,3** | 30.624,5 | 8.960,4 | 32.639 | **127.296** |
| | **PARCHE** | **−9.204,8** | **10.884,0** | 5.808,0 | 32.640 | **2** |

El PARCHE coincide con `adpcm_256k_PROPUESTO.wav` (el WAV de referencia del informe
anterior) hasta la última cifra en los cuatro segmentos.

### 4.3 Margen de latencia — la prueba fuerte

| corrida | latencia de lectura (ciclos de 108 MHz) | ticks gateados | resultado |
|---|---|---:|---|
| B realista | 8-40 (≈ 0,07-0,37 µs) | **3** de 650.000 | referencia |
| C ×22 | 300-900 (≈ 2,8-8,3 µs) | **19** de 650.000 | **bit a bit igual a B, retrasado 3-5 muestras** |
| D ×150 | 2.000-6.000 (≈ 18-55 µs) | 70.694 (10,9 %) | degrada suave; ni se clava ni corrompe |

La corrida C es la que cierra el argumento: alineando por el desfase, **0 de 149.960
muestras distintas en cada uno de los cuatro segmentos**. El gate por `word_hit` sólo
puede *retrasar* un tick, nunca cambiar el dato — que es justo lo que predecía el diseño.

Y recuérdese que el banco va ×15 acelerado: los 2,8-8,3 µs de la corrida C equivalen a
**42-125 µs de latencia real** frente a los ~148 ns del turno del puerto. Es un margen
absurdo, y aun así la salida es la misma.

### 4.4 Ocupación del puerto y salud

```
puerto: 22.532 lecturas + 131.072 escrituras en 99.169.500 ciclos de 108M
ocupación: 0,155 % de los ciclos          (incluida la subida entera de 128 KB)
latencia servida: media 24,0, máxima 40 ciclos
direcciones fuera de los 256 KB: 0
watchdog del handshake (wd_hits): 0
bytes perdidos por cola llena (wq_lost): 0
```

Las 22.532 lecturas para 650.000 muestras son **0,035 lecturas por tick**: la caché de 2
palabras + prefetch está haciendo su trabajo (sin ella serían ~0,07, el doble, y con
misses en el camino crítico).

### 4.5 Lint

`verilator --lint-only -Wall` sobre `y8950_adpcm.v` (con sus dependencias jt10) y sobre
`adpcm_sdram.v`: **cero errores, cero warnings**. `memory.v`: sin MULTIDRIVEN ni LATCH nuevos.

---

## 5. Riesgos

1. **La SDRAM arranca indeterminada.** El HW real arranca la sample RAM a `FF` (openMSX
   `clearRam`) y la BSRAM Gowin arrancaba a `00`. Ahora es basura. Sólo afecta a lecturas
   de zonas **nunca escritas**, que ya eran indefinidas para el software y que todo
   replayer evita subiendo sus muestras antes del key-on. Si se quisiera cerrar del todo,
   un barrido de 128 K escrituras al arranque cuesta ~20 ms del puerto — pero es lógica
   nueva en el camino crítico por un caso que ningún software real ejercita.
2. **Comparte árbitro con el OPL4.** Es el único riesgo real del cambio. Mitigado por
   construcción: la prioridad de `memory.v` es `wave > wv2`, la ocupación medida es del
   0,155 % (frente a los ~2 MB/s del motor wavetable), y wv2 sólo roba turnos de CPU
   **vacíos**. Aun así, el punto 4 del plan de placa (un VGZ de MoonSound a la vez) no es
   opcional.
3. **`mem_diag` queda sin cablear.** Los contadores `wq_lost`/`wd_hits` salen del módulo y
   se quedan en un wire libre en `top.v`. Colgarlos de la telemetría UART (`fr[15]`, como
   `ifw_hits` del OPL4) es trivial pero toca el bloque de debug, y he preferido no meter
   ese cambio aquí. **Recomendado hacerlo antes de la primera build de placa.**
4. **BUF_RDY cambia de semántica** (pasa a ser real). Es más correcto, pero es un cambio
   observable: software que hoy escriba a ciegas confiando en que el flag está siempre a 1
   ahora ve ceros transitorios. Con la cola de 4 y el freno a 2, un Z80 escribiendo a
   pelo con `outi` (un byte cada ~5 µs) contra un servicio de ~1-2 µs no pierde nada.
5. **El cambio de filas toca la línea _137**, aunque hoy no se compile. Está contemplado
   (wv2 y wv3 se mueven juntos), pero esa línea **no se ha simulado**: si alguna vez se
   vuelve a ella, hay que revalidar la VRAM del V9968.
6. **No hay síntesis.** El presupuesto de recursos de §3 es analítico. Y la discrepancia
   de ocupación de BSRAM que ya señalaba el informe de diseño (73/118 del rpt rancio vs
   117/118 de los informes del 26/07) sigue **sin resolver**: el −16 es sólido, el absoluto no.
7. **El banco no valida el timing físico.** Corre con `cen3m6 = 1` y con relojes ideales en
   fase. El CDC se ejercita, pero el PnR puede tener otra opinión sobre el camino
   `wv2_addr → pre_row` (que es de la familia _122, la reincidente del placement) — aunque
   ahí el cambio es una **constante**, no lógica nueva.

---

## 6. Plan de validación

### 6.1 En simulación (hecho — se puede repetir en 2,5 min)

```bash
wsl -d Ubuntu-24.04 -- bash -lc "cd /mnt/c/.../scratchpad/adpcm_impl/sim && ./run.sh"
```

Debe imprimir: `131072 de 131072`, `segmento #1: 0` diferencias, `wq_lost: 0`,
`wd_hits: 0`, `direcciones fuera de los 256KB: 0`, y desfases de 3-5 muestras con
0,0000 % de diferencias en la corrida lenta.

### 6.2 Antes de sintetizar

1. **Regenerar el PnR** y cerrar de una vez el número real de BSRAM (paso 1 del orden de
   trabajo del informe de diseño). El −16 debería aparecer tal cual.
2. Añadir a mano la línea del `build_est_y8950.tcl` si se usa esa estimación (§2.5).
3. Decidir si se cuelga `mem_diag` de la telemetría UART (riesgo 3).

### 6.3 En placa (§7.2 del informe de diseño, sin cambios)

1. **msxtest.rom**, pantalla Y8950: `ADPCM: W:OK R:OK Play:OK` sigue verde.
   *(Es el test que más directamente ejercita el BUF_RDY nuevo.)*
2. **Fire Hawk** (Thexder II): las voces "Fire!" idénticas a la _80 → no regresión del
   camino que ya cabía en 32 KB. La simulación ya lo dice bit a bit, pero esto valida el
   CDC real.
3. **El VGZ de Psycho Soldier con VGMPlay**: la voz debe salir entera y el fondo FM dejar
   de sonar apagado. Contrastar con el vídeo del PicoVerse 2350 — recordando que el
   fichero es de recreativa (Y8950 @ 4 MHz) y en un MSX suena un **10,6 % más grave**:
   eso es correcto, no un fallo.
4. **Un VGZ de MoonSound/OPL4 a la vez** (los de Daytona en `Downloads/emul/opl4/`) para
   confirmar que el ADPCM en SDRAM no perturba al motor wavetable. **Es el punto crítico.**
5. Telemetría UART (`tools/dbg_reader.py`): `fr[15] = {ifw_hits, alive}` sin acumular hits
   del watchdog del OPL4.
6. **Sólo después**, aplicar `02_mixer_balance.patch` y repetir 2 y 3 para juzgar el
   balance. El orden importa: aplicar el mixer antes haría la voz rota *más silenciosa*
   sin arreglarla, y enmascararía el diagnóstico.

---

## 7. Lo que no cuadra / dónde puedo estar equivocado

1. **El −12 dB del parche 02 sigue sin medirse.** La aritmética de §3.2 del informe de
   diseño se apoya en que una portadora del `jtopl` pica en ±4.095 y en que `dB2LinTab` de
   openMSX pica en 2.048. No lo he verificado; me limito a empaquetar el cambio como se
   pidió, con el intermedio `>>>2` documentado en el propio comentario del código.
2. **El criterio 3 del banco no se cumple para el segmento #16** (§4.1). No es del parche
   — el WAV de referencia da lo mismo —, pero deja el criterio como estaba mal calibrado.
3. **La rama `FALLBACK_BSRAM=1` no se ha probado en la línea _137 real**, sólo en el banco
   (donde es bit a bit idéntica al RTL actual). Si esa línea se resucita, hay que
   comprobar además que el cambio de filas de wv3 no rompe la VRAM del V9968.
4. **La cola de 4 plazas la ha impuesto el banco, no la teoría.** El diseño decía "una
   plaza basta"; el banco demostró que 2 pierden bytes con un consumidor agresivo. Puede
   que 4 sea generoso para un Z80 real (§3), pero perder muestras en silencio es
   exactamente el tipo de bug que costó el diagnóstico de la _158.
5. **No he tocado la telemetría ni el `.cst`**, ni he sintetizado. Todo lo que digo de
   recursos y de timing es papel.
