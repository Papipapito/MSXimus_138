# 03. Mapas de memoria

Cuatro mapas distintos y cómo se relacionan: lo que ve el Z80 (slots y páginas), lo que hay en la SDRAM física, lo que hay en la flash y lo que va a la DDR3. Sale del mux de direcciones de `fpga/top.v`, de `fpga/src/megaram.v`, de `fpga/src/gm2_slot1.v` y del script que monta el pack en el repositorio de la BIOS.

## 1. Lo que ve el Z80: slots

| Slot | Página 0 (0000-3FFF) | Página 1 (4000-7FFF) | Página 2 (8000-BFFF) | Página 3 (C000-FFFF) |
|---|---|---|---|---|
| **0-0** | BIOS principal | BIOS principal | | |
| 0-1 | | | | |
| **0-2** | | ROM UNAPI del ESP (16 KB) | | |
| **0-3** | | Logo de arranque (16 KB) | | |
| **1** | | Segundo SCC o Game Master 2 | Segundo SCC o Game Master 2 | |
| **2** | | Megaram, cuando el menú la mueve aquí al lanzar una ROM | Megaram | |
| **3-0** | Mapper | Mapper | Mapper | Mapper |
| **3-1** | SubROM (16 KB) | Menú + FM-BIOS (16 KB) | Segunda página del menú (16 KB) | |
| **3-2** | | Nextor: kernel paginado y ventana de la SD | Nextor | |
| **3-3** | | Megaram en su posición de arranque | Megaram | |

Los slots 0 y 3 son expandidos; el 1 y el 2 no. Es el reparto de un MSX2+ de Panasonic con el disco en el slot 3-2, más el cartucho emulado en el 2.

Detalles que importan:

- **El mapper** son 2 MB en 128 segmentos de 16 KB. Los registros FCh-FFh son de solo escritura y el bit 7 se ignora: los segmentos 128 a 255 son alias de los 0 a 127.
- **El menú corre desde ROM**, como un cartucho de 32 KB, en las páginas 1 y 2 del slot 3-1. Antes se descomprimía en RAM; ahora la página 2 ocupa la ventana que tenía el driver kanji del MSXnano, que en el MSXimus no existe. La fuente kanji sí, por puertos.
- **Nextor** ocupa el slot 3-2 con su kernel de 128 KB paginado en 6000h, y en la página 1 lleva además la **ventana de la SD**: 7C00h-7DFFh es el búfer de sector y 7E00h-7EFFh son los registros del controlador, activos solo cuando se ha escrito un 1 en 7E00h. Es el interfaz WonderTANG original; el capítulo 06 lo detalla.
- **La megaram** arranca en el slot 3-3 (config 1 = F3h). Al lanzar una ROM, el menú manda la orden 0Fh al dispositivo OCM, que la pasa a modo SCC-I y la mueve al slot 2; ahí es donde el juego la encuentra como cartucho. El segundo SCC, si está activo, ocupa el slot que no tiene la megaram: normalmente el 1.
- **El slot 1** es del segundo SCC si Ajustes lo pide, o del Game Master 2 cuando el menú lo arma para un juego Konami. Si no, no responde.
- La **BIOS principal** del pack está parcheada con la corrección de interrupciones del MSXnano; hay dos variantes de pack, internacional y japonesa, que cambian BIOS y SubROM.

## 2. La SDRAM física: 8 MB

El controlador direcciona 8 MB con 23 bits para la CPU (filas 0-2047 del W9825); por encima, en las filas 4096 y siguientes, fuera del alcance de cualquier mapeo de la CPU, viven los 4 MB de la familia de ondas del OPL4 (la YRW801 de 2 MB, copiada de la flash al arrancar, y 2 MB de RAM de muestras), servidos por el puerto `wv` de `memory_ctrl` en los turnos de CPU vacíos. Los cuatro bancos de 2 MB de la CPU se reparten así:

| Rango | Banco | Contenido | Bits altos de la dirección |
|---|---|---|---|
| 000000-1FFFFF | A | Mapper de RAM, 2 MB | 00 |
| 200000-3FFFFF | B | Megaram, mitad alta (A21 = 1), y el Game Master 2 | 01 |
| 400000-5FFFFF | C | Megaram, mitad baja (A21 = 0), 2 MB | 10 |
| 600000-7FFFFF | D | El pack de BIOS, la fuente kanji y la VRAM de respaldo | 11 |

