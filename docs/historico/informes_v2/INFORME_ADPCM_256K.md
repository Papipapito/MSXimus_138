# Bug de audio del MSXimus — VGZ "Psycho Soldier" (Y8950 ADPCM-B)

**Fecha**: 2026-07-28 · **Base**: `MSX_up` @ `6d15c0b` (v2.0.2 BORDES) · **Repos SOLO LECTURA**
**Síntoma reportado**: reproduciendo `files/20260726/03 Psycho Soldier Theme (Area 1 JP).vgz`
con VGMPlay en placa, *"la música suena MUY baja y la voz muestreada se distorsiona"*.

---

## 0. Resumen ejecutivo

| # | Hallazgo | Veredicto |
|---|---|---|
| **A** | El VGZ es un volcado **Y8950 puro** (no YMF262/OPL3) con un bloque DELTA-T de **128 KB** y necesita los 128 KB completos. La RAM de muestras del MSXimus son **32 KB**. | **CONFIRMADO** (simulado con el bloque real) |
| **B** | Lo que se oye NO es "voz recortada": leer 0x00 fuera de rango hace que el decoder deltaT **se clave en el raíl positivo**. Inyecta un **DC de +16.3k** en el mixer durante toda la nota. | **CONFIRMADO** (medido en simulación) |
| **C** | Ese DC se come el **50% del headroom positivo** del `sat16` → todo lo demás (el FM) se recorta asimétricamente y "suena muy bajo". Los dos síntomas son **la misma causa**. | **CONFIRMADO** |
| **D** | Además, y con independencia de A/B, el término ADPCM del mixer entra **+12 dB por encima** de la referencia openMSX (`>>>1` donde tocaría `>>>3`). | **CONFIRMADO** (aritmética cerrada) |
| **E** | La hipótesis del orquestador de que "con 128 KB el contenido se envolvería 4 veces" es **incorrecta en el mecanismo**: no hay wrap, hay guarda `rd_oob`/`wr_oob` que devuelve 0 e ignora la escritura. El efecto es peor que el wrap. | **REFUTADA en el mecanismo, confirmada en la consecuencia** |
| **F** | La cabecera del VGZ **no** declara YMF262: declara `Y8950 @ 4.000.000 Hz` (offset 0x58). Es un ripeo **de recreativa** (SNK, 1987), no de MSX. | **CORRECCIÓN al análisis previo** |
| **G** | Los registros de dirección DELTA-T del RTL **ya son de 256 KB** (puntero de 19 bits en nibbles, máscara `0x3FFFF`). No hay nada que ensanchar aguas arriba. | **CONFIRMADO** |
| **H** | 256 KB en BSRAM = **128 bloques**; el GW5AT-60 tiene **118 en total**. Imposible aunque el chip estuviera vacío. | **CONFIRMADO** |
| **I** | Los puertos `wv2`/`wv3` de `memory.v` (SDRAM) están **atados a 0** desde que la VRAM del V9968 se mudó a DDR3: hay **dos clientes SDRAM libres, ya cableados y validados**. | **CONFIRMADO** |

**El arreglo bueno sale a coste negativo de BSRAM**: mover los samples a la SDRAM
**libera los 16 bloques** que hoy ocupan los 32 KB, a cambio de ~200 LUT.

---

## 1. Qué contiene realmente el fichero (evidencia)

Descomprimido y parseado con `tools` propios (script en `sim/`, fuente en este informe):

```
Vgm  · versión 1.51 · 150.848 bytes · 74,8 s
clock @0x58  Y8950 = 4.000.000 Hz     <-- ÚNICO chip declarado
comandos: 0x5C (Y8950) ×4298 · 0x67 ×1 · esperas
bloque de datos: tipo 0x88 (Y8950 DELTA-T ROM), 131.080 bytes
   cabecera: romsize=0x40000 (256 KB)  romstart=0
   datos:    131.072 = 128 KB, 97,9% de bytes no nulos en TODO el rango
```

Registros ADPCM escritos por el VGM: `07`×90, `08`×1 (**valor 0x01**), `09/0A`×15,
`0B/0C`×14, `10/11`×1 (`deltaN=0x24E0`), `12`×2. **Cero escrituras al reg `0F`** →
el flujo VGM no sube muestras: las sube el reproductor.

### 1.1 Cómo lo toca VGMPlay (desensamblado del binario, no conjetura)

`VGMPlay 1.4 by Grauw` — binario analizado: `…/OCM-SDBIOS Pack v3.8.1/…/utils/VGMPLAY.COM`.
Rutina de escritura de registro Y8950 en `0x6B2D`:

