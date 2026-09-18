# 01. Qué es el MSXimus_138

Un **MSX2+ completo dentro de una FPGA**, en la placa Sipeed Tang Console 138K. No necesita un MSX: es un MSX. Se conecta a un televisor por HDMI, se le enchufa un teclado USB y arranca en un MSX-DOS o en un menú desde el que se lanzan juegos y discos guardados en una tarjeta microSD.

Es el **porte del [MSXimus](https://github.com/Papipapito/MSXimus)** (el mismo core en la Tang Console 60K) a la Console 138K: la misma placa base con un SOM más grande. Y el MSXimus, a su vez, es el hermano mayor del [MSXnano](https://github.com/Papipapito/MSXnano): la misma línea de core (goauld, luego MSXnano), portada a una placa con más recursos y ampliada con lo que en la pequeña no cabía. Nano era el pequeño; Maximus el grande.

> **Estado.** El porte está compilado y verificado en simulación, pero **nunca se ha probado en una placa 138K**: las entregas de `files/20260907` y `files/20260909` quedaron sin validar. Todo lo que en la documentación del 60K está "validado en placa", aquí está pendiente de placa.

## Lo que trae

| | |
|---|---|
| **CPU** | Z80 a 3,58 MHz, con turbo a 5,37 MHz al estilo Panasonic (tecla F11) y la identificación de turbo R que el software consulta |
| **Vídeo** | El **V9968** de HRA!, un V9958 ampliado con 256 KB de VRAM, comandos rápidos, paleta de 32768 colores y sprites multicolor escalables. Salida HDMI a 720p, con bordes como un monitor de tubo y scanlines opcionales |
| **Audio** | PSG, dos SCC, OPLL (MSX-MUSIC), MSX-Audio Y8950 con ADPCM, y el MoonSound completo: OPL4 con FM y tabla de ondas. Mono o estéreo por el HDMI |
| **Memoria** | 2 MB de RAM mapeada y una megaram de 4 MB para el cartucho emulado |
| **Almacenamiento** | Nextor sobre microSD. Lanza ROMs de hasta 4 MB con los mappers Konami, Konami-SCC, ASCII8, ASCII16, NEO-8 y NEO-16, y discos `.dsk` |
| **Guardado** | La SRAM de los cartuchos ASCII y el Game Master 2 de Konami se guardan en la tarjeta |
| **Entrada** | Teclado, mando y ratón USB directos a la placa, sin hub |
| **Red** | WiFi UNAPI con un ESP32-C6 externo, con pantalla de estado opcional, y descarga de ROMs y discos desde el propio menú |
| **Panel** | Un panel de estado sobre la imagen con la tecla F12, dibujado por el microcontrolador BL616 que la placa ya trae. En la 138K está pendiente: el firmware del BL616 del 60K no se ha compilado para ella |
| **Extras** | Logo de arranque, ventilador controlado por temperatura, dos BIOS a elegir (internacional y japonesa), y un menú de pruebas para diagnosticar |

## Lo que cambia respecto al 60K

La Console 138K es la **misma placa base** que la 60K (el dock con el HDMI, la microSD, los dos USB-A, el PMOD, el BL616 y el conector del ESP32-C6, más el módulo SDRAM) con otro SOM encima: el **Tang Mega 138K** en vez del Mega 60K. Por eso casi todo el MSXimus pasa tal cual; lo que cambia es esto:

| | 60K | 138K |
|---|---|---|
| **Chip** | GW5AT-LV60PG484A: 60K LUT, DDR3 de 512 MB | GW5AST-LV138PG484A: 138.240 LUT, 340 BSRAM, 12 PLL, 298 DSP, DDR3 de 1 GB. El diseño usa la misma IP de DDR3 x16 a 297 MHz |
| **Versión del chip** | — | B o **C** (Sipeed monta chips C desde julio de 2025). Se compila con `GW5AST-138B` o `GW5AST-138C` según la serigrafía del SOM |
| **Pines** | `msx_console60k.cst` | Bola a bola idénticos: `msx_console138k.cst` es una copia. Quedan sin contrastar contra el esquemático `sd_*`, `spi_irqn`, `s2`, `fan_en_o` y `esp_*` (pendiente de verificar en placa) |
| **Relojes** | PLLA | El GW5AST no tiene PLLA: PLL + PLL_INIT en cascada. El motor del OPL4 va a 36 MHz en vez de 37,5 |
| **Flash (SPI de 16 MB)** | bitstream 0x000000 (2,47 MB), pack 0x400000, configuración 0x480000, YRW801 0x500000 | bitstream 0x000000 (~4,88 MB), pack **0x800000**, configuración **0x880000**, YRW801 **0x900000**. Los packs son los mismos ficheros que en el 60K; solo cambia dónde se graban |
| **Gowin EDA** | 1.9.12.03 Education o Standard | 1.9.12.03 **Standard con licencia**: la Education no soporta el 138K |
| **Panel F12 (BL616)** | Fork TangCore | Pendiente: la Console 138K trae su propio firmware partner de Sipeed |

Todo lo demás (menú, tarjeta SD, mappers, megaram, guardado, DMA, DOS/Nextor, WiFi, audio, V9968 con la VRAM en la DDR3, puertos, pack) es idéntico al 60K.

## Lo que hace falta

| | Qué | Notas |
|---|---|---|
| **Obligatorio** | [Sipeed **Tang Console 138K**](https://wiki.sipeed.com/hardware/en/tang/tang-console/mega-console.html) | Con el módulo SOM Tang Mega 138K (Gowin GW5AST-138, 484 bolas), HDMI, dos USB-A, microSD y DDR3 de 1 GB |
| **Obligatorio** | El **módulo SDRAM** de la Console | Es la memoria del MSX. Sin él el core no arranca |
| **Obligatorio** | Una **microSD** de marca, clase 10, en FAT16 | Las tarjetas sin marca leen bien pero pierden escrituras en ráfagas largas. Está medido en el banco del 60K: una sin marca fallaba escrituras aunque se le diera tiempo y una Samsung EVO+ no falló ninguna con el mismo código |
| Recomendado | Disipador de 20×20 mm sobre el SOM | El core mantiene el chip ocupado |
| Opcional | Ventilador de 5 V de 20×20 mm, conector JST de 1,25 mm y dos pines | El core lo gobierna solo con el termómetro interno del chip; parado si no hace falta. En la 138K la salida va a 3,3 V (pendiente de verificar en placa) |
| Opcional | Teclado y mando USB | Directos a los USB-A de la placa |
| Opcional | Ratón USB **con cable** | Un receptor inalámbrico no funciona: se presenta como dispositivo compuesto |
| Opcional | **ESP32-C6** Waveshare C6-LCD-1.3 | Para la WiFi y su pantalla. Tres cables y la alimentación desde la placa |
| Opcional | Nada que comprar: el **BL616** de la placa | Para el panel F12. En el 60K basta con flashearle un firmware una vez; en la 138K ese firmware está pendiente |
| Opcional | Una **carcasa** impresa en 3D | Con forma de Spectravideo SVI-728, con sitio para la placa, el C6 con su pantalla y el ventilador. Como la placa base es la misma, vale la del 60K. Los ficheros y las fotos están en [`carcasa/`](../../carcasa/README.md) |

## Lo que no es

- No es un turbo R: se identifica como tal para que el software que lo consulta funcione, pero no hay R800.
- No tiene salida de vídeo ni de audio analógicos. Todo va por el HDMI.
- No tiene conectores de joystick, ni de casete, ni de impresora. Los mandos van por USB.
- No lleva la variante de VDP V9958: el V9968 es el único, y es compatible con todo lo que espera un V9958.
- No aprovecha el resto del chip: el 138K lleva el mismo core que el 60K, con más sitio libre (CLS ~57 %, 116 de 340 BSRAM), no un MSX más grande.

## Cómo seguir

El [capítulo 02](02-instalacion.md) explica qué flashear y dónde. El [03](03-tarjeta-sd.md), cómo preparar la tarjeta. El [04](04-menu.md), el menú tecla a tecla. Los siguientes van tema por tema: ROMs, discos, red, audio, vídeo y problemas. Quien quiera saber cómo está hecho por dentro tiene la [referencia técnica](../INDICE.md#referencia-técnica-docstecnica).
