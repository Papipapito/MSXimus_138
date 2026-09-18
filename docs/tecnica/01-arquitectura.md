# 01. Arquitectura del core

Cómo está montado el MSXimus por dentro: qué bloques hay, cómo se conectan, con qué relojes van y qué pasa desde que se enciende la placa hasta que el Z80 ejecuta su primera instrucción. Todo sale de `fpga/top.v` y de los módulos que instancia; los números están tomados del RTL tal como se sintetiza.

Este es el porte del MSXimus a la **Tang Console 138K**. El core es el mismo que el del MSXimus 60K salvo en el chip, los relojes y el mapa de flash, y eso es lo que cambia en este capítulo. Una advertencia que vale para todo el documento y no se repite en cada apartado: el porte está compilado y verificado en simulación, pero **nunca se ha probado en una placa 138K**. Lo que en el 60K son medidas en placa (márgenes de dados, velocidades, temperaturas) se cita aquí como del 60K.

## 1. La placa y lo que se usa de ella

El MSXimus_138 corre en la **Sipeed Tang Console 138K**: la misma placa base que la Console 60K con el SOM **Tang Mega 138K** en vez del Mega 60K. El SOM lleva la FPGA **Gowin GW5AST-LV138PG484A** (484 bolas; 138.240 LUT, 340 bloques de BSRAM, 12 PLL, 298 DSP), una **DDR3** de 1 GB de la que el core usa una región (la VRAM del V9968) y una flash SPI de 16 MB. En la placa base hay una **SDRAM Winbond W9825G6KH** de 16 bits (el módulo de 40 pines de 32 MB, el mismo que en el 60K), la ranura de la tarjeta SD, dos puertos USB-A, el HDMI, el conector 2×20 libre donde va el ESP32-C6 y un microcontrolador **BL616** que hace de programador y de canal de servicio.

El SOM Mega 138K saca a la placa base las mismas bolas que el Mega 60K, dock y DDR3 incluidos, así que el fichero de pines (`fpga/constraints/msx_console138k.cst`) es una copia del del 60K con tres retoques que exige el chip: `IO_TYPE=SSTL15`/`SSTL15D` en la DDR3 (el 138 rechaza el sufijo `_I`), `s1`/`s2`/`fan_en_o` a `LVCMOS33` porque en el 138 el banco 5 va a 3,3 V, y fuera las `INS_LOC` del DLL/PLL de la DDR3. Quedan sin contrastar contra el esquemático las señales que nand2mario no usa en sus cores para la 138K: `sd_*`, `spi_irqn`, `s2`, `fan_en_o` y `esp_*` (pendiente de verificar en placa).

| Recurso | Para qué lo usa el core |
|---|---|
| SDRAM externa de 16 bits | Toda la memoria del MSX: BIOS y ROMs del pack, mapper de 2 MB, megaram de 4 MB, fuente kanji, driver de disco. Mapa en el capítulo 03. Y, por encima de los 8 MB que direcciona la CPU (filas 4096+), la tabla de ondas de 2 MB del OPL4 más 2 MB de RAM de muestras (`wave_sdram`, desde la _104) |
| DDR3 del SOM | La VRAM del V9968, con su propio controlador (la misma IP x16 a 297 MHz que en el 60K). Es el único cliente de la DDR3: las ondas del OPL4 no van aquí |
| Flash SPI de 16 MB | El bitstream (4,88 MB), el pack de BIOS de 512 KB, once bytes de configuración y la ROM de ondas YRW801 |
| Tarjeta SD | Discos y ROMs del usuario, con su propio controlador en el core (capítulo 06) |
| BL616 | Flasheo por JTAG, y una UART con el core para el panel de estado F12 sobre el HDMI. El firmware del BL616 del 60K (fork de TangCore) no se ha compilado para la 138K, que trae el partner firmware de Sipeed: el panel F12 queda pendiente |
| ESP32-C6 externo | WiFi UNAPI y pantalla de estado, por UART a unos 860 kbps |
| USB-A ×2 | Teclado, ratón y mando, con un host USB HID propio en el fabric, sin hub |

