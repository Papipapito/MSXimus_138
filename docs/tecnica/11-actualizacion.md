# 11. La actualización desde el MSX

Cómo graba el MSX su propia flash (V3.8; en la 138K desde la v3.8.4, la primera V3.8 compilada para ella). El manual de usuario está en [manual/11-actualizar.md](../manual/11-actualizar.md); aquí va lo que hay debajo.

El puente, el formato `.UPD` y MXUPDATE son los mismos que en el 60K, donde están validados en placa desde la 3.8.0b3 (2 de octubre de 2026). Lo propio de la 138K (su IDCODE, su mapa de la flash y su carpeta en la web) está en las fuentes, pendiente de placa.

Las piezas:

| Pieza | Dónde | Qué hace |
|---|---|---|
| Puente de la flash | `fpga/src/flash_bridge.v` + `flash_rw.v` | Deja leer, borrar y programar la flash SPI de la FPGA por E/S |
| Formato `.UPD` | `tools/mxupd.py` | Fichero con los segmentos a grabar y sus CRC |
| `MXUPDATE.COM` | `tools/mxupdate/` | El programa de MSX-DOS: fichero o internet. Es el mismo `mxupdate.c` que en el repositorio del 60K (`MSXimus`); su banco (`banco/`) y `publicar_mxu.py` están aquí y allí, iguales |
| «Instalar actualización» | `bios-msxnano-msximus/src/actualizar.asm` | Lo mismo desde Ajustes, sin DOS, con el `.UPD` de la placa de la SD (`MSX138K.UPD` en la 138K) |
| La web | `https://msx.barcelona/wp-content/ota/tang138k/` | Los `.UPD` de la 138K y su `manifiesto.txt` |

## 1. El puente de la flash

Es un dispositivo de **E/S conmutada** más, como el de Panasonic y los demás de [02-puertos-es.md](02-puertos-es.md): se selecciona escribiendo su ID, **4Dh** ('M'), en el puerto 40h, y entonces 41h-4Fh son suyos. Con él seleccionado, `IN 40h` devuelve **B2h** (el ID invertido, como el resto).

| Puerto | Dirección | Qué |
|---|---|---|
| 41h | OUT | A[23:16] |
| 42h | OUT | A[15:8] (la dirección va en páginas de 256 bytes) |
| 43h | OUT | Orden: **1** borrar el sector de 4 KB de A[23:12]; **2** programar la página A[23:8] (después, 256 `OUT 44h`); **3** leer desde A[23:8]:00 (después, `IN 44h` byte a byte, seguidos); **0** acabar la lectura |
| 44h | OUT / IN | Dato a programar / dato leído (cada lectura pide el siguiente) |
| 41h | IN | Estado: bit 0 orden en curso o lectura sin dato todavía; bit 1 la programación espera un dato; bit 2 hay dato leído; bit 3 la flash la usa otro (el arranque o el cargador de ondas): esperar; bits 7-4 = **1010** (firma: hay puente) |
| 4Eh | OUT / IN | Información del menú para el OSD del BL616: bit 0 menú en inglés, bit 1 Nextor 3. Se guarda hasta apagar (el reset del MSX no la borra) |

Usa el módulo `flash` de `flash_rw.v`, el mismo que guarda los ajustes. Su escritura de siempre borra el sector y programa los bytes que le dan; para el puente se le añadió **programar sin borrar** (`write_noerase`) y **esperar a cada byte** (`write_din_ok`). Un borrado es su escritura de siempre con un solo byte FF (programar FF no cambia nada). Todo va en `clk_54m`, el reloj del módulo; las peticiones del bus se registran una vez, como las de la configuración.

La FPGA sigue funcionando con el bitstream que cargó al encender, así que grabar uno nuevo no la afecta hasta el siguiente encendido: si algo falla, se repite.

Banco: `tools/flash_tb` (el puente contra un modelo de la flash).

## 2. El formato `.UPD`

Little endian:

