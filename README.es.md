<p align="center"><img src="docs/logo/msximus.svg" alt="MSXimus" width="480"/></p>

<h1 align="center">MSXimus</h1>
<p align="center"><b>Un MSX2+ completo, en una Tang Console 138K — ahora con el VDP V9968</b></p>

> **Este repositorio es el porte del MSXimus a la Tang Console 138K (MSXimus_138, v3.8.4).** Lo específico del porte (SOM Mega 138K, mapa de flash, cascada de PLL, campañas, lo probado y lo no probado) está en [README.138.md](README.138.md); la documentación adaptada al 138K, en [docs/INDICE.md](docs/INDICE.md). La instalación, la actualización y el panel F12 se cuentan aquí para la 138K; el resto es el MSXimus tal como nació en la Tang Console 60K: la misma placa base y el mismo core.
<p align="center">
  <img alt="version" src="https://img.shields.io/badge/versi%C3%B3n-v3.8.4-blue">
  <img alt="fpga" src="https://img.shields.io/badge/FPGA-Gowin%20GW5AST--138-green">
  <img alt="licencia" src="https://img.shields.io/badge/licencia-GPLv3-orange">
</p>

<p align="center">🇬🇧 <a href="README.md">English version</a></p>

<p align="center"><img src="docs/img/v9968_devcon.jpg" alt="La demo DEVCON del V9968 corriendo en el MSXimus" width="820"/></p>
<p align="center"><i>La demo oficial del V9968 de HRA!, corriendo en el MSXimus.</i></p>

---

