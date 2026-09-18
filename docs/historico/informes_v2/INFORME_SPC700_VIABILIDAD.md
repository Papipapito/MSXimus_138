# Estudio de viabilidad: audio SNES (SPC700 + S-DSP, "SHVC-SOUND") en el MSXimus

**Fecha:** 27/07/2026 · **Base:** build _157 (GW5AT-60, Tang Console 60K) · **Método:** investigación web + clon de SNESTang + **síntesis de humo real** con Gowin 1.9.11.03 Education contra la GW5AT-LV60PG484AC1/I0 (el chip exacto del MSXimus), usando el mismo patrón de harness que `fpga/opl4_20k_est/opl4_est_top.v`.

---

## 0. Veredicto en una pantalla

| | LUT+ALU | FF | CLS | BSRAM | DSP | Fuente |
|---|---|---|---|---|---|---|
| **APU SNES completo** (S-SMP+SPC700+timers+IPL + S-DSP) | **4.733** | **1.725** | **3.062** | **7** | **12** | síntesis de humo (medida, no estimada) |
| Variante sin REGRAM/BRR_BUF en BSRAM | 4.773 (+95 RAM16) | 1.745 | 3.303 | 5 | 12 | síntesis de humo v2 |
| Pegamento de integración (interfaz MSX + shim ARAM + resampler 32→44,1k) | ~400–750 | ~300 | **~250–450** | 0 | 1–2 | estimación por estructura |
| **Hueco libre en la _157** | — | — | **3.363** (11%) | **1** | 103 | informe PnR _157 |

- **Escenario A — añadirlo a la _157 tal cual: NO CABE.** Aritméticamente necesita ~3.3–3.7K CLS contra 3.363 libres (98–110%), y a 89% de CLS el rutado ya se muere (la lección de los 3 builds clavados en Routing Phase 1). Además faltan **6 bloques BSRAM** (necesita 7, hay 1). Veredicto claro: no.
- **Escenario B — build variante sin OPL4 (FM+wave): SÍ CABE, con fontanería de BSRAM.** El OPL4 solo mide **10.715 lógica / 3.218 FF / 6.440 CLS / 2 pROM / 1,5 DSP** (informe real `opl4_20k_est/rpt_v1_opl4_solo.txt`). Quitarlo deja el core en ~68% CLS; añadir APU+pegamento lo devuelve a **~79–81% CLS** — zona confortable, por debajo del umbral de dolor. Queda un **déficit de 1–2 bloques BSRAM** que hay que rascar de otro sitio (detalles en §5).
- **Escenario C — Tang Console 138K (GW5AST-138): sobra todo** (2,3× LUTs, 340 BSRAM vs 118, 298 DSP). Cabe la _157 completa + APU + margen. Y además el chasis está probado: SNESTang/TangCore ya corren la SNES *entera* en esa familia.
- **Bonus de credibilidad:** SNESTang tiene proyecto oficial para la **Tang Console 60K** (`snestang_console60k.gprj`) — este mismo APU cierra timing y suena en este mismo silicio, dentro de una SNES completa.

---

## 1. El cartucho "SHVC-SOUND": qué es y qué contrato impone

### 1.1 Qué es SHVC-SOUND

**"SHVC-SOUND" es la denominación de Nintendo del módulo de sonido de la Super Famicom** (SHVC = Super Home Video Computer, el prefijo de placa de la SFC). En las SFC tempranas es una **placa hija extraíble** que contiene el subsistema de audio completo:

- **S-SMP** (Sony SPC700): CPU de sonido de 8 bits a 1,024 MHz efectivos, con 4 puertos de E/S hacia el host, 3 timers y una **IPL ROM de 64 bytes**.
- **S-DSP**: 8 voces BRR (ADPCM 4:1), ADSR, eco FIR de 8 taps, pitch modulation, ruido; salida estéreo 16 bits a **32 kHz**.
- **64 KB de ARAM** (PSRAM) compartida SMP↔DSP, y DAC + ópamps.
- Cristal de **24,576 MHz** (32 kHz × 768).