```
6B47  fe 04     cp 4          ; reg 4  -> solo sombra (el player gestiona la máscara)
6B4A  fe 08     cp 8
6B4C  28 13     jr z,6B61     ; reg 8  -> ver abajo
6B50  fe 0b     cp 0Bh
6B52  38 14     jr c,6B68     ; reg 9/0A -> remapeo de START
6B54  fe 0d     cp 0Dh
6B56  38 28     jr c,6B80     ; reg 0B/0C -> remapeo de STOP
...
6B61  7a        ld a,d
6B62  e6 c4     and 0C4h      ; <<< reg 8 = valor & 0xC4: BORRA b0 (ROM) y b1 (64K)
6B64  57        ld d,a
6B66  18 ca     jr 6B32       ;     y lo escribe

6B68  21 15 6b  ld hl,6B15h   ; sombra del reg 8
6B6B  cb 46     bit 0,(hl)    ; ¿el VGM pidió ROM?
6B6D  28 c3     jr z,6B32     ;   no -> escritura literal
6B6F  2a 16 6b  ld hl,(6B16h) ;   sí -> toma el valor de 16 bits del VGM
6B72  29 29 29  add hl,hl ×3  ;        y lo MULTIPLICA POR 8  (granularidad
6B75  55        ld d,l        ;        ROM 32 B/unidad -> RAM 4 B/unidad)
6B78  cd 32 6b  call 6B32     ;        reg 9 = L, reg 0A = H
```
(idéntico para STOP en `0x6B80`, con `or 7` sobre el byte bajo)

Y el bucle de subida en `0x6B9B`: `reg 4 = 0x70`, `reg 0F` seleccionado, y por cada byte
`reg4=0xF0` → re-selecciona `0F` → **espera BUF_RDY (`in a,(C0)/and 8/jr z`)** → `outi`.
El mensaje `"Loading samples..."` del binario es exactamente eso.

**Contrastado contra el fuente** (`MSXAudio.asm` / `Y8950.asm` de `vgmplay-msx`, en
`scratchpad/adpcm/`): coincide instrucción a instrucción con el desensamblado.

```asm
MaskMiscControl:              ; reg 08
    ld a,d
    and 11000100B             ; = 0xC4  -> fuera b0 (ROM) y b1 (64K)
WriteStartAddress:            ; regs 09/0A
    ld hl,safeControlMirror + MSXAudio_MISC_CONTROL
    bit 0,(hl)                ; ¿el VGM pidió ROM?
    jr z,WriteRegister
    ld hl,(safeControlMirror + MSXAudio_START_ADDRESS_L)
    add hl,hl / add hl,hl / add hl,hl        ; x8
...
MSXAudio_SetADPCMWriteAddress:               ; antes de subir el bloque:
    ld d,0FFH / ld e,MSXAudio_STOP_ADDRESS_L / call MSXAudio_WriteRegister
    ld d,0FFH / ld e,MSXAudio_STOP_ADDRESS_H / call MSXAudio_WriteRegister
    ; STOP = 0xFFFF:0xFFFF  ->  ventana de escritura = LOS 256 KB ENTEROS
```

Es decir: **el propio reproductor abre la ventana de escritura a los 256 KB
completos** y sube el bloque en trozos de ≤64 KB (`ld hl,0FFFFH` / `LessThan64K`).
Da por hecho una unidad ampliada. También confirma que **no hay reajuste de tono**:
los registros `10`/`11` (delta-N) y todos los `>=0x20` (F-NUM) se escriben
literalmente (`cp MSXAudio_IO_CONTROL / jr c,WriteRegister`), aunque el driver
declare `MSXAudio_CLOCK: equ 3579545` frente a los 4 MHz del fichero (ver §7.3).

**Tres consecuencias que cambian el diagnóstico:**

1. **El bit ROM nunca llega al chip** (`and 0C4h`). La sospecha razonable de que
   `rom_bank` matara la reproducción queda **descartada**: en placa `rom_bank = 0`
   y `is64k = 0` (máscara de 256 KB). El RTL recibe exactamente lo que espera.
2. **Las direcciones del VGM hay que multiplicarlas por 8** para saber qué toca de
   verdad. Interpretadas "en crudo" el fichero parecería usar sólo 16 KB — es un
   espejismo. Con el remapeo real:

   ```
   rango de bytes REALMENTE direccionado: 0x00000 .. 0x1FFFF  =  128,0 KB EXACTOS
   16 key-on, de los cuales 3 caben enteros en 32 KB y 13 no
   bytes de sample referenciados: 143.360 · perdidos por el tope de 32 KB: 110.580 (77%)
   ```