**MSXimus** es el hermano mayor del [**MSXnano**](https://github.com/Papipapito/MSXnano): el mismo linaje de core MSX2+ (goauld → MSXnano), portado y ampliado sobre la **Tang Console 60K**. *Nano* era el pequeño; *Maximus* es el grande.

No necesita un MSX. Es un MSX.

## Por qué v3.1 y no v2.2

Porque se movió el suelo.

En agosto de 2026 Gowin confirmó que el **SSRAM del GW5AT-60B está retirado a propósito**: hay un problema de silicio en investigación, y su recomendación es migrar a BSRAM o a registros todo lo que lo use.

La v2.1 tiraba mucho de ese recurso — solo los motores de audio se llevaban la mayor parte. Así que la v3 no es la v2.1 con cosas nuevas encima: es el mismo MSX **reconstruido para que no quede ni un bit sobre el recurso retirado**. Cada memoria que vivía ahí se mudó a BSRAM o a registros, y eso obligó a rehacer por dentro el motor wavetable del OPL4, los ficheros de registro del OPL3 y la caché del PCM.

Eso es un cambio en los cimientos, no en la superficie, y merecía número propio. Todo lo que ya conocías funciona exactamente igual; lo que ha cambiado es sobre qué se apoya.

## Qué lleva dentro

**Vídeo** · Salida HDMI 720p a pantalla completa · **V9968** o V9958 · bordes estilo CRT · scanlines conmutables desde el menú

**Audio** · PSG · doble SCC con estéreo · OPLL (MSX-Music) · **MSX-Audio Y8950** con FM y ADPCM-B · **MoonSound / OPL4** completo, FM (OPL3) y wavetable de 24 voces

**Almacenamiento** · Nextor sobre microSD · megaram de 8 MB con Konami4, Konami-SCC, ASCII8, ASCII16, NEO-8, NEO-16, ASCII16-X y Plain 0000h

**Entrada** · Teclado USB directo sin hub, con F1–F10 físicas · gamepads USB mapeados a joystick MSX · ratón USB como ratón MSX

**En pantalla** · **Panel de estado en F12** opcional, en color, pintado sobre el MSX por el BL616 que la placa ya lleva

**Actualizaciones** · Desde el propio MSX, sin PC: `MXUPDATE /N` baja la última versión de internet y la graba; también vale un fichero `.UPD` en la SD

**WiFi** · UNAPI mediante un **ESP32-C6** externo, con **pantalla opcional** para información adicional

**Extras** · Turbo Panasonic 5,37 MHz en **F11** · identificación de máquina estilo turboR · dos BIOS a elegir · logo de arranque · control de ventilador por temperatura · telemetría por puerto serie para diagnóstico

## Hardware necesario

| | Qué | Notas |
|---|---|---|
| **Obligatorio** | [Sipeed **Tang Console 138K**](https://wiki.sipeed.com/hardware/en/tang/tang-console/mega-console.html) | SOM Tang Mega 138K (Gowin GW5AST-138), HDMI, 2× USB-A, microSD, DDR3 |
| **Obligatorio** | Módulo de **SDRAM** de la Console | Es la RAM del MSX; sin él el core no arranca |
| Opcional | **Disipador de 20×20 mm** sobre el SOM | Recomendado: el core va bastante cargado. [Como estos](https://s.click.aliexpress.com/e/_c4WMlpD9) |
| Opcional | **Ventilador de 20×20 mm** de 5 V | Conector **JST de 1,25 mm, 2 pines** — [como este](https://s.click.aliexpress.com/e/_c328rXwB). Se gobierna solo por temperatura |
| Opcional | Teclado y gamepad **USB** | Directos a los USB-A de la placa, sin hub |
| Opcional | **Ratón USB**, con cable | Directo a la placa. ⚠️ Un receptor **inalámbrico** no vale: se presenta como dispositivo compuesto |
| Opcional | **ESP32-C6** (Waveshare C6-LCD-1.3) | Para el **WiFi**, con pantalla opcional de información |
| Opcional | *Nada que comprar* — el **BL616** de la propia placa | Habilita el panel de estado de F12. Hay que grabarle el firmware una vez |

El ventilador no hace falta para funcionar. Si lo pones, el core lo controla solo: mide la temperatura del chip con un termómetro interno y solo sopla cuando toca.

## Instalación

Todo va a la **flash SPI** de la placa, en tres direcciones distintas. ⚠️ **Son las direcciones del 138K**: su bitstream mide el doble, así que el pack y las ondas del OPL4 van 1 MB más arriba que en el 60K (allí, `0x400000` / `0x500000`). La flash es de 8 MB y las ondas ocupan sus últimos 2 MB.

| # | Fichero | Dirección | ¿Obligatorio? |
|---|---|---|---|
| 1 | `msximus138_v3.8.4_dado5569.fs` | **`0x000000`** | Sí — es el core |
| 2 | Pack de BIOS (`pack_bios_msximus*.bin`) | **`0x500000`** | Sí — sin él no arranca el MSX |
| 3 | `yrw801.bin` | **`0x600000`** | No — solo para MoonSound/OPL4 (la ROM de ondas va como `.bin`: el Programmer de Gowin no acepta `.rom`; si tienes una `yrw801.rom`, cámbiale la extensión) |

El resto de la release no va a esa flash:

| Fichero | Dónde |
|---|---|
| `MXUPDATE.COM` | A la SD: actualiza la placa desde el MSX ([más abajo](#actualizar-desde-el-msx)) |
| `bl616_msximus_v3.8_138k.zip` | Al BL616, para el panel de F12 (opcional) |
| `firmware_esp32c6_v3.8_merged.bin` | Al ESP32-C6, para la WiFi (opcional) |

Cada pieza opcional tiene su sección más abajo.

**Esto solo hace falta una vez.** Desde la v3.8.4, las siguientes actualizaciones se hacen desde el propio MSX: ver [Actualizar desde el MSX](#actualizar-desde-el-msx).

**Las herramientas que necesitas**, todas gratuitas y todas oficiales:

| Para | Herramienta |
|---|---|
| Los tres ficheros de arriba | [**Gowin Programmer**](https://www.gowinsemi.com/en/support/download_eda/) (el que viene con el IDE 1.9.12 va bien) |
| ESP32-C6 (WiFi) | [**esptool-js**](https://espressif.github.io/esptool-js/) en el navegador — sin instalar nada — o `esptool` |
| BL616 (panel de F12) | [**Bouffalo Lab Dev Cube**](https://github.com/bouffalolab/bouffalo_sdk) (BLDevCube) |

### Cómo grabarlo

1. Conecta la placa por el **USB-C** y abre el **Gowin Programmer** (va bien el de la versión 1.9.12).
2. Deja que detecte el dispositivo: debe salir el **GW5AST-138**.
3. Para **cada** uno de los tres ficheros, configura una operación de escritura en la **flash SPI externa** (las opciones que empiezan por *exFlash*, no las de SRAM), pon el fichero en *Programming File* y **la dirección de la tabla en el campo de dirección de inicio**. Usa *exFlash Erase,Program,Verify* para el `.fs` y *exFlash C Bin Erase,Program* para el pack y la `yrw801.bin`: con la primera, el Programmer rechaza un fichero en bruto con un error de "id-code" distinto. Si el campo de dirección tiene siete cifras, el pack va como `0x0500000` y las ondas como `0x0600000`.
4. Graba primero el `.fs` y luego los otros dos. El orden entre ellos da igual, pero **las direcciones no**: si el pack no cae exactamente en `0x500000`, el core arranca y se queda en negro.
5. **Apaga y enciende la placa.** Un reset **no** basta: la DDR3 necesita recalibrar desde frío y con un reset caliente puede quedarse colgada.

> Si al arrancar ves la pantalla azul y nada más, casi siempre es (a) el pack en la dirección equivocada, o (b) que no has hecho el ciclo de apagado.

### Sobre el pack de BIOS

La release trae **todo lo necesario**: el core, el pack de BIOS, la `yrw801.bin` del OPL4 y los firmwares. Descargas, grabas y arranca.

Hay **cuatro versiones del mismo pack**: el menú en castellano o en inglés, y el kernel de disco que llevan dentro:

| Pack | Menú | Nextor |
|---|---|---|
| `pack_bios_msximus.bin` | castellano | **2.1.4** — la estable |
| `pack_bios_msximus_en.bin` | inglés | **2.1.4** — la estable |
| `pack_bios_msximus_nextor3.bin` | castellano | **3.0 beta 2** — para probar la beta |
| `pack_bios_msximus_en_nextor3.bin` | inglés | **3.0 beta 2** — para probar la beta |

Si prefieres montarte el pack con tus propias ROMs, está el [**MSXnano Pack Builder**](https://github.com/Papipapito/MSXnano), que arma el fichero con ellas, Nextor incluido.

Sin la `yrw801.bin` el core funciona igual; simplemente no tendrás MoonSound.

### Una sola BIOS, y el menú es un ajuste

Hasta la v3.1 había **dos** packs y tenías que decidir cuál grabar. Ahora hay **uno**, y aquella elección es una casilla en Ajustes.

Al encender, la máquina **arranca el MSX directamente**. Si quieres el navegador de la SD: pulsa **S** al arrancar, marca **«Menu al arrancar»** y `Save & Restart`. Para volver a la salida directa, lo desmarcas. La elección se guarda en la flash de la placa, así que sobrevive al apagón.

Con el menú encendido tienes el navegador de la tarjeta, el lanzador de ROM y DSK y —si has puesto el WiFi— la tecla **F** para buscar y descargar ROMs y discos directamente a la microSD, sin PC.

> Montar un `.dsk` reescribe sectores de un fichero **que ya existe**: no crea entradas de directorio ni asigna clústeres.

Después, mete una microSD con tus ROMs y discos y listo. La mejor forma de prepararla es **[MSX SD Maker](https://github.com/Papipapito/SD_Maker)**, que tiene su propio repositorio (en [`MSXsdmaker/`](MSXsdmaker/LEEME.md) hay una copia con sus instrucciones): un programa para Windows que parte la tarjeta como lo hace Nextor, copia Nextor y una colección de programas (SofaRun, Multi Mente…) y escribe el `AUTOEXEC.BAT`.

> **Sobre las microSD:** usa una tarjeta **de marca y Clase 10** (Samsung, SanDisk, Kingston...), formateada en **FAT16**. Las tarjetas baratas sin marca leen bien pero rechazan o pierden escrituras en ráfagas sostenidas — lo medimos en placa: una sin marca fallaba escrituras incluso con pausas, y una Samsung EVO+ iba perfecta con el mismo código y la misma geometría. Si las descargas o los guardados fallan, sospecha de la tarjeta primero.

## Actualizar desde el MSX

Desde la v3.8 el MSXimus se actualiza **solo**: el core y el pack de BIOS se graban en la flash de la placa desde el MSX, sin PC y sin programador. En la 138K la primera v3.8 es la v3.8.4, y hay que grabarla con el PC (es la que trae el *puente de la flash*, lo que deja al MSX escribir en ella); a partir de ahí vale cualquiera de estos tres caminos:

| Camino | Qué hace | Hace falta |
|---|---|---|
| `MXUPDATE /N` | Baja la última versión de la 138K de [msx.barcelona](https://msx.barcelona) y la graba | MSX-DOS 2 o Nextor, y el ESP32-C6 (WiFi) |
| `MXUPDATE fichero.UPD` | Graba un fichero `.UPD` de la 138K de la SD | MSX-DOS 2 o Nextor |
| Ajustes → **Instalar actualización** | Graba el `MSX138K.UPD` de la raíz de la SD (el mismo nombre con el que lo guarda `MXUPDATE /N`) | Nada más: sin DOS |

**Los arreglos llegan solo por aquí.** GitHub lleva las versiones grandes; los arreglos se publican solo para `MXUPDATE /N`. Se graba una vez la release de GitHub y con `MXUPDATE /N` se llega a la última.

`MXUPDATE.COM` va en la release y, en una tarjeta hecha con [MSX SD Maker](https://github.com/Papipapito/SD_Maker), en la carpeta `FPGA` (en el `PATH`). La 138K necesita la **1.3 o posterior**: la 1.2 esperaba el pack de la 138K en la dirección de antes y rechaza sus ficheros sin tocar nada. La release publicada de MSX SD Maker (la 1.4) lleva la 1.2: copia el `MXUPDATE.COM` de esta release encima de `FPGA\MXUPDATE.COM`, o lanza `MXUPDATE /N`, que antes de nada se pone al día solo. Reconoce la placa sola, habla el idioma del menú y **se actualiza solo**: antes de buscar un core nuevo en internet mira si hay un MXUPDATE más nuevo; si lo hay, lo baja, lo comprueba, se sustituye y sigue con el nuevo.

```
MXUPDATE                  graba el fichero de esta placa del directorio actual (MSX138K.UPD en el
                          138K, MSXIMUS.UPD en el 60K, MSXNANO.UPD en el MSXnano); si no esta,
                          ofrece bajar la ultima version
MXUPDATE fichero.UPD      graba ese fichero
MXUPDATE /C fichero.UPD   solo lo comprueba (cabecera y CRC); no toca la flash
MXUPDATE /N               baja la ultima version y la graba
MXUPDATE /N /R            la completa (core, pack y ondas del OPL4) y ajustes de fabrica
MXUPDATE /H   /?          la ayuda: las ordenes, sin tocar nada
```

Con `/N` eliges la variante (Nextor 2.1.4 o 3, menú en castellano o en inglés), la baja a la SD, la comprueba, pregunta, la graba y relee la flash entera para comprobarla otra vez. Después: **apagar y encender**. La conexión es **TLS con el certificado validado**, con el firmware del C6 de la v3.8, que trae las autoridades de certificación; con uno anterior funciona igual, sin validar, y lo dice.

Todo se comprueba **antes de borrar nada** y la flash se relee al final. Si algo sale mal, el MSX sigue con el core de antes hasta que se apaga, así que basta con repetir; y por el USB-C, con el Gowin Programmer, la placa siempre se puede volver a grabar: así no se puede estropear. Los ajustes guardados se conservan (solo `/R` los borra, a propósito).

Tiempos, porque todo lo hace el Z80: solo el pack, 1,5 minutos. El core de la 138K mide el doble que el del 60K, así que core y pack tardan unos 16 minutos y la completa unos 22 (estimados con lo medido en el 60K); más la descarga. Todo lo demás está en el manual: [`docs/manual/11-actualizar.md`](docs/manual/11-actualizar.md).

## El panel de estado — F12 (opcional)

La Console 138K lleva, como la 60K, un segundo chip que probablemente no hayas usado nunca: un microcontrolador **BL616**, conectado a la FPGA de fábrica. Dale un firmware y te pinta un panel de estado directamente sobre la imagen del MSX.

Pulsas **F12** y el MSX se congela y sale el panel, en color. Lo pulsas otra vez (o ESC) y la partida sigue exactamente donde estaba. Es de **solo lectura** — no hay menú, ni cursor, ni nada que romper. Enseña lo que el core dice de sí mismo, en el idioma del menú:

```
  MSXimus 138K                V3.8.4
  MSX
    Z80     3,58 MHz   normal
    Vídeo   V9968 · HDMI 720p
  Tarjeta SD
    SDHC    lista
  Ajustes
    Scanlines      Estéreo
    Segundo SCC
  USB
    Puerto 1  teclado    Puerto 2  mando
  Sistema
    Ventilador        parado
    Bloq. mayúsculas  no
  Actualizar: MXUPDATE /N
  [F12] Volver al MSX
```

Y no te cuesta nada en hardware: **ni cables, ni soldar, ni módulo**. El enlace entre los dos chips (una línea serie a 2 Mbps) ya estaba rutado en la placa; simplemente no se usaba.

> Como el BL616 se queda la F12 para él, esa tecla no llega nunca al MSX. **El turbo está en F11.**

### Grabar el BL616

La release lo trae en un ZIP, **`bl616_msximus_v3.8_138k.zip`**: la imagen del MSXimus, que va en **`0x40000`**, y el `.ini` que la graba. El firmware de Sipeed que la Console 138K lleva en `0x0` no se toca: los dos **conviven**.

1. **Mantén pulsado el botón BOOT mientras enchufas el USB.** Eso mete el chip en modo ISP.
2. Aparece un **puerto COM nuevo** — ese es el BL616. (Listar los puertos antes y después de enchufar es la forma fácil de saber cuál.)
3. Descomprime el ZIP en una carpeta, abre **BLDevCube** y carga su **`flash_prog_cfg.ini`**: ya trae la imagen con su dirección, así que no hay que teclearla.
4. Desenchufa el USB del PC y alimenta la placa con un **cargador USB**.

> El panel solo funciona con la placa alimentada por un cargador: con el USB del PC enchufado, el BL616 hace de puente JTAG para el Gowin Programmer y no hay panel.

El modo ISP vive en la ROM del chip, no en su flash, así que funciona pase lo que pase con lo que hayas escrito. **Es la marcha atrás que nunca falla**: por aquí no puedes dejar la placa inservible.

Y si prefieres no grabarlo, no lo grabes: el MSX funciona exactamente igual, simplemente no tendrás el panel de F12.

## Conexión del ESP32-C6 (WiFi)

Opcional — el core funciona igual sin él; simplemente no tendrás WiFi. Son tres o cuatro cables entre el conector **J10** de la placa y el módulo:

<p align="center"><img src="docs/img/esp32_c6_j10.svg" alt="Diagrama de conexión del ESP32-C6 al J10" width="820"/></p>

| Pin J10 | Señal | Bola FPGA | ESP32-C6 |
|---|---|---|---|
| **11** | +5 V (alimentación) | — | **5V** (tira derecha, el último) |
| **12** | GND | — | **GND** (tira derecha) |
| **14** | TX (FPGA → C6) | W21 | **IO17** (tira izquierda, el RX del C6) |
| **16** | RX (FPGA ← C6) | N17 | **IO16** (tira izquierda, el TX del C6) |
| **18** | TURBO (FPGA → C6) | N13 | **GPIO3** (tira derecha, el primero) — opcional, solo alimenta el indicador de turbo de la pantalla |

Y así queda del lado del módulo:

<p align="center"><img src="docs/img/esp32_c6_pinout.jpg" alt="Pines del ESP32-C6 usados por el MSXimus" width="820"/></p>

- **J10 es el conector 2×20 libre**, el que el esquemático de Sipeed llama *SDRAM1 CONN.* — **no** el que lleva el módulo de SDRAM que el core necesita.
- **Identificar los pines sin serigrafía**: con la placa apagada y el polímetro en continuidad, **el pin 12 es el único de todo el conector con paso a masa**. Su compañero de fila es el 11 (+5 V), y desde el 12, hacia el lado largo (el que deja 14 filas, no 5), van el 14, el 16 y el 18.
- **La alimentación sale del propio J10** (pin 11 → `5V` del módulo): el USB-C del C6 solo hace falta para grabarle el firmware.
- ⚠️ **Mejor no tener las dos alimentaciones a la vez**. El módulo lleva protección y aguanta, pero al grabar el firmware por USB-C lo recomendable es desconectar el cable de 5 V (o apagar la placa).
- TX y RX van **cruzados**, como siempre. La UART va a 859 372 baudios.
- ⚠️ Si algún día pinchas un segundo módulo de SDRAM en J10, hay que mudar el ESP a otro sitio.

### Grabar el C6

El firmware del módulo y su inventario técnico completo viven en su propio repositorio, [**ESP32-for-FPGA**](https://github.com/Papipapito/ESP32-for-FPGA) — el mismo binario sirve al MSXimus y al MSXnano, así que ya no se guarda una copia aquí. Coge el `firmware_esp32c6_v3.8_merged.bin` de la release y grábalo en el C6 por **su propio USB-C**. El de la v3.8 lleva las autoridades de certificación con las que `MXUPDATE /N` valida el certificado de msx.barcelona (duran hasta 2046: no hay que regrabarlo cuando la web renueva su certificado). **No** hace falta el IDE de Arduino, ni compilar nada: la release trae un único binario ya fusionado.

**Lo fácil — desde el navegador, sin instalar nada.** Abre [**esptool-js**](https://espressif.github.io/esptool-js/), el grabador web del propio Espressif, en Chrome o Edge. Conectas, eliges el fichero, pones la dirección `0x0` y le das a Program. Sin drivers, sin Python, sin IDE.

**Por línea de órdenes**, si ya lo tienes:

```
esptool --chip esp32c6 --port COMx write_flash 0x0 firmware_esp32c6_v3.8_merged.bin
```

> No hay una vía de arrastrar y soltar como el `.uf2` de la Raspberry Pi Pico: el ESP32 no lleva bootloader de almacenamiento masivo en ROM, así que copiar un fichero a una unidad no es posible en **ningún** ESP32. El grabador web de arriba es lo más cerca que se puede estar: una página, dos clics y nada instalado.

## La carcasa

Una carcasa para imprimir en 3D con la forma de un Spectravideo SVI-728, con la Console 60K dentro, una bahía con tapa para el ESP32-C6 y su pantalla, ventilador, y los conectores sacados atrás y al frontal. Deriva de la [SVI-728 Retropie case](https://www.thingiverse.com/thing:4066021) de Palver.

<p align="center"><img src="docs/img/carcasa/carcasa_teclado.jpg" alt="La carcasa impresa, con la tapa de la pantalla abierta" width="820"/></p>
<p align="center"><img src="docs/img/carcasa/carcasa_abierta_pantalla.jpg" alt="Por dentro: la Console 60K, el C6 en su bahía, el cableado" width="820"/></p>

El proyecto de Bambu Studio, los STL, los ajustes de impresión y las notas de montaje están en [`carcasa/`](carcasa/README.md).

## Estado

**La v3.8.4 (17/10/2026) es la primera v3.8 de la Console 138K.** Su RTL es el de la v3.8.4 del 60K, validada en una 60K el 16/10/2026, más lo propio de la 138K (relojes, mapa de flash, timing). **Todavía no está validada en una 138K**: lo probado y lo pendiente está en [README.138.md](README.138.md). En el 60K, la base de la v3.7 se validó con la batería de tests del V9968 de HRA!, las demos DEVCON, Metal Gear 2, Aleste 2 y el catálogo MSX2+ habitual. El V9968 está alineado con la **última revisión publicada** por HRA!; su procedencia y cada parche local están documentados en [`fpga/v9968/ORIGEN.txt`](fpga/v9968/ORIGEN.txt).

## Estructura del repositorio

```
carcasa/         La carcasa imprimible en 3D (3MF, STL, montaje)
docs/            Manual, referencia técnica, histórico, logo, fotos
MSXsdmaker/      MSX SD Maker: prepara la tarjeta SD (programa para Windows + instrucciones)
fpga/            top.v, build.tcl
  v9968/         El VDP V9968 (+ ORIGEN.txt: procedencia y parches locales)
  video720/      Puente HDMI y escalador
  src/           RTL propio (shim de VRAM, backend DDR3, audio, USB, S1990…)
    iosys/       El enlace con el BL616 y el panel en pantalla
  constraints/   Pinout y constraints de la Console 138K (y de la 60K)
  pll138/        La cascada PLL + PLL_INIT del GW5AST
tools/           Testbenches y utilidades de validación
  mxupdate/      MXUPDATE.COM (MSXgl + UNAPI)
  mxupd.py       Hace los .UPD y el manifiesto de la actualización
```

## Lo nuevo de la v3.8.4

La primera v3.8 de la Console 138K. Cambian el core y el pack: **graba los dos, una vez, con el PC**, en las direcciones de la 138K; después, las actualizaciones llegan desde el MSX.

- **Actualizar desde el MSX.** Un *puente de la flash* en el core (dispositivo de E/S conmutada 4Dh) deja al MSX leer, borrar y programar la flash de la placa. `MXUPDATE.COM` 1.3 lo usa: un fichero `.UPD` de la SD, o directamente de internet con `/N` (msx.barcelona, TLS con el certificado validado); `/R` hace la actualización completa (core, pack y ondas del OPL4) y vuelve a los ajustes de fábrica. **Ajustes → Instalar actualización** hace lo mismo sin DOS. Todo se comprueba antes de borrar nada y se relee después. Ver [Actualizar desde el MSX](#actualizar-desde-el-msx).
- **El panel F12 en color**, ahora también en la 138K, con el firmware del BL616 compilado para ella: Z80 y turbo, vídeo, tarjeta SD, los ajustes principales, qué hay en cada USB-A, ventilador, mayúsculas y la orden para actualizar, en el idioma del menú. ESC también lo cierra.
- **El OPL4 como el chip real** (lo que el 60K recibió como actualizaciones por red 3.8.1 a 3.8.4): los registros del wavetable se releen bien a la primera, `F8h` arranca en 1Bh, el vibrato y el trémolo del FM como el YMF262, NEW2 también por el puerto `C5h` (los discos de música del MoonBlaster Wave BASIC driver callaban), margen para las 24 voces del wave, fundidos sin zumbido, envolvente y ataque como el YMF278B, pan en pasos de −3 dB, DAMP y pseudo-reverb, y sin el ruido de *Dutch Moonsound Veterans*. El wave queda 3 dB por canal más bajo que antes (el nivel de openMSX); el canal 6 del mezclador de Ajustes ya está a 8/8, así que para darle más peso hay que bajar los demás canales.
- **El mapper por la firma de la propia ROM** ([convención de MSXgl](https://aoineko.org/msxgl/index.php?title=ROM_type_signature)): las ROM de geo3d y lo hecho con MSXgl se lanzan con su mapper, sin `[ASCII16]` en el nombre.
- **La 3.7.1 a la 3.7.6 del 60K**: el navegador de la SD ordenado, ASCII16-X y megaram de 8 MB, los arreglos del V9968 de HRA! (puerto 99h, copias con DIY, sprites en el borde izquierdo) y las rayas de arranque de nuestro shim de la VRAM, los mandos USB genéricos sin la izquierda fantasma, packs en inglés, y Ajustes con la versión de tres dígitos (`3.8.4`).
- **El firmware del ESP32-C6 lleva autoridades de certificación** (16 de Mozilla): la placa valida el certificado del servidor de actualizaciones.
- **Lo propio de la 138K**: el mapa de flash de la v3.7-8mb, que cabe en los 8 MB de la placa (una W25Q64, la misma que la del 60K): pack en `0x500000`, ajustes en `0x580000`, ondas del OPL4 en `0x600000`. Y el dato que la CPU escribe en la SDRAM se registra a 54 MHz antes del cruce a 108: era el peor camino de temporización de los dados de la 138K rechazados desde octubre.
- **Documentación**: dos capítulos nuevos, [`docs/manual/11-actualizar.md`](docs/manual/11-actualizar.md) (cómo actualizar) y [`docs/tecnica/11-actualizacion.md`](docs/tecnica/11-actualizacion.md) (el puente de la flash, el formato `.UPD`, el manifiesto).

## Lo nuevo de la v3.2

El core **no cambia**: es el mismo `.fs` de la v3.1. Lo que cambia es lo que hay encima.

- **Una sola BIOS** — se acabó elegir pack. El navegador de la SD es ahora una casilla en Ajustes: `S` al arrancar, «Menu al arrancar», y ya. Se guarda en la flash.
- **Descargas desde el menú** — con WiFi, la tecla `F` busca y baja ROMs y discos a la microSD sin pasar por el PC.
- **Logo de arranque en la pantalla del C6** — el logotipo MSX armándose desde los dos lados, como en un MSX2 de verdad.
- **El firmware del C6 vive en su propio repositorio**, [ESP32-for-FPGA](https://github.com/Papipapito/ESP32-for-FPGA), y es el mismo binario para el MSXimus y el MSXnano.

## Lo nuevo de la v3.1

- **Reconstruido fuera del silicio retirado** — el core entero funciona ya sin el SSRAM del GW5AT-60B. Es el titular de la versión y la razón del número; el [por qué](#por-qué-v31-y-no-v22) está arriba del todo.
- **Panel de estado en F12** — el BL616 que la placa ya lleva pinta el estado real de la máquina sobre la imagen, con el MSX congelado debajo. Ni cables, ni módulo, ni hardware extra.
- **Se presenta como un turboR** — están los registros de identificación del S1990 (`E4h`–`E7h`), y `CHGCPU` mueve el turbo de verdad. Sin R800: el mismo Z80, diciendo la verdad sobre lo que es.
- **Ratón MSX con un ratón USB** — enchufa un ratón USB **con cable** a la placa y el software MSX ve un ratón MSX. (Un receptor inalámbrico no vale: se presenta como dispositivo compuesto.)
- **Dos BIOS a elegir** — un MSX a secas, o el mismo más navegador y lanzador de la SD. *(Unificadas en una sola en la v3.2.)*
- **El turbo, en F11** — la F12 es ahora del panel.

Todo lo de la v2.1 sigue aquí: el V9968 en la última revisión de HRA!, el audio remasterizado, el MSX-Audio de 256 KB, la imagen estilo CRT y las megaROMs ASCII16 de 2 MB completas.

## El V9968

El corazón del MSXimus es el **[V9968](https://github.com/hra1129/V9968_Cartridge) de Takayuki Hara (HRA!)**, un VDP imaginario que extiende el V9958 con lo que Yamaha nunca llegó a sacar:

- **Sprites multicolor**: 15 colores más transparencia **por sprite**, definidos píxel a píxel
- **16 sprites por línea** en vez de 8 — se acabó el parpadeo
- **Sprites escalables**, con magnificación libre, rotación y espejado
- **Paleta extendida**: 256 colores en 16 juegos de 16
- **256 KB de VRAM**, comandos extendidos (rotación LRMM, LFMM, LFMC) y modo de comandos rápido

<p align="center"><img src="docs/img/v9968_sprites.jpg" alt="Sprites multicolor del V9968" width="760"/></p>
<p align="center"><i>Sprites de 15 colores definidos píxel a píxel: imposible en un MSX2+ real.</i></p>

La VRAM del V9968 vive en la **DDR3** de la placa, lo que deja la SDRAM entera para la RAM del MSX y para lo que venga después.

Y sigue siendo un MSX2+ normal: el software de siempre funciona igual.

## Licencia

**GPLv3**, por derivación de [`Papipapito/MSXnano`](https://github.com/Papipapito/MSXnano). Ver [LICENSE](LICENSE) y [UPSTREAM.md](UPSTREAM.md) para la atribución completa y la IP de terceros.

El **V9968** es de Takayuki Hara y viene con su licencia propia, tipo BSD pero **no comercial**: se puede redistribuir conservando los avisos y publicar gratis, **pero no vender**. Esa condición se hereda, así que **este proyecto no se vende**.

El logo del MSXimus es del proyecto.

---

# Gracias

Esto no lo he hecho yo solo, ni de lejos. Todo lo que hay aquí se apoya en el trabajo de gente que publicó lo suyo para que otros pudiéramos seguir.

### El core y su linaje

- **[jabadiagm](https://github.com/jabadiagm)** — MSXgoauldSD, el Goa'uld, origen de todo este linaje (goauld → MSXnano → MSXimus), y MSX_LCD_tn20k.
- **Linaje OCM-PLD / ESE Artists' Factory** — Kunihiko Ohnaka, KdL y todos los que han mantenido vivo el MSX2+ en FPGA durante dos décadas. De ahí viene el VDP V9958.

### El V9968

- **[Takayuki Hara — HRA!](https://github.com/hra1129)** — autor del **V9968**, el VDP que hace especial a esta versión, y de la demo DEVCON y de toda la batería de tests con la que se ha validado. Gracias por publicarlo y por documentarlo tan bien.
- **[Albert Herranz — herraa1](https://github.com/herraa1)** — port de la demo a MSXgl (`ru66-v9968-demo`), el cartucho V9968 y el material de referencia que ha permitido depurar el core.

### Audio

- **[Jose Tejada — jotego](https://github.com/jotego)** — jt2413 (OPLL), jtopl2 (FM del Y8950) y jt10_adpcmb. GPLv3.
- **[Greg Taylor — gtaylormb](https://github.com/gtaylormb)** — opl3_fpga (LGPLv3), que incluye `afifo.v` de **Dan Gisselquist (ZipCPU)**.
- **Jokin Miragaia (antxiko)** — mangOPL4, los arreglos para Gowin y las lecciones de integración.
- **srg320** — YMF278B.sv, el motor PCM del OPL4, cedido con permiso expreso.
- **Equipo MAME** — R. Belmont, Olivier Galibert y hap (ymf278b.cpp), y **Aaron Giles** (ymfm).
- **Tatsuyuki Satoh** — el algoritmo ADPCM-B de referencia.

### La placa y la cadena de vídeo

- **[nand2mario](https://github.com/nand2mario)** — `ddr3_framebuffer_gowin` (la receta de la IP DDR3 que hace posible meter ahí la VRAM), `usb_hid_host`, la plantilla de vídeo 720p y, en general, por abrir camino en el ecosistema Tang.
- **hdl-util (Sameer Puri)** — el empaquetador HDMI (MIT).
- **[ducasp](https://github.com/ducasp)** — firmware y protocolo UNAPI del ESP.

### Validación y herramientas

- **Equipo de [openMSX](https://openmsx.org)** — la referencia contra la que se comprueba si algo está bien o mal.
- **Laurens Holst (grauw)** — VGMPlay MSX y la MSX Assembly Page.
- **aoineko (Guillaume Blanchard)** — MSXgl.
- **[Sipeed](https://sipeed.com)** y **Gowin** — la placa y el toolchain.
- **Yamaha** — por los chips originales (V9958, YM2149, YM2413, Y8950, YMF262, YMF278B) que esto emula con cariño.

### Y

- **Claude (Anthropic)** — **coautora del código**: RTL nuevo, el shim de VRAM sobre DDR3, las integraciones de audio, la suite de validación, y una cantidad indecente de horas de depuración a base de simulación, telemetría y equivocarse mucho antes de acertar.

---

<p align="center"><i>Para la comunidad MSX. Que dure otros cuarenta años.</i></p>
