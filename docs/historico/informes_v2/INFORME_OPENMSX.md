# openMSX frente al MSXimus — síntesis del reconocimiento

**Fecha:** 2026-07-29 · **openMSX auditado:** HEAD `e954c5ce` (2026-07-26) · **MSXimus:** árbol `MSX_up` (build _162)

Cinco frentes en paralelo (VDP/sprites, audio, mappers+softwaredb, dispositivos/extensiones, aportaciones).
Informes de detalle en el mismo directorio: `vdp-timing-sprites.md`, `audio.md`, `mappers_softwaredb.md`,
`opus5-devices-extensiones.md`, `aportar_a_openmsx.md`.

**Titular:** el valor de openMSX no está en las funciones que le faltan al MSXimus, está en los **30 bugs
nuestros** que su código delata. Cinco de ellos están **medidos** (ejecutados en openMSX real o en un
simulador diferencial), y de los diez más graves **siete cuestan cero o menos LUTs** — uno incluso libera
gate. Con el CLS al 91% esto es exactamente el tipo de trabajo que se puede hacer hoy.

Nada de este reconocimiento ha tocado los repos del usuario, ni ha ejecutado síntesis de Gowin.

---

## 1. 🐛 BUGS NUESTROS que openMSX delata

Confianza: **PROBADO** = medido ejecutando openMSX real, simulador diferencial o aritmética cerrada sobre
nuestras propias tablas. **DEDUCIDO** = comparación de código contra el fuente de openMSX, sin ejecutar.

### 1.a Primera división — probados y/o de coste cero