| Desplazamiento | Tamaño | Qué |
|---|---|---|
| 0 | 8 | `"MXUPD1"`, 1Ah, 0 |
| 8 | 16 | Placa: `console60k`, `console138k`, `msxnano` (con ceros) |
| 24 | 16 | Versión (`3.8.4`) |
| 40 | 16 | Variante: `nextor214`, `nextor3`, `nextor214-en`, `nextor3-en`, o `core` sin pack |
| 56 | 1 | Número de segmentos (1 a 4) |
| 57 | 7 | Ceros |
| 64 | 16·n | Por segmento: dirección en la flash, tamaño, CRC-32, desplazamiento en el fichero (u32 cada uno) |
| … | 4 | CRC-32 de todo lo anterior |

Los datos de cada segmento van en su desplazamiento, alineado a 256. El CRC-32 es el de siempre (zlib, polinomio EDB88320).

Direcciones por placa:

| Placa | IDCODE | Core | Pack | Ajustes | Ondas del OPL4 |
|---|---|---|---|---|---|
| 60K | 0001481Bh | 0x000000 | 0x400000 | 0x480000 | 0x500000 |
| **138K** | **0001081Bh** | 0x000000 | **0x500000** | **0x580000** | **0x600000** |
| MSXnano 2.1.1 | 0000081Bh | 0x000000 | 0x200000 | 0x280000 | — |

La 138K lleva la misma flash de 8 MB que el 60K (W25Q64); su bitstream, unos 4,9 MB (5.096.124 bytes), cabe por debajo del pack ([capítulo 03](03-mapas-memoria.md)). Cada segmento se acepta solo en su sitio: el core desde 0 y hasta el pack, el pack (512 KB) en la dirección del pack y las ondas (2 MB) 1 MB más arriba.

MXUPDATE 1.2 y los packs anteriores a `a8844a7` (rama `v38` de `bios-msxnano-msximus`) tenían la 138K con el pack en 0x800000, el mapa de 16 MB de la v3.7. Un `.UPD` de la 138K de ahora no cumple esa regla y lo rechazan como no válido sin tocar la flash. Hace falta **MXUPDATE 1.3** y los packs de la v3.8.4.

El bloque de ajustes **nunca** va en un `.UPD`. De los packs del MSXnano se quita la cola de 6 bytes de configuración. `MXUPDATE /R` borra el sector de los ajustes a propósito (0x580000 en la 138K): sin la firma «AB» el core arranca con los de fábrica, los mismos que el rescate con S2.

`tools/mxupd.py`:

```
python tools/mxupd.py crear -o MSX138K.UPD --placa console138k --version 3.8.4 --variante nextor214 \
    --bitstream msximus138.fs --pack pack_bios_msximus.bin [--onda yrw801.bin]
python tools/mxupd.py info MSX138K.UPD
python tools/mxupd.py publicar --dir <carpeta del servidor> --placa console138k --version 3.8.4 \
    --bitstream msximus138.fs --packs <bios-msxnano-msximus>/packs/msximus [--onda yrw801.bin] [--notas "..."]
```

`publicar` deja en `<dir>/tang138k/` los cuatro `.UPD` normales (`384_n214_es.upd`, `384_n3_es.upd`, `384_n214_en.upd`, `384_n3_en.upd`), los cuatro completos (`384_*_full.upd`, con `--onda`) y el `manifiesto.txt`.

## 3. El manifiesto

Texto, final de línea LF:

```
MSXIMUS-UPD 1
placa=console138k
version=3.8.4
notas=...
imagen=nextor214 384_n214_es.upd <tamaño>
imagen=nextor3 384_n3_es.upd <tamaño>
imagen=nextor214-en 384_n214_en.upd <tamaño>
imagen=nextor3-en 384_n3_en.upd <tamaño>
completa=nextor214 384_n214_es_full.upd <tamaño>
...
```

Las notas son solo para el usuario (las enseña `MXUPDATE /N`), de 60 caracteres como mucho. `/R` usa las líneas `completa=`.

## 4. `MXUPDATE.COM`