La flash está compartida con el BL616 y el bitstream del GW5AST-138 ocupa 4,88 MB (el del 60K, 2,47), así que todo el mapa sube 4 MB respecto al 60K: el pack de BIOS va en 0x800000 (60K: 0x400000), el bloque de configuración en 0x880000 (60K: 0x480000) y la YRW801 en 0x900000 (60K: 0x500000). Son tres `localparam` en `top.v` (`FLASH_START_ADDRESS`, `FLASH_CONFIG_ADDRESS`, `WL_FLASH_BASE`). Los packs son los mismos ficheros que en el 60K, solo cambia la dirección donde se graban; el programador de Gowin graba el `.fs` en 0x000000 igual.

El dispositivo en `build.tcl` es `GW5AST-138B`. Sipeed monta chips versión C desde julio de 2025 y para ellos Gowin pide compilar con `GW5AST-138C`: hay que mirar la serigrafía del chip del SOM. Hace falta Gowin EDA 1.9.12.03 en edición Standard con licencia; la Education no soporta el 138K.

## 2. Diagrama de bloques

```mermaid
flowchart LR
    subgraph CPU["Bus del MSX (54 MHz, T-estados a 3,58 / 5,37 MHz)"]
        Z80["Z80 (G80a)"]
        PPI["PPI A8-AB"]
        SLOT["Decodificador de slots\ny puertos de E/S"]
    end
    Z80 --- SLOT
    PPI --- SLOT

    subgraph MEM["Memoria"]
        MC["memory_ctrl\n(SDRAM 16 bits, 108 MHz)"]
        MAP["Mapper 2 MB"]
        MEGA["Megaram 4 MB\n+ SCC + GM2"]
        ROM["BIOS, menú, Nextor,\nkanji (del pack)"]
    end
    SLOT --> MAP --> MC
    SLOT --> MEGA --> MC
    SLOT --> ROM --> MC

    subgraph VID["Vídeo"]
        VDP["V9968 (85,9 MHz)"]
        SHIM["Shim de VRAM\n+ caché"]
        VDDR["Backend DDR3\n(VRAM 256 KB)"]
        HDMI["msx2hdmi\n720p, 74,25 MHz"]
    end
    SLOT --> VDP --> SHIM --> VDDR
    VDP --> HDMI

    subgraph AUD["Audio"]
        PSG["PSG ×2"]
        SCC["SCC ×2"]
        OPLL["OPLL"]
        Y8950["Y8950 + ADPCM"]
        OPL4["OPL4: FM + PCM\n(ondas en SDRAM)"]
        MIX["Mezclador con\nganancia #44"]
    end
    SLOT --> PSG & SCC & OPLL & Y8950 & OPL4 --> MIX --> HDMI
    OPL4 --> MC

    subgraph IO["Periféricos"]
        SD["Controlador SD\n+ DMA"]
        USB["USB HID ×2"]
        ESP["UART ESP32-C6"]
        BL["UART BL616\n(panel F12)"]
        FLASH["Streamer de flash"]
    end
    SLOT --> SD --> MC
    USB --> PPI
    SLOT --> ESP
    BL --> HDMI
    FLASH --> MC
```

Todo lo que toca la SDRAM pasa por un único controlador, `memory_ctrl`, que reparte turnos entre la CPU y los clientes secundarios. El V9968 no toca la SDRAM: su VRAM vive en la DDR3 a través del shim.

## 3. Relojes y dominios

El GW5AST no tiene el primitivo `PLLA` del GW5AT del 60K: tiene `PLL`, con los mismos divisores pero sin mDRP, y un `PLL_INIT` que le carga los parámetros del lazo (ICP/LPF) por puertos directos. Los seis PLL del core están regenerados para él en `fpga/pll138/`. Además impone dos límites que el PLLA no tenía: VCO entre 650 y 1300 MHz y frecuencia de comparación (PFD) entre 19 y 81,25 MHz. Desde el pad de 50 MHz no salen 108/54/27 ni 371,25 exactos y enteros, así que los PLL van **en cascada**, como en los cores de nand2mario para esta consola: `pll_27` (50 ÷ 2 × 27, VCO 675) da 27,000 MHz exactos y de él cuelgan `pll_main` (× 40, VCO 1080: 108, 54, 27, 135 y 36 MHz), `pll_86` (VCO 945) y `pll_ddr3` (× 33, VCO 891: 297 MHz para la DDR3 y 74,25 para el HDMI). `pll_main` y `pll_ddr3` esperan en reset al lock de `pll_27`. El vídeo y la DDR3 siguen teniendo sus propios PLL, a propósito: así el HDMI no comparte nada con el bus del MSX y los cruces se reducen a FIFOs y sincronizadores.