3. **VGMPlay sube los 128 KB pase lo que pase** (su changelog documenta el fix de
   "samples >128K" en la 1.3): asume una unidad MSX-AUDIO **ampliada**, que es
   justo lo que documenta la wiki (32 KB de serie, ampliables a 256 KB).

---

## 2. Síntoma 1 — la voz: CONFIRMADO, y es peor que "recortada"

### 2.1 El RTL

`fpga/src/y8950_adpcm.v:96-111`:

```verilog
wire [17:0] rd_byte_addr = ptr[18:1]    & (is64k ? 18'h0FFFF : 18'h3FFFF);
wire [17:0] wr_byte_addr = wr_ptr[18:1] & (is64k ? 18'h0FFFF : 18'h3FFFF);
wire        rd_oob       = (rd_byte_addr[17:15] != 3'b000) | rom_bank;
wire        wr_oob       = (wr_byte_addr[17:15] != 3'b000) | rom_bank;
...
reg  [7:0] sram [0:32767];                                    // <-- 32 KB
always @(posedge clk) ram_q <= sram[rd_byte_addr[14:0]];      // <-- índice de 15 bits
wire [7:0] mem_byte = rd_oob ? 8'h00 : ram_q;                 // <-- fuera de rango = 0x00
wire ram_we = ... && !wr_oob;                                 // <-- escritura ignorada
always @(posedge clk) if (ram_we) sram[wr_byte_addr[14:0]] <= din;
```

**No hay envolvente**: la guarda `[17:15] != 0` corta limpiamente. El camino de
direcciones (`ptr[18:0]` en nibbles, máscara `0x3FFFF`) **ya cubre los 256 KB del
chip real** — el único tope son el array y esas dos guardas. Esto es fiel a openMSX
(`Y8950Adpcm::readMemory`: `if (romBank || addr >= ram.size()) return 0;`), es
decir: el MSXimus emula correctamente una unidad **de serie**; el fichero pide una
**ampliada**.

### 2.2 Por qué "0x00" no es silencio, es un raíl

Con `mem_byte = 0`, los nibbles que entran al `jt10_adpcmb` son `0x0`:
`data_use[3] = 0` (signo **positivo**) y `d2 = {000,1} = 1` → cada `adv` suma
`step/8` a `x1` de forma monótona, y `step` decae hasta su suelo de 127. Resultado:
**`x1` trepa hasta `limpos` y se queda ahí**. La salida no es silencio: es un
**escalón de fondo de escala** que dura toda la nota.

(Si la RAM arrancara a `0xFF` como el HW real en vez de a 0, sería el raíl
*negativo* — la nota del RTL sobre ese detalle sólo cambia el signo del artefacto.)

### 2.3 Simulación con el bloque real de 128 KB — la prueba

Banco `sim/tb_adpcm128k.v` (Icarus, WSL Ubuntu-24.04): instancia el
`y8950_adpcm.v` del repo **sin tocar**, sube los 128 KB reales del VGZ por el
protocolo `reg 0F`/BUF_RDY exactamente como VGMPlay, y reproduce 4 segmentos
representativos con las direcciones ya remapeadas ×8. Se corre dos veces: contra el
RTL actual (32 KB) y contra una copia parcheada a 256 KB.

Lo primero que dice el banco, antes de reproducir una sola nota:

```
=== ORIGINAL (32 KB) ===          === PARCHE (256 KB) ===
[TB] subida completada: 128 KB    [TB] subida completada: 128 KB
[TB] bytes del bloque presentes   [TB] bytes del bloque presentes
     en la RAM: 32768 de 131072        en la RAM: 131072 de 131072
```

| Segmento (bytes) | pico 32K | RMS 32K | **DC 32K** | pico 256K | RMS 256K | DC 256K |
|---|---:|---:|---:|---:|---:|---:|
| #1 `0x00000-0x027FF` (dentro) | 22.041 | 3.564 | −302 | 22.041 | 3.564 | −302 |
| #4 `0x07000-0x097FF` (cruza) | 32.639 | 23.142 | **+16.725** | 18.647 | 2.401 | −394 |
| #9 `0x12000-0x157FF` (fuera) | 32.639 | 31.722 | **+31.244** | 32.640 | 7.801 | +618 |
| #16 `0x1D800-0x1FFFF` (fuera) | 32.639 | 30.624 | **+29.284** | 32.640 | 10.884 | −9.204 |

- El segmento de control **#1 es bit-a-bit idéntico** en ambas versiones → el
  parche es un superconjunto puro, cero regresión sobre lo que ya funcionaba
  (Fire Hawk, MoonBlaster, `msxtest.rom`…).