La megaram está partida en dos bancos a propósito. Hasta la versión 3.5 era de 2 MB y vivía en el banco C; el mapper ocupaba A y B. Al recortar el mapper a 2 MB, la megaram creció a 4 MB quedándose con el B, y la traducción es un simple cruce de bits, sin sumador: la dirección física es `{~A21, A21, A[20:0]}`. Todo lo que cabía en 2 MB sigue en las mismas direcciones que antes.

El banco D, en detalle:

| Dirección física | Tamaño | Contenido | Origen en el pack |
|---|---|---|---|
| 700000-73FFFF | 256 KB | Fuente kanji JIS1 y JIS2 | 00000 |
| 740000-75FFFF | 128 KB | Nextor (kernel y driver) | 40000 |
| 760000-767FFF | 32 KB | BIOS principal | 60000 |
| 768000-76BFFF | 16 KB | SubROM | 68000 |
| 76C000-76FFFF | 16 KB | FM-BIOS + menú, primera página | 6C000 |
| 770000-773FFF | 16 KB | Menú, segunda página | 70000 |
| 774000-777FFF | 16 KB | Reserva, a FF | 74000 |
| 778000-77BFFF | 16 KB | ROM UNAPI del ESP | 78000 |
| 77C000-77FFFF | 16 KB | Logo de arranque | 7C000 |
| 7C0000-7FFFFF | 256 KB | VRAM, solo en la línea de respaldo con la VRAM en SDRAM | |

El pack se copia entero, 512 KB, desde 700000. Cada región del banco D es exactamente el pack más 700000, lo que hace trivial comprobar en placa que el streaming ha ido bien.

## 3. La megaram: 4 MB y sus rincones reservados

La megaram es el cartucho emulado del slot 2. El menú carga ahí la ROM y configura el mapper con el que se va a comportar: Konami, Konami-SCC, ASCII8, ASCII16, NEO-8 o NEO-16. Los registros de banco son de 9 bits; en los mappers de 8 bits el noveno es siempre 0, y en ASCII16 y los NEO llega desde el propio registro. Para llenar la mitad alta durante la carga, que se hace en modo SCC con registros de 8 bits, el menú usa el bit 4 del puerto 46h.

Los 512 segmentos de 8 KB tienen dueño:

| Segmentos | Uso |
|---|---|
| 0-255 | Mitad baja. Toda ROM de hasta 2 MB cabe aquí |
| 256-479 | Mitad alta, libre para ROMs de más de 2 MB |
| 480-495 | ROM del Game Master 2 (128 KB), cuando está armado |
| 496 | SRAM del Game Master 2 (8 KB) |
| 497 | Descriptor "GM2S" del guardado del Game Master 2 |
| 498-510 | Libres |
| 511 | Descriptor "SRM1" del guardado de SRAM de cartucho |

La **SRAM de cartucho** de los ASCII8 y ASCII16 se emula en los segmentos 252 a 255, los últimos 32 KB de la mitad baja. Los descriptores de guardado viven en la mitad alta porque un juego normal no llega ahí; una ROM de 4 MB sí la pisa, y por eso con ellas no hay guardado ni Game Master 2.

El mecanismo de guardado depende de que la SDRAM sobreviva al reset del MSX, que lo hace: el menú, al arrancar de nuevo, comprueba el descriptor y el checksum y reescribe el fichero en la tarjeta si la SRAM ha cambiado.

## 4. La flash: 16 MB del SOM

Es el mapa que cambia respecto al 60K: el bitstream del GW5AST-138 mide unos 4,88 MB (el del GW5AT-60, 2,47) y se comía el pack que allí vivía en 400000, así que todo lo que va detrás del bitstream sube 4 MB.

| Dirección | Tamaño | Contenido | En el 60K |
|---|---|---|---|
| 000000-7FFFFF | 8 MB | Bitstream del GW5AST-138 (unos 4,88 MB) y margen | 000000 |
| 800000-87FFFF | 512 KB | Pack de BIOS | 400000 |
| 880000-88000A | 11 bytes | Configuración: 'A', 'B', config 1, config 2, turbo al arrancar ('T'), ganancia (C0h + valor), los 28 bits de niveles del mezclador en little-endian (4 bytes) y un byte de suma (xor ^ A5h) | 480000 |
| 88000B-8FFFFF | | Libre (el guardado borra el sector de 4 KB entero, así que lo libre de verdad empieza en 881000) | |
| 900000-AFFFFF | 2 MB | ROM de ondas YRW801 del OPL4 | 500000 |
| B00000-FFFFFF | 5 MB | Libre | |

