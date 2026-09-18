# V9990 en el MSXimus (Tang Console 60K) — Estudio de viabilidad EN NÚMEROS

**Fecha:** 2026-07-27 · **Línea base:** build _157 (GW5AT-LV60PG484AC1/I0, informe PnR real)
**Método:** clones de tnCart/tnCartWonder + **síntesis de humo REALES con Gowin 1.9.11.03 Education (`gw_sh`) sobre el MISMO device** + sonda PnR de pares diferenciales en los pines PMOD + web.
Artefactos: `scratchpad/v9990/{smoke,smoke/nocmd,smoke_opl,smoke_ymf,probe}/impl/pnr/project.rpt.txt`.

---

## 0. Veredicto en una línea

**En el 60K con el MSXimus completo NO CABE** (déficit ≈ 2.600–6.300 CLS según variante, sobre 3.363 libres, y 0 BSRAM libres contra 21 que pide el core). La vía realista es la **Tang Console 138K ($99)**: todo el añadido entra al ~51% de CLS. El resto del diseño (VRAM en DDR3, HDMI por PMOD1 a 480p) **sí es viable y está verificado pieza a pieza** — ver §2–§4.

---

## 1. El core: tiny9990 (buppu3/tnCart, BSD-3)

- **Qué es**: `rtl/src/peripheral/video/tiny9990/` de [buppu3/tnCart](https://github.com/buppu3/tnCart) (clonado @ `f62511b`, 2024-11-16), 17 ficheros SV, 9.672 líneas. Autor Shinobu Hashimoto, **BSD-3-Clause** (compatible con los créditos previstos). El "tiny9990 de herraa1" es en realidad este core corriendo en la WonderTANG vía su port [herraa1/tnCartWonder](https://github.com/herraa1/tnCartWonder) (@ `d3a54f1`, 2025-10-02) — GW2AR-18 (el chip del TN20K, 20.736 LUT), lo que ya acotaba su tamaño.
- **Estado funcional (honesto)**: es un V9990 **parcial**. Según el README de tnCart NO implementa: modos **B0, B5 (640x400) ni B6 (640x480)** (la entrada `CLK_25M_EN` está marcada "未対応"/no soportada), cursor EOR, corrección de pantalla R#16, ni kanji-ROM. Corren "razonablemente" msx-samurai, los samples V9990 de MSXgl y la tech-demo de TINY. Nivel de compatibilidad claramente menor que el del V9968 respecto al V9938/58.
- **Salida de vídeo nativa**: **720x480 a ~27MHz de pixel clock, DVI** (README tnCart) — *exactamente el timing de la salida HDMI actual del MSXimus*.
- **Blitter (VDP cmds)**: opción de compilación `CONFIG::ENABLE_V9990_CMD`; el propio autor avisa de que dispara el tamaño.

### 1.1 Números REALES — síntesis de humo en GW5AT-60B con 1.9.11.03 Education

Standalone, `-verilog_std sysv2017`, sin SDC (números de ÁREA; el PnR terminó limpio, 0 errores):

| Configuración | Logic (LUT+ALU) | Registros | CLS | BSRAM | DSP |
|---|---|---|---|---|---|
| **tiny9990 CON blitter** | **9.569** (8.774 LUT + 795 ALU) | 4.766 | **6.216 (21%)** | **21** (8 SDPB + 9 DPB + 4 pROM) | 0 |
| **tiny9990 SIN blitter** | **5.964** (5.506 + 458) | 4.242 | **4.289 (15%)** | **17** | 0 |
| Δ blitter | +3.605 | +524 | +1.927 | +4 | — |

Desglose interno (XML de síntesis): el blitter (`u_blit`) son 4.355 LUT él solo (2.262 su FIFO, ya en registros); sprites (`u_sp`) 2.448 LUT + 4 BSRAM; puertos 434; timing 388.

**Los 21 BSRAM son "blandos"**: todas las memorias internas son diminutas (buffers de 16–64 entradas: 4 ROMs de bitmask del blitter, 4 de patrones/atributos de sprite, 3 shift-buffers, 2 line-buffer bitmap, 3 de paleta 64×16, 2 de decode) — suman ~10Kbit reales contra 378Kbit de capacidad ocupada (>97% desperdicio, culpa de los hints `syn_ramstyle="block_ram"` del fuente). **Cambiando los hints a distributed se van TODAS a SSRAM por ~+600–800 LUT** y el core pasa a 0 BSRAM. Imprescindible aquí: la _157 tiene BSRAM 117/118 = **0 bloques libres**.

- **Fmax**: sin SDC el smoke no lo valida, pero hay evidencia fuerte: herraa1 cierra **>108MHz con todas las opciones** en GW2AR-18 (fabric más lento que GW5A) — [hilo WonderTANG en msx.org, pág. 89](https://www.msx.org/forum/msx-talk/hardware/wondertang-who-wants-to-juice-up-your-msx?page=88).
- **Reloj**: dominio único con clock-enables (arquitectura tnCart: 107,4864MHz = 30×3,58 con ENs a 21,4772/14,3182MHz). Encaja con el dominio ~108MHz del MSXimus (ver §3.3).

### 1.2 Interfaz de VRAM y qué usa en la WonderTANG

- Interfaz: **slots de 32 bits, 19 bits de dirección (512KB)**, protocolo `RAM_REQ` (el sistema OFRECE un slot) + `RAM_ACK_n`, con rotación interna de 6 solicitantes (CPU/cmd, sprites, bitmap, patrón A, patrón B, refresh) en `t9990_ram.sv`.
- En tnCart/WonderTANG la VRAM vive en la **SDRAM de 32 bits embebida del GW2AR-18** (8MB), compartida con la RAM principal MSX vía `uma.sv` (slots UMA a 21,48MHz sobre reloj de 107,4864MHz, 5 ciclos por slot ≈ **46,5ns por acceso de 32 bits**).
- **Latencia tolerada**: el ACK debe llegar dentro del slot (~46,5ns) — el core NO tolera latencia DDR3 en crudo (§2.3). El glue MSX (puertos 60h-6Fh, WAIT_n) está resuelto en `cartridge_v9990.sv` (BSD-3, reutilizable).

---

## 2. VRAM en la DDR3 del SOM

### 2.1 Demanda del V9990 (peores modos)

Master clocks del V9990 ([Yamaha V9990 E-VDP-III Application Manual]: 21,47727MHz ó 14,31818MHz; 25,175MHz solo B5/B6): P1 dot 5,37MHz (2 capas+sprites), P2/B3 10,74MHz, B2 7,16MHz, B4 14,32MHz.

| Escenario | Slots/s × 4B | MB/s |
|---|---|---|
| **Techo duro tiny9990 hoy** (P1/P2/B1–B4: 1 slot 32b por ciclo master 21,4772MHz) | 21,48M × 4 | **85,9** |
| Techo si algún día implementara B5/B6 (25,175MHz) | 25,18M × 4 | 100,7 |
| Sostenido típico P1 (display 2 capas + 16 sprites/línea ≈ 700B/63,5µs + blitter) | — | ~15–40 |

### 2.2 Presupuesto DDR3

- Bus: 297MHz × 16b × 2 (DDR) = **1.188 MB/s** teóricos; −6,7% de refresh ≈ **1.108 MB/s efectivos**.
- Cliente actual (V9968): lecturas de línea display + lado CPU medido en juego ~60K lect + ~20K escr palabra/s (<1 MB/s el lado CPU) — marginal.
- **Ocupación añadida por el V9990: ≤ 85,9/1.108 = 7,8%** en el peor caso sostenido. En líneas de 128 bits secuenciales, ~7% de ocupación del puerto app (74,25MHz × 128b = 1.188 MB/s). **El ancho de banda NO es el problema — sobra más de un orden de magnitud.**

### 2.3 El problema real: LATENCIA, y su solución conocida

El slot del tiny9990 dura **46,5ns**; la línea de 128b en el backend actual tarda **~175ns** ida-vuelta (comentario de cabecera de `v9968_ddr3_backend.v`, CDC incluido). Un puente 1:1 slot→DDR3 NO cumple. La receta es la misma que ya ganó la guerra del V9968: **prefetch por streams + caché de línea** delante del core (los fetches de display PA/PB/SP/BP son secuenciales y predecibles → se rellenan por ráfagas adelantadas; el canal aleatorio CPU/blitter va con cola). Lección DEVCON aplicable: dimensionar la caché para que SAT/SPT/capas no colisionen.

**Coste del añadido en el backend** (`v9968_ddr3_backend.v`, hoy mono-cliente con canales A/B wv2 sobre clk_x1=74,25MHz):

| Pieza | Estimación |
|---|---|
| Extensión a 2º cliente (mux 128b, prioridades fijas V9968-display > V9990-display > V9990 blit/CPU, done-routing, colas 1–2 entradas, vacunas _87/_95/_100 heredadas) | ~500–800 logic |
| Shim V9990 (generador de slots + REQ/ACK + prefetch/caché de línea + CDC 108↔74,25) | ~1.500–2.000 logic |
| Caché/buffers (~2KB): **sin BSRAM libre → SSRAM** | +~1.000 logic |

### 2.4 Alternativa: ¿SDRAM del dock? — NO, con números

La W9825G6KH es de **16 bits** @108MHz = 216 MB/s brutos. Un slot de 32b son 2 beats + overhead de fila ≈ 5–6 ciclos aun con interleave de bancos → 21,48M slots × ~5,5 ciclos ≈ **118M ciclos/s > 108M disponibles: >100% del bus sin contar la RAM principal, la wave OPL4 ni el refresh**. tnCart solo puede hacerlo porque la SDRAM del TN20K es de **32 bits** (1 beat por slot). Habría que subir la SDRAM a ~150–166MHz por GPIO (el clk ya es "punto delicado" a 108). **Descartada; la DDR3 es el sitio.**

---

## 3. Segunda salida HDMI/DVI por PMOD

### 3.1 Pines: VERIFICADO con sonda PnR (1.9.11.03, device real)

Pinout PMOD del Console 60K (fuentes: cst de [C64Nano console60k](https://github.com/MiSTle-Dev/C64Nano) y comentarios `PMOD1_IOn` de [nestang console.cst](https://github.com/nand2mario/nestang)):
**PMOD1** = W19(IO0), W20(IO1), F19(IO2), F20(IO3), E22(IO4), D22(IO5), E21(IO6), D21(IO7) · **PMOD0** = V19, V18, G22, G21, E18, F18, B22, C22.

Sonda PnR (diseño dummy con IO_TYPE=LVCMOS33D, `scratchpad/v9990/probe/`): **los 8 IOs de PMOD1 forman EXACTAMENTE 4 pares A/B verdaderos del die**, adyacentes en el conector:

| Par | Sitio IO | Banco | Nota |
|---|---|---|---|
| W19/W20 | IOB93[A]/[B] | 8 | además GCLKT_9/GCLKC_9 |
| F19/F20 | IOT124[A]/[B] | 2 | |
| E22/D22 | IOT140[A]/[B] | 2 | |
| E21/D21 | IOT138[A]/[B] | 2 | |

(PMOD0 también son 4 pares: V18/V19=IOB81, G21/G22=IOT144, F18/E18=IOT117, C22/B22=IOT133.) Al constreñir el lado P como LVCMOS33D, el PnR reclama automáticamente el pin B como complementario — la misma mecánica pseudo-diferencial que el HDMI onboard (lección del bring-up: nada de TRUELVDS a 3,3V). **Corrección a la línea base: los PMODs NO cuelgan de bank5/6 — cuelgan de bank2 (3 pares) y bank8 (1 par), ambos a 3,3V, y los 8 pines de PMOD1 hoy los ocupa el electrocardiograma de debug (`dbg_pmod1[0..4]` + `uart_pmod_rx` en D22) → habría que mudarlo a PMOD0/2×20.**

### 3.2 Placas hechas, y una trampa de mapeo

| Placa | Tipo | Encaje |
|---|---|---|
| [Machdyne DDMI Pmod](https://machdyne.com/product/ddmi-pmod/) (~12€, con step-up 5V) | 1 PMOD, 4 pares directos | ⚠️ [Su pinout](https://github.com/machdyne/ddmi) empareja P/N en VERTICAL (pin n ↔ pin n+6): **no casa con los pares del die (horizontales)**. Usable solo con driver de 2 single-ended complementarios (pierde el matching del par; a 270Mbps probablemente funcione, sin garantía) |
| [1BitSquared PMOD Digital Video](https://1bitsquared.com/products/pmod-digital-video-interface) ([docs](https://docs.icebreaker-fpga.org/hardware/pmod/dvi/)) | **2 PMODs**, paralelo 12bpp + TFP410/SII164 | Sin señales rápidas, pero se come LOS DOS PMODs y recorta el RGB555 del V9990 a 444 |
| PMOD propio (KiCad) sobre diseños abiertos [Wren6991/DVI-PMOD](https://github.com/Wren6991/DVI-PMOD) / [adwranovsky/hdmi_pmod](https://github.com/adwranovsky/hdmi_pmod) | 1 PMOD pasivo | **La opción limpia**: emparejar P/N según los pares del die (tabla §3.1); polaridad invertida se corrige gratis en el serializador. Trivial para quien ya fabrica PCBs |

### 3.3 Resolución realista y relojes

- **480p (720x480@59.94: 27MHz pixel, 270Mbps/par, reloj TMDS 27MHz)**: el MISMO enlace eléctrico que ya funciona en el HDMI onboard de esta placa, y el tiny9990 **sale nativamente en 720x480@~27MHz** → ni upscaler ni framebuffer. Experiencia comunitaria de TMDS por PMOD a 480p: [Black Mesa Labs](https://blackmesalabs.wordpress.com/2017/12/15/bml-hdmi-video-for-fpgas-over-pmod/), Machdyne (Schoko/Bonbon). **Realista: SÍ.**
- **720p (742,5Mbps/par)** por header 2,54mm + módulo + cable: fuera de toda especificación razonable del conector. **No contar con ello.**
- **Relojes**: opción A — **compartir los 27/135MHz existentes** (0 PLLA extra; si el dominio MSX va a 108,0MHz el V9990 corre +0,57% rápido, mismo error que asuma ya el resto del core). Opción B — **1 PLLA** (de los 2 libres) a 107,4864MHz + 134,36MHz de serie para timing V9990 de libro. En ambos casos **sobran PLLAs**. IOLOGIC: +8 OSER10 sobre 23% usado — irrelevante. CLKDIV 1/20 — sin conflicto.

---

## 4. EL VEREDICTO EN NÚMEROS

### 4.1 El añadido completo vs lo libre en la _157

Densidad de empaquetado real de la _157: 26.589 CLS / 40.636 logic = **0,654 CLS por celda**.

| Componente | Logic | BSRAM |
|---|---|---|
| tiny9990 con blitter (medido) | 9.569 | 21 → 0 (a SSRAM, +~700 logic ya contado abajo) |
| Conversión BSRAM→SSRAM del core | +~700 | — |
| Shim VRAM + prefetch/caché (caché en SSRAM) | +~2.500–3.000 | 0 |
| Árbitro 2º cliente DDR3 | +~500–800 | 0 |
| 2º TMDS (3 encoders + 4 OSER10 + glue) | +~400–700 | 0 |
| **TOTAL añadido** | **≈ 13.700–14.800** | **0 (todo SSRAM)** |

| Métrica | Libre en _157 | Necesita el añadido | Δ |
|---|---|---|---|
| **CLS** | **3.363** | **≈ 8.950–9.700** (a 0,654 CLS/logic) | **DÉFICIT ≈ 5.600–6.300** |
| CLS (empaquetado perfecto 0,5 — irreal) | 3.363 | ≈ 6.850–7.400 | déficit ≥ 3.500 |
| Registros | ~35.200 | ~5.500 | sobra |
| BSRAM | **0** | 0 (con conversión) / 21 (sin ella) | justo/imposible |
| PLLA | 2 | 0–1 | sobra |
| DSP / IOLOGIC / CLKDIV | 87% / 77% / 19 | 0 / +8 OSER / 0 | sobra |

**Sin blitter** el añadido baja a ≈ 10.100–11.200 logic ≈ 6.600–7.300 CLS: **déficit ≈ 3.200–3.900**.

> **NO CABE.** Ni con blitter ni sin él, y con la agravante de que la _157 ya sufre routabilidad a 89% — cualquier cosa que empuje por encima de ~90% es una build de lotería. La necesidad es ~2–3× el espacio libre.

### 4.2 Alternativas

**(a) Build VARIANTE del 60K** — medido con smokes en el mismo device: quitar el OPL4 libera opl3 = 2.946 logic/1.774 CLS/2 BSRAM/1 DSP + YMF278B = 3.104 logic/1.823 CLS/1,5 DSP + glue wave ≈ **~4.300 CLS liberados** → libres ≈ 7.660. El V9990 completo (≈9.000–9.700) sigue sin caber; el V9990 SIN blitter (≈6.600–7.300) "cabe" de milímetro pero deja el chip a **93–97% de CLS** — por encima de la pared donde ya murió un fix. Quitar el V9968 sí liberaría de sobra, pero mata la razón de ser del core. Veredicto: solo como experimento, nunca como build de batalla.

**(b) Tang Console 138K** — GW5AST-LV138FPG484A: **138.240 LUT (≈69.120 CLS), 340 BSRAM (6.120Kb), 298 DSP, 12 PLL**; consola completa **$99** ([CNX](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/)). MSXimus+V9990 completo ≈ 54–55K logic ≈ **~51% CLS, BSRAM 138/340 = 41%** — sobra todo, blitter incluido, y sin convertir BSRAMs. nand2mario ya publica cst para console138k con los MISMOS pines PMOD/DDR3 → port de constraints casi verbatim + regenerar IP DDR3 (ojo: con la 1.9.11.03 Education por la regresión SSRAM de la 1.9.12.03). **La vía recomendada: días de trabajo, no semanas, y riesgo bajo.**

**(c) V9990 externo (plan aparcado, estilo tnCartWonder en TN20K)** — tnCartWonder YA corre tiny9990+VRAM SDRAM+DVI en un GW2AR-18: cero presión sobre el 60K y hardware probado (~30€). A cambio: puente de bus Z80↔FPGA2 por PMOD/cartucho (I/O 60h-6Fh con WAIT_n cruzando el enlace — lecturas de puerto en <1µs, protocolo serie rápido o paralelo estrecho), dos bitstreams que mantener y dos flasheos. Más fricción de integración (menú, packs) que (b) para un ahorro pequeño.

---

## 5. Fuentes

- Smokes y sonda (este estudio): `scratchpad/v9990/smoke/impl/pnr/project.rpt.txt` (tiny9990 full), `smoke/nocmd/` (sin blitter), `smoke_opl/` (opl3), `smoke_ymf/` (YMF278B), `probe/` (pares PMOD); logs `smoke_run2.log`, `run.log`.
- Core: [buppu3/tnCart](https://github.com/buppu3/tnCart) @f62511b (`rtl/src/peripheral/video/tiny9990/`, `cartridge_v9990.sv`, `uma.sv`, README: limitaciones y salida 720x480@27MHz) · [herraa1/tnCartWonder](https://github.com/herraa1/tnCartWonder) @d3a54f1 (GW2AR-18) · [hilo WonderTANG msx.org p.89](https://www.msx.org/forum/msx-talk/hardware/wondertang-who-wants-to-juice-up-your-msx?page=88) (Fmax>108MHz con todo activado).
- Proyecto (solo lectura): `C:\Users\alber\proyectosAI\msx\MSX_up_th9958\fpga\constraints\msx_console60k.cst` (HDMI LVCMOS33D, pines dbg_pmod), `fpga\src\v9968_ddr3_backend.v` (canales wv2, 74,25MHz, ~175ns/línea, vacunas), `fpga\build.tcl` (device, opl3/jtopl/opl4wave en la _157).
- PMOD/pines: [nestang console.cst](https://github.com/nand2mario/nestang) (mapeo PMOD1_IOn) · [C64Nano console60k.cst](https://github.com/MiSTle-Dev/C64Nano) · sonda PnR propia (sitios IOB93/IOT124/IOT138/IOT140/IOB81/IOT117/IOT133/IOT144).
- Placas DVI-PMOD: [Machdyne DDMI](https://machdyne.com/product/ddmi-pmod/) + [pinout](https://github.com/machdyne/ddmi) · [1BitSquared PMOD DVI](https://1bitsquared.com/products/pmod-digital-video-interface) + [docs iCEBreaker](https://docs.icebreaker-fpga.org/hardware/pmod/dvi/) · [Wren6991/DVI-PMOD](https://github.com/Wren6991/DVI-PMOD) · [adwranovsky/hdmi_pmod](https://github.com/adwranovsky/hdmi_pmod) · [BML DVI over PMOD](https://blackmesalabs.wordpress.com/2017/12/15/bml-hdmi-video-for-fpgas-over-pmod/).
- V9990: Yamaha V9990 E-VDP-III Application/Programmer's Manual (relojes maestros 21,47727/14,31818/25,175MHz, modos P1/P2/B1–B6, VRAM 512KB).
- 138K: [CNX Software — Tang Console](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/) (GW5AST-138: 138.240 LUT4, 6.120Kb BSRAM/340 bloques, 298 DSP, 12 PLL; $99).