MSXgl + la librería UNAPI de red, compilado en el WSL (`tools/mxupdate/build.sh`, entorno de `sdk-tools/msx-unapi-env`). Lo que el UNAPI lee con la página 1 conmutada a su ROM o a su segmento (la cadena «TCP/IP» que busca EXTBIO y el nombre msx.barcelona para el DNS y el SNI) tiene que estar por debajo de 4000h o en RAM: `unapi_tcp_mxu.asm` (el `unapi_tcp.asm` de MSXgl sin UDP, IP en crudo, eco ni configuración) va el primero en `ProjModules`, justo detrás del arranque, y `g_web` es una variable en RAM. Los datos van desde 8000h (`ForceRamAddr`). El resto del código ya pasa de 4000h desde la 1.1.

**La tabla de placas.** `g_placas` lleva, por placa, los bits 23-8 del IDCODE, su nombre en el `.UPD` y en el manifiesto, su carpeta en la web, el byte alto de la dirección del pack y su `.UPD` por defecto. La de la 138K es `{ 0x0108, "console138k", "tang138k/", 0x50, "MSX138K.UPD" }` desde la **1.3** (en la 1.2, el pack en 80h); los ajustes van 512 KB detrás del pack y las ondas 1 MB detrás.

**Versión y autoactualización (1.1).** La versión está en un solo sitio, el cartel `"MXUPDATE " MXU_VERSION " - "`: se enseña al arrancar, se compara con la de la web y es lo que se busca en el `.COM` bajado. Antes de ir a por las imágenes de la placa (`/N`, o sin fichero y con un sí), MXUPDATE lee `mxupdate/manifiesto.txt` (el mismo formato, `placa=mxupdate`); si la versión es mayor, baja `MXUPDATE.COM` a `MXUPDATE.NEW` junto a sí mismo (variable `PROGRAM` de MSX-DOS 2), comprueba el tamaño y que lleve el cartel de esa versión, borra el viejo, renombra el nuevo y se relanza: un cargador de 30 bytes debajo del tope de la TPA lo lee sobre 0100h y salta, con la orden intacta en 0080h. Si algo falla, sigue con el que tiene.

Sin fichero, el de la placa (`MSX138K.UPD` en la 138K, el mismo que busca «Instalar actualización») o, si no está, un `MSXIMUS.UPD` que sea de esa placa; si no hay, ofrece bajarlo.

**Cada versión nueva de MXUPDATE**: subir `MXU_VERSION`, `build.sh`, `banco/run.sh` (todo bien), `python tools/mxupdate/publicar_mxu.py` y `python ota_subir.py mxupdate` (MSXimus_zynq/fpga/zynq/ota), y el `.COM` nuevo a las releases del 60K, del 138K y del MSXnano y a SD_Maker (`sd/extras/FPGA`). El banco y `publicar_mxu.py` están aquí y en el 60K, iguales; `mxupdate.c` tiene que ser el mismo en los dos.

Orden de trabajo:

1. Que el core tenga el puente (ID 4Dh, firma 1010 en el estado) y que la placa del fichero sea la de la flash: el IDCODE del bitstream grabado.
2. La cabecera y el CRC-32 de cada segmento **del fichero**, antes de borrar nada.
3. Borrar y programar sector a sector (4 KB). Las páginas que son todo FF no se programan.
4. Releer la flash entera y comprobar los CRC otra vez.

El CRC-32 en ensamblador cuesta unos 135 estados por byte. Tiempos medidos en el 60K a 3,58 MHz: el pack 75 s, core y pack 447 s (un `.UPD` de 3,1 MB), la completa 749 s (5,2 MB), más la SD; unos 144 s por millón de bytes. En la 138K el `.UPD` normal mide 5.620.736 bytes y el completo 7.717.888: unos 810 s y 1.110 s a ese ritmo, más la SD (en total, los 16 y 22 minutos del manual), sin medir todavía.

### Por internet (`/N`)

