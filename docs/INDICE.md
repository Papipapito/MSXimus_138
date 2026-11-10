# Documentación del MSXimus_138

Índice general del porte del MSXimus a la Tang Console 138K. Cada capítulo dice para quién es, en qué estado está y de qué fuente sale, para que se pueda escribir y revisar por separado.

La portada del porte es [`README.138.md`](../README.138.md), en la raíz del repositorio: qué cambia respecto al 60K (dispositivo, mapa de flash, relojes, licencia de Gowin) y qué no. El `README.md` (inglés) y el `README.es.md` son los del MSXimus, con la instalación, la actualización desde el MSX y el panel F12 contados para la 138K. Todo lo demás vive aquí.

Aviso que vale para toda la documentación: **ninguna versión del porte 138 se ha validado todavía en una placa 138K**. Lo que en el MSXimus 60K está validado en placa, aquí está compilado y verificado en simulación, pendiente de placa. Cada capítulo lo dice donde importa (instalación, problemas, changelog, arquitectura) sin repetirlo en cada párrafo.

## Cómo está organizada

| Carpeta | Para quién | Qué contiene |
|---|---|---|
| `docs/manual/` | Quien tiene la placa y quiere usarla | Instalación, tarjeta SD, menú, ROMs, discos, WiFi, audio, vídeo, problemas |
| `docs/tecnica/` | Quien quiere entender o modificar el core | Arquitectura, puertos de E/S, mapas de memoria, pack de BIOS, V9968, SD y DMA, changelog, actualización |

Idioma: castellano. El manual de usuario se traducirá al inglés cuando esté cerrado, como el README. La referencia técnica se queda en castellano.

## Manual de usuario (`docs/manual/`)

| Nº | Capítulo | Estado | De dónde sale |
|---|---|---|---|
| 01 | [Qué es el MSXimus_138](manual/01-que-es.md): la máquina, lo que trae, lo que hace falta, lo que no es | **escrito** | README.138, README |
| 02 | [Instalación](manual/02-instalacion.md): la flash de la placa con el mapa del 138K (pack en 0x500000, configuración en 0x580000, YRW801 en 0x600000), los ficheros de la release, el pack, el BL616 (solo la imagen del panel, en 0x40000), el ESP32-C6 con su cableado, actualizar | **escrito** | README.138, top.v |
| 03 | [La tarjeta SD](manual/03-tarjeta-sd.md): qué tarjeta, formato, qué poner y dónde, ficheros especiales, etiquetas, discos, editar desde el PC | **escrito** | menu_main.asm, srm_saves.asm, gm2.asm |
| 04 | [El menú de arranque](manual/04-menu.md): flujo de arranque, teclas del logo, navegador, lanzar ROM, lanzar disco, Ajustes, WiFi, File-Hunter, Pruebas, mensajes | **escrito** | menu_main.asm, gm2.asm, srm_saves.asm, test_menu.asm |
| 05 | [ROMs y mappers](manual/05-roms-mappers.md): la megaram de 8 MB, los nueve mappers (con ASCII16-X y Plain 0000h), cómo se decide (con la firma de tipo de ROM de MSXgl), la SRAM y su guardado, el Game Master 2, ROMs que no lanzan | **escrito** | menu_main.asm, srm_saves.asm, gm2.asm, megaram.v |
| 06 | [MSX-DOS y Nextor](manual/06-msxdos-nextor.md): las dos versiones, arrancar en DOS, discos de imagen, rendimiento, otros sistemas | **escrito** | sd_rw_ports.inc, LEEMEs |
| 09 | [Vídeo](manual/09-video.md): la salida 720p, scanlines, 50 Hz, el panel F12, el V9968 para el usuario | **escrito** | msx2hdmi_v9968.sv, README |
| 10 | [Problemas frecuentes](manual/10-problemas.md): por síntoma, con causa probable y qué hacer; herramientas de diagnóstico; cómo reportar; lo que aún no se ha visto en una placa 138K | **escrito** | LEEMEs, test_menu.asm |
| 11 | [Actualizar desde el MSX](manual/11-actualizar.md): MXUPDATE 1.3 por internet o desde un fichero, Instalar actualización en Ajustes, qué es un `.UPD` de la 138K (pack en 0x500000, ondas en 0x600000), tiempos, mensajes (v3.8.4) | **escrito** | mxupdate.c, actualizar.asm |

