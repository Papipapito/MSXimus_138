# 10. Problemas frecuentes

Por síntoma, qué mirar. Casi todo lo que hay aquí ha pasado de verdad durante el desarrollo del MSXimus en la Console 60K, y la causa fue casi siempre la que se dice en primer lugar. El porte a la 138K es el mismo diseño con la misma placa base, así que los síntomas y las causas se heredan tal cual; pero **el MSXimus_138 no se ha probado nunca en una placa 138K**, de modo que todo lo que sigue está pendiente de verificar en placa, y lo primero que hay que descartar en la 138K son los puntos propios del porte: direcciones de flash, versión del chip y licencia de Gowin (tabla siguiente).

## Al encender

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Pantalla azul y nada más | El pack no está en 0x800000 (en el 138K **no** es el 0x400000 del 60K: ahí lo pisa el bitstream, que ocupa unos 4,88 MB), o falta apagar y encender tras grabar | Regrabar el pack en la dirección exacta y **apagar y encender**, no reset |
| Pantalla negra, sin señal HDMI | La DDR3 no calibró tras un reset en caliente | Apagar y encender |
| Pantalla negra (o negra y luego el menú sin logo) al encender **desde un cargador**, pero arranca bien desde el USB del PC; el LED de la SD (U12) parpadea solo y va más rápido con F11 | La DDR3 de la VRAM no ha calibrado: cada intento de calibración sale bien con una probabilidad que depende del core (del dado, capítulo 07 de la técnica) y de la alimentación. Es la lotería medida en el 60K; el 138K usa la misma IP de DDR3 y el mismo motor de reintentos, así que le aplica igual (pendiente de verificar en placa). El MSX corre por debajo, sin vídeo | Esperar: desde la v3.7 del 138 (la v3.7b del 60K) el core reintenta con ventanas cada vez más largas y, si sigue sin calibrar, con el PLL reiniciado; el arranque espera hasta 10 s. Probar otro cargador o una batería USB (algunos cargadores USB-C hacen caer VBUS un instante al negociar). Si un core concreto falla siempre, es su dado: otro `.fs`. Desde BASIC `PRINT INP(&H2C) AND 127` dice los intentos que fallaron |
| Arranca pero se reinicia en bucle | Una ROM con el punto de entrada fuera del cartucho, o un core antiguo con un pack nuevo | Reset; si es al lanzar una ROM, el menú ya lo veta desde la 2.x |
| Arranca directo en DOS y no sale el menú | Menú al arrancar en Off | **S** durante el logo, marcar *Menú al arrancar*, Save & Restart |
| Los ajustes vuelven a los de fábrica | Se grabó un pack antiguo con cola de configuración, o se encendió con S2 pulsado | Volver a Ajustes y guardar. Los packs actuales no pisan la configuración |
| Sale el menú del Game Master 2 en vez del juego | El juego no es Konami pero usa el mapper Konami-SCC (Space Manbow 2) con GM2 activo | Tecla **G** en la pantalla de lanzar para ese juego |

## Propios del porte a la 138K

Lo que en el 60K no existe y en la 138K puede dar un susto antes de llegar al menú.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Se grabó el pack donde decía la documentación del 60K y hay pantalla azul, o el core deja de arrancar | Las direcciones de flash del 138K son otras: el bitstream ocupa unos 4,88 MB y el pack de BIOS va en **0x800000**, la configuración en 0x880000 y `yrw801.rom` en **0x900000**. Grabar el pack en 0x400000 pisa el bitstream | Regrabar el `.fs` en 0x000000 (el programador de Gowin lo hace igual que en el 60K), el pack en 0x800000 y el YRW801 en 0x900000. Los packs son los mismos ficheros que en el 60K; solo cambia dónde se graban |
| Gowin (la síntesis o el programador) avisa de "unexpected compatibility issues" | El SOM lleva un chip **versión C** (Sipeed los monta desde julio de 2025) y el `.fs` se compiló para `GW5AST-138B` | Mirar la serigrafía del chip del SOM; el `LEEME` de cada entrega en `files/` dice para qué versión se compiló. Para un chip C hay que compilar con `GW5AST-138C` (basta cambiar el nombre del dispositivo en `build.tcl`) |
| Gowin EDA no deja abrir el proyecto ni sintetizar ("device not supported" o similar) | La edición **Education** no soporta el GW5AST-138 | Hace falta la edición **Standard con licencia**, 1.9.12.03 |
| El `.fs` recién compilado no arranca o el vídeo se corrompe | Dado sin margen en el dominio de 86 MHz del V9968: en el 138K solo cierra ~1 de cada 3 dados (`clk_86` va sobre-restringido a 11,30 ns para forzar margen) | No entregar un `.fs` que no pase el gate; con CLS ~57 % y ~7 min de PnR, una campaña de 3 dados basta para tener uno bueno ([capítulo 07 de la técnica](../tecnica/07-sintesis-campanas.md)) |
| Los botones S1/S2 o el ventilador no responden | En el 138K esas señales van a 3,3 V (banco 5, `LVCMOS33`), y `s2`, `fan_en_o`, `sd_*`, `spi_irqn` y `esp_*` no se han contrastado contra el esquemático | Pendiente de verificar en placa: si falla, lo primero es revisar esos pines en `msx_console138k.cst` |

