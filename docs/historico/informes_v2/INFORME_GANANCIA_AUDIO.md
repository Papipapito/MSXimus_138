# Estructura de ganancia del audio del MSXimus

**Fecha:** 2026-07-28 · **Base:** `C:\Users\alber\proyectosAI\msx\MSX_up` (SOLO LECTURA, no se ha
tocado ni un byte del repo) · **Build de referencia:** `_160` (`msximus_60k_20260728_160_adpcm256k.fs`)

**Evidencia:** `…\scratchpad\ganancia\` (WAVs de openMSX, scripts de medida, banco de pruebas
iverilog) y `…\scratchpad\audio_dbg\grab.wav` (grabación de placa).

---

## 0. Resumen ejecutivo — las cinco conclusiones

| # | Conclusión | Confianza |
|---|---|---|
| **C1** | **El diagnóstico de partida ("sacamos ~1/10 del nivel") es FALSO en su magnitud.** Frente a openMSX con sus ajustes por defecto estamos **−2,2 dB** (aritmética) / **−2,6 dB** (medido), no −20 dB. | **ALTA** — dos rutas independientes coinciden en 0,4 dB |
| **C2** | La sensación es real, pero la causa no es un bug: el mezclador tiene su unidad puesta en **"8 portadoras FM = fondo de escala"** y la música real pica en **~1 portadora**. Nos comemos ~18 dB por diseño; openMSX se come ~16 dB. | **ALTA** — medido: 0,86 portadoras de pico en placa, 1,14 en openMSX |
| **C3** | `grab.wav` es una captura **a ganancia unidad (±0,5 dB)** del flujo digital de 16 bits del HDMI. Los dBFS de la grabación son de fiar. | **ALTA** — validado con la calibración de portadora (§3.4) |
| **C4** | El bug #10 (PSG sin signo) es real y **cuesta la mitad del recorrido positivo** (los DOS PSG en mono se lo comen entero). Hay que arreglarlo **antes** de tocar ninguna ganancia. | **CONFIRMADO** |
| **C5** | **Ya existe un control de volumen en el core** — el del linaje OCM (`switched_io_ports`, puertos `$45`/`$46` ID212, con `MstrVol`/`PsgVol`/`SccVol`/`OpllVol`) — pero sus salidas **no están cableadas** en la instancia de `top.v`: son registros que el software MSX puede escribir y que no hacen nada. | **CONFIRMADO** (`fpga/top.v:4489`) |

**Y un hallazgo colateral que probablemente sea EL culpable de los "chasquidos"** (§8): el camino
al HDMI remuestrea los cores FM de **49,7 kHz a 44,1 kHz por vecino más próximo, sin filtro**.
Cada tono FM genera un alias dentro de banda a **−24 dB**. Eso no lo arregla la ganancia; la
ganancia lo hará *más* audible.

---

## 1. El camino de audio, tal cual está hoy

```
YM2149 ×2 ──► psg_filter ──► psgSound3[7:0]  ─┐  (unsigned 0..255, <<6)
scc_wave2 ×2 ────────────► scc_wav[14:0]    ─┤  (<<1)
jt2413 (OPLL) ───────────► jt2413_wav[15:0] ─┤
jtopl2 (Y8950 FM) ───────► y8950_wav[15:0]  ─┤   suma 19 bits  ──► sat16 ──► audio_sample[15:0]
y8950_adpcm ─────────────► …_wav[15:0] >>>3 ─┤   (top.v:3610-3623)   (3606)     @ 3,58 MHz
opl3 (OPL4 FM) ──────────► opl4fm_wav +F8   ─┤
YMF278B (OPL4 PCM) ──────► opl4pcm_l/r >>1  ─┘
                                             │
   msx2hdmi_v9968.sv:597-601 (doble registro, SIN atenuación)
                                             ▼
   packet_picker.sv:117  24'(muestra)<<8  +  WORD_LENGTH="16 bits"  →  HDMI L-PCM 44,1 kHz