Las tres direcciones son tres `localparam` de `fpga/top.v` (`FLASH_START_ADDRESS`, `FLASH_CONFIG_ADDRESS`, `WL_FLASH_BASE`); es lo único del RTL que el mapa de flash obligó a tocar en el porte. Los packs y la YRW801 son los mismos ficheros que en el 60K: solo cambia la dirección donde se graban. El programador de Gowin graba el .fs en 000000 igual que allí. La otra ruta del 60K, grabar la flash desde el BL616 del dock con el `_jtag.bin`, en el 138 está pendiente: su firmware (el fork de TangCore) no se ha compilado para la 138K y la Console 138K trae el partner firmware de Sipeed.

El pack se flashea en 800000 y el core lo copia a la SDRAM en cada encendido. El mismo streaming que copia los 512 KB lee los once bytes siguientes: los seis primeros van a los registros 41h, 42h, 45h y 44h y los cuatro de niveles al mezclador por fuente. Un bloque viejo de seis bytes (flash borrada detrás) siembra lo de siempre y deja el mezclador a 8/8; un bloque con la suma mal o un nivel mayor que 8, igual. El menú, al hacer Save & Restart, reescribe solo esos once bytes. Desde el 9 de septiembre de 2026 el pack del MSXimus mide 512 KB justos, sin esa cola: así grabar un pack nuevo no pisa los ajustes guardados (en el 60K se perdió dos veces en un día el "Slot 1 = Game Master 2" por eso). El pack del MSXnano sí la lleva.

Si la cola no empieza por 'AB' el core no la carga y se queda con los valores de fábrica: config 1 = F3h (mapper en 3-0 y megaram en 3-3 activos, segundo SCC y scanlines apagados), config 2 = 0Fh (SD activa en el slot 3-2 y menú al arrancar), sin turbo y ganancia 5. Con el botón S2 pulsado en el encendido pasa lo mismo aunque la cola sea válida: es el rescate.

## 5. La DDR3 del SOM: un solo cliente

El SOM Mega 138K trae 1 GB de DDR3; el diseño usa la misma IP x16 a 297 MHz que en el 60K y el mismo cliente único: el backend de vídeo, con los 256 KB de VRAM del V9968, escritos todo el tiempo por el shim. Las ondas del OPL4 **no** van aquí: desde la _104 la YRW801 y la RAM de muestras viven en la SDRAM del dock (apartado 2), y el **cargador de ondas** las copia de la flash (0x900000) a la SDRAM una vez, en segundo plano, tras copiar el pack; el bit 2 del puerto 36h dice que sigue copiando (los puertos 34h-37h conservan el nombre "DDR3" de cuando las ondas vivían en ella).

El controlador es el de la receta de nand2mario para esta placa: PLL a 297 MHz (en el 138 es un `PLL` + `PLL_INIT` de `fpga/pll138/`, VCO 891 MHz colgado de los 27,000 de `pll_27`, y el `pll_stop` de la IP va directo a ENCLK2 del PLL, como lo cablea nand2mario en la 138K; en el 60K era la danza mDRP), órdenes de ráfaga de 128 bits y refresco automático activado. El motor de reintentos de calibración y los puertos 2Ah-2Ch son los de la V3.7b del 60K; la lotería de calibración por dado se le aplica igual, pero en el 138 todo esto está compilado y verificado en simulación, pendiente de placa.

## 6. Qué comparte el camino de streaming

Cuando la CPU está parada, la SDRAM la escriben dos fuentes por el mismo camino: el streamer de la flash al arrancar y la DMA de la SD. Ninguna de las dos pasa por el decodificador de slots; escriben direcciones físicas de 23 bits directamente:

- El streamer escribe siempre en el banco D, desde 700000.
- La DMA escribe donde le diga el menú o el driver: en la megaram, con dirección física, o en el mapper, con una dirección lógica del Z80 que el core traduce con los registros FCh-FFh (capítulo 06).

## 7. Referencias cruzadas

- Cómo se decide en el core cada región del mux: `fpga/top.v`, el comentario "sdram map" y el `assign ram_addr`.
- El mapa de flash del 138, con el del 60K al lado: `fpga/top.v`, el comentario "MSXimus_138 (07/09/2026)" junto a `FLASH_START_ADDRESS`, y `README.138.md`.
- El pack, ROM a ROM: `tools/desmontar_pack.py` y `tools/hacer_packs.py` en el repositorio de la BIOS.
- El guardado de SRAM y el Game Master 2 desde el lado del menú: capítulo 04 del manual.