## La tarjeta

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| "No se detecta la tarjeta SD" | Tarjeta mal insertada, formato no reconocido, o tarjeta que no inicializa | Comprobar el formato; probar otra tarjeta. Tecla T, la cabecera dice qué tipo detecta |
| Descargas o guardados que fallan de forma aleatoria | Tarjeta sin marca que pierde escrituras | Cambiar a una de marca, clase 10 |
| "FH: la SD es FAT32" o los guardados no se escriben | La partición no es FAT16 | Reparticionar con una FAT16 de hasta 2 GB para el menú |
| "DSK fragmentado: recopialo" | El `.dsk` no está en clusters consecutivos | Copiarlo de nuevo desde el PC |
| "Falta NEXTOR.EMU en la raiz" | El menú no pudo crear el fichero oculto | Tarjeta llena o protegida; con FAT32 no hace falta |
| "Falta FHUNT (MKDIR en DOS)" | No existe la carpeta | Crearla desde MSX-DOS |
| Nextor da "Disk error writing drive A" con DRVTEST | Se ha redirigido la salida a la SD | Redirigir a un disco RAM |

## ROMs

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Mapper "? (desconocido)" | La ROM cambia de banco de una forma que el análisis no ve | Tecla **M** hasta acertar; luego poner la etiqueta en el nombre |
| El juego arranca y se cuelga a los pocos segundos | Mapper equivocado | Probar los otros con M |
| "INIT pag.0/BASIC: no lanzable" | ROM de un programa BASIC | No es lanzable como cartucho |
| La partida no se guardó | Se apagó en vez de hacer reset, o no hay carpeta FHUNT | Reset siempre; crear FHUNT |
| Metal Gear 2 en pantalla negra con el Game Master 2 | La versión [9692] de la ROM, con chequeo de MSX-DOS en el arranque | Usar otra versión, por ejemplo la [3371] o la [1489] |
| "Analizando ROM..." tarda mucho | Core v1 o v2 del 138 (equivalentes a la 3.5d y 3.5f del 60K), sin análisis por hardware | Actualizar el core; con el 3.7 (que trae el DMA de la 3.6c) es instantáneo |

## Vídeo y audio

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El televisor no muestra imagen | Receptor que no acepta 720p60 con audio embebido | Probar otro cable o entrada; es una señal estándar |
| Un juego a 50 Hz se ve con la geometría rara | El modo 50 Hz es el menos probado | Anotar cuál y reportarlo |
| Sin MoonSound, o instrumentos que faltan | `yrw801.rom` no grabado en 0x900000 (en el 138K, no en el 0x500000 del 60K) | Grabarlo |
| Todo suena bajo o distorsionado | Ganancia maestra tocada | Volver a 5 ([capítulo 08](08-audio.md)) |
| VGMPlay se cuelga con OPL3 | Nextor 3 beta | Usar el pack con Nextor 2.1.4 |
| El SCC no suena en un juego | El juego busca el SCC en otro slot | Ajustes, Slot 1 = 2o SCC |

## Teclado, mando y ratón

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El teclado no responde | Teclado con hub interno o inalámbrico con receptor compuesto | Probar otro teclado; conectar directo, sin hub |
| El ratón no se ve | Receptor inalámbrico | Solo ratones con cable |
| El mando no hace nada | Es XInput (Xbox o un receptor 2,4 GHz que se presenta como Xbox 360): el host de los USB-A es HID puro | Un mando USB genérico HID; muchos receptores tienen un modo D (DirectInput) además del X |
| F12 no hace nada | El BL616 no lleva el firmware del MSXimus: el del 60K no se ha compilado para la 138K, y la Console 138K trae el partner firmware de Sipeed | Pendiente ([capítulo 02](02-instalacion.md)); el turbo es F11 |
| La ñ no sale con un teclado español | La distribución del MSX no la tiene en esa tecla | Pendiente |

## Red

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Con W salen caracteres sin sentido y no aparece el menú | El módulo no está o no responde | Comprobar alimentación y cables; la pantalla del módulo tiene que encender |
| La pantalla del módulo dice "Sin WiFi" | Red no configurada | Tecla W, Scan/Join |
| "FH: sin UNAPI" | El MSX no ve el driver: RX del FPGA mal cableado | TX y RX cruzados: IO16 al pin 16, IO17 al pin 14 |
| Conectado pero nada descarga | Sin internet, o File-Hunter caído | Probar más tarde |
| El módulo se porta raro | Alimentado a la vez por J10 y por USB-C | Una sola fuente |

## Herramientas para diagnosticar

- **Tecla T en el arranque o en el navegador**: el menú de pruebas. Dice la versión del core, el tipo de tarjeta, los bytes de configuración, y mide la velocidad de la tarjeta por sus cuatro caminos, el sonido del PSG y del OPLL, el Game Master 2 y el VDP.
- **Tecla H**: la ayuda del navegador.
- **Ajustes**: muestra la versión del core que hay grabada.
- **F12**: el panel del BL616, con el estado de la CPU, la tarjeta, el ventilador, el teclado y la red (con el firmware del 60K; en la 138K está pendiente).
- **La pantalla del ESP32**: red, tráfico, turbo, hora.
- **La tira de LEDs**, si se ha montado la tira de ocho WS2812 en el pin previsto: encendido, CAPS, kana, actividad de disco, turbo, red, mando y teclado.
- **Puertos de diagnóstico** desde BASIC: `INP(&H2F)` da la versión del core, `INP(&H2D)` el estado del USB, `INP(&H2E)` el del ratón ([capítulo 02 de la referencia técnica](../tecnica/02-puertos-es.md)).

## Cómo reportar un problema

Con la versión del core (Ajustes o `INP(&H2F)`, que en la 3.7 del 138 dice 37h), el dado del `.fs` grabado (está en el nombre del fichero y en el `LEEME` de `files/`) y la versión del chip del SOM (B o C, por la serigrafía), el pack (2.1.4 o Nextor 3), el nombre exacto de la ROM o disco con su tamaño, y lo que dice la línea de estado del menú o el mensaje de DOS. Una foto de la pantalla vale más que una descripción. Como el porte no se ha probado en placa, cualquier reporte de la 138K, aunque sea "arranca y funciona", es información nueva.