- En #9 el RMS (31.722) es prácticamente el DC (31.244): **es una continua**, no
  audio. Eso es lo que Albert oye como "voz distorsionada".
- 13 de los 16 key-on del fichero están en esa situación.

Ficheros para escuchar (49.716 Hz, mono, 13,1 s):
`sim/adpcm_32k_ACTUAL.wav` vs `sim/adpcm_256k_PROPUESTO.wav`.

---

## 3. Síntoma 2 — "música muy baja": dos causas, una dominante

### 3.1 Causa dominante — el DC del raíl se come el headroom (misma raíz que §2)

`fpga/top.v:3476` y `:3516-3529`:

```verilog
wire [15:0] y8950_adpcm_term = {y8950_adpcm_wav[15], y8950_adpcm_wav[15:1]};   // >>>1
...
function [15:0] sat16(input signed [18:0] v);      // clamp simétrico a ±32767
```

Con el ADPCM clavado en el raíl, `y8950_adpcm_term` aporta un **DC constante de
+16.319** a `mixL_st`, `mixR_st` y `mix_mono`. El `sat16` recorta a +32767, así que
**la mitad del recorrido positivo desaparece** mientras suena cualquiera de esas 13
notas: el FM del Y8950 se recorta sólo por arriba (distorsión asimétrica) y la
sensación es exactamente "la música suena muy baja y sucia".

Es el **mismo mecanismo** que el bug #10 del `INFORME_NIQUELADO.md` (los PSG
unsigned comiéndose el headroom positivo), sólo que aquí el offensor mete +16k en
vez de los +32k de los dos PSG — y en este VGZ los PSG están callados (el BIOS deja
volúmenes a 0), así que **el ADPCM es el único culpable del desbalance de continua**.

> Nota: el bug #10 sigue siendo real y **agrava** el caso general (juego + PSG +
> ADPCM), pero no hace falta invocarlo para explicar este fichero.

### 3.2 Causa secundaria e independiente — el ADPCM entra +12 dB de más

Aritmética cerrada, cadena por cadena:

| | MSXimus | openMSX (ground truth del proyecto) |
|---|---|---|
| Salida del decoder deltaT | `jt10_adpcmb.pcm` = ±32.767 (`limpos/limneg`) | `pd.out = Math::clipToInt16(...)` = ±32.767 |
| Volumen (reg 12 = 0xFF) | `pcm_inter * 255 >> 8` = ±32.639 | `output = out*volume; return output >> 12` = ±**2.040** |
| Término al mixer | `>>> 1` → **±16.320** | ±**2.040** |
| Portadora FM a tope | `jtopl_acc` INW=13 → ±**4.095** por canal | `dB2LinTab` máx = `1<<11` = ±**2.048** |
| **ADPCM / 1 portadora FM** | 16.320 / 4.095 = **3,99×** | 2.040 / 2.048 = **1,00×** |

→ El ADPCM del MSXimus está **+12,0 dB** por encima del balance interno del chip
según openMSX. (Verificación cruzada: `Y8950::getAmplificationFactorImpl()` devuelve
`1/(1<<11)` = 1/2048, o sea que openMSX diseña cada canal del Y8950 —los 9 de FM y
el de ADPCM— para picar en ~2048. Dos rutas independientes dan el mismo número.)

El valor canónico es **`>>> 3`**: `32.639/8 = 4.080` frente a los `4.095` de una
portadora FM → 0,99×, clavado.

---

## 4. Escalón (a) — "el barato": ampliar la BSRAM. **NO EXISTE**

Aritmética del GW5AT-60 (bloque BSRAM = 18 Kb ⇒ 2 KB útiles en configuración ×8):

| Objetivo | Bloques BSRAM |
|---|---:|
| 32 KB (lo actual — corroborado por `LEEME_80.txt`: *"los 32KB de samples = +16 bloques"*) | 16 |
| 64 KB | 32 |
| 128 KB (lo que pide este VGZ) | 64 |
| **256 KB (el máximo del Y8950, el objetivo real)** | **128** |
| **Total del dispositivo** | **118** |

**128 > 118: los 256 KB no caben en BSRAM ni con el chip vacío.** No hay
"presupuesto que rascar" que pueda cambiar eso; el escalón (a) está cerrado por
aritmética, no por ocupación.

Y sobre la ocupación, con los 4 bloques que libera `6d15c0b`:

- +4 bloques = **+8 KB** → la RAM pasaría de 32 a 40 KB. Ni siquiera es una
  potencia de dos válida para la máscara del chip, y sigue perdiendo el 69% del
  fichero. **Inútil.**
