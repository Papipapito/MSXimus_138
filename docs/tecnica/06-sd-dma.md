# 06. La tarjeta SD y la DMA

Cómo llega un sector de la tarjeta a la memoria del MSX. Hay cuatro caminos, del más antiguo al más rápido, y todos gobiernan el mismo controlador. Sale de `fpga/src/wondertang/` (el lector, el controlador de órdenes y los puertos), de `fpga/src/sd_dma.sv` y del driver `nextor214/sd_rw_ports.inc` del repositorio de la BIOS.

## 1. El controlador

La tarjeta se maneja en **modo SD nativo de un bit**, no en SPI: líneas CMD, CLK y DAT0. El lector es el `sd_reader` del proyecto WonderTANG, con la escritura que le añadió Felipe Antoniosi, y encima de él el MSXimus ha ido poniendo capas:

| Capa | Qué aporta |
|---|---|
| `sdcmd_ctrl` | Las órdenes SD y su CRC7 |
| `sd_reader` | Inicialización de la tarjeta (SD v1, v2 y SDHC), lectura y escritura de sector, CRC16 de datos, y desde la 3.5c **multibloque** con CMD18 y CMD25 sobre un único búfer de 512 bytes |
| Búfer de sector | Una BSRAM de doble puerto: el puerto A lo ve el Z80, el puerto B lo ve la tarjeta, y también la DMA |
| `sdc_ioport` | Los registros en los puertos 47h-4Fh |
| `sd_dma` | La copia del búfer a la RAM sin pasar por el Z80 |

Dos relojes. La inicialización va a 69,6 kHz, por debajo de los 400 kHz que exige la norma. La transferencia va a **6,75 MHz**: el divisor rápido está a cero, que es el mínimo del diseño actual porque el periodo de `sdclk` son `2 × divisor + 4` ciclos de 27 MHz. Subir a 13,5 MHz exigiría rehacer el divisor y el muestreo, y es la fase 3 pendiente.

Todo el módulo va en `clk_27m` y sus salidas están registradas, con las órdenes convertidas en pulsos de un ciclo con el dato ya capturado. No es una elección de estilo: los nodos IORQ_n y WR_n del Z80 están saturados en esta FPGA, y colgar de ellos un decodificador combinacional se llevó por delante tres campañas de síntesis seguidas antes de hacerlo así.

Un detalle de arranque que costó encontrar: el lector solo acepta la orden de inicializar estando en reposo. Si algo arranca la tarjeta antes que Nextor, la petición de Nextor se ignora en silencio y el MSX no arranca. El menú, que monta la tarjeta antes que Nextor, la deja en reposo al terminar.

## 2. Los cuatro caminos

### Camino 1: la ventana de memoria

El interfaz original del WonderTANG. En la página 1 del slot 3-2, activa tras escribir un 1 en 7E00h:

| Dirección | Contenido |
|---|---|
| 7C00h-7DFFh | El búfer de sector, 512 bytes, byte a byte |
| 7E00h | Habilitar (1) o deshabilitar (0) los registros |
| 7E01h | Orden: 1 leer, 2 escribir, 80h inicializar |
| 7E02h | Estado |
| 7E03h-7E06h | Número de sector, cuatro bytes |
| 7E07h-7E18h | Datos de la tarjeta: tamaño, multiplicador, longitud de bloque, tipo, fabricante, OEM, nombre, número de serie |
| 7E80h | Habilitar el SCC+ |

Un sector por orden, y el Z80 lo saca del búfer con LDIR a 21 T-estados por byte. Es el camino de los drivers antiguos y sigue funcionando tal cual; una orden dada por la ventana fuerza el contador de bloques a 1.

### Camino 2: los puertos, sector a sector

Los registros del capítulo 02 en 47h-4Fh. La ganancia es que el búfer se lee con INIR, a 16 T-estados por byte, y que el búfer de destino puede estar en cualquier página, no solo donde la ventana deje sitio. Con Nextor 3 eso resolvió un solape entre su kernel y la ventana.

### Camino 3: los puertos, multibloque