| Reloj | Frecuencia | Quién lo usa |
|---|---|---|
| `clk_108m` | 108,000 MHz | El controlador de SDRAM |
| `clk_54m` | 54,000 MHz | El Z80 y todo el bus del MSX: slots, puertos, PPI, PSG, SCC, mezclador, SD |
| `clk_27m` | 27,000 MHz | Registros de configuración, RTC, OPL3, UART del ESP, cronómetro de la SD, streamer de flash |
| `clk_135` | 135,000 MHz | Serializadores TMDS heredados (el HDMI real va por la cadena de vídeo) |
| `clk_wave375` | 36,000 MHz | Motor PCM del OPL4. En el 60K son 37,5 MHz (de ahí el nombre de la señal); aquí sale del mismo VCO de 1080 dividido por 30, en fase con 27/54/108, y el CE de 44,1 kHz del motor se recalculó a 14112/15000 |
| `clk_86` | 85,909 MHz | El V9968 y su shim de VRAM. Es 27 × 35/11, cero ppm respecto a 24 veces la subportadora de color |
| `clk_hdmi` / `clk_hdmi5` | 74,25 / 371,25 MHz | Píxel y TMDS ×5 del 720p. `pll_74` multiplica por 10 (VCO 742,5) el 74,25 que presta el PLL de la DDR3 (VCO 891 ÷ 12, sin gatear), como en la cascada de nand2mario para la 138K |
| DDR3 | 297 MHz | Un solo controlador, el de la VRAM del V9968 (las ondas del OPL4 van por la SDRAM), con el reloj de calibración desde el pad de 50 MHz. El `pll_stop` de la IP va directo a `ENCLK2` del PLL; en el 60K era la secuencia mDRP con `pll_mDRP_intf` |

El Z80 no va a 3,58 MHz: va a 54 MHz con habilitaciones de reloj que dibujan los T-estados. El divisor normal es 108 ÷ 30 = 3,6 MHz; el turbo es 108 ÷ 20 = 5,4 MHz con un pulso tragado cada 176, que da 5,369318 MHz exactos, la receta del turbo de Panasonic. El cambio entre los dos se hace sin glitch, solo cuando el bus está en reposo y la SDRAM libre.

Dos frenos deliberados mantienen la velocidad de un MSX real: un estado de espera en cada búsqueda de opcode (M1) y otro en cada escritura a memoria. En turbo la latencia de la SDRAM y su refresco no caben en un T-estado de 186 ns, así que hay una guarda que cuesta un 18 % del turbo teórico; se probó a quitarla en el 60K y la máquina se colgaba.

En el sdc, `clk_86` está **sobre-restringido a 11,30 ns** (el periodo real es 11,64): es la forma de obligar al rutador de Gowin, que cumple el periodo y para, a dejar margen. Un gate OK con 0,07 ns contra 11,30 son unos 0,41 ns reales. En el 138 ese dominio cierra alrededor de uno de cada tres dados; el resto del chip va holgado (CLS ~57 %, BSRAM 116/340, PnR de unos 7 minutos), así que las campañas son de tres dados (capítulo 07).

## 4. El bus del MSX

El Z80 es un **G80a**, la variante del T80 en Verilog, en modo Z80 con ciclos de E/S estándar. El bus que sale de él es el de un MSX de cuatro slots primarios, dos de ellos expandidos:

| Slot | Contenido |
|---|---|
| 0-0 | BIOS principal (32 KB) |
| 0-2 | ROM del driver de red UNAPI (16 KB, página 1) |
| 0-3 | ROM del logo de arranque (16 KB, página 1) |
| 1 | Segundo SCC o Game Master 2, según Ajustes; libre si no |
| 2 | Megaram: el cartucho emulado, con su SCC, una vez que el menú lanza una ROM |
| 3-0 | Mapper de RAM de 2 MB |
| 3-1 | SubROM (página 0), menú con FM-BIOS (página 1), segunda página del menú (página 2) |
| 3-2 | ROM del disco: Nextor y la ventana de la SD |
| 3-3 | Megaram en su posición de arranque, antes de lanzar nada |

