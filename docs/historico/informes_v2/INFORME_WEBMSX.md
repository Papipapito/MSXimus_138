# ¿Qué de WebMSX nos conviene? — Informe de síntesis para Albert

**Proyecto:** MSXimus (Tang Console 60K, GW5AT-60) · **Fecha:** 2026-07-29
**Fuentes:** los 5 estudios de `scratchpad/webmsx/` (`turbor.md`, `teclado-es-int.md`, `kanji.md`, `mappers-webmsx.md`, `webmsx-ideas-libres.md`)

## Los números que mandan en todo el informe

| Recurso | Ocupado | Libre | Comentario |
|---|---|---|---|
| **CLS (GW5AT-60)** | 27.006 / 29.952 (**90,2 %**, "el 91 %") | **2.946 CLS (9,8 %)** | El problema real ya no es la capacidad, es el **rutado**: hay precedente de builds atascadas 62 min |
| BSRAM | — | **17 bloques** | Suficiente para casi todo, pero no es infinito |
| DSP | 13 % | Sobra | Un multiplicador es "gratis" |
| Flash SPI | pack @0x400000 | **~1,5 MB en 0x280000–0x3FFFFF** | Sobrado |
| **Banco del menú Z80 (#8000–#A000)** | — | **~60 bytes** | 🔴 **El cuello de botella real.** Desbordar `.org #A010` es SILENCIOSO |
| Sección de datos #A010–#C000 | — | ~500 bytes | Aquí sí hay sitio para tablas |
| config1[7:0] / config2[5:0] | **COMPLETOS** | 0 bits | Cualquier toggle nuevo exige puerto #46 y ensanchar `config_sig` |

**Reglas de decisión usadas:** <100 CLS = ruido · 100–400 CLS = medir con build de sonda · >400 CLS = no en el 60K.
**Ningún número de este informe viene de una síntesis ejecutada**: todos son estimaciones ancladas en el informe PnR real en disco (`fpga/impl/pnr/project.rpt.html`, factor medido 0,78–1,28 CLS/LUT4 según empaquetado). Están dados como rangos a propósito.

**La conclusión estructural, antes que nada:** de las ~30 ideas estudiadas, la mayoría de las buenas **no tocan la FPGA**. Y la mayoría de esas chocan con **~60 bytes de banco de menú**, no con el 91 % de CLS. El argumento para el frontend del ESP32-C6/S3 ya no es estético: es que el menú Z80 está lleno.

---

## 1. Ranking coste/beneficio — todo lo estudiado

De más a menos recomendable.

| # | Idea | Qué gana el usuario | Dónde se toca | Coste | Veredicto |
|---|---|---|---|---|---|
| 1 | **Kanji: verificar y anunciar** (ya está en silicio) | Software japonés con kanji (MSX-Write, DOS-JP, *Illusion City*) dibuja texto real en vez de basura | Nada: 4 líneas de `initializers` en `kanji.v` + pruebas | **0 CLS / 0 flash / 0 BSRAM / 0 bytes de menú** | ✅ **HACER YA** |
| 2 | **Teclado ES — Fase 0** (BIOS parcheada en el pack) | La tecla **Ñ** escribe `ñ`/`Ñ` de verdad | `MSXnanoPackBuilder` sobre la ranura mainbios (@0x60000) | **0 CLS.** 21 B *dentro* de los 32 KB que ya viajan. **Sin resintetizar** | ✅ **HACER YA** |
| 3 | **Detección de mapper por firma de 8 B @0x10** | Cero fallos de mapper en todo el homebrew MSXgl + arranque **2–3 s más rápido** (se salta `scan_rom`) | `menu_main.asm`: 28–38 B de código + 21–40 B de datos en #A010 | **0 CLS.** Toca el hueco de oro del menú | ✅ **HACER YA** |
| 4 | **NEO-8 / NEO-16 / ASCII16-X** | Estándar de facto del homebrew 2023+; Albert podría cambiar el target de MSXgl y arrancar en su propia placa | `megaram.v`: ignorar escrituras de banco en dirección impar (6 condiciones) | **0–4 CLS** | ✅ HACER (colar en la próxima build) |
| 5 | **R-Type (384 KB)** | Un juegazo de MSX2 que **hoy no arranca** | Preinicializar el banco 15 en el stub del menú | **0 CLS**, ~14–18 B de menú | ✅ HACER |
| 6 | **Teclado ES — Fase 1** (tabla HID ES + hotkey F12) | De 2/12 a **8/12** teclas de puntuación donde pone la serigrafía | `usb_keyboard_msx.vhd` + `top.v` (bit 3 del byte de ganancia; F12 como F11) | **10–25 CLS** (0,03–0,08 %), 0 flash, **0 B de menú** | ✅ HACER |
| 7 | **Turbo Z80 existente a 7,16–8,06 MHz** | El **catálogo entero** va más rápido. Vale 10× más que todo el frente TurboR | `top.v` (divisor/PLL) + ⚠️ árbitro SDRAM | **~0–200 LUT**, pero **riesgo alto** en el árbitro que costó sangre calibrar | 🟡 EVALUAR — el mayor ROI del informe, y el que más puede romper |
| 8 | **SRAM del cartucho → SD** ("Load/Save Data File") | Cierra un pendiente **real y documentado**: hoy los saves se pierden al apagar | Firmware/menú (o mejor, un `.COM`) | **0 CLS.** 300–500 B de menú ⚠️ o 0 si va como `.COM` | 🟡 SÍ, pero decidir antes el vehículo |
| 9 | **Rewind / seek / auto-run de cinta** | Control de cinta de verdad, no solo "play" | Firmware C6 (~200 líneas) | **0 CLS** — el C6 ya tiene la cinta en RAM con tabla de bloques y `cas_stream.v` re-arma solo (CVS1) | 🟡 SÍ, tras el frente TSX |
| 10 | **Gramática de modificadores + pantalla ABOUT** | N funciones al precio de 1 string (Shift = drive B, Ctrl = vacío, Alt = quitar) | `menu_main.asm` | **0 CLS.** *AHORRA* 100–300 B de menú | ✅ Gratis y encima libera espacio |
| 11 | **OSD en el LCD del C6** | Estado de cinta/disco fuera de la pantalla del MSX | `Display.ino` (~150 líneas) | **0 CLS.** `tapeBusy/tapeTotal/tapeSent` **ya existen** y no se pintan | 🟡 SÍ (frente C6) |
| 12 | **Captura de pantalla VRAM→UART→C6** | Pantallazos reales… **y el volcado de VRAM que falta para cerrar DEVCON** | Firmware C6 + `.COM` (~1,5 s para 128 KB) | **0 CLS** | 🟢 Alto valor colateral de depuración |
| 13 | **Impresora mínima "siempre lista"** | `LLIST` deja de colgar | `top.v` | **10–20 CLS** | 🟢 Barato, quita un cuelgue |
| 14 | **Majutsushi: DAC de voz** | La voz digitalizada del juego (ya juega como Konami4) | `megaram.v`/audio | **12–20 CLS** | 🟢 Barato, prioridad mínima |
| 15 | **S1990 mínimo + CHGCPU/GETCPU honestos** | El software que pide acelerar **acelera de verdad** | `top.v` (puertos #E4–#E7, #A7) | **120–235 CLS** (<0,8 %) | 🟡 Solo si se hace el #7 |
| 16 | **MULUB / MULUW del R800** | Multiplicación rápida para software que la detecte | `t80_mcode.vhd` + 1 DSP | **160–470 CLS** (<1,6 %), 1–2 DSP | 🟡 Cabe, pero sin R800 casi nadie los llamará |
| 17 | **Stub PCM estilo WebMSX** (parche BIOS #0186/#0189 → carry=1) | Que el software que pide PCM **no se cuelgue**, sólo falle limpio | Pack (BIOS) | **0 CLS**, ~16 bytes | 🟢 Truco elegante de WebMSX; sólo tiene sentido con el #15 |
| 18 | **Turbo de CPU escalonado (estilo Alt+T)** | Elegir velocidad por juego | `top.v` + puerto #46 | **40–80 CLS** | 🟡 Depende del #7 |
| 19 | **Pausa + avance de frame + cámara lenta** | Depuración y accesibilidad | `top.v` (gate de `ce`) + puerto #46 | **75–145 CLS** | 🟡 Empaquetar con el #20 |
| 20 | **Inyector de teclado / paste** | Auto-teclear `RUN"CAS:"`, macros | `top.v` (FIFO + FSM) | **90–175 CLS**, 0–1 BSRAM. El formato `{0xC0\|fila,máscara}` **ya está en `MenuProto.h`** | 🟡 Empaquetar con el #19 (~165–320 CLS juntos, comparten decodificador de #46) |
| 21 | **Selector de pack de BIOS** | Varias BIOS en la misma flash | `top.v` (sumador de base) | **20–40 CLS + 1,5 MB flash** (todo el hueco libre) | 🟡 Requiere frontend F2 |
| 22 | **Teclado ES — Fase 2 (AltGr sintético)** | `[ ] { } @ # \ \|` donde pone la tecla | `usb_keyboard_msx.vhd` | **20–40 CLS**, pero obliga a **reubicar GRAPH** (hoy RAlt) | 🟠 Sólo si la Fase 1 convence en placa |
| 23 | **Crear/formatear DSK, importar ficheros, Open URL, POKEs** | Gestión de medios como un emulador | Frontend C6/S3 | **0 CLS**, pero **dependen del frontend** | 🟠 Aparcado hasta el companion |
| 24 | **Ratón MSX por USB** | Ratón real en el MSX | `msx_mouse.v` nuevo + ampliar HID de `usb_direct` | **200–700 CLS** (0,7–2,3 %). El rango es honesto: no se puede acotar sin abrir el módulo | 🟠 **Build de sonda ANTES de comprometerse.** Si sale >500 CLS → 138K |
| 25 | **MSX-JE (escribir japonés)** | Entrada de texto japonés | slot decode + 32–256 KB flash | **20–35 CLS** + hay que alargar el pack o usar SDRAM 0x7C0000 | 🟠 Aparcar hasta el companion |
| 26 | **5º modo de mapper (CrossBlaim, HarryFox)** | 2 juegos sueltos | `map_sel` (2 bits, los 4 valores usados) + registro de config nuevo | **30–60 CLS de fontanería por DOS juegos** | ❌ No merece la pena |
| 27 | **Declarar turbo R en el byte #002D** | Nada bueno | Pack | **0 CLS** … y **el software salta a rutinas R800 y va peor o se cuelga** | ❌ **PELIGROSO. No hacer** |
| 28 | **VDP turbo (Alt+Y de WebMSX)** | Comandos del VDP más rápidos | Motor de comandos del V9968 | Barato en LUTs, **carísimo en riesgo** justo donde acabamos de cerrar Aleste | ❌ No |
| 29 | **Fuente kanji 12×12 ($DC/$DD)** | Nada medible (ni WebMSX la emula) | `kanji.v` | 40–60 CLS + 128 KB | ❌ No |
| 30 | **TurboR real (R800 + S1990 + PCM)** | ~8 títulos etiquetados, **uno solo lo explota** | CPU nueva + rehacer el árbitro SDRAM | **4.300–7.300 CLS** vs **2.946 libres** | ❌ **No cabe** (ver §3) |
| 31 | **Savestates / rebobinado** | Guardar partida en cualquier punto | Todo el core | No es cuestión de CLS: el T80 no expone sus registros | ❌ **Ni en la 138K** |
| 32 | **NetPlay, paddle/trackball, DMK, Nowind** | — | — | — | ❌ No aplica a hardware real / WebMSX tampoco los tiene |
| 33 | **Empaquetar WebMSX como companion** | — | — | — | ❌ **Imposible legalmente** (§5) |

---

## 2. Las tres que haría YA

Las tres suman **≤ 29 CLS de 2.946 libres**, y **dos de las tres no requieren resintetizar nada**. Ese es exactamente el criterio: con el rutador al 91 % y builds que se han atascado 62 minutos, lo primero que hay que cobrar es todo lo que no pasa por Place & Route.

### YA-1 · Kanji: verificar lo que ya tenemos (0 CLS)

**Por qué es la primera:** es la única funcionalidad *nueva anunciable* que no pide ni una LUT. Está compilada dentro de la _162 del 91 %, la ROM ya viaja en el pack del usuario, y **nunca se ha probado** (`git log --all --grep=kanji` = 0 commits). Ignorarla es tirar algo que ya está en silicio.

**Plan:**
1. `fpga/src/ocm/kanji.v` — añadir `initializers` a los punteros (hoy instanciado con `.reset(0)` y sin valores iniciales: **imposible de simular**; en HW arranca a 0 por power-up Gowin). **4 líneas, 0 CLS.**
2. Testbench mínimo + prueba dorada en **openMSX con la MISMA ROM** del pack:
   `OUT &HD9,&H10 : OUT &HD8,&H01` + 32 × `INP(&HD9)` ⇒ debe salir **亜**.
   (Ya verificado forensemente sobre `mi_release/v2.1_rc1/pack_bios_V5_151_menufix.bin`: JIS X 0208 auténtica, ku 15 en blanco = firma perfecta, SHA-1 `5aff2d9b…`.)
3. Misma prueba **en placa**, luego `CALL KANJI` desde BASIC.
4. Contrastar las filas de kana (D9=4,5) contra openMSX — en el volcado rápido salían raras.
5. Documentar el hueco de 256 KB en el README y en el **Pack Builder** (hoy el usuario no sabe que puede poner ahí su JIS).

**Riesgo:** ninguno. Nada de esto obliga a resintetizar salvo el paso 1, que puede viajar en cualquier build futura.

### YA-2 · Teclado español — Fase 0 y Fase 1

**Por qué:** es lo único de toda la tanda que el usuario nota **cada línea que escribe** en BASIC o Nextor. Hoy sólo **2 de 12** teclas de puntuación coinciden con su serigrafía (la `-` escribe `/`, la `'` escribe `-`, la `Ñ` escribe `;`, no hay `ñ`). Es petición directa de Albert. Y es entregable **en dos mitades independientes**.

**Fase 0 — pack, 0 CLS, hoy mismo:**
1. En `MSXnanoPackBuilder/src/`, localizar la tabla de conversión por **firma de bytes** `2D 3D 5C 5B 5D 3B 27 60 2C 2E 2F FF` sobre la ranura mainbios (offset 0x60000, 32 KB).
2. Parchear **4 bytes** de tabla: `0x0DE8 3B→A4`, `0x0DF4 3A→A5`, `0x0DEA 60→3B`, `0x0DF6 7E→3A`; más `#002C 0x11→0x16` (tipo de teclado 1→6).
3. 🔴 **Y los glifos** — hallazgo que no sabía nadie: el **CGTABL de nuestra BIOS es japonés** (`ptr` en #0004 = 0x1BBF; 0xA4 es la coma ideográfica, 0xA5 el punto medio, todo 0xA0–0xDF es katakana). Sin parchear `0x20DF` y `0x20E7` (8 B cada uno), la Ñ sale como una coma japonesa. **Esto es la mitad del trabajo real de la Fase 0.**
4. Total: **21 bytes dentro de una imagen que ya viaja**. Validar en `msxnano_omsx` sin tocar la FPGA.

⚠️ El parche **no puede hacerse en runtime**: la región de BIOS en SDRAM es de sólo lectura desde el bus (`top.v:2164-2172`) y la config llega como los **últimos 6 bytes** del stream (`top.v:4257-4287`), después de la BIOS.

**Fase 1 — RTL, 10–25 CLS, se cuela en la siguiente build que se haga por otro motivo:**
1. `fpga/src/usb/usb_keyboard_msx.vhd` (287 L): puerto nuevo `KBD_ES` + **6 ramas condicionadas** del CASE (usages 0x2D, 0x31, 0x34, 0x35, 0x38, y rama nueva 0x64).
2. `fpga/top.v`: L.4997-5006 la instancia · L.3926 y L.4106 el **bit 3 del byte de ganancia** (estrechando el tag de `[7:3]=11000` a `[7:4]=1100`, **retrocompatible 100 %** con bloques legados 0xC0..0xC7 y con 0xFF) · L.3994 readback de #44 · hotkey **F12** junto al bloque de F11 (L.1197) · opcional tinte del LED WS2812.
3. **Cero bytes del menú**: una opción de menú costaría 65–75 B contra ~60 libres ⇒ **no cabe**, por eso va como hotkey en RTL y la persistencia sale gratis reutilizando el Save del menú.
4. **No se toca**: `usb_kbd_decode.v`, `fpga_companion.v` (el remapeo cubre las dos fuentes a la vez vía `top.v:4950`), firmware C6, ni `menu_main.asm`.

**Honestidad:** la paridad perfecta es imposible — el plano SHIFT de la fila de dígitos de un PC español (`1! 2" 3· 4$ 5% 6& 7/ 8( 9) 0=`) no coincide con el de **ningún MSX que haya existido**. Y los acentos (DEAD) siguen rotos por el mismo charset japonés: son 8 glifos más, como mínimo.

### YA-3 · Mappers: firma + NEO/ASCII16-X + R-Type

**Por qué:** casi todo el valor se cobra **sin gastar CLS**, y arregla un fallo de fondo: hoy dependemos de un escaneo estadístico de opcodes `LD (nn),A` que se traga los juegos que hacen banking con `LD (HL),A`.

**Plan:**
1. **Detección por firma (0 CLS)** — WebMSX no escanea opcodes: usa SHA-1 + tag `[Formato]` en el nombre (**eso ya lo tenemos**) + **firma de 8 bytes en offset 0x10** (`ROM_ASC8` / `ROM_AS16` / `ROM_KON4` / `ROM_KON5` / `ROM_NEO8` / `ROM_NE16` / `ASCII16X`), spec **abierta** de MSXgl.
   Truco de espacio: bastan **2 bytes discriminantes** (offsets 0x15 y 0x17, sin colisiones en las 7 firmas) ⇒ tabla de **7×3 = 21 B** en la sección de DATOS desde `#A010` (500 B libres, fuera del guarda `ds #A000-$`) y sólo **28–38 B de bucle** en los ~60 de oro.
2. **NEO-8 / NEO-16 / ASCII16-X (0–4 CLS)** — hallazgo central: dentro de nuestro techo de **2 MB** (`megaram_addr[20:0]`) son **alias bit a bit** de ASCII8/ASCII16: mismos registros en 0x6000/0x6800/0x7000/0x7800 y el byte alto de NEO siempre 0. **Único cambio de RTL:** ignorar escrituras de banco en dirección **impar** (`bus_addr[0]==0`) en las 6 condiciones de la rama ASCII de `megaram.v` — hoy 0x6001 se toma como 0x6000 y corrompería el banco.
3. **R-Type (0 CLS)** — es ASCII16 crudo con el **banco 15 fijo en 0x4000**: se resuelve preinicializando ese registro en el stub del menú (~14–18 B).
4. **Documentar** que Manbow2 (Konami-SCC) y AlQuranDecoded (ASCII8) **ya juegan hoy**.

**Antes de escribir código, verificar:** (a) R-Type como ASCII16+banco15 en openMSX; (b) que el target NEO-8 de MSXgl no use las ventanas de página 0; (c) el hueco real de código con `out/menu_main.sym`.

⚠️ **Regla de build**: el cambio de `megaram.v` toca el camino de **escritura** (`always @posedge clk_27m`), no el cono combinacional de `megaram_addr`/`megaram_req` que ya rompió en placa (regresión MG2 v1.7). Aun así: **nunca sacar una build sólo por esto** — empaquetar YA-2 Fase 1 + YA-3 en la misma síntesis.

### El cuarto, para que conste

**SRAM del cartucho → SD** tiene más valor de usuario que YA-1 (cierra el pendiente documentado "save emulado = SDRAM volátil"). No está en el podio por una razón puramente logística: cuesta **300–500 B de banco de menú** cuando quedan ~60, así que primero hay que decidir si va como `.COM` (0 B de menú). En cuanto se decida, es el siguiente.

---

## 3. Lo que NO cabe hoy — y lo que simplemente no merece la pena

Hay que separar las dos cosas, porque tienen remedios distintos.

### 3.a. NO CABE — aritmética, no opinión

**TurboR real (R800).** El número que lo cierra:

| Partida | CLS |
|---|---|
| Core R800 (5.100–8.500 LUT, ×0,78 CLS/LUT medido en esta build) | 4.000–6.600 |
| + S1990 + PCM + rehacer el árbitro | 4.300–7.300 |
| **Disponible** | **2.946** |
| **Déficit** | **1.400–4.400 CLS** |

Y no existe atajo: **no hay ningún core RTL abierto del R800** — ni OpenCores, ni OCM/1chipMSX, ni MSX_MiSTer; sólo la placa **cerrada** de Hiroyuki (XC3S250E), y el decap *"Uncovering the R800"* no ha producido RTL. Habría que escribirlo desde cero (pipeline, datapath de 16 bits, multiplicador, doble estado Z80/R800, DRAM en page mode a 7,16 MHz), 3–5× el T80 que ya tenemos.
**Y el peor cuello no es la CPU**: es rehacer el **árbitro de la SDRAM compartida** (RAM MSX + OPL4 + ADPCM) que costó sangre calibrar a 5,37 MHz.
**ROI:** ~8 títulos etiquetados turbo R, y sólo *Illusion City* explota R800+PCM.
*Qué haría falta:* una Console 138K **y** rehacer el subsistema de memoria. No es un problema de comprar chip más grande.

**Savestates y rebobinado.** No caben **ni en la 138K**, y no por área: el **T80 no expone sus registros**. Habría que serializar Z80 + V9968 + 5 chips de audio + mappers + 4 MB de SDRAM + 128 KB de VRAM — es un **rediseño del core**, no una funcionalidad. (El propio Roadmap de WebMSX aún tiene un bug de savestates abierto.) El rebobinado depende de savestates, así que cae con ellos; WebMSX ni siquiera lo tiene.

**Ratón MSX por USB — el único caso "quizá".** Rango honesto **200–700 CLS (0,7–2,3 %)**. `msx_mouse.v` en sí son 125–225 CLS; la incertidumbre está en **ampliar el HID de `usb_direct`**: si basta ramificar por `bInterfaceProtocol`, 75–150 CLS; si hay que añadir un segundo endpoint/pipe, 300–500 CLS. Caso bueno cabe de sobra; caso malo sube la ocupación a **~93,5 %** y ahí el rutador castiga. *Qué haría falta:* una **build de sonda** que mida el HID ampliado antes de comprometerse. Si sale >500 CLS → 138K.

**Nuevas opciones de menú (casi cualquiera).** 8 de las 9 ideas de coste-RTL-cero chocan con los **~60 bytes libres** del banco Z80 (`ds #A000-$` + `.org #A010`, `menu_main.asm:4862`), y el desbordamiento es **silencioso**. *Qué haría falta:* rebancar el menú **o** —mejor— el frontend del ESP32-C6/S3. Este es el hallazgo estratégico del informe.

**Toggles nuevos de configuración.** `config1[7:0]` y `config2[5:0]` están **completos** (`top.v:3963-4014`). Todo toggle nuevo exige el puerto **#46** + extender `config_sig[0:5]` y `flash_write_counter` (#43=sram_cfg, #44=ganancia, #45=turbo-boot ya están). Por eso conviene **agrupar** los cambios de configuración en una sola tanda.

**Pack completo TurboR (A1ST 2 MB + kanji font 256 KB):** no cabe en el hueco de 1,5 MB. El pack turboR *mínimo* (BIOS 32K + SubROM 16K + Kanji-drv 32K, sin FDC porque usamos Nextor) = 80–112 KB, ése sí cabría… pero sin R800 no sirve para nada.

### 3.b. SÍ CABE, pero NO MERECE LA PENA

- **5º modo de mapper (CrossBlaim, HarryFox):** 30–60 CLS de fontanería (`map_sel` es de 2 bits con los 4 valores usados ⇒ registro de config nuevo) **por dos juegos**. No.
- **Zemina / SuperLodeRunner / Dooly / AlQuran cifrado / Halnote / KUC / GM2 / SuperSwangi:** multicarts piratas o casos que exigen espiar todo el bus o descifrar en la ruta de **lectura**. No.
- **VDP turbo (Alt+Y):** barato en LUTs, carísimo en **riesgo** — tocar el motor de comandos del V9968 justo después de cerrar Aleste y DEVCON. No.
- **Fuente kanji 12×12 ($DC/$DD):** 40–60 CLS + 128 KB de flash con valor ≈ 0. **Ni WebMSX la emula.**
- **Declarar turbo R en #002D:** 0 CLS y **activamente dañino**: el software salta a rutinas optimizadas y va peor o se cuelga con opcodes R800.
- **MULUB/MULUW sueltos:** caben (160–470 CLS + 1 DSP), pero sin R800 declarado casi ningún software los invocará.
- **NetPlay:** WebRTC entre emuladores; no aplica a hardware real. Y en **red del MSX de verdad nosotros vamos por delante** (UNAPI/TLS/SSH).
- **Paddle, trackball, light-pen, DMK, Nowind/Sunrise:** WebMSX tampoco los tiene (están en su Roadmap como TODO). No hay nada que copiar.

### 3.c. La inversión que sí paga (y que no es de WebMSX)

**Subir el turbo Z80 existente de 5,37 a 7,16–8,06 MHz.** Coste RTL ≈ 0 y **beneficia al catálogo entero**, no a 8 títulos. Ya tenemos "modos de velocidad por software" (turbo Panasonic con `OUT &H41` vía `pana41_wr`). El riesgo está todo en el **árbitro SDRAM**, y eso hay que medirlo, no estimarlo. Si el frente TurboR ha servido para algo, es para señalar esto.

---

## 4. Lo que ya teníamos sin saberlo

Este es, en mi opinión, el capítulo más rentable del estudio.

1. **El kanji está entero y compilado.** `fpga/src/ocm/kanji.v` (ESE Artists' factory 2006, BSD-3 no comercial) está en `build.tcl:104` ⇒ **dentro de la _162 del 91 %**. Puertos $D8–$DB decodificados (`top.v:3780-3803`), datos mapeados a SDRAM 0x700000–0x73FFFF y driver a 0x770000, integrados en `any_ram_req` y en el mux de `cpu_din`, y el driver de **KANJI BASIC** mapeado en slot 0-1 páginas 1-2. **La ROM ya viaja en el pack del usuario** (verificado byte a byte: JIS X 0208 auténtica, 亜/唖/娃/阿 correctos, ku 15 en blanco). Coste ya gastado: ~55–90 CLS. **Nunca se ha probado.**
2. **Manbow2 y AlQuranDecoded ya juegan hoy.** Manbow2 **es** Konami-SCC; AlQuran (versión decoded) es ASCII8 puro. Sólo falta documentarlo.
3. **NEO-8/NEO-16/ASCII16-X ya los soportamos casi al 100 %** — son alias de ASCII8/16 con ≤2 MB. Nos separa de ellos **una condición AND**.
4. **Los "modos de velocidad por software" ya existen**: turbo Panasonic 5,37 MHz con `OUT &H41` (`pana41_wr` en `top.v`). El frente TurboR llegó buscando algo que ya está.
5. **El C6 ya tiene la cinta entera en RAM con tabla de bloques**, y `cas_stream.v` re-arma solo gracias a la magia `CVS1` ⇒ rewind/seek/auto-run cuestan **0 en la FPGA**.
6. **`tapeBusy` / `tapeTotal` / `tapeSent` ya existen** en el protocolo y `Display.ino` simplemente **no los pinta**. El OSD del LCD está medio hecho.
7. **El formato de tecla `{0xC0|fila, máscara}` ya está especificado en `MenuProto.h`** ⇒ el inyector de teclado tiene la mitad del diseño escrito.
8. 🔴 **Descubrimiento negativo, y es importante:** el **CGTABL de nuestra BIOS es japonés** (0xA0–0xDF = katakana de media anchura). **No hay glifos acentuados.** Esto invalida cualquier plan de teclado español que se limite a la tabla de conversión, y explica por qué los acentos DEAD están rotos. Nadie lo sabía antes de este análisis.
9. **`kanji.v` está instanciado con `.reset(0)` y sin initializers** ⇒ es **imposible de simular**. En HW cuela por el power-up de Gowin. Fix de 4 líneas.
10. **`config1`/`config2` están llenos.** Bueno saberlo antes de prometer el siguiente toggle.
11. ⚠️ **Higiene de release:** `mi_release/**/pack_bios_V5*.bin` contiene BIOS + fuente kanji **con copyright**. Que no se cuele en un release público.

---

## 5. Licencias y atribución

**Conclusión jurídica, verificada por los cinco frentes de forma independiente:**

> **WebMSX NO tiene licencia.** `GET /repos/ppeccin/WebMSX/license` devuelve **404**. No hay `LICENSE` en la raíz, ni en `doc/`, ni en `src/`, ni en `release/stable/6.0/standalone`. `package.json` no tiene campo `license`. Cada `.js` dice *"See license.txt distributed with this file"* — y **ese `license.txt` no existe** en el repositorio (buscado también por code-search: 0 resultados). El **issue #4**, abierto desde 2016, confirma que el autor pide que se le contacte para permisos.

**Por defecto, sin concesión expresa, eso significa todos los derechos reservados.** Regla operativa para el MSXimus:

- ❌ **Cero copia de código de WebMSX.** Ni una función, ni una tabla transcrita literalmente, ni "inspirada muy de cerca". Tampoco empaquetarlo como companion.
- ✅ **Sí se puede leer y documentar el comportamiento.** Todo lo que necesitamos está además en **fuentes abiertas y en hardware documentado**, y de ahí es de donde hay que re-derivarlo:
  - Kanji $D8–$DB → **MSX Datapack** (y nuestro `kanji.v` viene de ESE Artists' factory, no de WebMSX).
  - ASCII16-X → **grauw.nl**.
  - NEO mapper y la firma de tipo de ROM → **MSXgl / aoineko.org**.
  - Teclado → **USB HID Usage Tables** + keymatrix de grauw/MAP. Las 6 celdas del delta es-ES se re-derivan, no se copian.
- ✅ **Para código real, la fuente correcta es openMSX (GPL)** — no WebMSX. (Con la cautela habitual: la GPL es vírica; nuestro `scan_rom` ya viene de esa tradición.)
- 📝 **Atribución que debe aparecer en el README y en los créditos del MSXimus** (que ya están pendientes para la publicación):

  > *Algunas ideas de interfaz y de detección de formatos han sido inspiradas por el estudio del comportamiento de **WebMSX** (© Paulo Augusto Peccin). **No se ha utilizado ningún código de WebMSX** en este proyecto.*

- ℹ️ Nota de coherencia: `kanji.v` es **BSD-3 no comercial** (ESE Artists' factory, 2006) — ya está en el árbol y su licencia debe figurar en los créditos junto al resto.

**Valor real de este apartado:** queda cerrado y documentado, con evidencia reproducible, que WebMSX no se puede copiar. Eso evita un problema serio si alguien —hoy o dentro de un año— hubiera tirado de copy-paste "porque es open source". No lo es.

---

## Resumen en una línea

Con 2.946 CLS libres y ~60 bytes de menú, lo correcto es cobrar primero **todo lo que cuesta 0 CLS** (kanji ya está hecho, BIOS española, detección por firma, R-Type), colar **un solo paquete de ≤30 CLS** en la siguiente build (teclado ES Fase 1 + NEO/ASCII16-X), decir **no** al TurboR con el número delante (déficit de 1.400–4.400 CLS) — y aceptar que el siguiente salto de funcionalidad no lo da la FPGA, lo da el **frontend del ESP32**.