Con N mayor que 1 en 4Dh, la orden de 47h lanza un CMD18 o CMD25 y la tarjeta encadena N sectores sin volver a negociar. Con un solo búfer, el protocolo entre el lector y el que vacía es este: cuando hay un bloque en el búfer, el lector para el reloj de la tarjeta, la tarjeta se queda en espera, y levanta `blk_rdy`; el que vacía lee los 512 bytes por 4Ch y, al pasar por el byte 511, el puerto emite `buf_ack`, que reanuda el reloj y trae el siguiente bloque. En escritura es simétrico.

### Camino 4: la DMA

Con el bit 2 en la orden de lectura, el búfer no lo vacía el Z80 sino el core. La cuenta que lo motivó: la tarjeta tarda 0,6 ms en traer un bloque y el Z80 tardaba 3 ms en vaciarlo, así que la tarjeta esperaba parada el 80 % del tiempo. Con la DMA el vaciado son 150 µs y el cuello vuelve a ser la tarjeta.

Las velocidades medidas en placa con la prueba 1 del menú de pruebas, sobre los mismos 128 KB:

| Camino | KB/s |
|---|---|
| Ventana | 90 |
| Puertos, sector a sector | 104 |
| Puertos, multibloque | 112 |
| DMA | 640 |

Con turbo los tres caminos por Z80 suben (109, 129 y 144) y la DMA no cambia, porque durante ella la CPU está parada.

## 3. Cómo funciona la DMA

La máquina de estados vive en `clk_54m`, el dominio de la RAM:

1. El Z80 deja el destino con `OUT 4Fh,80h` seguido de tres bytes, programa el sector y los bloques, y da la orden 05h en 47h. La instrucción siguiente al OUT no llega a ejecutarse hasta que todo ha acabado.
2. La DMA pide congelar la CPU y espera a que el bus esté en reposo: sin ciclo de memoria ni de E/S en curso, sin M1, sin espera pendiente y con el controlador de RAM libre. Entonces corta la habilitación de reloj del Z80. Sin CPU no hace falta árbitro: el puerto de RAM queda libre y la DMA escribe por el mismo camino de streaming que usa la flash al arrancar.
3. Por cada bloque espera a `blk_rdy`, o al fin de la orden en el último bloque, que no lo levanta. Antes del primer byte deja pasar 40 ciclos de guarda por si hay un refresco de SDRAM en vuelo. Luego lee los 512 bytes por el puerto B del búfer, que está ocioso mientras la tarjeta espera, y los escribe uno por turno del controlador. Al terminar manda `buf_ack`.
4. Con la orden acabada y el búfer vacío, suelta la CPU. El Z80 despierta en la instrucción siguiente al OUT y lee el estado de 47h como siempre.

Si la orden falla, por timeout o por CRC, el bloque no se copia y la máquina termina igual: nunca se queda colgada, y el estado dice qué pasó.

**El refresco de la SDRAM** es la parte delicada. Con la CPU parada, el controlador entra en refresco autónomo, y ese refresco puede pisar una escritura en vuelo. Por eso la DMA solo lo permite mientras está esperando a la tarjeta, que son 600 µs por bloque, de sobra para varios refrescos, y lo prohíbe durante la ráfaga de escrituras. Esa señal entra en la misma `cpu_run` que gobierna el refresco en todos los demás casos, y desde la 3.6d va registrada porque era el peor camino de temporización de la campaña.

**Coste**: unos 150 registros y ninguna BSRAM, que está al 100 %. Nada en el cono de la CPU: el mux de la RAM sigue teniendo dos ramas, y la elección entre flash y DMA va por debajo, sobre registros.

### Los dos modos de destino

| Modo | Byte alto del destino | Dirección |
|---|---|---|
| **Físico** | bit 7 = 0 | 23 bits de RAM, lineal. El menú carga así la megaram: la dirección de un segmento es `{~A21, A21, A[20:0]}` con A = mitad × 2 MB + segmento × 8 KB + desplazamiento |
| **Lógico** | bit 7 = 1 | Los 16 bits bajos son una dirección del Z80. El core la traduce con los registros del mapper: física = `{00, registro[página][6:0], desplazamiento[13:0]}`, en el banco A. Al cruzar los 16 KB pasa a la página siguiente, como haría el Z80 escribiendo de seguido |