La decodificación es la clásica: el registro de slot primario está en el puerto A del PPI y los registros de slot secundario en FFFFh de cada slot expandido. Todos los `*_req` que salen del decodificador están registrados en `clk_54m` y son mutuamente exclusivos; el mux de lectura del bus es un OR plano de esas peticiones. No es cosmética: viene del 60K, donde con la FPGA al 98 % de celdas lógicas los nodos IORQ_n y WR_n del Z80 están saturados y cualquier cono combinacional colgado de ellos aparece en la lotería de rutado. En el 138 la lógica cabe holgada, pero el diseño se conserva tal cual.

Las señales del bus que llegan a módulos en otros dominios se registran antes: el módulo de red y el V9968 ven el bus un ciclo tarde, y el glue del V9968 lo convierte en una transacción valid/ready por ciclo de E/S.

## 5. La memoria

`memory_ctrl` gobierna la SDRAM externa a 108 MHz. Es el controlador del MSXnano adaptado al bus de 16 bits: en cada turno sirve un byte, con la máscara DQM sacada del bit 0 de la dirección. Los turnos se reparten con un divisor libre de 108 ÷ 8 y ÷ 16 que marca las ranuras de CPU a 6,75 MHz, y los huecos vacíos los aprovechan dos puertos secundarios, `wv` para las ondas del OPL4 y `wv2`/`wv3` para la RAM de muestras del ADPCM-B en la línea principal (o para el V9968 cuando la VRAM va por SDRAM en la línea de respaldo).

La dirección física de 23 bits se elige en un mux de dos ramas. La rama normal es la de la CPU: mapper, BIOS, megaram, Game Master 2, kanji, menú y logo, cada uno con su región del capítulo 03. La otra rama es el **camino de streaming**, activo cuando la CPU está parada: por él escriben el streamer de la flash al arrancar y la DMA de la SD. La elección entre esos dos va por debajo, sobre registros, fuera del cono de la CPU, que en el 60K es donde vive el 98 % de la congestión.

El refresco de la SDRAM tiene dos modos. Con la CPU en marcha lo dispara la señal RFSH del Z80. Con la CPU parada entra un refresco autónomo, y ahí hay una regla dura aprendida a base de fallos: el refresco autónomo solo puede correr cuando se sabe que nadie está escribiendo, porque puede pisar una aceptación en vuelo. Por eso la señal `cpu_run` que lo gobierna junta el reset del Z80, el fin del streaming de flash, el arranque del ESP, la congelación del panel F12 y la ventana de espera de la DMA, y desde la V3.6d va registrada.

## 6. El vídeo

El VDP es el **V9968** de Takayuki Hara, el superconjunto del V9958 con comandos rápidos, paleta de 5 bits, sprites en modo 3 y VRAM de 256 KB. Va en su propio dominio de 85,9 MHz. El capítulo 05 cuenta su procedencia y su estado; aquí, cómo encaja:

1. **Glue del bus**. El V9968 espera un interfaz valid/ready. El glue registra el bus del Z80 y emite una transacción por ciclo de E/S en 98-9B (y en 88-8B, que se aliasa al mismo chip para el software que busca un V9968 como cartucho externo).
2. **Shim de VRAM**. El core pide la VRAM con un contrato de ocho ciclos. El shim la sirve con una caché de línea y prefetch y traduce las peticiones a palabras de 32 bits con máscara de bytes hacia el backend. Dos canales en paralelo, porque los modos de 256 bytes por línea consumen una palabra cada 730 ns y un canal solo no llegaba.
3. **Backend DDR3**. La VRAM vive en la DDR3 del SOM, con un controlador propio calcado del framebuffer de nand2mario para esta placa. La IP de Gowin (v3.0, x16, 297 MHz) es la misma que en el 60K: el netlist encriptado es portable dentro de Arora V, y nand2mario usa una sola para las dos consolas. El motor de reintentos escalonado de la calibración y los puertos 2Ah-2Ch (capítulo 05) van igual; la lotería de calibración por dado que se vio en el 60K es igual de aplicable aquí (pendiente de verificar en placa). Existe una línea de respaldo con la VRAM en la SDRAM compartida, que serializa cada palabra en hasta cuatro accesos al controlador de memoria; se conserva pero no es la que se entrega.
4. **msx2hdmi**. El puente al HDMI de 720p a 60 Hz. El HDMI corre en su dominio de 74,25 MHz y se alimenta del VDP a través de un anillo de 32 líneas en BRAM de doble reloj; la captura se auto-alinea con las señales reales de sincronismo y blanking del VDP. El audio va embebido en el mismo HDMI. Sobre esta imagen el BL616 puede superponer el panel de texto de la tecla F12.