- Ni siquiera duplicar a 64 KB (+16 bloques) cabe en 4-5 bloques libres.

> ⚠️ **Discrepancia que hay que resolver con un PnR fresco**: el informe de la
> herramienta que hay en el repo (`fpga/impl/pnr/project.rpt.html`, 16/07) dice
> `BSRAM 7 SP + 54 SDPB + 1 SDPX9B + 1 DPB + 10 pROM = **73/118 (62%)**`, y el
> `INFORME_BORDES_MSX.md` cita ese mismo 73→69. En cambio `INFORME_V9990_VIABILIDAD.md`
> y `INFORME_SPC700_VIABILIDAD.md` (26/07) afirman **117/118** para la _157.
> El delta de −4 es sólido; el absoluto no. **Lo más probable es que el rpt del repo
> esté rancio** (es de la _110, antes del ring de vídeo de 24 bloques y de las cachés
> del shim), y que lo real hoy sea 117→113. Da igual para la conclusión: 128 > 118.

---

## 5. Escalón (b) — "el bueno": los 256 KB desde la SDRAM

### 5.1 Por qué SDRAM y no DDR3

- La cabecera de `wave_sdram.v` documenta por qué el OPL4 se mudó de la DDR3 a la
  SDRAM (saga _94-_103: la DDR3 del SOM es analógicamente marginal en esta placa).
  La VRAM del V9968 vive hoy en DDR3 y funciona, pero **es el subsistema más frágil
  del core**: no conviene meterle un cliente nuevo.
- La SDRAM del dock ya sirve mapper/megaram/VRAM clásica/wave sin corromper un byte.
- **Y sobre todo: hay dos puertos libres ya cableados.** `fpga/top.v:2195-2205`,
  con `ENABLE_VRAM_DDR3` (la línea v2.0), `wv2_*` y `wv3_*` están atados a 0. El
  árbitro, el CDC, el `inflight` de 4 fases y las prioridades de `memory.v` ya
  existen y están validados en placa desde la _104.

### 5.2 Mapa de memoria propuesto

`memory.v:384-389` mapea toda la familia wave a `row = {1'b1, 2'b00, addr[21:12]}`,
`bank = addr[11:10]`, `col = addr[9:1]` ⇒ **filas 4096-5119** (los 4 MB del OPL4:
YRW801 en 0x000000-0x1FFFFF + RAM de muestras en 0x200000-0x3FFFFF). El W9825G6KH
tiene 8192 filas: **5120-8191 están libres** (12 MB).