## Referencia técnica (`docs/tecnica/`)

| Nº | Capítulo | Estado | De dónde sale |
|---|---|---|---|
| 01 | [Arquitectura](tecnica/01-arquitectura.md): la placa y el SOM Mega 138K, diagrama de bloques, relojes y dominios (la cascada PLL + PLL_INIT del GW5AST), el bus y los slots, la memoria, el vídeo, el audio, los periféricos, la secuencia de arranque | **escrito** | top.v, fpga/pll138/ y sus módulos |
| 02 | [Mapa de puertos de E/S](tecnica/02-puertos-es.md): la E/S conmutada 40h-4Fh con los cuatro dispositivos (el puente de la flash, 4Dh, incluido), los puertos de la SD, y el resto puerto a puerto | **escrito** | top.v, sdc_ioport.sv, swioports.vhd |
| 03 | [Mapas de memoria](tecnica/03-mapas-memoria.md): slots y páginas, la SDRAM física banco a banco, la megaram y sus segmentos reservados, la flash de 8 MB con el mapa del 138K, la DDR3 | **escrito** | top.v, megaram.v, gm2_slot1.v, desmontar_pack.py |
| 04 | [El pack de BIOS](tecnica/04-pack-bios.md): qué es, las diez ROMs y su procedencia, el menú de 32 KB en ROM, construir, un pack para todos los cores (el del 138K es el mismo fichero que el del 60K, solo cambia la dirección) | **escrito** | bios-msxnano-msximus |
| 05 | [El V9968 en el MSXimus](tecnica/05-v9968.md): qué es, de dónde sale, las tres generaciones del interfaz de registros y en cuál estamos, el puerto 4, cómo está integrado, cómo se comprueba | **escrito** | fpga/v9968/ORIGEN.txt, hra1129/V9968_Cartridge |
| 06 | [La tarjeta SD y la DMA](tecnica/06-sd-dma.md): el controlador, los cuatro caminos con sus velocidades (medidas en el 60K), cómo funciona la DMA, los dos modos de destino, los contadores de mapper, quién usa qué, las firmas | **escrito** | sd_reader.sv, sdc_ioport.sv, sd_dma.sv, sd_rw_ports.inc |
| 09 | [Changelog del porte 138](tecnica/09-changelog.md): de la v1 (07/09/2026, = V3.5d del 60K) y la v2 (Game Master 2) a la v3.7 (porte de la V3.7b del 60K), la v3.7-8mb (el mapa de flash en 8 MB) y la v3.8.4 (la V3.8 del 60K, con MXUPDATE), con el dado, el margen y los hashes de cada entrega, todas pendientes de placa | **escrito** | los LEEME de files/, README.138 |
| 11 | [La actualización desde el MSX](tecnica/11-actualizacion.md): el puente de la flash (4Dh), el formato `.UPD` con la fila de la 138K (IDCODE 0001081Bh), el manifiesto, MXUPDATE por dentro, la web (`tang138k`), los bancos (v3.8.4) | **escrito** | flash_bridge.v, mxupd.py, mxupdate.c, actualizar.asm |

Además: `img/` (con las fotos de la carcasa en `img/carcasa/`) y `logo/`. La carcasa imprimible vive en [`carcasa/`](../carcasa/README.md), en la raíz del repositorio, con su propio README.

## Estado

El porte se ha comprobado con el mismo RTL en la Console 60K. En una placa 138K quedan por probar la instalación, el arranque, la calibración de la DDR3, la SD, la WiFi, el audio, el vídeo y el firmware del BL616 (`bl616_msximus_v3.8_138k.zip`): todo el manual describe lo que hace el 60K con el mismo RTL.