| # | Síntoma esperable | Qué hace openMSX | Qué hacemos nosotros | Confianza | Coste |
|---|---|---|---|---|---|
| 1 | **El gamepad USB nº2 no funciona nunca.** Ningún juego de 2 jugadores | `MSXPSG.cc:117` — **solo el bit 6** de R#15 selecciona puerto; el bit 7 es el LED KANA (`:119-121`) | `top.v:769-812` exige `{b7,b6}` y cae a `8'hFF` con `{1,1}`, que es justo lo que deja la BIOS | **PROBADO** — medido en Philips NMS 8250: `STICK(2)`→R#15=0xCF, `STICK(1)`→0x8F | **1 línea, CLS negativo** (quita un comparador) |
| 2 | Todo el PSG suena aplastado y sin dinámica en pasajes densos; techo plano | `AY8910.cc:691-760` + MSXMixer suman en float sin límite, `volumeTab` máx 1.0/canal | `PSG_YM2149/YM2149.vhdl:601-615` suma 3 canales (máx 765) y saca `audio_final(8..1)` con **clip duro a 0xFF** por encima de 511 | **PROBADO** — aritmética cerrada con la `dac_amp` del propio core: 3×vol15 = 765 → sale 255 (−3,6 dB) | ~32 FF + 2 bits en el árbol del mezclador. **Ganancia-neutro**: idéntico bit a bit donde hoy no recorta |
| 3 | **Aleste 2 y compañía mal detectados**: mapper equivocado → cuelgue o basura | `RomFactory.cc:185-202`: SHA1 en la DB **primero**, heurística solo si no hay entrada. Empate → gana KONAMI_SCC (orden del enum) | `menu_main.asm:1561-1566` invierte la prioridad ("el contenido decidió → respetarlo SIEMPRE"); `:1496-1507` itera SCC/KON/A8/A16 → en empate gana ASCII16 | **PROBADO** — simulador diferencial `scratchpad/heur.py` + 2 ROMs sintéticas: empate KON=SCC → openMSX KonamiSCC, nosotros Konami4 = **firma exacta del fallo Aleste 2** | **0 bytes** (reordenar 4 bloques) + ~14 bytes Z80 |
| 4 | El mismo, agravado: ROMs grandes puntúan de menos | `RomFactory.cc:129` escanea el fichero entero | `menu_main.asm:1434-1436` corta el escaneo a 256 KB | **PROBADO** — medido sobre `mg2.rom` (512 KB): el tope cuesta **exactamente 1 punto** en cada categoría, justo el margen que perdió Aleste 2 | ~0 bytes |
| 5 | **7/8 de la ventana de banco de Konami4 no responde**: juegos Konami sin SCC con gráficos rotos | `RomKonami.cc:60-66` decodifica los **8 KB** enteros (`0x6000-0xBFFF`) | `megaram.v:146-159` compara `bus_addr[15:11]` = solo los primeros 2 KB de cada ventana | **DEDUCIDO** (asimetría deliberada en openMSX: Konami-SCC **sí** es 2 KB y ahí coincidimos, `RomKonamiSCC.cc:117`) | `[15:11]`→`[15:13]`: **CLS negativo**, ~2-4 LUT menos |
| 6 | **El puerto 0xAB del PPI no existe** → motor de casete muerto, CASW muerto, click de teclado muerto | `I8255.cc:315-341` bit set/reset del puerto C; `MSXPPI.cc:118-133` cuelga de ahí PC4/PC5/PC6/PC7. La BIOS usa **exclusivamente** 0xAB para los cuatro | `grep 8'hAB fpga/top.v` = **cero coincidencias**. Solo 0xA8/0xA9/0xAA | **PROBADO** — `OUT &HAB,&H0D` / `&H0C` + `INP(&HAA)` da 0x5A / 0x1A (difieren en el bit 6). Precedente interno: `MSXnano-cinta:top.v:575-582` ya se topó con esto | ~15 líneas, ~0 CLS |
| 7 | **El LED CAPS del WS2812 no puede encenderse jamás** | `I8255.cc:190-208`: con el puerto C como salida, leer 0xAA devuelve **el latch** | `top.v:816` solo decodifica **escritura** de 0xAA; la lectura cae al `8'hFF` del mux (`:910`). SNSMAT hace `in a,(0AAh) / and 0F0h / or c / out (0AAh),a` → escribe `0xF0|fila` cada frame → `ppi_port_c[7:4]` clavado a 1111, y `top.v:4850` es `~ppi_port_c[6]` | **PROBADO** (mismo experimento que #6: el nibble alto se conserva entre barridos, imposible sin leer 0xAA) | ~5 líneas, ~0 CLS. **Mismo parche que #6** |
| 8 | **Columna rota justo en el punto de corte del SP2** (R#23/R#26), más visible en SCREEN 7/8 | El V9938 **no predice**: 32 bloques de 20 ciclos con direcciones calculadas de cero | `v9968_vram_shim.v:1012-1096`: prefetcher lineal con ventana `pwq` (tag `spr_addr1[15:6]`) + cadena `obl`. El SP2 salta ±32 KB (SC5/6) o ±64 KB (SC7/8) a mitad de scanline → **fallo de ventana seguro** ≈ 1 miss/línea, y cada miss = "una palabra negra un frame" (comentario del propio shim, `:382`) | **DEDUCIDO** — pero **explica literalmente el síntoma abierto** del README, incluida la asimetría SC7/8 (dos streams entrelazados, se rompen los dos) | Primero **banco de simulación** (~40 líneas sobre `tb_geomfast.sv`, sin síntesis). Cura real: 2ª ventana `pwq/obl`, ~1 BSRAM |
| 9 | Glitch del **logo MSX2+**; página equivocada en G4-G7 cuando el blink de R#13 está activo con EO=0 | `VDP.hh:467-472` (`getEvenOddMask`): `P = (!EO \|\| campo) && !blinkState` — máscaras **independientes** | `vdp_timing_control_ssg.v:473` fuerza `1'b1` cuando `EO=0` en vez de `ff_interleaving_page`; combinamos blink-page, EO-page y SP2 con un **AND** sobre el mismo bit de dirección | **DEDUCIDO** — sospechoso nº1 del glitch abierto | **1 línea, 0 LUT.** NO-OP garantizado con R#13=0 (`:415-418` fuerza el flag a 1 si `reg_blink_period==0`) |

### 1.b Segunda división — deducidos, baratos, con regresión conocida

| # | Síntoma esperable | Qué hace openMSX | Qué hacemos nosotros | Confianza | Coste |
|---|---|---|---|---|---|
| 10 | Muestra ADPCM que ocupa los **256 KB completos**: bucle infinito sin EOS (software colgado) o principio de la muestra sobrescrito en silencio | `Y8950Adpcm.cc:491-511`/`:269-294` usa unsigned de 32 bits y **nunca** enmascara `stopAddr` | `y8950_adpcm.v:356` y `:428`: `ptr + 19'd1 > stop_addr` con ambos operandos [18:0] → **se trunca**; con `stop_addr=0x7FFFF` la comparación nunca se cumple | **DEDUCIDO** (aritmética evidente). **Agujero abierto por la _159**: con 32 KB era inalcanzable | **2 líneas** (comparar en 20 bits) |
| 11 | Colisión de sprites **falsa** con sprites de color 0 y TP=0 | `VDP.hh:199-208` (`canSpriteColor0Collide`, medido sobre V9958 real, issue #1198) aplica el filtro a **los dos** sprites del par | `vdp_sprite_makeup_pixel.v:981-993`: el "ya pintado" sí filtra color 0 (`:883`), el plano actual **no** | DEDUCIDO | **~0 LUT** — el término ya está sintetizado dos líneas más arriba |
| 12 | Colisión **falsa** con un sprite IC=1 de prioridad alta solapando a uno normal | `SpriteChecker.cc:436-446`: `if (colorAttrib & 0x60) continue` aplicado a **i y a j** | `vdp_sprite_makeup_pixel.v:981` filtra IC/CC solo del plano actual; el "ya pintado" filtra CC pero **no IC** | DEDUCIDO | 2 FF + 2 LUT |
| 13 | **Dragon Quest 2 (MSX2)** y todo software que no lee S#0: 5S deja de actualizarse | `SpriteChecker.cc:158-172` y `:389-403` exigen `(status & 0xC0)==0`, o sea **F=0 Y 5S=0**. Comentario literal: *"Dragon Quest 2 needs this"* | `vdp_sprite_select_visible_planes.v:346-371` solo mira `!ff_sprite_overmap` | DEDUCIDO (con regresión de prueba nombrada) | 1 puerto a través de `vdp.v` + 1 LUT |
| 14 | Comandos VDP con velocidades mal repartidas; el test de NYRIKKI daría un **cuadrado donde el hardware da un octógono** | Tabla medida sobre V9938 real (`doc/internal/vdp-vram-timing/vdp-timing.html`) + remedida por bengalack (#2057) | `vdp_command.v:108-119`: los **doce** `c_wait_*` valen 40. Reales: HMMV 41 vs 48, **YMMM 82 vs 60** (único donde vamos MÁS LENTOS, y es el de los scrolls verticales), HMMM 82 vs 88, LMMV 82 vs 96, LMMM 123 vs 120, LINE 82 vs 112. Además no cobramos coste por línea ni el paso del eje menor | DEDUCIDO (contra medidas de terceros sobre silicio) | **0 LUT** — 6 constantes. El coste por línea son ~10-20 LUT aparte |
| 15 | Software que hace leer-conmutar-restaurar el memory mapper recupera 255 | `MSXMemoryMapperBase.cc:60-63` devuelve `registers[port&3] \| ~(bit_ceil(numSegments)-1)`; 40 máquinas del catálogo declaran los 8 bits legibles | `top.v:2050` solo decodifica **escritura** de 0xFC-0xFF | **PROBADO** — NMS8250: `OUT &HFC,7` → `INP` = 0xFF = `7\|0xF8`; `OUT &HFD,6` → 0xFE. Coincide término a término | ~8 líneas / ~10 LUT |
| 16 | **287 títulos** de la DB arrancan a basura (3D Golf Simulation, 3D Tennis, 3D Night City Designer…) | `RomFactory.cc:99-114`: ROM ≤ 0x4000 con cabecera AB y `(textAddr & 0xC000)==0x8000` → tipo **PAGE2**, carga en 0x8000 | `menu_main.asm:1526-1542` devuelve MAP_PLAIN y `load_rom` carga desde el segmento 0 → la ROM aparece en 0x4000 y el boot_stub salta a basura | DEDUCIDO | ~45 bytes Z80 + `LOAD_SEG=2` |
| 17 | **A-Train ve su SRAM plegada 4 veces** — y el README y el menú lo anuncian como soportado | `RomAscii16_2.cc:27-28`: 0x0800 para ASCII16SRAM2, **0x2000 (8 KB)** para ASCII16SRAM8 | `megaram.v:104` fija siempre 2 KB espejados | DEDUCIDO | 1 mux de 21 bits, ~10 LUT |
| 18 | **La SRAM no persiste nada**, y el menú muestra "SRAM: On" | `SRAM.cc:56-125`: carga de fichero al insertar, guardado diferido 5 s, volcado forzado en el destructor | Vive en los segmentos 252-255 de la megaram (DRAM volátil) y `launch_rom` la **borra a 0xFF** en cada lanzamiento (`menu_main.asm:1906-1934`) | DEDUCIDO (funcionalidad simplemente ausente) | Carga desde `.SRM` en la SD: ~80 bytes Z80. Guardado: proyecto de firmware C6 |
| 19 | El mezclador FM del OPL4 (reg F8) ignora el canal **derecho** | `YMF278.cc:491-504`: bits 2:0 = izquierda, bits 5:3 = derecha | `top.v:3619-3623` calcula un único `opl4fm_term` con `opl4_mixfm[2:0]` y lo suma a los dos canales. `opl4_pcm.v:52` **ya exporta** `mix_fm[5:0]` — los bits están cableados y sin usar | DEDUCIDO | ~40 LUT |
| 20 | Le decimos al software que el teclado es **japonés (JIS)** | `MSXPSG.cc:16-31`: `keyLayout` = 0x00 internacional (por defecto), 0x40 JIS; OR-eado en `readA()` | `top.v:808-812` fuerza `{2'b11, ...}` | **PROBADO** — NMS8250: `INP(&HA2)` con R#14 = 0xBF, bit 6 = **0** | 1 bit, colgar de los puertos de config del pack (0x40-0x45) |
| 21 | SCC: reproductores de PCM por SCC con timbre y altura equivocados; clics al reescribir la wave RAM | `SCC.cc:392`: `incr = (per <= 8) ? 0 : 32`, **no** toca `pos`, y `count[ch]=0` en **toda** escritura de frecuencia | `scc_wave2v.v:138-181` congela con `reg_freq[11:3]==0` (desplazado uno), **fuerza `ff_ptr<=0`**, y `:88-97/141` solo recarga `ff_cnt` si el canal está congelado | DEDUCIDO (documentado por NYYRIKKI en la cabecera de `SCC.cc:73-88`) | Paquete SCC ~2 h, ~100 LUT junto con los bits 0/1 del registro de deformación |
| 22 | Divergencias finas de SRAM ASCII8 respecto a openMSX (offsets, ventanas visibles, bit de habilitación) | `RomAscii8_8.cc:29-30,83`: máscara de página según tamaño real, SRAM solo en 0x8000-0xBFFF (+0x4000 solo para KOEI), valor exacto `size/0x2000` | `megaram.v:213-251` usa siempre 2 bits; `:94-98` la expone en las 4 ventanas (nos comportamos como KOEI para todos); `menu_main.asm:1897-1905` usa potencia de 2 | DEDUCIDO | ~8 bytes Z80 + unos pocos LUT |
| 23 | Escaneo de mapper: se pierden **2 de cada 512** posiciones de arranque de instrucción | `RomFactory.cc:129` solo pierde los 3 últimos bytes del fichero | `menu_main.asm:1386-1387` examina `bc=510` por sector: un `32 lo hi` en el offset 510/511 o a caballo entre sectores nunca se cuenta | DEDUCIDO | ~15 bytes Z80 |
| 24 | ROM que conmuta con `LD (HL),A`: el escaneo no ve nada y cargamos **32 K lineales** = basura garantizada | `RomFactory.cc:164` arranca en **GENERIC_8KB** (responde en todo 0x4000-0xBFFF) | `menu_main.asm:1494,1540` devuelve MAP_PLAIN | DEDUCIDO (nuestro propio comentario de `:1768` ya identifica el caso) | Depende de si se implementa Generic8kB |
| 25 | Latente: ROM ASCII8/16 de 2 MB exactos con SRAM pierde su cola | — | `load_rom` carga desde el seg 0 y `launch_rom` borra 252-255 | DEDUCIDO, no disparable hoy | ~12 bytes de guardia |

### 1.c Punto que hay que resolver ANTES de tocar nada (contradicción entre frentes)

**ADPCM-B: `>>>1` o `>>>3` en `top.v:3476`.** El frente *aportar* afirma que hoy hay `>>>1` y que el balance
canónico es `>>>3` (verificado contra `Y8950::getAmplificationFactorImpl()` = `1/(1<<11)`), o sea
**+12,0 dB de más**. El frente *audio* reconstruyó la cadena completa y concluye que el ADPCM entra a 4080
frente a los 4079 esperados: **exacto, no tocar** — es decir, evaluó `>>>3`. Ambos coinciden en que `>>>3` es
lo correcto; discrepan sobre qué hay hoy en el árbol. **Mirar `top.v:3476` antes de editar nada de audio.**
Si es `>>>1`, el arreglo ya está redactado en `INFORME_ADPCM_256K.md §6`.

### 1.d Erratas nuestras que este reconocimiento cierra

- **`INFORME_GANANCIA_AUDIO.md §4.2` es falso**: "Metal Gear 2 se quedó colgado en la pantalla de carga de
  openMSX". Probado hoy en FS-A1GT con la ROM de 512 K: PC 0x4803→0x4371, SCREEN 5, IFF=07. **Arranca y
  corre**; fue fallo nuestro de montaje. Corolario importante: **sí se puede medir el riesgo del SCC con
  ganancia ×3 en openMSX**.
- **Retirar la hipótesis** de `INFORME_ADPCM_256K.md §2.2` ("la RAM de muestras arrancaría a 0xFF como el
  HW real"). openMSX devuelve 0 fuera de rango con el comentario literal *"checked on a real machine"*.
  Nuestro RTL ya está alineado (`y8950_adpcm.v:126-132`).
- **Regla operativa nueva, gratis:** nuestra ROM de instrumentos del OPLL (`jtopll_reg.v:109-130`) es el
  volcado **real de Nuke.YKT 2019**, más exacta que el core Okazaki que openMSX usa por defecto (violín reg0
  = 0x71 nuestro vs 0x61 suyo). **No "corregir" nuestra tabla contra openMSX**, y antes de cualquier A/B del
  OPLL ejecutar `set ym2413_core NukeYKT` en su consola.
- **Documentar, no arreglar:** `y8950_adpcm.v:427/462` hace el "reset+set en tiempo 0" de BUF_RDY/EOS
  copiado de openMSX; en el chip real BUF_RDY sube ~25 µs antes que EOS (issue #1160). Tres líneas de
  comentario evitan que se redescubra como bug misterioso.

---

## 2. Lo que nos falta y merece la pena

### 2.a RTL — caro, el CLS está al 91%

Ordenado por valor/coste. Los tres primeros caben; los demás son para cuando haya sitio.

| Prioridad | Qué | Coste estimado | Por qué |
|---|---|---|---|
| **1** | **Ratón MSX**. `usb_hid_host` **ya nos entrega** botones y deltas y los estamos tirando: `top.v:4912` y `:4924` tienen `.mouse_btn()`, `.mouse_dx()`, `.mouse_dy()` **desconectados en las dos instancias**. Protocolo completo en `Mouse.cc`: 8 fases sobre el pin 8 (STROBE=0x04), nibbles alto/bajo de xRel/yRel, timeout de 1,5 ms, `clamp(±127)` al entrar en XHIGH1 y `xRel=yRel=0` al entrar en XHIGH2 | ~150 LUT (~0,5% CLS) + 2 FF para los bits 4/5 de R#15 | Desbloquea Graph Saurus, MSX-Paint, Dynamic Publisher, Eddy II, Illustrator. **El hardware ya está** |
| **2** | **Cinta/casete TSX**. openMSX engancha el casete al bus con **solo 3 bits**: PSG R#14 b7 (CASR), PPI PC4 (motor), PPI PC5 (CASW). Nuestro frente está al **80%**: `cas_stream.v` + `tape_uart.v` **validados en Icarus** (70 KB byte-exacto, rama `cinta-virtual` del MSXnano), conversor TSX→CVS1 5/5, catálogo tsx.eslamejor.com 50/50, comandos UNAPI escritos y auditados, tecla T del menú escrita | Portar 2 ficheros RTL (<300 LUT) + 2 pines del J10 | **Bloqueado por los bugs #6 y #7**: sin 0xAB no hay motor, y sin leer 0xAA la BIOS pisa PC4/PC5 cada frame. Arreglar el PPI **desbloquea el frente entero** |
| **3** | Módulo único `msx_joyport_dev.v` con **todos** los dispositivos de puerto (Trackball GB-7, Paddle, Arkanoid pad, JoyMega de 6 botones, NinjaTap, dongles). Todos multiplexan sobre el mismo pin 8 y comparten registro de estado, temporizador de 1,5 ms y mux de salida | ~250 LUT **extra sobre el ratón** (el combo sale por ~350-450 LUT en vez de la suma) | La selección de dispositivo por puerto se escribe desde el **menú** (puertos 0x40-0x45): coste RTL cero |
| 4 | Coste por línea de los comandos VDP (mux de 6 bits en cada `c_state_*_make`; `w_nx_end` ya está en el mismo `if`) | ~10-20 LUT | Bloques altos y estrechos son hoy hasta **3,7× más rápidos** que el hardware |
| 5 | Segunda ventana `pwq/obl` en el shim para el stream de la otra página | ~1 BSRAM + lógica (BSRAM 101/118, hay margen; CLS hay que medirlo) | **Cura real del bug #8.** NO subir `obl_la`: la nota _147 ya documenta que empeora monótona |
| 6 | DAC de 8 bits del puerto de impresora (Simpl/Covox, puerto 0x91) | ~25 LUT | Y habilita Majutsushi/Synthesizer casi gratis. *(Nuestra lectura de 0x90 devolviendo 0xFF **ya es correcta**)* |
| 7 | Click de teclado (PC7) como DAC de 1 bit | ~10 LUT | **Va gratis con el parche del PPI** (#6/#7) |
| 8 | Mappers por **tabla de perfil** (registro de 4-5 bits escrito por el menú, igual que ya escribe `sram_cfg` por 0x43): KoeiSRAM8/32, GameMaster2, R-Type, CrossBlaim, HarryFox, Wizardry, Zemina*, Padial* | ~80 LUT para **todo** el grupo de variantes triviales; +40 Koei, +60 GM2 | Ver §3: con la DB en la SD, el menú sabe qué perfil escribir |
| 9 | Kanji12 (12×12, puertos 0xF7/0xF9) | ~20 LUT + pack | Ya tenemos kanji JIS1+JIS2 y el driver; falta el 12×12 |

**Aparcado con motivo:** RS-232 (600-900 LUT = 3% de CLS, y UNAPI cubre el 90% de los casos reales), MIDI (sin
conector físico el valor es cero), modelo real de *access slots* del VDP (154/88/31 con prioridad
CPU-sobre-comando: módulo nuevo, imposible con CLS 91%), ensanchar `c_wait` a 7 bits para SRCH (salvo que se
haga junto con el ajuste de constantes).

**Descartado:** V9990/gfx9000 (el V9968 lo cubre mejor), SunriseIDE/SCSI (Nextor sobre microSD ya lo cubre),
nowind, SG-1000/Coleco (ya eliminado en v1.9), YM2151 de los SFG (chip entero, y ya tenemos
OPL4+Y8950+OPLL+2×SCC), laserdisc, advram.

**Ya estamos igual o mejor** (para no perder el tiempo): RAM de muestras del Y8950 a 256 KB = el
`<sampleram>256</sampleram>` por defecto de openMSX; SCC-I/SCC+ con ventana en B800; nuestro autofire es
superior al Ren Sha Turbo; registro del PSG espejado a 4 bits = su `mirrored_registers` por defecto; mapper
de 4 MB por encima de cualquier máquina de su catálogo; el buffer de pre-lectura del _149 y el
`&& !w_bus_accept` del _162 ya coinciden con ellos. **Único punto abierto de audio:** openMSX declara
`<sampleram>640</sampleram>` para el MoonSound — verificar que nuestra ventana escribible de `wave_sdram.v`
llega a 640 KB.

### 2.b Menú / firmware — barato, 0 CLS

| Prioridad | Qué | Coste |
|---|---|---|
| **1** | **Reordenar el desempate + etiqueta antes que heurística + tope de escaneo + ventana de 510 bytes** (bugs #3, #4, #23) | ~30 bytes Z80 |
| **2** | **La etiqueta ES la base de datos** (ver §3): la herramienta de PC calcula el SHA1, consulta `softwaredb.xml` y **renombra** con el tag GoodMSX. El menú ya sabe leerlo (`override_mapper_by_name`) | ~80 bytes Z80 para ampliar el vocabulario |
| **3** | **Hora por NTP desde el ESP32-C6.** `fpga/src/ocm/rtc.v:84-89` arranca todos los registros a 0: cada arranque es `00-00-00 00:00:00` y toda fecha que escriba Nextor es basura. openMSX arranca con la hora del host | ~15 líneas de Arduino + 1 comando UNAPI + ~60 bytes Z80 (0xB4/0xB5 ya decodificados) |
| **4** | Regla PAGE2 + `LOAD_SEG=2` (bug #16) | ~45 bytes Z80, **+287 títulos** |
| **5** | Importar los **24 alias** de `RomInfo.cc:139-163` al reconocedor de tags (KONAMI4, KONAMI5, SCC, HYDLIDE2, RC755, RTYPE, ROMBAS, KOREAN80IN1, '0'..'5', 'Plain', '64kB'…) | 24 cadenas → compatibles con **cualquier romset etiquetado del mundo** |
| **6** | Cargar `<rom>.SRM` de la SD en los segs 252-255 en vez de rellenar a 0xFF (mitad del bug #18) | ~80 bytes Z80, reutiliza `sd_read_sector` |
| **7** | Persistir la CMOS del RTC (bloques 2 y 3 del RP5C01: colores, ancho, beep, país, contraste) y la config del menú | ~150 bytes Z80 |
| **8** | Guardado de SRAM vía ESP32-C6 (comando "dame los segs 252-255") | Proyecto de firmware, 0 FPGA. Encaja con el menú/frontend en el C6 que ya está en el roadmap |
| **9** | Barrido de la RAM de muestras del ADPCM a 0xFFFF en el reset (openMSX hace `clearRam` a 0xFF y documenta software que **mide** el tamaño de la sample RAM) | ~65k ciclos, imperceptible. Blindaje barato |

---

## 3. La base de datos de romtypes — VIABLE, y es lo más valioso del reconocimiento

El frente de mappers concluye que **sí** es destilable, con una condición de diseño que cambia el planteamiento.

### Los números duros de `softwaredb.xml`

| Métrica | Valor |
|---|---|
| Tamaño del XML | 1.399.456 bytes |
| Entradas `<software>` | 3.747 |
| Entradas `<rom sha1= type=>` | 9.821 |
| SHA1 **distintos** | 9.821 → **0 duplicados, 0 conflictos de tipo** |
| Tipos de mapper usados | 63 |
| Truncando el SHA1 a 24 bits | 2 colisiones |
| Truncando a **28 / 32 / 40 / 48 bits** | **CERO colisiones** |
| Entradas útiles (sin ColecoVision ni Mirrored) | 4.108 |
| Cobertura actual del MSXimus | ~7.500 de 8.480 entradas MSX |

Tabla recomendada por SHA1 truncado: **4.108 × (4 B hash + 1 B tipo) = 20,1 KB = 41 sectores**, índice de
164 B en RAM, 13 sondeos binarios. Variante "solo tipos que ejecutamos": 3.570 entradas = 17,4 KB. Todo:
48,0 KB.

### El bloqueo, y cómo se rodea

**El Z80 no puede calcular SHA1.** ~700 T-states/byte → 128 KB = 25 s, 512 KB = 100 s, **2 MB = 410 s** a
3,58 MHz; el turbo de 5,37 MHz no salva nada. CRC32 completo tampoco (~120 T/B → 70 s para 2 MB).

**Solución: clave acotada.** `(tamaño 32 bits) || (CRC32 de los primeros 32 KB)` = clave de 64 bits.

| Concepto | Coste |
|---|---|
| Lectura de 32 KB de la SD | ~0,33 s |
| CRC32 de 32 KB en Z80 | ~1,1 s |
| **Total del cálculo de clave** | **< 1,5 s** — *menos de lo que tardamos hoy escaneando* |
| Entradas de 9 B × 4.108 | 36,9 KB, 56 entradas/sector, 73 sectores |
| **Consulta** (índice en RAM + 1 sector) | **2 lecturas de sector ≈ 12 ms** frente a los **2-3 s** del escaneo actual |
| Código Z80 | ~300 B + 1 KB de tabla CRC |

La tabla la genera la **herramienta de PC**: recorre la colección, calcula SHA1, cruza contra `softwaredb.xml`
y emite la clave barata. (El XML solo trae SHA1, así que la clave no se puede derivar sin los ficheros, o sin
cruzar por SHA1 contra un DAT No-Intro/GoodMSX que sí traiga CRC32.) Opcional: añadir un CRC16 de los últimos
8 KB para desambiguar parches de traducción aplicados tarde.

### Por qué esto importa

**Es el fin de la detección por heurística** — la que ya nos falló con Aleste 2 por un margen de exactamente
1 punto (bug #4). Bonus enorme: los **nombres canónicos de openMSX ya codifican la información de SRAM**
(`KoeiSRAM32`, `ASCII8SRAM8`, `ASCII16SRAM2`, `ASCII16SRAM8`, `Wizardry`, `HYDLIDE2`), así que sustituyen a
la detección por tags 'KOEI'/'SRAM' del nombre **y nos dan el tamaño exacto de SRAM gratis** — que es
justamente lo que le falta al bug #17 (A-Train).

### Primer paso, de coste CERO, hacer ya

No hace falta la tabla para empezar: **la herramienta de PC renombra con el tag y el menú lo lee**
(`override_mapper_by_name`, `menu_main.asm:1771-1800`, ya existe). Solo hay que aplicar el bug #3 (etiqueta
antes que heurística) y ampliar el vocabulario. Elimina de paso los 2-3 s de escaneo en toda ROM etiquetada.

### Restricción de licencia (ver §5)

`softwaredb.xml` no tiene licencia propia → cae bajo la GPL de openMSX. **No empotrar la DB ni derivados en
el bitstream** (chocaría con la licencia no comercial del V9968 de HRA). Generarla en el PC del usuario y
dejarla en la SD como fichero de datos, con su atribución (Nicolas Beyaert 2003, BlueMSX Team 2004-2013,
openMSX Team 2005-2026, aguas arriba romdb.vampier.net).

### Mappers que faltan, ordenados por títulos desbloqueados

Page2 **287** · Generic8kB 72 + Generic16kB 25 · KoeiSRAM32 24 · ASCII8SRAM8 17 · ASCII16-X 15 (se detecta
por la firma `ASCII16X` en el offset 16) · Manbow2 13 · Zemina x-in-1 13 · YAMANOOTO 10 · Synthesizer 10 ·
R-Type 8 (hoy lo detectamos como ASCII16) · Namco 6 · Majutsushi 3. *(ColecoVision son 1.341 entradas
irrelevantes.)*

---

## 4. Qué podríamos aportarles

**Cero bugs de openMSX demostrados.** Los cuatro contrastes serios que hemos hecho contra su emulador dan
**openMSX correcto y nosotros equivocados**. La única sospecha viva quedó **refutada hoy con prueba
ejecutada** (§1.d, Metal Gear 2). openMSX **no emula el V9968** (0 coincidencias en su código, 0 issues), así
que por ahí no hay nada que reportar; el autor natural sería HRA, que ya tiene interlocución directa con
ellos (issues #1960 y #1961, arreglados en menos de una semana — ese es el canal probado).

### P1 — RECOMENDADA: desbloquear el PR openMSX #2126 (WaveGame)

El PR existe (autor @MBilderbeek, cierra #1975, +867/−1, 10 ficheros, etiqueta *device emulation*), está
**abierto, mergeable_state clean, sin mergear y parado desde 2026-07-13**. Y **no por código**: el mantenedor
pide desde el 29/05 *"a definitive spec"* que @jeroentaverne no da. Último mensaje del hilo: *"do you still
care about this?"*.

Nosotros tenemos **la única ingeniería inversa independiente del protocolo que existe fuera del firmware del
Pico** (F1 Spirit parcheado). Aportaríamos, con evidencia:

1. **Respuesta a la pregunta abierta del mantenedor sobre la lectura de memoria:** en toda la ROM hay
   **exactamente 3 sitios** con `D3 92` (`OUT (0x92),A`) y **cero lecturas** → protocolo fire-and-forget de
   1 byte, primitivo `C138: out (0x92),a / ret`. Puede simplificar ese camino sin romper software existente.
2. **Mapa de comandos observado en un juego real**: 0x41/0x42/0x4D one-shot, 0x83-0x8B bucle, 0x00 stop,
   0x04 stop/fade, 0xF0 pausa, 0xE0 resume → para la ambigüedad `0000'xxxx` vs `xx00'0000` del
   `sound_fadeout()`, el software real **solo usa la forma de nibble bajo**.
3. **Dato de arquitectura que no está en el readme del Pico**: el parche no sustituye el driver de sonido, lo
   **filtra en la cola** (un solo hook en el epílogo, 0x4188); las canciones con WAV se tragan y los SFX pasan
   y suenan por PSG/SCC. Caso probatorio: la canción 0x3C manda cmd 0x00 **y** pasa al driver, y luego suena
   en SCC.
4. **Requisito de mapper**: las ROMs wave son Konami-SCC de **17 bancos** (0x22000 = 136 KB, no potencia de 2).
5. Ofrecernos a **compilar su rama `wavegame` y probarla**, que es lo que pidió el 14/05.

**Entrega:** comentario en inglés en el PR, **solo hallazgos y offsets**. No se sube la ROM parcheada ni el
desensamblado (copyright Konami + del parche). Si piden caso de prueba, un `.COM` mínimo propio que haga
`OUT (0x92),A`.

**Interés propio directo:** nuestra fase A del WaveGame planea *"validar con F1 Spirit en openMSX primero"*
— o sea que **hoy ese plan depende de un PR sin mergear**.

**Coste:** 2-4 h de redacción + repaso del desensamblado de `scratchpad/wg_re/residente.asm`. Cero líneas de
C++, cero riesgo. +2-3 h si además probamos su rama compilada.

### P2 — Regla, no trabajo (coste 0 hoy)

Cuando un banco de `tools/v9968_sim/` discrepe de openMSX **en territorio V9958**, reducirlo a un `.COM` de
<1 KB. Si openMSX difiere del A1GT real de Albert → issue con el formato de HRA (síntoma + parámetros
exactos + `.COM`/`.asm`/`.txt` + foto del hardware). Si difiere de nosotros y no del A1GT → **es bug nuestro
y se calla**. Hoy no tenemos ningún caso.

### P3 — Obligación, no propuesta (15 min)

**Atribución en el README del MSXimus.** openMSX no nos ha dado código pero sí **cuatro diagnósticos**:
balance 1/2048 del Y8950, periodo del blink de R#13, pre-lectura de VRAM del V9938 (vía el NMS 8250) y
semántica de EOS/wrap de la RAM de muestras. Dos frases: reconocer el uso como *golden reference* **y**
declarar que no se incluye código suyo.

### Descartadas con motivo

Implementar el V9968 en openMSX (meses de C++ ajeno; el autor natural es HRA). Arreglar el timing
BUF_RDY/EOS del Y8950 (el dato ya lo dio Eugeny1 en 2019; falta implementación con `setSyncPoint` y hay
precedente de regresión con el Philips Music Creator en 2020). "Aportar" nuestra calibración de ganancia (es
una medida **de** su emulador **para** nuestro mezclador). Abrir issue por MG2 (refutado hoy).

---

## 5. Licencias

### Qué declara openMSX

| Hecho | Evidencia |
|---|---|
| Licencia | **GPL-2.0**. `doc/GPL.txt` = *"GNU GENERAL PUBLIC LICENSE Version 2, June 1991"*; el README la declara para todo fichero sin cabecera propia |
| ¿"only" u "or later"? | `meson.build:3` declara **GPL-2.0-only**. Ojo: **no hay `LICENSE` en la raíz** y GitHub reporta `license: null`; el README no dice "or later". Un frente lo leyó como "only" por el meson, otro como "sin cualificar". **Asumir `only`, que es lo más restrictivo** |
| Excepciones | `src/sound/opll.*` y `YM2413NukeYKT.*` son **GPL-2.0-or-later** (Nuke.YKT). `src/3rdparty/imgui` e `ImGuiFileDialog` son **MIT** |
| `share/softwaredb.xml` | **Sin licencia propia** → cae bajo la GPL del proyecto. Créditos en la cabecera CDATA: Nicolas Beyaert (2003), BlueMSX Team (2004-2013), openMSX Team (2005-2026); aguas arriba romdb.vampier.net |
| Proceso de contribución | **No hay `CONTRIBUTING.md`**, ni plantillas, ni guía de estilo publicada. Issues y PRs en GitHub; discusión real en IRC #openMSX (Libera), Discord puenteado y foro MRC |

### Qué implica para nosotros

1. **GPL-2.0-only es incompatible con nuestro árbol.** El MSXimus es GPLv3 **y** contiene el V9968 de HRA con
   una licencia **no comercial**. Ni podemos absorber código GPL-2.0-only en GPLv3, ni podemos mezclar GPL de
   ningún sabor con la cláusula no comercial. **Ni una línea de openMSX entra en el MSXimus.** Esto es una
   frontera dura, no una preferencia.
2. **Lo que sí podemos usar es el conocimiento.** Los hechos sobre cómo se comporta un chip real —que el bit 7
   de R#15 es el LED KANA, que 5S no se actualiza con F=1, que HMMV cuesta 48 ciclos por píxel— **no son
   copyrightables**. Son descripciones de silicio de Yamaha/Toshiba de los 80. openMSX es aquí una
   **bibliografía y un oráculo ejecutable**, no una fuente de código.
3. **Regla de trabajo para todo el equipo:** de openMSX se leen los ficheros, se anota el *comportamiento* en
   prosa, y el RTL/asm se escribe desde esa prosa. Los informes de este reconocimiento están redactados así a
   propósito: describen qué hace openMSX y citan fichero:línea como referencia bibliográfica, **sin transcribir
   su código**. Mantener ese estilo en cualquier informe futuro.
4. **`softwaredb.xml`: nunca en el bitstream.** Es GPL y colisionaría con la cláusula no comercial del V9968.
   Se genera/destila **en el PC del usuario** y vive en la SD como fichero de datos, con su atribución. Esto
   no es una limitación práctica: es exactamente el diseño que §3 recomienda por otros motivos (el Z80 no
   puede calcular SHA1 de todos modos).
5. **Atribución obligatoria** (P3 de §4): reconocer el uso como referencia **y** declarar explícitamente que
   no se incluye código de openMSX. Ambas frases, no solo la primera.
6. Para las contribuciones **hacia** ellos (§4 P1): aportar **hallazgos y offsets**, no ROMs ni desensamblados
   (copyright de Konami y del autor del parche).

---

## 6. Recomendación: las 3 acciones que haría ya

### Acción 1 — Build "quirks de coste cero" (medio día de edición + 1 síntesis)

Todos estos son de 1-15 líneas, ninguno añade LUTs y **dos los quitan**. Van en **dos commits separados** para
poder bisecar si la placa se queja:

- *Commit E/S* — bug #1 joystick 2 (`top.v:769-812`, 1 línea, CLS negativo, y libera el bit 7 para el LED
  KANA), bugs #6+#7 el parche del PPI 0xAB/0xAA (~20 líneas, ~0 CLS), bug #5 Konami4 a `bus_addr[15:13]`
  (`megaram.v:146-159`, **CLS negativo**), bug #20 el bit JIS.
- *Commit VDP* — bug #9 blink-page con EO=0 (1 línea, NO-OP garantizado con R#13=0), bug #11 filtro de color 0
  en la colisión (~0 LUT, el término ya existe), bug #12 el bit IC (2 FF), bug #13 el gate de 5S por F.

**Verificación en placa:** gamepad USB nº2 en un juego de 2 jugadores · LED CAPS del WS2812 · un Konami4 sin
SCC · logo MSX2+ (¿desaparece el glitch?) · Dragon Quest 2.

**En paralelo, sin coste de gate:** montar el **banco de simulación del SP2** (~40 líneas sobre
`tb_geomfast.sv`: SCREEN 5, R#2 b5=1, R#25 b0=1, barrer R#26 de 0 a 63 y contar `bg_miss`/frame). Predicción
falsable: `bg_miss` salta de ~0 a ~1/línea en cuanto `hScroll != 0` y vuelve a 0 cuando `R#26 & 0x1F == 0`.
Añadir un barrido **decreciente** para atacar de paso el "scroll hacia atrás". Esto decide si el bug #8 —el
síntoma abierto del README— se arregla con una mitigación barata (dejar de predecir ante deltas grandes) o
con la segunda ventana `pwq/obl`.

### Acción 2 — Fin de la heurística de mappers (un día, 0 CLS)

En el menú Z80, en este orden: reordenar los cuatro bloques `.dm_cand` a A8/A16/KON/SCC (**0 bytes**) →
llamar a `override_mapper_by_name` **al principio** de `detect_mapper` (~14 bytes) → arrastrar 2 bytes entre
sectores (~15 bytes) → ampliar el vocabulario de tags a los nombres canónicos de `RomInfo.cc` **incluida la
información de SRAM** (~80 bytes).

En el PC: que la herramienta calcule el SHA1, consulte `softwaredb.xml` y **renombre con el tag**. Con eso,
sin escribir todavía la tabla `MAPPERS.DB`, toda ROM etiquetada se identifica **sin escanear** y el caso
Aleste 2 queda cerrado por dos vías independientes. La tabla en la SD (§3) es el paso siguiente natural, ya
dimensionado: 36,9 KB, 73 sectores, consulta en ~12 ms.

### Acción 3 — Build de audio (una tarde + 1 síntesis)

Primero **mirar `top.v:3476`** y resolver la contradicción `>>>1`/`>>>3` de §1.c. Luego, en la misma build:

- **PSG sin recorte** (bug #2): `O_AUDIO` a 10 bits sin shift ni clip, `psg_filter.v` a 10 bits (`<<2`/`>>2`),
  `top.v:3565` a `{2'b00, psg10, 5'b0}` (×32). **Ganancia-neutro**: idéntico bit a bit para toda señal que hoy
  no recorta, así que no hay riesgo de desbalancear el mezclador. Es el arreglo de audio con más impacto
  audible de todo el informe.
- **ADPCM a 20 bits** (bug #10): 2 líneas, cierra el agujero que abrió la _159 con los 256 KB.
- Opcional en la misma build: canal derecho del mezclador FM del OPL4 (bug #19, ~40 LUT), y medir el
  +3 dB del MoonSound tocando el mismo VGM por OPL3 y por MSX-Audio antes de tocar nada.

**Fuera de las tres acciones, para cuando toque:** las 6 constantes `c_wait_*` (0 LUT, validable contando
ciclos en `run_battery.sh`) van bien pegadas a cualquier build del VDP; el ratón MSX (~150 LUT con el hardware
ya cableado) es el mejor RTL nuevo del catálogo; y la hora por NTP desde el C6 es el mejor ratio valor/coste
del lado firmware.

---

## Anexo — notas operativas del reconocimiento

- Trabajo de **solo lectura**: clon shallow/sparse de openMSX en el scratchpad (`omsx/`), ~150 llamadas de
  lectura/grep. **Cero escrituras** en los repos del usuario, **cero síntesis de Gowin**.
- Las estimaciones de LUTs son **órdenes de magnitud razonados** a partir del tamaño de las FSM, **no medidas
  de PnR**. Cualquier cosa por encima de ~100 LUT hay que medirla antes de comprometerse con el 91% de CLS.
- **El MCP de openMSX es compartido.** Quedó una instancia corriendo con **Philips_NMS_8250** (se relanzó a
  mitad de sesión para las medidas de dispositivos). Las capturas de pantalla están rotas por permisos en
  `C:\Program Files\openMSX`; las medidas se hicieron con `debug_memory`, no con capturas.
- Herramientas reutilizables dejadas en el scratchpad: `heur.py` (simulador diferencial que reimplementa
  `guessRomType` de openMSX y `scan_rom`+`decide_mapper` del menú byte a byte, y saca el marcador de ambos),
  `tie_kon_scc.rom` y `tie_scc_a16.rom` (ROMs sintéticas de 128 KB con marcadores empatados).
- **Conocimiento nuevo a archivar:** openMSX cambió en 2026 el YMMM de "40 R 24 W +0" a "36 R 24 W +68" y
  añadió un hack condicional en LMMM (`dstReadDelta` D48 en vez de D32 cuando hay sprites,
  `VDPCmdEngine.cc:1126-1140`), ambos a raíz de las mediciones de bengalack (issue #2057). **Es el estado del
  arte y contradice la tabla de 2013 que sigue en su propia documentación.**