Aplicar el arreglo que ya propone el `INFORME_NIQUELADO.md` (bug #3) — sacar `wv2`
a su propio bloque de filas — y darle esa ventana al ADPCM:

```diff
--- a/fpga/src/memory.v
+++ b/fpga/src/memory.v
@@ -384,7 +384,7 @@
             pre_row <= (wv_req == 1 && wv_inflight == 0)   ? { 1'b1, 2'b00, wv_addr[21:12] } :
-                       (wv2_req == 1 && wv2_inflight == 0) ? { 1'b1, 2'b00, wv2_addr[21:12] } :
+                       (wv2_req == 1 && wv2_inflight == 0) ? { 1'b1, 2'b01, wv2_addr[21:12] } :
                                                              { 1'b1, 2'b00, wv3_addr[21:12] };
```

⇒ `wv2` pasa a filas **5120-6143**, físicamente inalcanzable por la wave del OPL4,
por la CPU (filas 0-2047) y por el VDP. El ADPCM usa `wv2_addr[17:0]` (256 KB) con
`[21:18]=0`. Efecto colateral bueno: **cierra el bug #3 del niquelado** para la
línea de respaldo _137.

> Alternativa sin tocar `memory.v`: colocar los 256 KB en el techo de la ventana
> actual (`0x3C0000-0x3FFFFF`, último cuarto de MB de la RAM de muestras del OPL4).
> Coste cero, pero colisiona si algún software del MoonSound usa >1,75 MB de sample
> RAM. **No recomendada**: por un `2'b01` no merece la pena dejar una mina.

### 5.3 Ancho de banda — es ridículo, como se sospechaba

`fs` del ADPCM-B en el RTL = `cen3m6/72` = 49.716 Hz de *ticks*; cada `adv` consume
un nibble, y `adv` ocurre con probabilidad `deltaN/65536`.

| | nibbles/s | bytes/s | fetches de PALABRA/s (2 B) | plazo por byte |
|---|---:|---:|---:|---:|
| Este VGZ (`deltaN=0x24E0`) | 7.161 | 3.580 | 1.790 | 279 µs |
| **Peor caso absoluto** (`deltaN=0xFFFF`) | 49.716 | 24.858 | 12.429 | 40 µs |
| Subida CPU (VGMPlay, `OUT`+poll ≈30 µs/byte) | — | ~33.000 | ~33.000 | — |

Contra la capacidad del puerto wave de `memory.v` (**~6,75 M ops/s** en turnos de CPU
vacíos, según su propio comentario): **0,03%** para este fichero, **0,18%** en el
peor caso. El motor wavetable del OPL4 mueve ~2 MB/s por el mismo puerto: el ADPCM
es entre el **0,1% y el 1,2%** de lo que ya circula. Y con prioridad `wave > wv2`
el OPL4 ni se entera.

Márgenes de latencia: el plazo más apretado (40 µs) contra un turno concedido cada
~148 ns ⇒ **>270× de margen**. Un solo registro de palabra prefetcheada basta.

### 5.4 Cambios en `y8950_adpcm.v` (esbozo del parche)

Puerto nuevo (dominio `clk_54m`, toggle+3FF como el host de `wave_sdram.v`):

```verilog
    output reg         mem_req_t,      // TOGGLE: nueva operación
    output reg         mem_we,
    output reg [17:0]  mem_addr,       // byte dentro de los 256 KB
    output reg [7:0]   mem_wdata,
    input  wire [15:0] mem_rword,      // palabra alineada (memory.v ya devuelve 16 b)
    input  wire        mem_done_t      // TOGGLE de completado
```

Sustituir las líneas 96-111 por:

```verilog
// direcciones: SIN la guarda de 32 KB (el chip real direcciona 256 KB)
wire [17:0] rd_byte_addr = ptr[18:1]    & (is64k ? 18'h0FFFF : 18'h3FFFF);
wire [17:0] wr_byte_addr = wr_ptr[18:1] & (is64k ? 18'h0FFFF : 18'h3FFFF);
wire        rd_oob = rom_bank;          // el HW real lee 0 en banco ROM
wire        wr_oob = rom_bank;

// caché de PALABRA + una plaza de prefetch (el puntero avanza monótono)
reg [15:0] cw, nw;  reg [16:0] cw_tag, nw_tag;  reg cw_v, nw_v;
wire       word_hit = cw_v && (cw_tag == rd_byte_addr[17:1]);
wire [7:0] mem_byte = rd_oob ? 8'h00
                    : (rd_byte_addr[0] ? cw[15:8] : cw[7:0]);
```

y **gatear el motor con el hit** (fail-safe: si falta el dato se pierde un tick de
49,7 kHz en vez de decodificar basura):

```verilog
wire engine = cen_fs && playing && !dec_clr && (!mode_mem || word_hit);
```

FSM de servicio (una op en vuelo, prioridad escritura > miss > prefetch):

- `mode_mem && !word_hit && !busy` → leer palabra `rd_byte_addr[17:1]` (miss; sólo
  puede ocurrir tras un START/repeat).
- `word_hit && !nw_v` → prefetch de `cw_tag+1` en `nw` (promoción a `cw` al cruzar).
- `ram_we` → escritura de byte (el puerto de `memory.v` ya elige lane por `addr[0]`
  vía DQM) **e invalidación** de `cw`/`nw` si el tag coincide.
- **`buf_rdy` pasa a subir cuando llega el `mem_done_t`** de la escritura, no en
  tiempo 0. Es *más* correcto que ahora (es el significado real del flag) y le da al
  handshake de VGMPlay el control de flujo que ya está esperando con su `and 8`.
- Lecturas por `reg 0F` (modo 0x20, RAM→CPU): misma caché; en cada `rd_c1` se
  devuelve el byte ya traído y se lanza el siguiente, con `buf_rdy` bajo hasta que
  aterrice — que es literalmente lo que hace el chip real.

Y en `top.v`, cablear ese puerto al `wv2` libre a través de un shim
`adpcm_sdram.v` calcado del lado HOST de `wave_sdram.v` (líneas 61-141: `3FF` +
toggle + `ST_IDLE/ST_REQ/ST_DROP`), con `wv2_addr = {4'd0, mem_addr}`.

### 5.5 Coste estimado

| Concepto | Logic (LUT) | FF | BSRAM |
|---|---:|---:|---:|
| Retirar el array de 32 KB | — | — | **−16** |
| Caché de palabra + prefetch + tags + FSM en `y8950_adpcm` | +110 … 170 | +70 | 0 |
| Shim `adpcm_sdram` (CDC 3FF + FSM, copia del host de `wave_sdram`) | +60 … 90 | +45 | 0 |
| `memory.v` (`2'b00`→`2'b01` en un mux) | +0 | 0 | 0 |
| **Total** | **+170 … 260** | **+115** | **−16** |

A la densidad de empaquetado medida del proyecto (~1,53 logic/CLS): **≈ +110-170
CLS**, sobre los ~3.363 libres del informe del V9990. **Y devuelve 16 bloques de
BSRAM** — que es exactamente el déficit de 1-2 bloques que bloqueaba el escenario B
del SPC700 y buena parte de lo que pedía el V9990.

### 5.6 Un detalle que hay que decidir a la vez

`is64k` (reg 8 b1) hoy enmascara a `0xFFFF` (64 KB). Con la RAM real de 256 KB eso
queda correcto tal cual (es lo que hace openMSX: `addrMask = 64K ? (1<<16)-1 : (1<<18)-1`).
No tocar. **Y no hay nada que ensanchar aguas arriba**: `start_addr`/`stop_addr`/`ptr`
ya son de 19 bits en nibbles = 256 KB, y los registros 09/0A y 0B/0C ya alimentan
los bits [18:3]. El camino de direcciones está listo desde el _80.

---

## 6. Parche del mixer (independiente, 1 línea)

```diff
--- a/fpga/top.v
+++ b/fpga/top.v
@@ -3476 +3476 @@
-    wire [15:0] y8950_adpcm_term = {y8950_adpcm_wav[15], y8950_adpcm_wav[15:1]};
+    // _XX: balance canónico openMSX — el ADPCM-B pica igual que UNA portadora FM
+    //  del Y8950 (2040 vs 2048 en openMSX). Con >>>1 entraba a 3,99x = +12,0 dB.
+    wire [15:0] y8950_adpcm_term = {{3{y8950_adpcm_wav[15]}}, y8950_adpcm_wav[15:3]};
```

Escrito como concatenación con extensión de signo explícita, no como `>>>`, para no
repetir la **lección _85/_115** (signedness envenenada por un literal unsigned).

**Honestidad sobre este cambio**: −12 dB es mucho, y las voces de Fire Hawk /
MoonBlaster llevan validadas en placa desde la _80 con el `>>>1`. Si al probarlo
suena demasiado apagado, el intermedio es `>>>2` (−6 dB, `{{2{...[15]}}, ...[15:2]}`):
sigue quitando el 75% del exceso de headroom y deja el ADPCM a 2× la portadora FM.
Mi recomendación es **`>>>3` (canónico) y contrastarlo en placa contra el vídeo del
PicoVerse**, que es la referencia externa que ha traído Albert.

**Orden de aplicación importante**: aplicar §6 *antes* que §5 haría la voz rota
*más* silenciosa pero no la arreglaría, y podría enmascarar el diagnóstico. El
arreglo de verdad es §5; §6 es el balance correcto una vez que hay audio real.

---

## 7. Plan de validación

### 7.1 Banco (ya montado y corrido, reproducible)

`sim/` contiene todo lo necesario. Reproducir con:

```bash
wsl -d Ubuntu-24.04 -- bash -lc "cd /mnt/c/.../scratchpad/adpcm/sim && ./run.sh"
```

- `tb_adpcm128k.v` — banco con el bloque DELTA-T real, protocolo VGMPlay exacto.
- `deltat.hex` — los 128 KB extraídos del VGZ.
- `y8950_adpcm_orig.v` — copia intacta del repo (32 KB).
- `y8950_adpcm_256k.v` — variante con el array y las guardas a 256 KB.
- `out_orig.txt` / `out_256k.txt` — 650.000 muestras cada uno.
- `adpcm_32k_ACTUAL.wav` / `adpcm_256k_PROPUESTO.wav` — para escuchar la diferencia.

**Criterios de aceptación del banco** (todos verificados ya sobre la variante
"array a 256 KB"; hay que **repetirlos sobre la versión con SDRAM** cuando exista):

1. `[TB] bytes del bloque presentes en la RAM` = **131.072**.
2. Segmento #1 (dentro de 32 KB) **bit-a-bit idéntico** al RTL actual. *(no
   regresión)*