- A `msx.barcelona`, puerto 443, **TLS validando el certificado**. Si el ESP no puede validarlo (firmware sin autoridades de certificación), el mismo `TCP_OPEN` sin el bit de verificar, y avisa una vez: `Aviso: certificado sin validar.`. **En claro, nunca**: una versión anterior caía a HTTP:80 sin decir nada.
- La 138K baja de la carpeta `tang138k/`.
- HTTP/1.0 sin User-Agent: el IONOS de msx.barcelona sirve los estáticos con `Content-Length` y sin *chunked*.
- `Sin actualizaciones para esta placa (HTTP 404)` se distingue de `Sin conexion con el servidor`.
- `/S:ip[:puerto]` va a un servidor propio, en claro, con la misma estructura de carpetas: el de desarrollo es `fpga/zynq/ota/ota_servidor.py` del repo MSXimus_zynq.

El ESP32-C6 de la v3.8 lleva 16 autoridades de certificación de Mozilla de serie (`CaRaices.h` del repo ESP32-for-FPGA), entre ellas la Sectigo R46 de msx.barcelona, válida hasta 2046. El mbedTLS del core de Arduino 3.3.10 no mira las fechas, así que no depende del reloj.

## 5. «Instalar actualización» (Ajustes)

`actualizar.asm`, en la página 1 del menú (solo MSXimus). Hace lo mismo que `MXUPDATE.COM` sin MSX-DOS: busca el `.UPD` de la placa en la raíz de la SD con las rutinas del propio menú (`sd_read_sector`, `fatnext`, `clus2lba`), comprueba la cabecera y los CRC (`crc_mktab`, `crc_block`), y graba y relee igual. Usa como RAM la zona de la lista de ficheros (`ENT_ARRAY`); al salir pone `SD_READY = 0` para que el navegador la recargue. Sin puente, o en la MSXimus Z, lo dice y no hace nada.

La placa sale del IDCODE del bitstream grabado, como en MXUPDATE: con 0001081Bh pone el límite del pack en 50h (`UP_LIM`) y solo acepta un `.UPD` de `console138k`. El nombre que busca es el de MXUPDATE en cada placa: `MSX138K.UPD` en la 138K y `MSXIMUS.UPD` en el 60K. Copia a la RAM el aviso de «no hay» (`UP_NOF`), que lleva el nombre, y en la 138K le cambia `IMUS` por `138K`; de ahí salen el nombre que busca, el que enseña y el del aviso. Con solo un `MSXIMUS.UPD` en la raíz dice `No hay MSX138K.UPD en la raiz de la SD.` y no toca nada.

Banco: `bios-msxnano-msximus/tools/actualizar_tb` (Z80 emulado con la ROM y la página 2 reales, una SD FAT16 con el fichero troceado en la FAT, el puente con la flash del 60K o la de 8 MB de la 138K y fallos inyectados): 29 casos de las dos placas, con los del nombre del fichero, en castellano y en inglés (`--en` repite los 29).

## 6. Publicar

La web es `https://msx.barcelona/wp-content/ota/<placa>/`, con `tang60k`, `tang138k` y `msxnano`; el SFTP de IONOS solo llega a `wp-content`. Se sube con `fpga/zynq/ota/ota_subir.py` del repo MSXimus_zynq, que:

- comprueba en local los CRC de los `.UPD` y el manifiesto;
- sube cada fichero como `.subiendo` y lo renombra al acabar, y el manifiesto el último;
- lo vuelve a bajar por https, como haría una placa, para comprobarlo;
- deja la versión anterior en la web para volver atrás (`manifiesto.anterior.txt`).

## 7. Bancos

| Banco | Dónde | Qué prueba |
|---|---|---|
| `tools/flash_tb` | Este repositorio | El puente contra un modelo de la flash |
| `tools/mxupdate/banco` (`run.sh`) | Este repositorio (y el del 60K) | `MXUPDATE.COM` de verdad en un Z80 emulado con MSX-DOS, el puente, un ESP32 UNAPI y una web de imitación: flash del 60K, 138K y MSXnano, fichero dañado, otra placa, no, sin puente, `/C`, `/R`, y por red validado, sin validar, 404, sin TLS, descarga cortada y completa |
| `tools/actualizar_tb` | `bios-msxnano-msximus` | «Instalar actualización» |
| `tools/firma_tb` | `bios-msxnano-msximus` | La firma de tipo de ROM del menú ([manual/05](../manual/05-roms-mappers.md)) |