Solo hay salida de 60 Hz. La geometría de 50 Hz del V9968 no está medida.

## 7. El audio

Siete generadores entran en un mezclador con saturación en `clk_54m`:

| Chip | Puertos | Implementación |
|---|---|---|
| PSG YM2149 | A0-A2 | Con filtro de paso bajo, y el registro 14 sirve el joystick USB |
| Segundo PSG | 10-12 | El mismo módulo, para el software que lo busca ahí |
| SCC / SCC+ | En la megaram, 9800h y B800h | `scc_wave2` en Verilog puro; el VHDL original lo barría la síntesis de la GW5A |
| Segundo SCC | Slot 1 | El mismo módulo, en el slot que no ocupa la megaram |
| OPLL YM2413 | 7C-7D | `jt2413` de JOTEGO |
| Y8950 MSX-Audio | C0-C1 | `jtopl2` más un decodificador ADPCM-B con los 256 KB de muestras del Y8950 en la SDRAM (`adpcm_sdram`, puerto `wv2` de `memory_ctrl`, filas 5120+; en la línea de respaldo con la VRAM en SDRAM cae a 32 KB en BSRAM) y su IRQ al Z80 |
| OPL4 MoonSound | C4-C7 y 7E-7F | FM con `opl3_fpga` y motor PCM `YMF278B` de 24 slots (a 36 MHz en el 138) con las ondas en la SDRAM (`wave_sdram`, por el puerto `wv` de `memory_ctrl`), cargadas de la flash en segundo plano tras el arranque |

El grupo clásico pasa por una ganancia maestra ajustable de 0 a 7 por el puerto #44, guardada en la flash; el OPL4 entra después de esa ganancia, a nivel nativo, porque la ganancia existe justamente para subir los chips flojos a la altura del MoonSound. El OPLL entra atenuado a tres cuartos para igualar el balance medido en openMSX entre su portadora y la del Y8950. En el 138 su salida se registra en `clk_27m` antes de entrar al mezclador (`jt2413_wav_r27`): el árbol de sumas de 22 ns que en el 60K cabía por poco en la relación 54 → 27 aquí no cerraba (−4,3 ns en la campaña p138f); cuesta 37 ns de retardo, inaudible. Hay salida mono y estéreo, según Ajustes.

## 8. Periféricos