3. Segmentos #4/#9/#16: `|media|` < 2.000 y `RMS` < 15.000 (hoy: 16.7k/31.2k/29.3k
   de continua).
4. Ningún tramo de >1.000 muestras consecutivas pegado a `±32639`.

Añadir para la versión SDRAM: un modelo de latencia del puerto (p. ej. 20-500
ciclos aleatorios de `clk_54m` por operación) y comprobar que (2) sigue siendo
bit-a-bit — el `engine` gateado por `word_hit` sólo puede *retrasar* un tick, nunca
cambiar el dato.

### 7.2 Placa

1. **msxtest.rom** (pantalla Y8950): `ADPCM: W:OK R:OK Play:OK` sigue verde.
2. **Fire Hawk** (Thexder II): las voces "Fire!" siguen igual que en la _80 →
   no regresión del camino de 32 KB.
3. **Este VGZ con VGMPlay**: la voz de Psycho Soldier debe salir entera y el fondo
   FM dejar de sonar apagado. Comparar con el vídeo del PicoVerse 2350.
4. **Un VGZ de MoonSound/OPL4 a la vez** (p. ej. los de Daytona que ya hay en
   `Downloads/emul/opl4/`) para confirmar que el ADPCM en SDRAM no perturba al motor
   wavetable — es el único riesgo real del cambio (comparten árbitro).
