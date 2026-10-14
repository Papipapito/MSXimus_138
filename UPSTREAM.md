# Atribución y procedencia (GPLv3)

Este repositorio es una **obra derivada** de:

- **MSXnano** — https://github.com/Papipapito/MSXnano
  - Rama base: `dev`
  - Commit base: `390132d061f14dbc6072bb20d1dbcce7012bd525` ("docs: diseño de frontend grafico…", tip de `dev`; RTL idéntico a `eaa8ac4` = F1 de limpieza pre-port)
  - Licencia: **GNU GPL v3**

Al ser derivado de código GPLv3, **MSX_up es GPLv3** y conserva los avisos de copyright y atribución de todo el código heredado, incluso mientras el repo es privado. Al distribuir el bitstream o el código habrá que acompañar el fuente correspondiente.

## IP de terceros heredada (revisar licencia al portar cada pieza)

Registrado a partir de la auditoría y del historial del proyecto. Confirmar el aviso concreto de cada fichero al migrarlo:

| Componente | Origen | Licencia | Notas de port |
|---|---|---|---|
| Core VDP V9958 | `tn_vdp_v3_v9958/` (basado en trabajos previos de VDP FPGA) | ver cabeceras | Exonerado en la investigación R-Type; porta tal cual (revisar IPs de reloj internas) |
| PSG YM2149 | `PSG_YM2149/YM2149.vhdl` | ver cabecera | Bug #2 (bucle combinacional del envelope) — hacer carga síncrona antes de confiar en placement GW5A |
| OPLL / FM (jt2413, jtopl) | jotego | **GPLv3** | Porta tal cual; base para futuros MSX-Audio Y8950 (jt8950) y OPL4 |
| G80A (T80 / Z80) | `G80A/` | ver cabecera | Porta tal cual |
| SD reader (WonderTANG) | `src/wondertang/sd_reader.sv` | ver cabecera | CRC de lectura ignorado por diseño upstream; fixes #3/#4/#5 antes de portar |
| Companion / SPI (MiSTeryNano) | `src/usb/mcu_spi_new.v`, `sys_ctrl.v`, `fpga_companion.v` | ver cabecera | Topología BL616 del 60K (TangCore); limpiar restos del core Atari ST |
| LPF OCM (KdL / OCM-PLD) | `src/ocm/lpf.vhd` | ver cabecera | Binding cross-language con `psg_filter.v` (LPF1/LPF2); nunca añadir el `lpf.vhd` del tn_vdp al build |
| Firmware ESP UNAPI | ducasp | ver upstream | Reloj fijo 859372 bps — recalcular prescaler `wifi_lite.vhd` para la base nueva |
| Wrapper FM del OPL4 (mangOPL4) | Jokin Miragaia (antxiko), mangOPL4 = [antxiko/tnCartWonder](https://github.com/antxiko/tnCartWonder) (fork de tnCartWonder), `rtl/src/cartridge_opl3.sv`; commit sin anotar | **BSD-3** (la cabecera de `fpga/src/opl4fm.v` cita el origen, el autor y la licencia; el texto completo del aviso BSD-3 aún no está allí; los cambios nuestros, GPLv3) | `fpga/src/opl4fm.v` es obra derivada de ese wrapper. Cambios propios: registros sombra 2x256 para poder releer el FM, status en C4h/C6h, stub de 7Eh/7Fh, bus a 54 MHz. El core OPL3 de debajo (`fpga/opl3/`) es de Greg Taylor (gtaylormb/opl3_fpga, LGPL-3.0) en la versión de ese fork con los arreglos de Gowin |
| Motor PCM del OPL4 (YMF278B) | srg320, [Arcade-PsikyoSH2_MiSTer](https://github.com/srg320/Arcade-PsikyoSH2_MiSTer) `rtl/PSH2/YMF278B.sv`, commit `5379b34b` (14/07/2026); permiso explícito del autor por correo (13/07/2026) | **BSD-3** (derivado del `ymf278b.cpp` de MAME, titulares R. Belmont / Olivier Galibert / hap; aviso en `fpga/opl4wave/YMF278B.sv` y, desde el 13/10/2026, en el `ymf278b_gowin.v` generado) | `fpga/opl4wave/`: `YMF278B.sv` + `YMF278B_pkg.sv` son la fuente; `ymf278b_gowin.v` sale de `convert.sh` (sv2v + `postproc.py`) y es lo que se sintetiza. Cambios nuestros: registros por slot en BSRAM (era v3), stub del FM (`OPL3_DO = 0`), salida `MIX_FM` (F8) hacia el mezclador, relectura de los registros de slot a la primera (05/10/2026), F8 = 1Bh tras el reset y NEW2 también con el dato por C5h (13/10/2026), margen/TL/envolvente/pan/silencio (14/10/2026: margen de 24 canales con -15 dB por slot, TL con LD=0, envolvente, pan a -3 dB/paso y silencio por debajo de -60 dB) |
| Core FM OPL3 | Greg Taylor, [gtaylormb/opl3_fpga](https://github.com/gtaylormb/opl3_fpga), en la versión del fork mangOPL4 (cambios de Jokin Miragaia en `opl3_pkg.sv`, 2026) | **LGPL-3.0** (cabeceras de `fpga/opl3/*.sv`) | `fpga/opl3/`. Cambios nuestros: `timer.sv`, timer parado en el ciclo crítico (05/10/2026); vibrato y trémolo en canon (13/10/2026, 3.8.2) |
| FIFO asíncrona `afifo.v` | Dan Gisselquist (Gisselquist Technology, proyecto ETH10G) | **GPL-3.0** (cabecera de `fpga/opl3/afifo.v`) | Cruce host → OPL3 dentro de `host_if.sv`, sin cambios |

> Pinout y firmware del companion del 60K: referencias **TangCore / nand2mario** (NESTang / TangCore tienen ports GW5AT-60 funcionando). Documentar procedencia de cualquier `.cst`/firmware reusado.