```

**Verificado (punto 5 del encargo): entre `audio_sample` y el cable HDMI no hay ninguna
atenuación.** `msx2hdmi_v9968.sv:597-601` sólo hace un doble registro con filtro de estabilidad;
`packet_picker.sv:117-118` alinea a la izquierda los 16 bits dentro del hueco de 24
(`<<(24-AUDIO_BIT_WIDTH)` = `<<8`) y `packet_picker.sv:69-71` declara correctamente
`WORD_LENGTH` = 16 bits en el canal de estado. Cadena de bits exacta, ganancia = 1,000.
El reloj de audio es 44100 Hz exactos (divisor fraccionario, `msx2hdmi_v9968.sv:569-580`).

---

## 2. Inventario de amplitudes nativas (punto 1 del encargo)

Todo leído del RTL. Unidad de referencia: **1 CAR = 1 portadora FM a TL=0 = 4095 LSB**
(`jtopl_acc`/`jtopl_single_acc` con `INW=13` ⇒ `op_result` es `signed [12:0]`, y el mismo
acumulador lo usan `jt2413` (OPLL) y `jtopl2` (Y8950); el OPL3 de `opl4fm` usa
`OP_OUT_WIDTH = 13` en `opl3/opl3_pkg.sv:53`, o sea el mismo ±4095).

| Fuente | Fichero / evidencia | Pico nativo | Término al mixer | Pico del término | CAR | dBFS |
|---|---|---|---|---|---|---|
| PSG1 — 1 canal a vol 15 | `PSG_YM2149/YM2149.vhdl:602-613`, `src/psg_filter.v` | 127 | `{1'b0,x,6'b0}` | 0…**+8128** (CC +4064, CA ±4064) | 0,99 CA | −18,1 |
| PSG1 — 3 canales a vol 15 | ídem (`audio_mix` satura: 3×255 ⇒ recorte a 255) | 255 | ídem | 0…**+16320** (CC +8160, CA ±8160) | 1,99 CA | −6,1 |
| PSG2 | `top.v:2455-2460` | ídem | ídem | ídem | ídem | ídem |
| SCC1 — 1 canal máx | `src/ocm/scc_wave2.vhd:452` (`8b×4b`) | ±1920 | `{x,1'b0}` | ±3840 | 0,94 | −18,6 |
| SCC1 — 5 canales máx | `scc_wave2.vhd:527-529` (acum. 15 b) | ±9600 | `{x,1'b0}` | **±19200** | 4,69 | −4,7 |
| SCC2 (ghost) | `top.v:3516` | ídem | ídem | ídem | ídem | ídem |
| OPLL — 1 portadora | `jtopl/jt2413.v:73,199` | ±4095 | nativo | ±4095 | 1,00 | −18,1 |
| OPLL — chip a tope | `jtopl_single_acc` satura | ±32767 | nativo | **±32767** | 8,00 | 0,0 |
| Y8950 FM — 1 portadora | `jtopl/jtopl_acc.v` | ±4095 | nativo | ±4095 | 1,00 | −18,1 |
| Y8950 FM — chip a tope | ídem (ritmo ×2 incluido) | ±32767 | nativo | **±32767** | 8,00 | 0,0 |
| ADPCM-B a vol FF | `top.v:3570` | ±32639 | `>>>3` | ±4080 | 1,00 | −18,1 |
| OPL4 FM — 1 portadora | `opl3/opl3_pkg.sv:53` | ±4095 | nativo (atenuación F8) | ±4095 | 1,00 | −18,1 |
| OPL4 FM — a tope | `opl3/channels.sv:374-386` (clamp) | ±32767 | nativo | **±32767** | 8,00 | 0,0 |
| OPL4 PCM — 24 slots | `opl4wave/YMF278B_pkg.sv:379` `TrimWave` | ±32767 | `>>1` | **±16383** | 4,00 | −6,0 |

**Suma de todos los máximos (mono): 205 804 LSB = 50,3 CAR = +16,0 dB sobre fondo de escala.**
El `sat16` de 19 bits no desborda (205 804 < 262 143 ✔) pero recorta duro. Es decir: **el mezclador
ya vive de la saturación en el caso patológico**, hoy, sin haber tocado nada.

---

## 3. Referencia externa: openMSX (punto 2 del encargo)

### 3.1 Cómo se ha medido

- openMSX 21.x de `C:\Program Files\openMSX`, arrancado desde la consola con `-script`.
- Disco creado con `diskmanipulator create … 720k` + `import` (MSXDOS2.SYS, COMMAND2.COM,
  VGMPLAY.COM, PSYCHO.VGZ) — script `ganancia/ref.tcl`.
- Máquina **Panasonic FS-A1GT** + extensión **`audio`** ("Generic Yamaha Y8950 MSX-AUDIO
  with 256 kB sampleRAM" — los 256 KB del `_160`, mismo tamaño de RAM de muestras).
- Reproductor: **VGMPlay 1.4 (dev) de Grauw**, el mismo `.vgz` sin recomprimir.
- Grabación: `soundlog start` (WAV 44,1 kHz 16 bit) — `ganancia/om_ref.wav`.
- Ajustes de openMSX **por defecto**: `master_volume = 80`, volumen de cada dispositivo `= 75`.
- Pantallazo de confirmación: `ganancia/om_end.png` ("Y8950 (MSX-AUDIO) 4000000 Hz → MSX-AUDIO
  3579545 Hz / Length 1:14.77 / Playing…").
- La cabecera del `.vgz` confirma que el fichero es **sólo Y8950** (offset 0x58 = 4 MHz; ningún
  otro chip declarado). Toda la señal es MSX-Audio: FM + ADPCM-B.

### 3.2 Nivel del mismo tema

| | Pico | RMS (tramo con música) |
|---|---|---|
| **openMSX** (A1GT + `audio`, por defecto) | **−14,8 dBFS** (5995 LSB) | **−33,2 dBFS** |
| **MSXimus `_160`** (`grab.wav`) | **−19,3 dBFS** (3535 LSB) | **−35,8 dBFS** |
| **Diferencia** | **+4,6 dB** | **+2,6 dB** |

### 3.3 Calibración absoluta de openMSX (lo que de verdad hace falta)

Comparar dos temas no basta: hay que saber cuántos LSB vale **una unidad de chip** en openMSX.
Se han programado los chips a mano desde BASIC (una portadora sola, TL=0, seno de 440 Hz) y se
ha medido la salida — scripts `ganancia/cal.tcl` y `ganancia/cal2.tcl`:

| Medida en openMSX (defectos 80/75) | Pico LSB | Pico dBFS | RMS dBFS | Fichero |
|---|---|---|---|---|
| **Y8950 — 1 portadora FM, TL=0** | **5249** | −15,9 | −19,1 | `cal1.wav` |
| **OPLL — 1 portadora, vol=0** | **3915** | −18,5 | −21,7 | `opll1.wav` |
| **PSG — 1 canal, vol=15** (cuadrada) | 5675 pico / **4405 RMS** | −15,2 | −17,4 | `psg1.wav` |
| Y8950 — 1 portadora con master=100 y vol=100 | **8749** | −11,5 | −14,7 | `cal1_max.wav` |

La última línea confirma que el escalado de openMSX es lineal y exacto:
5249/8749 = **0,600** = 0,80 × 0,75. Los ajustes por defecto son **−4,4 dB** respecto al máximo
de openMSX.

### 3.4 Validación cruzada — y por qué `grab.wav` es de fiar

- **Predicción aritmética**: si `grab.wav` fuese una captura digital a ganancia unidad, la
  relación openMSX/MSXimus tendría que ser exactamente la relación de "1 portadora":
  5249 / 4095 = **1,282 = +2,16 dB**.
- **Medido**: +2,6 dB de RMS. **Error: 0,4 dB.**

Dos cadenas independientes (RTL del MSXimus y emulación de openMSX) coinciden en 0,4 dB
⇒ **`grab.wav` es una captura del flujo digital de 16 bits a ganancia unidad ±0,5 dB**
y sus dBFS absolutos son válidos. (El +4,6 dB de *pico* es mayor porque openMSX remuestrea
49,7→44,1 kHz con un resampler de verdad, que sobreoscila en los transitorios del ADPCM.)

> Matiz honesto: el suelo de ruido de `grab.wav` durante la carga es −85 dBFS (≈1,8 LSB) y no
> ceros exactos, así que la captura pasó por *alguna* etapa analógica o por un códec. La
> coincidencia de 0,4 dB dice que esa etapa está a ganancia unidad; no cambia ninguna conclusión.

### 3.5 Balance por voz: MSXimus vs openMSX (normalizado a Y8950 = 1)

| Voz | MSXimus | openMSX | Error del MSXimus |
|---|---|---|---|
| Y8950 FM (portadora) | 1,000 | 1,000 | **0 dB** (referencia) |
| ADPCM-B a vol FF | 0,996 | 0,996 | **0 dB** ✔ (ya arreglado en `_159b`/`f2141c5`) |
| **OPLL (portadora)** | 1,000 | 0,746 | **+2,6 dB de más** |
| **PSG (canal, CA)** | 0,992 | 0,839 | **+1,5 dB de más** |
| SCC (canal) | 0,938 | *no medido* | — |
| OPL4 FM / PCM | 1,000 / 4,00 | *no medido* | — |

Es decir: **el balance relativo ya está bastante bien**. Lo único claramente fuera es el OPLL,
+2,6 dB por encima de donde openMSX lo pone respecto al MSX-Audio (coherente con la realidad:
el MSX-Audio suena más fuerte que el MSX-Music en hardware real).

---

## 4. Presupuesto del peor caso (punto 3 del encargo)

### 4.1 La tensión de fondo, con números

Hoy la unidad del mezclador es **8 CAR = fondo de escala**. Pero:

| Contenido | Pico (CAR) | Pico (LSB, pre-ganancia) | Origen |
|---|---:|---:|---|
| El VGZ medido (MSX-Audio FM + voz) | **0,86** | 3535 | **medido en placa** |
| El mismo tema, equivalente en openMSX | 1,14 | — | medido |
| PSG, 1 chip, 1 canal a 15 | 0,99 | 4064 | aritmética |
| PSG, 1 chip, 3 canales a 15 (tope del YM2149) | 1,99 | 8160 | aritmética |
| PSG ×2 en mono, ambos al tope | 3,99 | 16320 | aritmética |
| SCC, 5 canales al tope | 4,69 | 19200 | aritmética |
| OPL4 PCM, 24 slots al tope | 4,00 | 16383 | aritmética |
| OPLL / Y8950 FM / OPL4 FM, chip al tope | 8,00 | 32767 | aritmética |
| **Todos los chips a la vez al tope** | **50,3** | **205 804** | aritmética |

**No existe ninguna ganancia lineal que cumpla las dos cosas a la vez.** Para no recortar nunca
haría falta **−16 dB** (o sea, atenuar). Para que la música típica suene bien hacen falta
**+10 dB**. Cualquier core de MSX en FPGA (y openMSX mismo, que recorta duro a int16 por encima
de sus 6,24 CAR) resuelve esto igual: **se dimensiona para el contenido típico y se degrada con
elegancia en los extremos.** Por eso la propuesta lleva limitador, no sólo ganancia.

### 4.2 Presupuesto elegido

Con la ganancia **G** y una rodilla suave en 0,75 × fondo de escala (24576) con pendiente ½:

| G | dB | 1 CAR (LSB) | Entra en rodilla a… | Recorta duro a… | El VGZ medido queda en |
|---|---|---:|---:|---:|---|
| ×1 (hoy) | 0,0 | 4095 | 6,00 CAR | 10,00 CAR | −19,3 dBFS pico / −35,8 RMS |
| ×1,5 | +3,5 | 6142 | 4,00 CAR | 6,67 CAR | −15,8 / −32,3 |
| ×2 | +6,0 | 8190 | 3,00 CAR | 5,00 CAR | −13,3 / −29,8 |
| **×3 (propuesto)** | **+9,5** | **12285** | **2,00 CAR** | **3,33 CAR** | **−9,8 / −26,3** |
| ×4 | +12,0 | 16380 | 1,50 CAR | 2,50 CAR | −7,3 / −23,8 |
| ×5 | +14,0 | 20475 | 1,20 CAR | 2,00 CAR | −5,9 / −22,4 |
| ×6 | +15,6 | 24570 | 1,00 CAR | 1,67 CAR | −3,8 / −20,3 |
| ×8 | +18,1 | 32760 | 0,75 CAR | 1,25 CAR | −1,9 / −17,8 |

(Simulado muestra a muestra sobre `grab.wav` con `ganancia/gainsim.py`: **ni siquiera con ×8
recorta este tema una sola muestra** — 0,000 % de rodilla, 0,000 % de recorte duro. Esa es la
medida de cuánto margen estamos tirando.)

**Por qué ×3 y no ×4:**
- La rodilla queda en **2,00 CAR = 8192 LSB**, justo por encima del tope del PSG (1,99 CAR =
  8160 LSB × 3 = 24480 < 24576). Un juego de PSG a todo volumen **no toca la rodilla**: ni un
  ápice de distorsión añadida.
- Con ×4 la rodilla baja a 1,50 CAR y el PSG al tope entra en compresión permanente.
- Deja 3,33 CAR de recorrido antes del recorte duro ⇒ cubre música FM/SCC densa.
- Quedamos **+6,9 dB por encima de openMSX con sus ajustes por defecto** (que es la referencia
  de oído de Albert) y **+9,5 dB por encima de hoy**: 1,6 bits efectivos más
  (de ~10,1 a ~11,6 bits sobre el RMS).

**Riesgo declarado:** un SCC con los 5 canales a fondo (4,69 CAR) se pasa del recorte duro con
×3. No hay medida de cuánto pican los juegos Konami reales (Metal Gear 2 se quedó colgado en la
pantalla de carga de openMSX y se descartó el dato). **Por eso la ganancia va en un registro**:
si un juego SCC distorsiona, se baja a ×2 con un `OUT` y sin re-sintetizar.

---

## 5. Control de volumen ya existente (punto 4 del encargo)

**Sí lo hay, y es el del linaje OCM.** `fpga/src/ocm/swioports.vhd` implementa entero el
protocolo de volumen del OCM/MSX++:

| Elemento | Detalle |
|---|---|
| Puertos | `$45` ID212 = `[estado+MstrVol(6:4)] [estado+PsgVol(2:0)]`; `$46` ID212 = `[SccVol] [OpllVol]` (líneas 178-183) |
| Escritura | líneas 1036-1042 (`PsgVol <= not dbo(2:0)`, `MstrVol <= dbo(6:4)`, etc.) |
| Teclas | subir/bajar volumen maestro y por chip vía `FKeys` (líneas 370-380, 416-430, 444-463, 483-497) |
| Defectos | `OpllVol/SccVol/PsgVol = "100"` (4 = nominal), `MstrVol = "000"` (0 = **máximo**; es un índice de **atenuación**) |
| Perfiles | hay hasta preajustes por máquina (líneas 760-773, 850-915) |

**El problema:** en `fpga/top.v:4489-4501` la instancia `switched_io_ports ocm_ports (…)` **no
conecta** `MstrVol`, `PsgVol`, `SccVol` ni `OpllVol`. Son registros vivos, escribibles y legibles
desde el MSX (paneles de control OCM, SofaRun, herramientas de KdL)… que no hacen absolutamente
nada. Además `swio_req` está condicionado a `config_enable_megaram` (`top.v:4485-4486`).

**Recomendación:** ver §6, Opción B. Para la v2.1 propongo la Opción A (registro propio,
riesgo cero); enganchar el OCM es la evolución natural en la v2.2 porque regala compatibilidad
con software MSX que ya existe.

---

## 6. La estructura de ganancia propuesta

**Sí, hacen falta varias etapas.** Cuatro, y en este orden:

```
  fuentes ──►[0] bloqueador de CC de los PSG ──►[1] trims por fuente ──► Σ(19b)
                                                                          │
                                              [3] rodilla suave + sat16 ◄─┤[2] ganancia maestra
                                                                          │      (×1…×8, registro)
                                                                          ▼
                                                                   audio_sample[15:0]
```

| Etapa | Qué hace | Ganancia neta sobre música típica | Por qué es imprescindible |
|---|---|---|---|
| **0** | DC-blocker de 1 polo en cada PSG (bug #10) | 0 dB | Devuelve **hasta +16320 LSB de recorrido positivo** (la mitad del total; con los dos PSG en mono, **todo**). Sin esto, cualquier ganancia recorta asimétricamente. |
| **1** | OPLL × 0,75 (`(x>>>1)+(x>>>2)`) | −2,5 dB sólo al OPLL | Clava el balance OPLL↔Y8950 de openMSX (0,746 medido). |
| **2** | Ganancia maestra ×1…×8 sin multiplicador, registro `snd_gain_ff` | **+9,5 dB** (defecto ×3) | Es la etapa que resuelve el problema real. |
| **3** | Rodilla suave a 0,75·FS, pendiente ½, tope ±32767 | 0 dB por debajo de la rodilla | Convierte el recorte duro de hoy en compresión 2:1 en el 25 % superior. |

El PSG queda +1,5 dB por encima del balance de openMSX; está dentro de la incertidumbre de
comparar la amplitud de una cuadrada con el pico de un seno, así que **no se toca** (si se
quisiera, ×13/16 con `(x>>>1)+(x>>>2)+(x>>>4)`).

---

## 7. El parche concreto

Fichero único: **`fpga/top.v`**. Diez puntos de inserción. Los números de línea son los del
árbol actual (`_160`). Nada de esto se ha escrito en el repo.

### 7.1 Declaración del registro de ganancia — insertar en las líneas en blanco 2288-2290

*(fuera de los `ifdef` para que exista con `ENABLE_SOUND`/`ENABLE_CONFIG` en cualquier combinación)*

```verilog
    // ===== _161 ESTRUCTURA DE GANANCIA: registro de ganancia maestra =====
    // 0:x1  1:x1,5  2:x2  3:x3  4:x4  5:x5  6:x6  7:x8   (defecto x3 = +9,5 dB)
    // Se escribe por el puerto #44 del bloque config goauld y se persiste en el
    // byte[5] del bloque de config de la flash (hoy sin usar, se escribe 0xFF).
    reg [2:0] snd_gain_ff = 3'd3;
```

### 7.2 Bloqueador de continua de los PSG (bug #10) — insertar tras la línea 3550

```verilog
    // ===== _161 BUG #10 (INFORME_NIQUELADO): los PSG entraban SIN SIGNO =====
    // {1'b0, psgSound3, 6'b0} es 0..+16320: un PEDESTAL DE CONTINUA que se come
    // la mitad del recorrido positivo del sat16 — y en mono, con los DOS PSG,
    // los +32640 se lo comen ENTERO. El mezclador recortaba sistematicamente
    // solo el semiciclo positivo (la "distorsion sucia" al cargar la mezcla).
    // Bloqueador de continua de 1 polo, uno por PSG:
    //     dc  = acc >>> 16 ;  ac = x - dc ;  acc += ac
    // A la tasa del mezclador (clk_enable_3m6_27 = 3,579545 MHz) y con N=16 la
    // esquina esta en 3,579545e6/(2*pi*65536) = 8,7 Hz y tau = 18 ms: es el
    // condensador de acoplo que el hardware real tiene y nosotros no teniamos.
    // Rango del acumulador: 16320<<16 = 1,07e9 < 2^31-1 = 2,15e9  (cabe).
    // Aritmetica CERRADA (leccion _85/_115): todo con $signed explicito y
    // extension de signo escrita a mano; ningun literal unsigned en el camino.
    reg  signed [31:0] psg1_dcacc = 32'sd0;
    reg  signed [31:0] psg2_dcacc = 32'sd0;
    wire signed [16:0] psg1_x  = $signed({2'b00, psgSound3,  6'b000000});   // 0..16320
    wire signed [16:0] psg2_x  = $signed({2'b00, psg2Sound3, 6'b000000});
    wire signed [16:0] psg1_dc = psg1_dcacc[31:16];
    wire signed [16:0] psg2_dc = psg2_dcacc[31:16];
    wire signed [16:0] psg1_ac = psg1_x - psg1_dc;                          // +-16320
    wire signed [16:0] psg2_ac = psg2_x - psg2_dc;
    always @(posedge clk_27m) begin
        if (~bus_reset_n) begin
            psg1_dcacc <= 32'sd0;
            psg2_dcacc <= 32'sd0;
        end
        else if (clk_enable_3m6_27) begin
            psg1_dcacc <= psg1_dcacc + {{15{psg1_ac[16]}}, psg1_ac};
            psg2_dcacc <= psg2_dcacc + {{15{psg2_ac[16]}}, psg2_ac};
        end
    end
```

### 7.3 Trim del OPLL — insertar junto al bloque de `o4fm_*` (tras la línea 3590)

```verilog
    // _161 BALANCE: openMSX pone la portadora del OPLL en 3915 LSB y la del
    // Y8950 en 5249 (medido, ver INFORME) => el OPLL vale 0,746 de una
    // portadora de MSX-Audio. En el MSXimus las dos valen 4095 (mismo
    // jtopl_acc, INW=13): el OPLL entraba +2,6 dB de mas. x3/4 = -2,5 dB.
    // Mismo idioma que o4fm_base (probado desde la _115): wire signed propio.
    wire signed [15:0] opll_s    = $signed(jt2413_wav);
    wire        [15:0] opll_term = (opll_s >>> 1) + (opll_s >>> 2);
```

### 7.4 Ganancia maestra y limitador — SUSTITUIR `sat16` (líneas 3606-3609)

```verilog
    // ---- ANTES ----
    // function [15:0] sat16(input signed [18:0] v);
    //     sat16 = (v > 19'sd32767)  ? 16'h7FFF :
    //             (v < -19'sd32768) ? 16'h8000 : v[15:0];
    // endfunction

    // ---- DESPUES: _161 ganancia maestra + limitador de rodilla suave ----
    // (a) Ganancia sin multiplicador: sumas de desplazamientos. La entrada son
    //     los 19 bits de la suma (+-262143); x8 => +-2097152, que cabe en 23
    //     bits con signo (+-4194303).
    function signed [22:0] gmul(input signed [18:0] v);
        reg signed [22:0] x;
        begin
            x = {{4{v[18]}}, v};                   // extension de signo explicita
            case (snd_gain_ff)
                3'd0: gmul = x;                     // x1     0,0 dB
                3'd1: gmul = x + (x >>> 1);         // x1,5  +3,5 dB
                3'd2: gmul = x <<< 1;               // x2    +6,0 dB
                3'd3: gmul = (x <<< 1) + x;         // x3    +9,5 dB  <- defecto
                3'd4: gmul = x <<< 2;               // x4   +12,0 dB
                3'd5: gmul = (x <<< 2) + x;         // x5   +14,0 dB
                3'd6: gmul = (x <<< 2) + (x <<< 1); // x6   +15,6 dB
                3'd7: gmul = x <<< 3;               // x8   +18,1 dB
            endcase
        end
    endfunction

    // (b) Limitador: por debajo de 0,75 x fondo de escala, unidad; por encima,
    //     pendiente 1/2 hasta el tope. El recorte duro de hoy se convierte en
    //     compresion 2:1 del 25% superior — inaudible en los picos ocasionales
    //     frente al chasquido del clip. Simetrico (+-32767).
    localparam signed [22:0] SND_KNEE = 23'sd24576;
    function [15:0] sat16k(input signed [22:0] v);
        reg               neg;
        reg signed [22:0] a, y;
        begin
            neg = v[22];
            a   = neg ? -v : v;
            y   = (a <= SND_KNEE) ? a : (SND_KNEE + ((a - SND_KNEE) >>> 1));
            if (y > 23'sd32767) y = 23'sd32767;
            sat16k = neg ? (~y[15:0] + 16'd1) : y[15:0];
        end
    endfunction
```

### 7.5 Términos del mezclador — SUSTITUIR las líneas 3610-3623

Sólo cambian los términos del PSG (ahora `psg1_ac`/`psg2_ac`, con signo) y el del OPLL
(`opll_term`). El resto es idéntico.

```verilog
    wire signed [18:0] mixL_st = {{2{psg1_ac[16]}}, psg1_ac}
        + {{3{scc_term[15]}}, scc_term} + {{3{opll_term[15]}}, opll_term}
        + {{3{y8950_wav[15]}}, y8950_wav} + {{3{y8950_adpcm_term[15]}}, y8950_adpcm_term}
        + {{3{opl4fm_term[15]}}, opl4fm_term} + {{3{opl4pcm_term_l[15]}}, opl4pcm_term_l};
    wire signed [18:0] mixR_st = {{2{psg2_ac[16]}}, psg2_ac}
        + {{3{scc2x_wav[14]}}, scc2x_wav, 1'b0} + {{3{opll_term[15]}}, opll_term}
        + {{3{y8950_wav[15]}}, y8950_wav} + {{3{y8950_adpcm_term[15]}}, y8950_adpcm_term}
        + {{3{opl4fm_term[15]}}, opl4fm_term} + {{3{opl4pcm_term_r[15]}}, opl4pcm_term_r};
    wire signed [18:0] mix_mono = {{2{psg1_ac[16]}}, psg1_ac}
        + {{2{psg2_ac[16]}}, psg2_ac}
        + {{3{scc_term[15]}}, scc_term} + {{3{scc2x_wav[14]}}, scc2x_wav, 1'b0}
        + {{3{opll_term[15]}}, opll_term} + {{3{y8950_wav[15]}}, y8950_wav}
        + {{3{y8950_adpcm_term[15]}}, y8950_adpcm_term}
        + {{3{opl4fm_term[15]}}, opl4fm_term} + {{3{opl4pcm_term[15]}}, opl4pcm_term};
```

> Comprobación de anchura: peor caso tras el parche
> 8160+8160+19200+19200+24575+32767+4080+32767+16383 = **173 292** < 262 143 ⇒ los 19 bits
> siguen sin desbordar, con 3,6 dB de margen (antes eran 205 804, con 2,1 dB).

### 7.6 Registro de salida — SUSTITUIR las líneas 3653-3660

```verilog
            if (config_enable_stereo == 1) begin
                audio_sample   <= sat16k(gmul(mixL_st));
                audio_sample_r <= sat16k(gmul(mixR_st));
            end
            else begin
                audio_sample   <= sat16k(gmul(mix_mono));
                audio_sample_r <= sat16k(gmul(mix_mono));
            end
```

> **Nota de temporización**: el cono combinacional pasa a ser sumador de 23 bits + mux + valor
> absoluto + rodilla, todo dentro de un ciclo de `clk_27m` (37 ns). Debería cerrar de sobra en el
> GW5AT. Si el `nextpnr`/`gw_sh` se queja, la variante segura es registrar la ganancia y
> saturar al ciclo siguiente (`clk_enable_3m6_27` sólo se activa 1 de cada 7,5 ciclos, así que
> hay hueco de sobra y el retardo extra de 37 ns es irrelevante).

### 7.7 Puerto #44 (escritura) — insertar tras la línea 3855

```verilog
    assign config4_req = (config_ok == 1 && bus_addr[7:0] == 8'h44 && bus_iorq_n == 0 && bus_m1_n == 1 && bus_wr_n == 0)? 1:0;
```
(y su `wire config4_req;` junto a `config3_req` en la línea 3761)

### 7.8 Latch del registro — dentro del `always` de la línea 3812-3841

```verilog
        if (config_init == 1) begin
            if (s2_press) begin
                ...
                snd_gain_ff <= 3'd3;                        // rescate S2: ganancia por defecto
            end
            else begin
                ...
                // byte[5] de la flash: 0xC0..0xC7 = ganancia valida; 0xFF/0x00
                // (bloques legados) => defecto x3. Mismo patron que 'T'=0x54 del turbo.
                snd_gain_ff <= (config_sig[5][7:3] == 5'b11000) ? config_sig[5][2:0] : 3'd3;
            end
        end
        if (config4_req == 1) begin
            snd_gain_ff <= cpu_dout[2:0];
        end
```

### 7.9 Lectura del registro — línea 3887

```verilog
                         ( bus_addr[3:0] == 4'h4 ) ? {5'b0, snd_gain_ff} :
```

### 7.10 Persistencia en flash — línea 3997

```verilog
    // ANTES:  (flash_write_counter == 8'd04) ? (config_turbo_boot_ff ? 8'h54 : 8'h00) : 8'hff;
    // DESPUES:
                             (flash_write_counter == 8'd04) ? (config_turbo_boot_ff ? 8'h54 : 8'h00) :
                             (flash_write_counter == 8'd05) ? {5'b11000, snd_gain_ff} : 8'hff;
```
`flash_write_terminate` ya está en `8'd6`, así que el byte 5 **ya se escribe hoy** (con 0xFF):
no hay que tocar el tamaño del bloque ni el lector (`config_sig[5]` ya se carga en la
línea 4174 y hoy **no se usa para nada** — es el hueco perfecto).

### 7.11 Cómo lo maneja el usuario (sin tocar el menú)

```basic
OUT &H40,&H48 : REM abrir el bloque de config goauld (config_ok)
OUT &H44,4    : REM ganancia x4  (0..7)
OUT &H42,INP(&H42) OR 64 : REM guardar en flash (bit6 = orden de guardar)
```
El menú puede añadir la opción "Volumen" más adelante; no es bloqueante.

### 7.12 Opción B (v2.2) — enganchar el volumen OCM que ya existe

En `top.v:4489` añadir al mapa de puertos:

```verilog
            .MstrVol       (ocm_mstr_vol),   // 0 = maximo, 7 = minimo (atenuacion)
            .PsgVol        (ocm_psg_vol),    // 0..7, defecto 4 = nominal
            .SccVol        (ocm_scc_vol),
            .OpllVol       (ocm_opll_vol),
```
y usar `3'd3 - ocm_mstr_vol[1:0]`-estilo como índice de `snd_gain_ff`, y `Vol/4` como trim por
chip. **Riesgo:** son puertos `inout` de VHDL conectados a nets de Verilog en flujo mixto de
Gowin; hay que probarlo en una build de diagnóstico antes de fiarse. Por eso va después.

---

## 8. Hallazgo colateral (fuera del encargo, pero es EL que explica los "chasquidos")

`msx2hdmi_v9968.sv:597-601` toma el valor instantáneo de `audio_sample` cada 44100 Hz. Pero
`audio_sample` es una **escalera** que sólo cambia al ritmo nativo de cada core:

| Core | Tasa nativa | Fuente |
|---|---|---|
| jtopl2 (Y8950 FM) | 3579545/72 = **49 716 Hz** | `jtopl_single_acc` (`zero` cada 72 cen) |
| jt2413 (OPLL) | **49 716 Hz** | mismo acumulador |
| opl3 (OPL4 FM) | 27e6/545 = **49 541 Hz** | `opl3_pkg.sv:34` |
| YMF278B (OPL4 PCM) | 44 100 Hz exactos | ya está bien |
| PSG / SCC / ADPCM | filtrados / interpolados | ya están bien |

Eso es un remuestreo **49,7 kHz → 44,1 kHz por vecino más próximo y sin filtro**. Las imágenes
del retenedor de orden cero caen en 49 716 ± f y se pliegan dentro de banda:
un tono FM de 1 kHz aparece **duplicado a 4,6 kHz y 6,6 kHz** con una atenuación de sólo
sinc(48716/49716) = **−24 dB**. Eso es perfectamente audible y suena exactamente a "sucio",
"chasquidos" y "granulado" — y afecta **sólo a los tres cores FM**, que es donde Albert lo oye.
openMSX no lo tiene porque usa un resampler de verdad (por eso su pico es +2 dB mayor de lo que
predice la aritmética: sobreoscilación del resampler).

**Aviso importante:** subir la ganancia +9,5 dB **sube también este alias +9,5 dB**. Conviene
atacarlo en la misma tanda. Arreglo mínimo: un IIR de 2-4 polos a ~12 kHz corriendo a 3,58 MHz
sobre `mix_*` **antes** del `gmul` (2 polos ⇒ −24 dB extra a 48,7 kHz; 4 polos ⇒ −48 dB); el
material MSX no tiene contenido útil por encima de 12 kHz. Arreglo bueno: interpolación lineal
entre las dos últimas muestras del chip en los instantes de 44,1 kHz.

---

## 9. Cómo validarlo

### 9.1 Ya validado aquí

Banco de pruebas **`ganancia/tb_gain.v`**, ejecutado con iverilog (Ubuntu-24.04 en WSL, porque
no hay iverilog en Windows):

```
=== 1) gmul: factores exactos y signo ===
    extremos: gmul(+262143)=786429  gmul(-262144)=-786432 (x3)
    extremos: gmul(+262143)=2097144 gmul(-262144)=-2097152 (x8)
=== 2) sat16k: unidad bajo rodilla, 1/2 encima, tope +-32767 ===
    monotonia y simetria comprobadas en el barrido
=== 3) bloqueador de continua de los PSG ===
    silencio: psg1_x=0 dc=0 ac=0
    continua 16320: dc=16174  ac_residual=146      (80 ms = 4,4 tau -> e^-4,4 = 1,2 % ✔)

RESULTADO: TODO OK (0 fallos)
```

Comprueba en particular las dos trampas históricas del proyecto: que `gmul` no degenere en
desplazamiento **lógico** con valores negativos (`gmul(-1000)` da −1500 con ×1,5, no un positivo
enorme) y que la extensión de signo del acumulador de continua sea correcta.

```bash
wsl -d Ubuntu-24.04 bash -lc "cd '…/scratchpad/ganancia' && iverilog -g2005-sv -o tb_gain.vvp tb_gain.v && vvp tb_gain.vvp"
```

### 9.2 En simulación, al integrar

1. Repetir `tb_gain.v` con el `top.v` parcheado de verdad (extraer el bloque del mezclador a un
   TB, como se hizo con `tb_defer_rst` para el bug #14).
2. Barrido de los 9 términos a sus máximos: comprobar que la suma de 19 bits **nunca** desborda
   (cota calculada: 173 292 < 262 143).

### 9.3 En placa — criterios numéricos, no impresiones

| Prueba | Qué hacer | Qué tiene que salir |
|---|---|---|
| **A. Nivel** | Reproducir *el mismo* `03 Psycho Soldier Theme.vgz` y grabar igual que `grab.wav` | Pico **−9,8 dBFS ±1** y RMS **−26,3 dBFS ±1** con ganancia ×3 (hoy: −19,3 / −35,8) |
| **B. Bug #10** | Un juego de PSG puro (o `SOUND 8,15` con los 3 canales) | Componente de continua de la grabación **< −60 dBFS**; hoy sube a +8160 LSB (−12 dBFS) mientras suena |
| **C. Simetría** | Misma grabación de B | Histograma de la onda **centrado**; hoy está desplazado y el recorte es sólo por arriba |
| **D. Balance OPLL** | Un VGM de MSX-Music y otro de MSX-Audio, mismo nivel de composición | El OPLL debe bajar 2,5 dB respecto a hoy |
| **E. Rodilla** | Juego SCC de los densos (Konami) con ganancia ×3, luego ×2 | Si con ×3 hay aspereza y con ×2 no, el defecto pasa a ×2 (un `OUT`, sin re-sintetizar) |
| **F. Instrumento ya integrado** | El **vúmetro `_133`** (`top.v:4544-4550`, pico de `\|audio_sample\|` por ventana de 0,31 s, sale por la telemetría UART de COM11) | Sirve para leer el pico real en placa sin grabar nada: con ×3 el pico del VGZ debe pasar de ~3535 a ~10600 |

### 9.4 Reproducir la referencia de openMSX

```bash
"C:/Program Files/openMSX/openmsx.exe" -machine Panasonic_FS-A1GT -ext audio \
   -script ".../scratchpad/ganancia/ref.tcl"
python .../scratchpad/ganancia/meas2.py grab.wav MSXimus om_ref.wav openMSX
```
(los volúmenes de openMSX quedaron restaurados a los defectos: `master_volume 80`,
dispositivos a 75 — comprobarlo en el log si se repite la medida)

---

## 10. Orden de trabajo sugerido

1. **Etapa 0 sola** (DC-blocker de los PSG), build de diagnóstico, prueba B/C. Es un arreglo de
   bug puro, sin cambio de nivel: si algo suena raro, es esto y sólo esto.
2. **Etapas 1+2+3** (trim OPLL + ganancia ×3 + rodilla) con el registro del puerto #44.
3. Prueba A/D/E en placa. Ajustar el defecto de la ganancia si hace falta y persistirlo.
4. **Después**: el antialias del §8 (es el que de verdad limpia el sonido) y, ya con tiempo, la
   Opción B (volumen OCM) y una entrada "Volumen" en el menú.

---

## Anexo — ficheros de evidencia

| Fichero (`…\scratchpad\ganancia\`) | Qué es |
|---|---|
| `om_ref.wav` | openMSX A1GT + `audio`, el VGZ completo, ajustes por defecto |
| `cal1.wav` / `cal1_max.wav` | 1 portadora Y8950 TL=0 a 80/75 y a 100/100 |
| `opll1.wav` | 1 portadora OPLL vol=0 |
| `psg1.wav` | 1 canal de PSG a vol 15 |
| `om_end.png`, `om_s34.png` | pantallazos de VGMPlay confirmando la reproducción |
| `ref.tcl`, `cal.tcl`, `cal2.tcl`, `cal3.tcl` | scripts TCL de openMSX |
| `meas.py`, `meas2.py` | medidores (pico/RMS/percentiles/CC/bits efectivos) |
| `gainsim.py` | simulación muestra a muestra de la ganancia + rodilla sobre `grab.wav` |
| `tb_gain.v`, `tb_gain.vvp` | banco de pruebas del parche (iverilog) — 0 fallos |
| `dsk/`, `ref.dsk` | disco DOS2 + VGMPlay + VGZ usado en openMSX |