5. Vigilar la telemetría UART (`tools/dbg_reader.py`): si el bug #4 del niquelado ya
   está aplicado, `fr[15]={ifw_hits,alive}` debe seguir sin acumular hits del
   watchdog del OPL4.

### 7.3 Lo que NO va a arreglar este parche (esperado, no es bug)

El VGM declara el Y8950 a **4,000 MHz** (recreativa) y el MSXimus lo corre a
**3,579545 MHz** (MSX). Todo el fichero —FM y ADPCM— sonará un **10,6% más grave y
lento** que el original de arcade. Es correcto: es lo que haría un MSX-AUDIO real.
No confundirlo con un fallo cuando se compare contra el vídeo de YouTube.

---

## 8. Lo que no cuadra / dónde puedo estar equivocado

1. **La ocupación real de BSRAM** (§4): dos fuentes del propio repo se contradicen
   (73/118 vs 117/118) y el rpt de la herramienta es del 16/07. **Hay que regenerar
   el PnR** antes de fiarse de cualquier presupuesto. La conclusión del escalón (a)
   no depende de ello, pero cualquier otra decisión de recursos sí.
2. **El +12 dB del mixer** (§3.2) se apoya en dos suposiciones que he verificado por
   caminos independientes pero no he podido *medir*: que una portadora del `jtopl`
   pica en ±4095 (INW=13 del acumulador) y que `dB2LinTab` de openMSX pica en 2048
   (`DB2LIN_AMP_BITS=11`, confirmado por `getAmplificationFactorImpl()=1/2048`). Si
   alguna es falsa, el factor cambia; el *signo* del error (el ADPCM va demasiado
   alto) no.
3. **`hg.sr.ht` devolvía 502**, así que §1.1 se apoya en el desensamblado del
   binario 1.4 (`VGMPLAY.COM` del pack OCM-SDBIOS) *y* en unas copias de
   `MSXAudio.asm`/`Y8950.asm` que ya había en el scratchpad. Las dos fuentes
   coinciden instrucción a instrucción, lo que se valida mutuamente; aun así, la
   procedencia de los `.asm` no la he verificado contra el repositorio oficial. Si
   Albert usa otra build de VGMPlay, reconfirmar `and 11000100B` y el `add hl,hl ×3`.
4. **La sospecha original del wrap ×4** era razonable pero incorrecta (§0-E). Lo
   digo explícitamente porque el mecanismo real (raíl DC) tiene una consecuencia
   *distinta y peor* en el mixer, y es la que explica el segundo síntoma.
5. El banco corre con `cen3m6 = 1` (acelerado ×15). Es legítimo porque toda la
   lógica del módulo es cen-based, pero **no valida el cruce de dominios** con el
   `clk_54m` real. Para la versión SDRAM eso hay que probarlo con el ratio real.

---

## 9. Orden de trabajo sugerido

| Paso | Qué | Riesgo | Ganancia |
|---|---|---|---|
| 1 | Regenerar PnR y cerrar el número de BSRAM | nulo | desbloquea todos los presupuestos |
| 2 | `memory.v`: `wv2` a filas 5120+ (`2'b01`) | muy bajo (wv2 está a 0 hoy) | habilita §5 y cierra el bug #3 del niquelado |
| 3 | `adpcm_sdram.v` + puerto en `y8950_adpcm.v` → **256 KB** | medio (comparte árbitro con el OPL4) | arregla el bug; **−16 BSRAM** |
| 4 | Re-correr el banco §7.1 con latencia inyectada | nulo | garantiza no-regresión bit a bit |
| 5 | `top.v:3476` → `>>>3` | bajo, reversible | balance canónico; contrastar en placa |
| 6 | (aparte) bug #10 del niquelado: centrar los PSG | bajo | recupera el headroom positivo en el caso general |