El modo lógico existe porque los registros FCh-FFh son de solo escritura: el driver de Nextor no puede leerlos para calcular una dirección física, pero el core sí los tiene. Ojo con el armado: 80h en 4Fh arma el registro solo estando desarmado; una vez armado, un tercer byte de 80h es un destino lógico con segmento 0. Así el menú anterior sigue valiendo.

### Los contadores de mapper

Con el bit 3 en la orden, mientras copia, la DMA busca el patrón `32 lo hi`, la instrucción LD (nn),A con que los mappers cambian de banco, y cuenta las direcciones que caen en cada familia:

| Familia | Direcciones |
|---|---|
| Konami-SCC | 5000h, 9000h, B000h y 7000h |
| Konami | 4000h, 8000h, A000h y 6000h |
| ASCII8 | 6800h, 7800h y 6000h, 7000h |
| ASCII16 | 6000h, 7000h y 77FFh |

Es la misma tabla que usaba el menú escaneando byte a byte en el Z80. El bit 4 pone los contadores a cero antes; sin él acumulan de una orden a la siguiente, que es lo que hace el menú a lo largo de los 256 KB que analiza. Un patrón que cruza de bloque se detecta igual, porque la ventana de tres bytes no se reinicia entre bloques. El resultado se lee en 4Eh, índices 32 a 39, y el análisis de una ROM sin etiqueta pasa de siete segundos a nada: es la misma DMA que ya la estaba cargando.

Las ROMs que cambian de banco de otra forma, con LD (HL),r por ejemplo, no dejan patrón y el mapper hay que elegirlo a mano con la tecla M.

## 4. Quién usa cada camino

| Cliente | Camino | Notas |
|---|---|---|
| Menú, cargar una ROM | DMA física por clusters enteros | Si el core no contesta 'D' en el índice 29, vuelve a los puertos con INIR |
| Menú, analizar una ROM | DMA con contadores | Sin 'M', DMA sin contadores y escaneo con CPIR desde la ventana de la megaram; sin 'D', el escaneo antiguo sector a sector |
| Menú, montar un disco | Puertos | Solo escribe el descriptor de emulación de Nextor |
| Driver de Nextor, lectura | DMA lógica | Solo si el core contesta 'M' y todas las páginas del búfer son RAM del mapper en el slot 3-0 y ninguna es la página 1, donde vive el propio driver. Si no, puertos con INIR |
| Driver de Nextor, escritura | Puertos multibloque con OTIR | No hay DMA de escritura |
| Drivers antiguos | Ventana | Sin cambios |

El driver de Nextor es un único include compartido por Nextor 2.1.4 y Nextor 3: sondea el core al arrancar (un core sin puertos devuelve FFh en 47h) y elige el camino en cada petición. El pack de Nextor 3 del MSXnano lleva la misma ROM; allí la sonda falla y va por la ventana.

## 5. Firmas: cómo sabe el software qué core tiene delante

| Sonda | Significa |
|---|---|
| IN 47h distinto de FFh, con el bit 4 a 1 y los bits 6-5 a 0 | Hay puertos (3.5c o posterior) |
| 4Eh índice 28 = 'T' | Hay cronómetro (3.5d) |
| 4Eh índice 29 = 'D' | Hay DMA de lectura (3.6) |
| 4Eh índice 31 = 'M' | La DMA tiene modo lógico y contadores (3.6c) |

Un mismo pack de BIOS funciona con cualquier core desde la 3.5c: cada pieza sondea y se degrada al camino anterior.

## 6. Verificación

- `tools/sd_tb/`: bancos en Icarus Verilog con un modelo de tarjeta. `tb_sd` para el lector en sus tres velocidades, `tb_sdio` para los puertos, `tb_mstimer` para el cronómetro, `tb_glue` para el pegamento con el bus y `tb_sddma` para la DMA: registro de destino, CMD17, CMD18 de cuatro bloques, espera con el bus ocupado, orden normal tras una DMA, guarda del refresco, modo lógico cruzando de página y contadores contra una cuenta por software.
- En placa: tecla T, prueba 1, mide los cuatro caminos sobre los mismos 128 KB con el cronómetro del core. Solo lee.
