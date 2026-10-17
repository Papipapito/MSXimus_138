# MSXimus_138 — el MSXimus en la Tang Console 138K

Porte del [MSXimus](README.md) (MSX2+ en la Tang Console 60K, linea V3.8) a la
**Tang Console 138K**: la misma placa base (dock con HDMI, SD, dos USB-A, PMOD, BL616,
ESP32-C6 y el modulo SDRAM W9825 de 32 MB) con el SOM **Tang Mega 138K**
(GW5AST-LV138PG484A, 484 bolas: 138.240 LUT, 340 bloques de BSRAM, 12 PLL, 298 DSP,
1 GB de DDR3; la flash SPI es la misma W25Q64 de 8 MB) en vez del Mega 60K.
Punto de partida: `MSX_up_v3`. La v1 (07/09/2026) salio de la rama `V3.5`, commit
`dd8d8ff`, mas los cambios de la v3.5d; la **v3.7** (18/09/2026) es el porte, por merge,
de la V3.7b del 60K, y la **v3.8.4** (17/10/2026, rama `V3.8`), el de su V3.8.4.

> **Ninguna version del porte se ha validado en una placa 138K.** La v3.7, grabada en
> una el 16/10/2026, se quedo en negro por su mapa de flash de 16 MB (de ahi la v3.7-8mb);
> la v3.7-8mb y la v3.8.4 estan sin probar. Todo lo que en la documentacion del 60K es
> "validado en placa" aqui es "compilado y verificado en simulacion, pendiente de placa".
> Ver [Estado](#estado).

La documentacion completa (manual de usuario y referencia tecnica, adaptados al 138K)
esta en [docs/INDICE.md](docs/INDICE.md). Este fichero recoge solo lo que es propio
del porte.

## Lo que cambia respecto al 60K (y lo que no)

| | 60K | 138K |
|---|---|---|
| SOM | Tang Mega 60K (GW5AT-LV60PG484A) | Tang Mega 138K (GW5AST-LV138PG484A) |
| Dispositivo (`build.tcl`) | `GW5AT-60B GW5AT-LV60PG484AC1/I0` | `GW5AST-138B GW5AST-LV138PG484AC1/I0` (chips version C: `GW5AST-138C`) |
| Pines (`constraints/`) | `msx_console60k.cst/.sdc` | `msx_console138k.cst/.sdc`, **copia 1:1** con tres retoques (abajo) |
| IP de DDR3 | `fpga/ddr3/` (Gowin v3.0, x16, 297 MHz) | **la misma**; su `pll_stop` va directo al `ENCLK2` del PLL |
| PLLs | `PLLA` con mDRP (`gowin_pll`, `pll_ddr3`, `pll74_video`...) | **`PLL` + `PLL_INIT` en cascada** (`fpga/pll138/`), sin mDRP |
| Motor de ondas del OPL4 | 37,5 MHz | **36 MHz** (CE de 44,1 kHz = 14112/15000) |
| Salida del OPLL (jt2413) | directa al mezclador | **registrada en `clk_27m`** (`jt2413_wav_r27`) |
| `clk_86` del V9968 (`msx_v9968.sdc`) | 11,64 ns (el periodo real) | **sobre-restringido a 11,30 ns** |
| SDRAM (modulo de 40 pines, W9825G6KH, 32 MB) | `src/memory.v` | **el mismo, mismos pines** |
| Pack de BIOS/menu | `bios-msxnano-msximus/packs/msximus/...` | **el mismo fichero** (para "Instalar actualizacion" en la 138K, desde la bios `30f1ce2`) |
| Flash: bitstream | 0x000000 (2,47 MB) | 0x000000 (**unos 4,9 MB**: 5.096.124 bytes) |
| Flash: pack | 0x400000 | **0x500000** |
| Flash: config (11 bytes desde la 3.7) | 0x480000 | **0x580000** |
| Flash: YRW801 (OPL4 wave, 2 MB) | 0x500000 | **0x600000** (hasta el final de la flash) |
| Firmware del BL616 | fork TangCore (V3.8, OSD con color) en 0x40000, con el partner de Sipeed en 0x0 | **el mismo, compilado para la Console 138K** (`bl616_msximus_v3.8_138k.zip`): solo la imagen en 0x40000; el partner firmware de Sipeed de la 138K, en 0x0, no se toca |
| MXUPDATE e "Instalar actualizacion" | pack en 0x400000, `MSXIMUS.UPD`, web `tang60k/` | pack en **0x500000** (MXUPDATE 1.3 y bios `30f1ce2`), **`MSX138K.UPD`** (MXUPDATE y el menu), web `tang138k/` |
| Dato de la CPU hacia la SDRAM | directo al cruce 54 -> 108 | **registrado a 54 MHz** antes del cruce (`cpu_dout_ram`, v3.8.4) |
| Gowin EDA | 1.9.12.03 Standard (la Education 1.9.11.03 tambien cubre el GW5AT-60B) | **1.9.12.03 Standard con licencia** (la Education no soporta el 138K) |
| Validado en placa | cada entrega (la V3.8.4, el 16/10/2026) | **ninguna version** |

Por que se puede reutilizar tanto:

- **Pines.** El SOM Mega 138K saca a la placa base las mismas bolas que el Mega 60K,
  tanto para el dock (HDMI, SD, USB, PMOD, UART del BL616, ESP32, SDRAM del modulo)
  como para la DDR3 del SOM. Verificado bola a bola contra `console.cst` (nestang) y
  `console138k.cst` (ddr3_framebuffer_gowin) de nand2mario, que compila sus cores
  para las dos consolas con un solo fichero de pines. Tres retoques que el chip
  exigio: `IO_TYPE` de la DDR3 a `SSTL15`/`SSTL15D` (el 138 rechaza el sufijo `_I`),
  `s1`/`s2`/`fan_en_o` a `LVCMOS33` (en el 138 caen en el banco 5, que va a 3,3 V) y
  fuera las `INS_LOC` del DLL/PLL de la DDR3 que traia el 60K. Quedan sin contrastar
  contra el esquematico (`docs/hw/` solo tiene el de la 60K) las senales que nand2mario
  no usa: `sd_*`, `spi_irqn`, `s2`, `fan_en_o`, `esp_*`.
- **IP de DDR3.** El netlist encriptado de Gowin es portable dentro de Arora V:
  nand2mario usa una IP generada para el GW5A-25 en el 60K y en el 138K. La VRAM del
  V9968 vive en ella con el mismo backend y el mismo motor de reintentos escalonado de
  la 3.7b (puertos 2Ah-2Ch); la loteria de calibracion por dado que se ve en el 60K es
  igual de aplicable aqui (pendiente de verificar en placa).
- **Mapa de flash.** Obliga a tocar el RTL, pero poco: el bitstream del 138 no
  cabe en los 4 MB que tenia por delante. Son tres `localparam` en `top.v`
  (`FLASH_START_ADDRESS`, `FLASH_CONFIG_ADDRESS`, `WL_FLASH_BASE`); el bloque de
  configuracion (`CONFIG_BYTES = 11`: los 6 bytes de siempre, los 4 niveles del
  mezclador y un byte de comprobacion xor) es el mismo que en el 60K, solo cambia de sitio. Los
  packs son los mismos ficheros; el programador de Gowin graba el `.fs` en 0x000000
  igual que en el 60K.

## Relojes: PLL + PLL_INIT en cascada

El GW5AST no tiene el primitivo `PLLA` (error RP0008): tiene `PLL`, con los mismos
divisores pero sin mDRP; en su lugar lleva los puertos ICP/LPF que alimenta un
`PLL_INIT` (`fpga/pll138/pll_init.v`, de nand2mario, Apache-2.0). Y tiene dos limites
que el PLLA no tenia: VCO entre 650 y 1300 MHz y frecuencia de comparacion entre 19
y 81,25 MHz. Desde el pad de 50 MHz no salen 108/54/27 ni 371,25 exactos y enteros,
asi que los PLL van en cascada, como nand2mario en esta misma consola:

| PLL | Entrada | VCO | Salidas |
|---|---|---|---|
| `pll_27` | 50 MHz del pad, /2 x27 | 675 | 27,000 exactos, referencia de los demas |
| `pll_main` | 27 x40 | 1080 | 108, 54, 27, 135 y **36** para el motor OPL4 (ya no puede ser 37,5) |
| `pll_86` | 27 x35/11 | 945 | 85,9 para el V9968 |
| `pll_ddr3` | 27 x33 | 891 | 297 para la DDR3 y `CLKOUT1` = 74,25 sin gatear |
| `pll_74` | 74,25 x10 | 742,5 | 74,25 y 371,25 para el HDMI |

`pll_main` y `pll_ddr3` esperan al lock de `pll_27`. El `pll_stop` de la IP DDR3 va
directo a `ENCLK2` del PLL (en el 60K era la danza mDRP con `pll_mDRP_intf`). La
salida del OPLL se registra en `clk_27m` antes del mezclador (`jt2413_wav_r27`): el
arbol de sumas de 22 ns que en el 60K cabia por poco en la relacion 54→27 aqui no
cerraba en ningun dado.

## Version del chip: B o C

Sipeed monta chips **version C** desde julio de 2025. Para un chip C, Gowin exige
compilar con `GW5AST-138C` (si no, "unexpected compatibility issues"). Mira la
serigrafia del chip del SOM; `build.tcl` esta en B y basta cambiar el nombre del
dispositivo. Las entregas en `files/` indican con que version se compilaron.

## Como se compila

Igual que el 60K: `tools/lanzar_campana.ps1 -Campana <nombre> -Dados <primos>` deja
los clones en `%LOCALAPPDATA%\Temp\claude\campanas\<nombre>\bx_cN` y
`tools/gate_check.ps1 -Campana <ruta>` aplica el mismo criterio (setup 0, holds solo
en la IP DDR3). El .fs se convierte a `_jtag.bin` con el mismo script de siempre.

Lo propio del 138:

- `clk_86` del V9968 esta **sobre-restringido a 11,30 ns** en `msx_v9968.sdc` (el
  periodo real es 11,64) para obligar al rutador a dejar margen: el rutador de Gowin
  cumple el periodo y para, asi que un gate OK "con 0,07 ns" contra 11,30 son unos
  0,41 ns reales. Antes del registro de abajo, los dados caian por ese dominio y por los
  cruces de la CPU (`cpu1/DO`, `cpu1/IORQ`): desde la v3.7 pasaron el gate 7 de 45 (con
  `v38b138` y los portes 3.7.x sin entrega, `pz138*` y `pf138*`) y se entregaron 2. Con
  el registro, la v3.8.4 paso 4 de 5 (`v384138a`; el quinto, por el 86).
- El dato de la CPU hacia la SDRAM (`cpu_dout`) se registra a 54 MHz antes del cruce a
  108 (`cpu_dout_ram`, commit `e402652`, v3.8.4): `cpu1/DO -> mem1/SdrDat` era el peor
  camino de los dados rechazados desde octubre (`v38b138` 5 de 5, `p138l`, `p138m`). El
  T80 fija `DO` al cerrar T1 y baja /WR a mitad de T2, medio estado T despues: 4,5 ciclos
  de 54 MHz con el turbo de 5,37 MHz (el maximo del core) y 6,5-7,5 a 3,58. Hasta que
  `memory_ctrl` captura `SdrDat` sobran al menos 8,5 ciclos, medidos con el T80 real en el
  banco [`tools/t80mem`](tools/t80mem/README.md) (2312/2312 escrituras; falla con 10
  ciclos de retraso), asi que el ciclo de mas no se nota. Es el mismo patron que el
  `cpu_run` registrado de la v3.7.
- CLS ~57 % (el 60K va al 98 %), BSRAM 116/340, PnR de 15 a 27 min por dado (7 en la v1;
  21-27 en la v3.8.4): campanas de 5 dados.
- Las campanas del porte son `p138a`..`p138m`, las de los portes 3.7.x que no se
  entregaron (`pz138a`, `pz138b`, `pz138r`, `pz138r2` y `pf138g`..`pf138i`), `v38b138` y
  `v384138a` (detalle en `files/<fecha>/LEEME_*.txt`, en el
  [capitulo 07](docs/tecnica/07-sintesis-campanas.md) y en el
  [changelog](docs/tecnica/09-changelog.md)).

## Versiones del porte

| Version | Fecha | Dado | Equivale a | Que trae |
|---|---|---|---|---|
| v1 | 07/09/2026 | 3389 (respaldo 3373; primera entrega 3361, en `superados/`) | V3.5d del 60K | SD por puertos y multibloque, cronometro, menu de pruebas |
| v2 | 08/09/2026 | 3469 | V3.5f del 60K | + Game Master 2 emulado (bloque 6) |
| v3.7 | 18/09/2026 | dado **4391** (campaña `p138k`; 0,034 ns contra 11,30 = ~0,37 ns real; `files/20260918/`) | V3.7b del 60K | DMA de la SD (3.6/3.6c), mandos HID por USB-A (3.6f), espera a la DDR3 + LED chivato (3.6g), generacion C del V9968, mezclador por fuente con persistencia de 11 bytes (3.7), `cpu_run` registrado, motor de reintentos escalonado de la DDR3 + puertos 2Ah-2Ch (3.7b) |
| v3.7-8mb | 17/10/2026 | dado **5519** (campaña `p138m`, place_option 2; 0,006 ns contra 11,30 = ~0,35 ns real; `files/20261017/`) | la v3.7 | El mapa de flash dentro de los 8 MB de la W25Q64: pack 0x500000, configuración 0x580000, YRW801 0x600000 |
| v3.8.4 | 17/10/2026 | dado **5569** (campaña `v384138a`, place_option 2; 0,143 ns contra 11,30 = ~0,48 ns real; md5 del `.fs` 8e24561ddc1d; `files/20261017/`) | la V3.8.4 del 60K | OSD con color (y el firmware del BL616 para la 138K), actualizar desde el MSX (`flash_bridge.v` + MXUPDATE 1.3), el motor wave del OPL4 de la 3.8.4, las 3.7.1 a 3.7.6 del 60K y el dato de la CPU a la SDRAM registrado a 54 MHz; el mapa de flash de la v3.7-8mb |

El puerto 2Fh de la v3.7 dice 37h, como en el 60K; el de la v3.8.4 dice 38h, con el 29h
(FPGA_PATCH) a 4: Ajustes y MXUPDATE dicen 3.8.4.

## Estado

Ninguna version del porte se ha validado en una placa 138K: v1 y v2 se entregaron sin
validar; la v3.7 se grabo el 16/10/2026 en una 138K y se quedo en negro por el mapa de
flash de 16 MB; la v3.7-8mb y la v3.8.4 estan sin probar. Lo que hay es sintesis limpia,
gate pasado, los bancos de simulacion del 60K y el de `tools/t80mem` para el registro de la
v3.8.4. Las cifras medidas en placa que cita la documentacion
(velocidades de la SD, margenes de dados de la 60K, temperaturas) son del 60K.

Pendiente, en este orden, cuando haya placa: el plan de pruebas de
`files/20260907/LEEME_138_v1.txt` (logo y menu, Ajustes, SD por las tres rutas,
ROMs grandes y SRAM, DOS, OPL4 a 36 MHz, V9968/DEVCON, WiFi/File-Hunter, ventilador y
botones a 3,3 V), la calibracion de la DDR3 con `pll_stop→ENCLK2`, los pines sin
contrastar, la version del chip (B/C), el firmware del BL616 de la v3.8.4 (el panel F12)
y la actualizacion desde el MSX con el mapa de 8 MB (`MXUPDATE /N`, `/R` e "Instalar
actualizacion").

Ver `files/<fecha>/LEEME_*.txt` para cada entrega: dado, margen, md5 y lo que falta
por validar en placa.
