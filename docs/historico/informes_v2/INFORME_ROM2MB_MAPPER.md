# Caso "ROM 2MB" (Aleste 2 v8 by Ricbit) — Informe de investigación

Fecha: 2026-07-27 · ROM: `C:\Users\alber\Downloads\Aleste 2 - Compile (1989) [ROM Version] [v8 by Ricbit] [3275].rom`
(2.097.152 bytes · SHA1 `e93d0840c59c6eba273df546d22148d486a150a6` · cabecera AB, INIT #4010)

## Resumen ejecutivo

1. **La ROM es DUAL-MAPPER**: el loader de Ricbit sondea el cartucho al arrancar y funciona
   tanto en **Konami-SCC ("Konami8")** como en **ASCII16** (las dos cadenas están en el binario
   y el probe está desensamblado más abajo). El forzado ASCII16 de Albert **era válido**, y el
   fix b6ab040 es exactamente lo que le faltaba: **post-fix debería funcionar en placa tanto
   forzando ASCII16 como forzando SCC**.
2. **Canon openMSX**: la softwaredb tiene ESTE dump exacto (por SHA1) como `KonamiSCC`.
   Cargada en openMSX arranca la bienvenida ("Konami8 mapper"), y tras SPACE avanza al intro
   en SCREEN 5 y sigue ejecutando estable (verificado ~2 min de emulación).
3. **La heurística del menú eligió Konami4 por ruido**: reproducida byte a byte sobre el
   fichero real → Konami=5, ASCII16=4, ASCII8=4(−1 quirk)=3, SCC=2 en los primeros 256 KB.
   Irónicamente 4 de los 5 puntos "Konami" vienen del propio probe dual del loader (escrituras
   a #6000, que la tabla openMSX acredita a Konami+A8+A16) más 2 de ruido de datos. **No hay
   arreglo a coste 0**; el parche robusto propuesto (promocionar Konami→SCC si la ROM es
   grande) cuesta **+24 bytes medidos** y hay **84 libres** (ensamblado verificado).
4. **Cobertura del fix b6ab040**: la carga SD→megaram va por los registros **Konami-SCC**
   (#5000, modo SWIO #0F) con segmento de 8 bits → **nunca tuvo truncado** (por eso la
   bienvenida salía: los 2 MB estaban bien cargados). Tras el fix **no queda ningún registro
   de banco truncado** en `megaram.v`: los cuatro modos direccionan los 2 MB físicos completos.

---

## (a) Canon: qué dice openMSX de esta imagen

### Base de datos

`C:\Program Files\openMSX\share\softwaredb.xml` contiene el dump por SHA1:

```xml
<title>Aleste 2</title> <genmsxid>1246</genmsxid> ... <company>Compile</company>
<dump><megarom><type>KonamiSCC</type><hash>e93d0840c59c6eba273df546d22148d486a150a6</hash></megarom></dump>
```

→ el romtype canónico de openMSX para este fichero es **KonamiSCC** (no ASCII16). Al insertarla
(MCP mcp-openmsx, C-BIOS MSX2+), el slot map la identifica como "Aleste 2" (match de db).

### Ejecución verificada

- Bienvenida (SCREEN 1, leída con screenGetFullText):
  `Aleste 2 ROM version v8 / Konami8 mapper / Please do not sell. / Press any key to start.`
- SPACE (por sendKeyCombo) → SCREEN 5, PC ejecutando código del juego, VRAM llenándose
  progresivamente (intro estilo anime de Compile, con fundidos a negro entre escenas).
  Estable durante ~2 minutos. Las capturas de pantalla del MCP siguen rotas
  (EPERM creando `share\screenshots` bajo Program Files); la evidencia es VRAM/PC/modo.
- Dato clave: a los pocos segundos **las 4 páginas del Z80 están en RAM (slot 3.2)** — es la
  conversión de un juego de DISCO: el juego corre desde RAM y el mapper solo se usa como
  "almacén" de 2 MB al que el loader va a buscar datos.

### La ROM es dual-mapper (desensamblado del loader)

El binario contiene AMBAS cadenas: `"Konami8 mapper"` (@0x261A) y `"Ascii16 mapper"` (@0x262C).
El boot (file 0x0010 = CPU #4010) copia un probe a RAM #F100 y bifurca por el flag #ED51:

**Probe (#F129, file 0x25A8):**
```asm
    ld  a,1
    ld  (#6000),a      ; escribe "banco 1" en el registro ASCII16
    ld  a,(#4000)
    cp  'A'            ; ¿sigue viéndose la cabecera 'AB'?
    jr  z,es_konami8   ; sin cambio -> el 6000 no es registro -> Konami8
    ld  a,1
    ld  (#ED51),a      ; cambió (file 0x4000 = EB, boot sector) -> ASCII16
es_konami8:
    xor a
    ld  (#6000),a      ; restaura
```

**Stub de banqueo (#F140, file 0x25BF)** — A = banco de 16 KB (0..127):
```asm
    bit 0,(#ED51)
    jr  nz,a16
    add a,a            ; Konami8 = layout Konami-SCC:
    ld  (#5000),a      ;   banco 8K par   -> reg 4000-5FFF
    inc a
    ld  (#7000),a      ;   banco 8K impar -> reg 6000-7FFF
    ret
a16:ld  (#6000),a      ; ASCII16: banco 16K directo (USA EL BIT 6 para el 2º MB)
    ret
```

### Veredictos (a)

- **"Konami8" de Ricbit = Konami-SCC** (registros #5000/#7000): coincide con la db de openMSX.
- **El forzado ASCII16 de Albert queda VALIDADO**: el loader lo detecta y usa `LD (#6000),A`
  con bancos 0..127 — exactamente el camino que el bug #24 truncaba (bit 6) a partir del
  2º MB. Bienvenida (bancos <64) OK + reset al pulsar SPACE (bancos ≥64 aliasados): la
  historia del bug #24 queda CONFIRMADA de punta a punta.
- **Por qué Konami4 (elección del menú) daba basura**: el probe escribe a #6000, que en
  Konami4 SÍ es registro (banco 8K de 6000-7FFF). El `xor a` final deja ese banco a 0
  (en vez del 1 de reset), así que hasta los textos de la bienvenida se leen del banco
  equivocado → basura inmediata. Y el stub (#5000/#7000) cae en direcciones que Konami4
  ignora → nada banquea.
- **Qué debe verse tras el fix** (con SCC o con ASCII16): bienvenida → SPACE → negro unos
  segundos → intro SCREEN 5 (secuencia con fundidos) → título → juego. En openMSX
  (KonamiSCC) así ocurre.

---

## (b) La heurística de detección del menú

Fuente: `C:\Users\alber\proyectosAI\msx\MSXnano\fpga\src\msxnano_menu\src\menu_main.asm`
(`classify_addr` L1320, `scan_sector_mapper` L1381, `scan_rom` L1407 —tope 512 sectores =
**256 KB**—, `decide_mapper` L1482, `detect_mapper` L1522). El MSXimus no tiene copia propia:
el menú se compila en el repo MSXnano y va embebido en `fm_logo_menu_60k_*.bin`.

### Reproducción (simulación fiel en Python sobre el fichero real)

Script: `scratchpad\rom2mb\sim_detect.py` (del agente anterior, verificado contra el asm:
sectores de 512 con bc=510, tabla de créditos openMSX, quirk ascii8--, empate ganado por el
iterado más tarde en orden SCC→Konami→A8→A16).

| Ámbito | SCC | Konami | A8 (tras −1) | A16 | Elección |
|---|---|---|---|---|---|
| Menú: primeros 256 KB | 2 | **5** | 3 | 4 | **Konami4** ❌ |
| Fichero entero (2 MB) | 6 | **6** | 3 | 4 | **Konami4** (empate, gana el iterado después) ❌ |

### Por qué salió Konami

Los conteos son minúsculos porque el juego corre desde RAM y solo el stub del loader banquea.
Desglose de los primeros 256 KB: el propio loader aporta `32 00 60`×3 (probe: crédito
Konami+A8+A16 cada uno), `32 00 50`×1 y `32 00 70`×1 (stub: crédito SCC; el 7000 también
A8+A16) → SCC=2, Konami=3, A8=4, A16=4. Los **2 puntos restantes de Konami son bytes de
DATOS** (32 xx 40/80/A0 casuales) que rompen el empate a favor de Konami4: 5>4. La detección
por contenido pierde por ruido, no por lógica.

- `MAP_THRESH equ 2` (L387) existe pero **no se usa en ningún sitio**; aplicarlo tampoco
  ayudaría (5≥2).
- Reordenar el desempate: no ayuda (5>4, no hay empate en 256 KB).
- Escanear el fichero entero: tampoco (empate 6-6 → Konami) y costaría ~24 s a ~170 sect/s.
- El tag del nombre no aplica: `override_mapper_by_name` solo corre si el scan no vio NADA,
  y este nombre no lleva tag reconocido (`[3275]` no matchea).

→ **No existe arreglo a coste 0 bytes.**

### Parche propuesto (concreto, ensamblado y medido)

Regla: *si el scan dice Konami4 y la ROM es grande, promocionar a Konami-SCC*. No existe
ningún Konami4 comercial >256 KB (los megaroms grandes "estilo Konami" son conversiones para
MegaFlashROM SCC+ = Konami-SCC, como esta). En `detect_mapper`, tras `call decide_mapper`
(L1541):

```asm
	call decide_mapper				; MAPPER_ID por CONTENIDO (estilo openMSX)
	ld   a, (MAPPER_ID)
	cp   MAP_KON_ID					; ¿el scan dijo Konami4?
	jr   nz, .det_kok
	ld   hl, (BR_REC)				; Konami4 >256KB no existe: los megaroms
	ld   de, SIZE_OFF+2				; grandes "Konami" son conversiones MFR
	add  hl, de						; SCC+ (Konami-SCC), p.ej. Aleste2 v8 2MB
	ld   a, (hl)					; size[23:16]
	cp   5							; >= 320 KB -> promocionar a SCC
	jr   c, .det_kok
	ld   a, MAP_SCC_ID
	ld   (MAPPER_ID), a
.det_kok:
	ld   a, (MAPPER_ID)				; (línea original)
	or   a
	ret  nz
	jp   override_mapper_by_name
```

- **Coste medido: +24 bytes** (ensamblado real con el asmsx del repo sobre una copia en
  scratchpad: fin de código pasa de `#9FAC` a `#9FC4`).
- **Presupuesto: 84 bytes libres antes de #A000** → quedan **60** tras el parche.
- El desborde ya NO es silencioso: el guard `ds #A000-$` (L4826) hace FALLAR el ensamblado
  si el código pisa #A000 (comentario "GUARD anti-desborde", L4822).
- Umbral `cp 5` (≥320 KB): deja en paz los Konami4 reales (128/256 KB → byte=2/4) y captura
  cualquier conversión grande (esta ROM: byte=0x20). Cualquier corte en (256 KB, 512 KB]
  vale para todo el software conocido.
- Con el parche, esta ROM: scan→Konami(5) → 2 MB ≥ 320 KB → **SCC** → el probe del loader
  detecta "Konami8" y banquea por #5000/#7000 (8 bits completos en megaram.v) → funciona.

**Workaround hoy sin recompilar**: tecla **M** en el menú (cicla plain→Konami→SCC→A8→A16,
L2629) y elegir **SCC** — o ASCII16, que post-fix también vale para esta ROM dual.

---

## (c) Cobertura del fix b6ab040 (megaram.v post-fix)

Fichero: `C:\Users\alber\proyectosAI\msx\MSX_up\fpga\src\megaram.v` (commit `b6ab040`,
"v2.0.1 bug #24"). `megaram_addr` es de **21 bits = 2 MB físicos**; banco 8K = `{reg, addr[12:0]}`.

### Camino de CARGA: NO pasa por ASCII16 — ya estaba bien

`load_rom` (menu_main.asm L1637) pone la megaram en modo **Konami-SCC** por SWIO
(`out #40,#D4` + `out #41,#0F` = Slot2 Int SCC-I) y `write_sector_to_megaram` (L1596)
escribe cada segmento de 8K fijando el banco en el **reg SCC #5000** con `LOAD_SEG` de
**1 byte completo** (0..255 = 2 MB exactos), con write-enable por #7FFE (mode_a bit4;
apaga el write-enable ANTES de tocar el reg, coherente con el gating del RTL). El mapper
del juego se aplica DESPUÉS, al lanzar. → **La copia nunca truncó**: consistente con que
la bienvenida (datos del 1er MB correctamente cargados) siempre salió.

### Anchuras de banco por modo (post-fix)

| Modo (map_sel) | Registros | Anchura | Alcance | Veredicto |
|---|---|---|---|---|
| Konami4 (00) | 6000/8000/A000 (reg1-3; reg0 fijo=0) | 8 bits | 256×8K = 2 MB | ✅ |
| Konami-SCC (10) | 5000/7000/9000/B000 (reg0-3) | 8 bits | 2 MB | ✅ |
| ASCII8 (x1, bit1=0) | 6000/6800/7000/7800 | 8 bits | 2 MB | ✅ |
| ASCII16 (11) | 6000/7000 → `{cpu_dout[6:0], mitad}` | 7+1 bits | 128×16K = 2 MB | ✅ (el fix) |

- **No queda ningún truncado**: los cuatro modos cubren el límite físico completo.
- ASCII16 ignora `cpu_dout[7]`: irrelevante — un ASCII16 de 4 MB no cabe en los 21 bits
  físicos de todas formas.
- Ventana SCC (`megaram_reg2[5:0]==0x3F` abre 9800-9FFF): misma regla que openMSX
  (`(banco & 0x3F)==0x3F`), así que bancos 0x7F/0xBF/0xFF también la abren en ambos —
  **sin discrepancia** emulador/placa. A esta ROM ni le afecta (su stub solo usa reg0/reg1).

### Flecos menores (anotar, no urgentes)

1. **SRAM alta vs ROM de 2 MB**: la SRAM de cartucho vive en los 32 KB altos de la megaram
   (segmentos 252-255). Con una ROM que llene los 2 MB **y** `sram_cfg≠0` (solo si el menú
   activa SRAM por tag ASCII), la ventana SRAM taparía los últimos 32 KB de ROM. No afecta a
   este caso (sin tag → sram_cfg=0).
2. **ROMs >2 MB**: `LOAD_SEG` es de 1 byte → una imagen mayor de 2 MB envolvería y
   sobreescribiría el principio. Si algún día entra un 4 MB, capar la carga.
3. `MAP_THRESH` (L387) es código muerto — o usarlo o quitarlo (ojo: usarlo NO arregla este
   caso).

---

## Evidencias y artefactos

- `scratchpad\rom2mb\sim_detect.py` — simulación de la heurística (verificada contra el asm).
- `scratchpad\rom2mb\asm\menu_main.asm` — copia parcheada que ENSAMBLA (medición +24 bytes);
  el repo MSXnano **no se ha tocado**.
- `scratchpad\rom2mb\aleste2_2mb.rom` — copia de trabajo (el romInsert del MCP no traga
  rutas con espacios: «invalid command name "ROM"»).
- Desensamblados del probe/stub: offsets de fichero 0x0010-0x004F, 0x257F-0x25D1.
- openMSX: db match por SHA1 → KonamiSCC; ejecución estable post-bienvenida en SCREEN 5.

## Recomendaciones

1. **Probar en placa YA con la build del fix**: la misma ROM forzada a **ASCII16** (debería
   pasar de la bienvenida) y también forzada a **SCC** (equivalente a openMSX). Ambas deben ir.
2. Aplicar el parche del menú (+24 bytes, 60 de margen) en el repo MSXnano cuando se pueda
   tocar (hoy tiene trabajo sin committear).
3. Anotar los flecos (SRAM alta con ROMs de 2 MB, cap de carga >2 MB, MAP_THRESH muerto).
