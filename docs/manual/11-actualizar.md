# 11. Actualizar desde el MSX

Desde la V3.8 el MSXimus se actualiza **sin PC**: el core y el pack de BIOS se graban en la flash de la placa desde el propio MSX. Hay tres caminos:

| Camino | Qué hace | Hace falta |
|---|---|---|
| `MXUPDATE /N` | Baja la última versión de la 138K de internet ([msx.barcelona](https://msx.barcelona)) y la graba | MSX-DOS 2 o Nextor, el ESP32-C6 con WiFi |
| `MXUPDATE fichero.UPD` | Graba un fichero `.UPD` de la 138K que tienes en la SD | MSX-DOS 2 o Nextor |
| Ajustes → **Instalar actualización** | Graba el `MSX138K.UPD` de la raíz de la SD (el mismo nombre con el que lo guarda `MXUPDATE /N`) | Nada más: no hace falta arrancar MSX-DOS |

Los tres hacen las mismas comprobaciones y graban igual. La única condición es que en la placa ya haya un **core V3.8 o posterior**, el primero que lleva el *puente de la flash* (el dispositivo que deja escribir en ella desde el MSX). En la 138K la primera V3.8 es la **v3.8.4**: se graba una vez con el PC, como siempre ([capítulo 02](02-instalacion.md)); desde ahí, ya no hace falta.

> Lo de este capítulo está validado en placa en el 60K (desde la 3.8.0b3). En la 138K es el mismo programa y el mismo puente, con su mapa de flash; en una placa 138K está pendiente de verificar.

> La MSXimus Z (la versión para la ZYNQ MINI) se actualiza de otra forma: **F12 y U**, desde el panel del propio OSD. Lo de este capítulo es para la Tang Console 138K (y para la 60K, con sus direcciones).

## 1. Qué es un `.UPD`

Un fichero `.UPD` lleva lo que hay que grabar en la flash, por trozos: el core (en 0x000000), el pack de BIOS (en 0x500000) y, en las actualizaciones completas, las ondas del OPL4 (en 0x600000). Cada trozo lleva su CRC-32. Cada `.UPD` es de una placa: uno del 60K no entra en la 138K, ni al revés. Se pueden hacer de tres tipos:

- **Normal**: core y pack. Es lo que baja `MXUPDATE /N`.
- **Solo el pack**: para cambiar de idioma del menú o de versión de Nextor en un minuto y medio, sin tocar el core.
- **Completa**: core, pack y ondas del OPL4. Es lo que baja `MXUPDATE /N /R`: todo desde cero.

Los **ajustes** que guardas con *Save & Restart* (en 0x580000) **nunca** van en un `.UPD`: una actualización los conserva. Solo `/R` los borra a propósito.

## 2. `MXUPDATE.COM`

Se lanza desde MSX-DOS. Va en la release y, en una tarjeta hecha con [MSX SD Maker](https://github.com/Papipapito/SD_Maker), en la carpeta `FPGA`, que está en el `PATH`: se lanza desde cualquier sitio. Reconoce la placa sola (60K, 138K o MSXnano 2.1.1) por el chip del core que hay grabado, y habla en el idioma del menú.

En la 138K hace falta la **1.3** o posterior. La 1.2 llevaba la 138K con el pack en 0x800000 (el mapa de la v3.7) y rechaza los ficheros de la 138K de ahora con `El fichero no es valido o esta danado. No se ha tocado nada.`. La release publicada de MSX SD Maker (la 1.4) pone la 1.2 en `FPGA`: copia encima el `MXUPDATE.COM` de la release de la v3.8.4. Por internet no hay que hacer nada: antes de bajar el core, MXUPDATE se actualiza solo.

```
MXUPDATE                  graba el fichero de esta placa del directorio actual: MSX138K.UPD en la
                          138K, MSXIMUS.UPD en el 60K y MSXNANO.UPD en el MSXnano (o un MSXIMUS.UPD,
                          si es de esta placa); si no esta, ofrece bajar la ultima version
MXUPDATE fichero.UPD      graba ese fichero
MXUPDATE /C fichero.UPD   solo lo comprueba (cabecera y CRC); no toca la flash
MXUPDATE /N               baja la ultima version de internet y la graba
MXUPDATE /N /R            la completa (core, pack y ondas) y vuelve a los ajustes de fabrica
MXUPDATE /EN   /ES        en ingles / en castellano
MXUPDATE /N /S:192.168.1.10:8000    desde un servidor propio en vez de msx.barcelona
MXUPDATE /H   /?          la ayuda: las ordenes, sin tocar nada (vale en cualquier MSX con DOS 2)
```

**Se actualiza solo.** Cada vez que va a internet (`/N`, o cuando no encuentra el fichero y le dices que lo baje), MXUPDATE mira primero si en msx.barcelona hay una versión suya más nueva. Si la hay, la baja junto a sí mismo, comprueba que es la que dice la web, se sustituye y se vuelve a lanzar con la misma orden: `MXUPDATE x.y en la web: actualizando MXUPDATE...` y `MXUPDATE actualizado: se vuelve a lanzar.` Tú no tienes que hacer nada. La versión que llevas sale arriba al lanzarlo (`MXUPDATE 1.3 - actualizar el core`).

### 2.1. Por internet: `MXUPDATE /N`

1. Configura antes la WiFi con la tecla **W** del menú ([capítulo 07](07-wifi-file-hunter.md)).
2. Arranca en MSX-DOS y escribe `MXUPDATE /N` (o solo `MXUPDATE` si no tienes el fichero: te ofrece bajarlo). Lo que baja se queda en la carpeta en la que estés.
3. Dice qué core tienes (`Core instalado: 3.8.4 (console138k)`) y pregunta al servidor: `Version en el servidor: ...`, con una nota de qué trae.
4. Elige la variante, del 1 al 4: Nextor 2.1.4 o 3, menú en castellano o en inglés. Avisa siempre, sea cual sea el Nextor de antes, de que la SD tiene que estar preparada para el elegido, con su `NEXTOR.SYS` ([MSX SD Maker](https://github.com/Papipapito/SD_Maker) la prepara), y pregunta si sigue: `Aviso: si la SD no esta preparada para Nextor 3, no arrancara MSX-DOS (MSX SD Maker la prepara). Seguir? (S/N)`.
5. La baja a la SD con el nombre de la placa (`MSX138K.UPD` en la 138K), la comprueba entera y pregunta `Fichero correcto. Grabar en la flash? (S/N)`.
6. **S**: `Grabando. NO APAGUES EL MSX.` Al acabar relee la flash y comprueba los CRC otra vez.
7. `Listo. Apaga y vuelve a encender el MSXimus para entrar con el core nuevo.`

La conexión con msx.barcelona es **cifrada (TLS) y con el certificado validado**. Para validarlo, el ESP32-C6 tiene que llevar el firmware de la v3.8, que trae las autoridades de certificación de serie. Con un firmware anterior funciona igual, pero sin validar el certificado, y lo dice: `Aviso: certificado sin validar.`. En claro, sin cifrar, no va nunca. El certificado de la web se renueva cada año y no hace falta volver a grabar el C6: lo que lleva el firmware son las autoridades, que duran hasta 2046.

Además, lo que se graba se comprueba con los CRC del propio fichero antes de borrar nada.

### 2.2. Desde un fichero

Copia el `.UPD` de la 138K a la SD (desde el PC, o lo deja ahí `MXUPDATE /N` si contestas **N** a la pregunta de grabar) y escribe `MXUPDATE fichero.UPD`. El resto es igual: comprueba, pregunta, graba y relee.

`MXUPDATE /C fichero.UPD` solo comprueba el fichero. Funciona en cualquier MSX con MSX-DOS 2, también sin el puente.

### 2.3. Todo desde cero: `/R`

`MXUPDATE /N /R` baja la variante **completa** (unos 7,4 MB en la 138K: core, pack y las ondas del OPL4) y, al acabar de grabar, **borra los ajustes**: la máquina arranca con los de fábrica, como recién grabada. Sirve para dejarla como nueva o si unos ajustes guardados dan guerra.

## 3. Desde Ajustes: «Instalar actualización»

Sin MSX-DOS, desde el propio menú:

1. Deja el fichero en la **raíz** de la SD con el nombre `MSX138K.UPD`, el mismo con el que lo baja `MXUPDATE /N`. Solo acepta un `.UPD` de la 138K.
2. Pulsa **S** al arrancar para entrar en Ajustes.
3. Baja hasta **Instalar actualización** (está entre *Mezclador de audio* y *Save & Restart*) y pulsa espacio.
4. Dice qué core tienes y qué trae el fichero, lo comprueba entero y pregunta `Fichero correcto. Grabar? (S/N)`.
5. **S**, y al acabar: `Listo. Apaga y enciende el MSXimus.`

Hace las mismas comprobaciones que `MXUPDATE.COM`. Si el core no tiene puente (anterior a la V3.8) lo dice y no hace nada.

## 4. Cuánto tarda

El Z80 hace todo el trabajo, a 3,58 MHz. El bitstream de la 138K mide unos 4,9 MB (5.096.124 bytes), el doble que el del 60K, así que grabar el core tarda el doble. Los tiempos de la 138K salen de los medidos en el 60K, en proporción al tamaño; en una placa 138K están sin medir:

| Qué | Grabar | Por internet, además |
|---|---|---|
| Solo el pack | 1,5 minutos | lo que tarde en bajar 0,5 MB |
| Core y pack | unos 16 minutos | 5,4 MB |
| Completa (con las ondas) | unos 22 minutos | 7,4 MB |

**No apagues la placa mientras graba.**

## 5. Si algo sale mal

| Mensaje | Qué ha pasado | Qué hacer |
|---|---|---|
| `Hace falta MSXimus 3.8 o MSXnano 2.1.1 (o posterior)` | El core grabado no tiene el puente | Grabar la v3.8.4 una vez con el PC |
| `Este fichero es para otra placa` | Es un `.UPD` del 60K o del MSXnano | El de tu placa |
| `El fichero no es valido o esta danado. No se ha tocado nada.` | Cabecera o CRC mal; o, en la 138K, un MXUPDATE 1.2, que espera el pack en 0x800000 | Bajarlo o copiarlo otra vez; en la 138K, MXUPDATE 1.3 |
| `No hay MSX138K.UPD en la raiz de la SD.` (Ajustes) | No está en la raíz, o tiene otro nombre (`MSXIMUS.UPD` es el del 60K) | Copiarlo a la raíz como `MSX138K.UPD` |
| `No hay MSXIMUS.UPD en la raiz de la SD.` (Ajustes) | El pack grabado es anterior a la v3.8.4: busca el nombre del 60K y espera el pack de la 138K en 0x800000 | Grabar el pack de la v3.8.4 (con el PC, o con `MXUPDATE /N`) |
| `El fichero no vale. No se ha tocado nada.` (Ajustes) | Cabecera o CRC mal, o un `.UPD` de otra placa; o, en la 138K, un pack anterior a la v3.8.4, que espera el pack en 0x800000 | Copiarlo otra vez; en la 138K, el pack de la v3.8.4 |
| `La descarga se ha cortado. No se ha tocado nada.` | Se fue la red a medias | Repetir `MXUPDATE /N` |
| `Sin conexion con el servidor de actualizaciones.` | No hay red, o el ESP no llega | Mirar la WiFi con la W del menú |
| `Sin actualizaciones para esta placa (HTTP 404).` | El servidor no tiene nada para tu placa | — |
| `No hay red (UNAPI)` | No hay ESP32 o no está configurado | La W del menú |
| `No se ha podido actualizar MXUPDATE: sigue este.` | No ha podido bajar o comprobar el MXUPDATE nuevo | Nada: sigue con el que tienes. El nuevo está también en la release |
| `La flash no ha quedado bien.` | Al releer, algo no coincide | **No apagues**: el core de antes sigue en marcha hasta apagar. Repite `MXUPDATE`, o graba con el PC |

Si se va la luz a mitad de grabar el core, la placa puede no arrancar. **No hay forma de estropearla**: por el USB-C, con el Gowin Programmer, siempre se puede grabar de nuevo ([capítulo 02](02-instalacion.md)).

## 6. El panel F12

Con el firmware del BL616 de la v3.8 para la 138K, el panel de F12 recuerda abajo la orden para actualizar: `Actualizar: MXUPDATE /N`.