Fuentes: [SHVC-SOUND — SNESdev Wiki](https://snes.nesdev.org/wiki/SHVC-SOUND), [S-SMP — SNESdev Wiki](https://snes.nesdev.org/wiki/S-SMP).

### 1.2 Estado de la búsqueda del cartucho MSX

**Honestidad primero: no he localizado ninguna página, repo ni producto indexado que documente un cartucho MSX llamado "SHVC-SOUND".** He barrido:

- Los **39 repos de hra1129 (HRA!/t.hara)** vía API de GitHub: nada de SNES/SPC700/SHVC (sí V9968_Cartridge, Y8960_Cartridge, TangCartMSX…). Tampoco en `hra1129.github.io` ni en el árbol RTL de TangCartMSX.
- Búsqueda global de repos GitHub con "SHVC": nada MSX.
- msx.org (wiki, foro, noticias), búsquedas en japonés (スーファミ音源 カートリッジ MSX, SHVC-SOUND MSX スロット): nada.

Si HRA! (u otro) lo ha enseñado, habrá sido en X/Twitter o en un evento y aún no está indexado. **Lo que sí es seguro es la naturaleza del bicho**: la familia de proyectos que montan el módulo SHVC-SOUND real en otro host es conocida y todos usan la misma interfaz, porque *el módulo no tiene otra*:

- [oykenkyu (oy, @0x6f_0x79): SHVC-SOUND + Arduino, MIDI](https://oykenkyu.blogspot.com/2024/09/snes-spc700.html) (y su [artículo de 2021](https://oykenkyu.blogspot.com/2021/12/snes-spc700-midi.html))
- [NS-Koubou: SHVC-SOUND conectado al PC](https://www.ns-koubou.com/blog/2017/04/11/snesapu/)
- [raphnet: SNES APU on a PC](https://www.raphnet.net/electronique/snes_apu/snes_apu_en.php)
- [MIDIbox SNES APU](https://www.midibox.org/dokuwiki/doku.php?id=midibox_snes_apu), Super MIDI Pak (comercial)

Un cartucho MSX de esta familia = módulo SHVC-SOUND real (SPC700+S-DSP físicos, cosechados de una SFC temprana) + latiglue al slot MSX + salida de audio analógica. **No es FPGA.** Eso define exactamente el contrato a clonar.

### 1.3 El contrato: 4 puertos + protocolo IPL

El SPC700 solo habla con el mundo por **4 puertos de 8 bits** (lado host: $2140–$2143 en la SNES; lado SPC: $F4–$F7). Un cartucho MSX los mapea a 4 direcciones (en E/S o en la página del slot; sin el doc del cartucho real, la implementación debe dejar el decode configurable — en el MSXimus es un mux de 4 bytes, trivial).

Protocolo de arranque (IPL ROM, 64 bytes — el estándar de toda la familia):

1. Tras reset, el SPC700 escribe **$AA en puerto 0 y $BB en puerto 1** ("ready").
2. El host escribe dirección destino en puertos 2–3, **$01 en puerto 1** (modo transferencia) y **$CC en puerto 0**; el SPC ecoa $CC.
3. Bytes de datos por puerto 1, con contador incremental en puerto 0 como handshake (el SPC ecoa cada índice).
4. Nuevo bloque o salto a ejecución: dirección en 2–3, puerto 1 = 0 → jump.

Para reproducir un SPC (música extraída de juegos) hay además que restaurar los registros del DSP con una secuencia bootstrap — técnica bien documentada por raphnet/MIDIbox/oykenkyu. **Software MSX específico: no he encontrado ninguno publicado** (ni players ni demos); habría que escribir/portar un player (subir 64 KB por 4 puertos a velocidad Z80 tarda del orden de segundos — asumible).

**Para el MSXimus la compatibilidad es barata:** el core FPGA que se propone (SMP de SNESTang) **ya incluye la IPL ROM de 64 bytes como `localparam` en LUTs** y el comportamiento exacto de los 4 puertos. Cualquier software escrito para un cartucho SHVC-SOUND real funcionaría contra el clon si el mapeo de puertos coincide.

---

## 2. Cores RTL disponibles y licencias

| Core | Lenguaje | Licencia | Notas |
|---|---|---|---|
| **[gyurco/SNES_FPGA](https://github.com/gyurco/SNES_FPGA)** (srg320 + gyurco, MiST) | VHDL | **GPL-3.0** | El origen: S-SMP/SPC700/S-DSP de Sergiy Dvodnenko (srg320) |
| **[SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer)** | VHDL | **GPL-3.0** | La rama MiSTer del mismo core |
| **[nand2mario/snestang](https://github.com/nand2mario/snestang)** | **Verilog/SV** | **GPL-3.0** | **El candidato.** Port a Gowin del core de srg320; APU reescrito en Verilog (`smp.v`, `dsp.v`, `spc700/*`); **proyectos oficiales para Tang Console 60K y 138K**; sintetiza tal cual con GowinSynthesis 1.9.11.03 (comprobado hoy) |
| TangCore (nand2mario) | — | GPL-3.0 | El multi-core de la Console 60K; incluye la SNES → prueba viviente en placa |

Puntos clave:

- **Licencia:** GPL-3.0 en toda la cadena. El MSXimus publica GPLv3 → **compatible sin fricción**; no hace falta permiso (sí atribución y fuente, como ya hace el proyecto). La convivencia con el módulo V9968 no-comercial es exactamente la misma situación que ya existe hoy con el resto del core — añadir más GPLv3 no cambia nada.
- **Precedente de autor:** srg320 es el mismo autor del YMF278B.sv al que ya se pidió permiso para el OPL4/MoonTANG. Buen karma acumulado; para este código GPL basta el crédito.
- **Calidad:** el S-SMP/S-DSP de srg320 es el que usa MiSTer para toda la biblioteca SNES — calidad de referencia, ciclo-aproximado y batalladísimo.
- **Detalle de SNESTang útil para nosotros:** el APU corre del reloj maestro (~21,6 MHz) con *clock enables* (DSP activo 1 de cada 4 ciclos; SMP en el subslot 3) y una señal `AUDIO_EN` que **pausa el APU para clavar la tasa efectiva a 32 kHz** — es decir, el core es *elástico*: tolera stalls. Esto simplifica reloj y memoria (ver §4).

---

## 3. Los números medidos (síntesis de humo real)

Harness `spc_est_top.v` (patrón idéntico a `opl4_est_top.v`: entradas por shift-register desde 1 pin, salidas XOR-reducidas a 1 pin, ARAM como puerto externo, debug podado), device **GW5AT-LV60PG484AC1/I0** rev B, `gw_sh` 1.9.11.03 Education, `run syn` + `run pnr`. Artefactos en `scratchpad/spc700/` (`est/`, `rpt_v1_apu_bsram.txt`, `rpt_v2_apu_distram.txt`, `rsc_v1_apu_bsram.xml`).

### 3.1 APU completo (v1, tal cual viene)

```
Logic    4823/59904 (8%)   = 4065 LUT + 668 ALU + 15 SSRAM(RAM16)
Register 1725 FF
CLS      3062/29952 (10,2%)
BSRAM    7/118  (1 SDPB + 1 DPB + 1 pROM + 4 pROMX9)
DSP      12/118 (12× MULTALU27X18)
```

### 3.2 Desglose por módulo (del XML de síntesis)

| Módulo | LUT | ALU | FF | BSRAM | DSP |
|---|---|---|---|---|---|
| S-SMP total (SPC700 + timers + puertos + IPL) | 1.287 | 125 | 384 | 4 (microcódigo, pROMX9) | 0 |
| — de los cuales SPC700 (CPU) | 958 | 106 | 233 | 4 | 0 |
| S-DSP total (+CEGen) | 2.648 | 526 | 1.315 | 3 (GTBL pROM + REGRAM + BRR_BUF) | 12 |

### 3.3 Variante v2 (REGRAM y BRR_BUF a RAM distribuida, `syn_ramstyle="distributed_ram"`)

```
Logic    5343 (4107 LUT + 666 ALU + 95 RAM16) · FF 1745
CLS      3303 (+241 vs v1)
BSRAM    5/118 (solo ROMs: GTBL 512×12 = 1 pROM; microcódigo 2048×31 = 4 pROMX9)
```

El microcódigo son 63,5 Kbit — 4 bloques de 18 Kb es su mínimo físico; forzarlo a LUTs costaría ~2K CLS más (mala idea). La GTBL (6 Kbit) sí podría pasarse a lógica reescribiendo su lectura (~+200 CLS) para bajar a 4 BSRAM.

### 3.4 Referencia OPL4 (para el intercambio)

Del informe real del proyecto (`fpga/opl4_20k_est/rpt_v1_opl4_solo.txt`, GW2AR-18, misma edición de herramientas): **OPL4 completo (FM OPL3 + motor PCM wave + shim SDRAM) = 10.715 lógica (7.157 LUT+ALU + 593 RAM16) / 3.218 FF / 6.440 CLS / 2 pROM / 3 MULT18X18.** La arquitectura CLS (2 LUT4/slice) es análoga en GW5A; en el MSXimus a su densidad de empaquetado real (~1,53 lógica/CLS) quitar el OPL4 libera del orden de **6–7K CLS (~21% del chip)**, 2 BSRAM y ~1,5 DSP.

---

## 4. Integración en el MSXimus

### 4.1 ARAM (64 KB): SDRAM del dock, ventana estilo wave-port — no DDR3

- **BSRAM descartada de raíz** (117/118): 64 KB serían 32 bloques.
- **SDRAM: el patrón ya existe y está de guardia.** `wave_sdram.v` documenta la doctrina: el puerto wave de `memory.v` roba solo turnos vacíos de CPU, handshake toggle+3FF en dominios de la familia del PLLA, y las filas 4096+ son físicamente inalcanzables por CPU/VDP. La ARAM son 64 KB dentro de ese mismo espacio. En el escenario B (sin OPL4) **el puerto wave queda huérfano y la ARAM lo hereda casi gratis** (shim más simple: un solo cliente de 8 bits, porque el S-DSP arbitra internamente los accesos del SMP — un único puerto externo `RAM_A/RAM_D/RAM_Q`).
- **Ancho de banda:** 1 byte por slot de DSP (1 de cada 4 ciclos APU) ≈ **6,2 MB/s pico a 24,576 MHz, SMP incluido** — ruido para la W9825G6KH a 108 MHz.
- **Latencia: el punto fuerte.** SNESTang ya sirve la ARAM desde SDRAM (banco 2 del controlador de 3 canales, req/ack a ~86 MHz) en placas Tang — precedente directo. Y como todo el APU funciona por *clock enables* con pausa (`AUDIO_EN`), un turno SDRAM que llegue tarde se absorbe **estirando el CE** en vez de corromper audio; solo la media de 32 kHz debe mantenerse (governor).
- **DDR3: no.** Su único cliente es la VRAM del V9968 y el refresh se acaba de estabilizar (_156); la saga _94–_103 ya demostró que esta DDR3 es analógicamente marginal para clientes pequeños. La SDRAM es la casa natural.

### 4.2 Reloj

Dos opciones, ambas baratas:
1. **PLLA libre** (hay 2 en la _157) generando 24,576 MHz exactos → 32.000,0 Hz.
2. **Sin PLL nuevo:** correr el APU de un dominio existente con enables + governor de 32 kHz (lo que hace SNESTang a 21,6 MHz). Coste: ~50 LUT.

### 4.3 Mezcla de audio

El S-DSP saca estéreo 16 bits a 32 kHz; el HDMI del MSXimus va a **44,1 kHz** (`video720/msx2hdmi.sv`, `AUDIO_RATE=44100`). Hace falta un interpolador lineal 32→44,1k (1–2 MULT + ~150–250 LUT) antes de entrar al mixer como una fuente estéreo más. (SNESTang lo esquiva emitiendo HDMI a 32 kHz nativos — en el MSXimus no es opción, el resto de fuentes ya viven a 44,1k.)

### 4.4 Interfaz MSX

4 latches de 8 bits + decode (E/S o slot, configurable para casar con el cartucho real cuando se documente): **~60–150 LUT**. La IPL ROM y la semántica de puertos ya vienen dentro del SMP.

**Pegamento total estimado: ~400–750 LUT / ~250–450 CLS / 0 BSRAM / 1–2 DSP.**

---

## 5. El veredicto, escenario a escenario

### Escenario A — sobre la _157 tal cual: **NO**

| Recurso | Libre (_157) | Necesario | Balance |
|---|---|---|---|
| CLS | 3.363 (11%) | ~3.312–3.753 (APU 3.062–3.303 + glue 250–450) | **98–112% del hueco** |
| BSRAM | 1 | 7 (o 5 en v2) | **faltan 4–6** |
| DSP | 103 | 13–14 | sobra |
| PLLA | 2 | 0–1 | sobra |

Aunque la aritmética de CLS rozara el 100%, a 89% de ocupación el rutador ya falla (evidencia empírica del propio proyecto). Y la BSRAM lo remata. **No cabe.**

### Escenario B — variante .fs sin OPL4 (FM+wave): **SÍ, con 1–2 bloques BSRAM por rascar**

| Recurso | Cálculo | Resultado |
|---|---|---|
| CLS | 26.589 − ~6.400 (OPL4) + ~3.300 (APU v2) + ~400 (glue) | **≈ 23.900/29.952 ≈ 80%** ✔ (de 89% a ~80%: incluso mejora la rutabilidad actual) |
| BSRAM | 117 − 2 (OPL4) + 5 (APU v2) | **120/118 → déficit 2** · con GTBL a lógica (+200 CLS): 119 → **déficit 1** |
| DSP | 15 − 1,5 + 12 + 1 (resampler) | 26,5/118 ✔ |
| PLLA | 6 − (relojes OPL4 que se liberen) + 0–1 | ✔ |

El déficit de 1–2 BSRAM es fontanería, no muro: candidatos a rascar son buffers/tablas hoy en BSRAM que pueden ir a la SDRAM (que gana 4 MB libres al desalojar la wave del OPL4) o a RAM distribuida. Es la misma clase de cirugía que ya se hizo con la wave. **Trade-off del producto:** un .fs "SNES-audio" pierde OPL4/MoonSound; son personalidades alternativas del mismo cartucho, como ya se contempla en el roadmap de builds variante.

### Escenario C — Tang Console 138K (GW5AST-138): **holgura total**

138.240 LUT4 (2,3×), **340 bloques BSRAM** (2,9×), 298 DSP, 12 PLL ([specs](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/), [Sipeed wiki](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html)). La _157 completa (26,6K CLS) + APU + pegamento ≈ 30K CLS sobre ~69K disponibles ≈ **43%**. Cabrían OPL4 **y** SNES-audio a la vez, con margen para el roadmap (Y8950 ADPCM, V9990…). Si el SNES-audio se quiere *además* de todo lo demás y sin sacrificios, este es el camino.

### Riesgos y letra pequeña (honestidad)

1. **El CLS medido es en chip vacío**: dentro de un core al 80% el empaquetado real puede variar ±10%; el invariante duro es 4,8–5,3K lógica + 1,7K FF. El margen del escenario B (~5–6K CLS de aire) absorbe esa varianza de sobra.
2. **El déficit BSRAM del escenario B es real** hasta que se identifiquen los 1–2 bloques a desalojar (inventario pendiente sobre el rpt de la _157).
3. **Compatibilidad con el cartucho real**: sin doc del SHVC-SOUND-para-MSX, el mapeo de los 4 puertos es una incógnita de 1 registro de configuración; el protocolo IPL en sí es estándar y ya está en el RTL.
4. **No existe software MSX conocido** que explote esto todavía: el player MSX (upload IPL + bootstrap DSP para .spc) es un proyecto de software aparte, factible pero no gratis.
5. La conversión 32→44,1 kHz introduce el clásico compromiso de interpolación; lineal es más que digno para BRR a 32 kHz (gauss ya interpola aguas arriba).

---

## 6. Artefactos generados (reproducibilidad)

En `scratchpad/` de esta sesión:
- `spc700/est/spc_est_top.v` + `build_spc_est.tcl` — harness y flujo (gw_sh, ~1 min por pasada).
- `spc700/rpt_v1_apu_bsram.txt` — PnR APU v1 (3.062 CLS / 7 BSRAM).
- `spc700/rpt_v2_apu_distram.txt` — PnR APU v2 (3.303 CLS / 5 BSRAM).
- `spc700/rsc_v1_apu_bsram.xml` — desglose jerárquico SMP/DSP.
- `snestang/` — clon (GPL-3.0, commit HEAD de hoy; `src/dsp.v` restaurado a pristino tras las pruebas).

## 7. Fuentes

- [SHVC-SOUND — SNESdev Wiki](https://snes.nesdev.org/wiki/SHVC-SOUND) · [S-SMP — SNESdev Wiki](https://snes.nesdev.org/wiki/S-SMP) (módulo, puertos, IPL)
- [oykenkyu: SNES APU/SPC700 con SHVC-SOUND (2024)](https://oykenkyu.blogspot.com/2024/09/snes-spc700.html) · [ídem 2021](https://oykenkyu.blogspot.com/2021/12/snes-spc700-midi.html) · [NS-Koubou](https://www.ns-koubou.com/blog/2017/04/11/snesapu/) · [raphnet SNES APU on PC](https://www.raphnet.net/electronique/snes_apu/snes_apu_en.php) · [MIDIbox SNES APU](https://www.midibox.org/dokuwiki/doku.php?id=midibox_snes_apu)
- [nand2mario/snestang](https://github.com/nand2mario/snestang) (GPL-3.0; `smp.v`, `dsp.v`, `spc700/`, `sdram_cl2_3ch.v` con ARAM en banco 2, `snestang_console60k.gprj`) · [gyurco/SNES_FPGA](https://github.com/gyurco/SNES_FPGA) (GPL-3.0, srg320) · [MiSTer-devel/SNES_MiSTer](https://github.com/MiSTer-devel/SNES_MiSTer) (GPL-3.0)
- [GitHub hra1129 (HRA!)](https://github.com/hra1129) — 39 repos auditados, sin proyecto SHVC/SNES
- [CNX: Sipeed Tang Console 60K/138K](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/) · [Sipeed wiki GW5AST-138](https://wiki.sipeed.com/hardware/en/tang/tang-mega-138k/mega-138k.html)
- Locales: `fpga/opl4_20k_est/rpt_v1_opl4_solo.txt` (OPL4 solo), `fpga/src/wave_sdram.v` (doctrina wave-port), `fpga/video720/msx2hdmi.sv` (44,1 kHz), informe PnR _157 (línea base facilitada).
