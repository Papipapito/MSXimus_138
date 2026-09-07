# MSXimus_138 — el MSXimus en la Tang Console 138K

Porte del [MSXimus](README.md) (MSX2+ en la Tang Console 60K, linea V3.5) a la
**Tang Console 138K**: misma placa base, SOM **Tang Mega 138K** (GW5AST-LV138PG484A,
138.240 LUT, 340 bloques de BSRAM, 12 PLL, 1 GB de DDR3) en vez del Mega 60K.
Punto de partida: `MSX_up_v3`, rama `V3.5`, commit `dd8d8ff` mas los cambios de la
v3.5d (SD por puertos y multibloque, cronometro, menu de pruebas) a 07/09/2026.

## Lo que cambia respecto al 60K (y lo que no)

| | 60K | 138K |
|---|---|---|
| Dispositivo (`build.tcl`) | `GW5AT-60B GW5AT-LV60PG484AC1/I0` | `GW5AST-138B GW5AST-LV138PG484AC1/I0` |
| Pines (`constraints/`) | `msx_console60k.cst/.sdc` | `msx_console138k.cst/.sdc`, **copia 1:1** |
| IP de DDR3 | `fpga/ddr3/` (Gowin v3.0, x16, 297 MHz) | **la misma** |
| PLLs | `gowin_pll`, `pll_ddr3`, `pll74_video`... | **los mismos** |
| SDRAM (modulo de 40 pines, W9825G6KH, 32 MB) | `src/memory.v` | **el mismo, mismos pines** |
| Pack de BIOS/menu | `bios-msxnano-msximus/packs/msximus/...` | **el mismo fichero** |
| Flash: bitstream | 0x000000 (2,5 MB) | 0x000000 (**~6-7 MB**) |
| Flash: pack | 0x400000 | **0x800000** |
| Flash: config (6 bytes) | 0x480000 | **0x880000** |
| Flash: YRW801 (OPL4 wave, 2 MB) | 0x500000 | **0x900000** |
| Gowin EDA | Education o Standard | **Standard con licencia** (la Education no soporta el 138K) |

Por que se puede reutilizar tanto:

- **Pines.** El SOM Mega 138K saca a la placa base las mismas bolas que el Mega 60K,
  tanto para el dock (HDMI, SD, USB, PMOD, UART del BL616, ESP32, SDRAM del modulo)
  como para la DDR3 del SOM. Verificado bola a bola contra `console.cst` (nestang) y
  `console138k.cst` (ddr3_framebuffer_gowin) de nand2mario, que compila sus cores
  para las dos consolas con un solo fichero de pines. Quedan sin contrastar contra
  el esquematico las senales que el no usa: `sd_*`, `spi_irqn`, `s2`, `fan_en_o`, `esp_*`.
- **IP de DDR3.** El netlist encriptado de Gowin es portable dentro de Arora V:
  nand2mario usa una IP generada para el GW5A-25 en el 60K y en el 138K.
- **Mapa de flash.** Es lo unico que obliga a tocar el RTL: el bitstream del 138 no
  cabe en los 4 MB que tenia por delante. Son tres `localparam` en `top.v`
  (`FLASH_START_ADDRESS`, `FLASH_CONFIG_ADDRESS`, `WL_FLASH_BASE`).

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

## Estado

Ver `files/<fecha>/LEEME_*.txt` para cada entrega: dado, margen, md5 y lo que falta
por validar en placa.