- **Teclado, ratón y mando USB**, por los dos USB-A: dos instancias del host USB HID en el fabric, con un PLL de 12 MHz propio, sin hub. El teclado se traduce a la matriz del MSX; el ratón se presenta por el puerto de joystick como un ratón MSX; el mando (desde la v3.6f) sale del host como una palabra de doce bits en formato SNES (4 arriba, 5 abajo, 6 izquierda, 7 derecha, 8 A, 0 B, 10 y 11 los hombros) y va al puerto 1 del registro 14 del PSG, con autodisparo en los botones 3 y 4. El host es HID puro con el informe de los mandos genéricos (ejes a 00/7F/FF): un mando **XInput** (Xbox y los receptores que lo imitan) no es HID y no se ve. El BL616 tiene su propio host USB en el USB-C OTG y el firmware TangCore del 60K entiende XInput, pero exige un hub o adaptador OTG con alimentación en el puerto donde normalmente va el cargador; el MSXimus no cuenta con él para los mandos (y en la 138K ese firmware está además pendiente).
- **Reloj de tiempo real** en B4-B5, alimentado por el reloj del sistema.
- **Fuente kanji** por los puertos D8-DB, con los 256 KB de JIS1 y JIS2 en la SDRAM.
- **S1990 del turbo R** en E4-E7: la máquina se identifica como turbo R y la rutina CHGCPU de la BIOS mueve el turbo. No hay R800.
- **ESP32-C6** por los puertos 06-07: el puente `wifi_lite` es una UART con FIFO de recepción de 2080 bytes, prescaler fijo 27 ÷ 31 = 870968 bps (el firmware del ESP va a 859372, un 1,3 % menos, dentro de la tolerancia de una UART), y "recepción rápida" que retiene la lectura hasta 25 ms cuando el FIFO está vacío.
- **BL616**: el core le manda su estado por UART y él dibuja el panel F12 sobre el HDMI. Mientras el panel está abierto, el MCU congela el Z80 parando su `cpu_run`, sin resetearlo. Esto lo hace el firmware del 60K (fork de TangCore), que no se ha compilado para la 138K; con el partner firmware de Sipeed que trae la Console 138K el panel no existe. Pendiente.
- **Tira de ocho LEDs WS2812**: diagnóstico. El LED de red parpadea con el tráfico de la UART del ESP.
- **Ventilador** por temperatura (`fan_ctrl` + oscilador de anillo `ro_osc` como termómetro relativo). En el 138 `fan_en_o` va a 3,3 V y es de los pines sin contrastar contra el esquemático (pendiente de verificar en placa).
- **Telemetría serie** (`dbg_uart` por E22 y la UART del USB-C): contadores del shim del V9968, la DDR3, el audio y el ventilador; su periodo (`PERIOD_MS`) es el dado que siembra el placement de cada campaña.
- La telemetría, la tira de LEDs, el ventilador por temperatura y el segundo PSG, más un decodificador de teclado único, forman la *dieta* de la v3.6h (`DIETA_V36H` en `top.v`, apagada): se probó en el 60K y rutaba peor, ver el [capítulo 07](07-sintesis-campanas.md).
- **UART de depuración** a 54 MHz por un PMOD, apagada en las entregas.

## 9. Qué pasa al encender

1. `pll_27` engancha y con él la cascada de PLL. Un secuenciador de reset suelta tres etapas separadas 39 ms.
2. El **streamer de flash** copia el pack de BIOS, 512 KB más once bytes, desde 0x800000 de la flash a la SDRAM, byte a byte por el camino de streaming. Al final lee los once bytes de configuración: los seis de siempre (los dos registros de Ajustes, el byte de turbo al arrancar y el de ganancia) más los cuatro niveles del mezclador por fuente y su byte de comprobación (V3.7). Con el botón S2 pulsado se cargan los valores de fábrica.
3. Mientras tanto la DDR3 calibra y, en cuanto el pack está en su sitio, el **cargador de ondas** empieza a copiar los 2 MB de la YRW801 desde 0x900000 a la región de ondas de la SDRAM, en segundo plano.
4. El core espera unos tres segundos a que el **ESP32** haya arrancado, para que el driver de red lo encuentre a la primera.
5. Cuando todo eso está, y la DDR3 de la VRAM ha calibrado (desde la V3.6g el paso a `reset3_n` espera al `ready` del backend, con un tope de unos 10 s desde la V3.7b para arrancar a ciegas si nunca calibra; mientras tanto el LED de la SD parpadea solo), el Z80 sale de reset y arranca la BIOS del pack. El menú de la BIOS vive como cartucho en el slot 3-1 y toma el control en el escaneo de slots; lo que hace a partir de ahí lo cuenta el capítulo 04 del manual.

Un reset del MSX no repite el streaming: la SDRAM conserva su contenido, y por eso conserva también la megaram con la partida guardada, que es lo que permite el guardado de SRAM al siguiente arranque. Un apagado lo pierde todo.

## 10. Lo que no está

- No hay R800 ni MSX-DOS 2 en ROM; el identificador de turbo R sirve para el turbo y para el software que lo consulta.
- No hay salida analógica de vídeo ni de audio: todo va por el HDMI.
- No hay host USB en el ESP32-C6, por silicio; el teclado va por los USB de la placa.
- La variante con el V9958 original está eliminada del árbol; el V9968 es el único VDP.
- No hay firmware propio del BL616 para la 138K: el fork de TangCore del 60K no se ha compilado para ella y el partner firmware de Sipeed no conoce el panel F12. Flashear por el programador de Gowin no lo necesita.
