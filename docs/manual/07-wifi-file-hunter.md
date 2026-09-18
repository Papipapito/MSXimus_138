# 07. WiFi y File-Hunter

La red del MSXimus_138 la pone un módulo **ESP32-C6** externo, conectado por cuatro cables al conector J10 de la placa. Con él, el MSX tiene una pila TCP/IP UNAPI como la de cualquier cartucho de red, y el menú puede buscar y descargar ROMs y discos sin pasar por el PC. El módulo, su firmware, el cableado al J10 y el driver son los mismos que en el MSXimus de la Console 60K: la placa base es la misma y el SOM 138K saca las mismas bolas al J10. El cableado y el firmware están en el [capítulo 02](02-instalacion.md); aquí, cómo se usa.

Como el resto del porte, esta parte está compilada y verificada en simulación, pero pendiente de probar en una placa 138K.

## 1. Qué pone el módulo

- **TCP/IP UNAPI** completo, con TLS, cliente HTTP y SSH, por la pila de ducasp. Todo el software de red de MSX que hable UNAPI funciona: HGET, los clientes de Telnet e IRC, los actualizadores, el propio File-Hunter del menú.
- **Una pantalla** de 240×240 en el módulo: el logo MSX al encender y después el estado, con la red a la que está conectado y su señal, si el turbo está activo, el tiempo encendido, la temperatura del propio módulo y la hora. Un punto verde arriba a la derecha parpadea cuando hay tráfico con el MSX; es el primer diagnóstico.
- **Reloj**: en cuanto hay red, el módulo se pone en hora por internet y la pantalla la muestra. Desde el MSX, la opción de reloj del menú de configuración pone en hora también el reloj del MSX.

Sin módulo, el core funciona igual. Las ROMs del driver de red siguen en su slot y no molestan.

## 2. Configurar la red: tecla W

En el navegador del menú, o durante el logo de arranque, la tecla **W** abre el **Wi-Fi Setup** del driver del ESP, que es el menú que trae el propio firmware de ducasp:

| Opción | Qué es |
|---|---|
| Set Nagle | Ajuste del protocolo TCP; se deja como está |
| Wi-Fi On Period | Cuánto tiempo mantiene la radio encendida sin uso |
| Scan/Join Access Points | Buscar redes y unirse a una, con su contraseña |
| Wi-Fi and Clock Settings | Huso horario y reloj automático |
| ESC | Volver al navegador |

Al pulsar W se ve un instante de caracteres raros antes del menú. Es normal: ese menú está pensado para arrancar en otro contexto de pantalla y carga sus propios caracteres. Sin el módulo cableado, en vez del menú salen datos sin sentido, porque lee una línea a la que no responde nadie.

La red y la contraseña se guardan en el módulo, no en el MSX: una vez configuradas, se conecta solo al encender. La pantalla del navegador no lo indica, pero la del módulo pasa de *Sin WiFi* a *Conectado* con el nombre de la red.

## 3. File-Hunter: tecla F

[File-Hunter](https://www.file-hunter.com/) es la base de datos de ROMs y discos de MSX. Con la red configurada y una carpeta `FHUNT` en la raíz de la tarjeta, la tecla **F** del navegador busca en ella y descarga a la tarjeta.

1. **F** abre el campo *"File-Hunter Buscar:"*. Se escribe un trozo del nombre, hasta 20 caracteres, y RETURN. ESC cancela.
2. El menú hace dos consultas, una de ROMs y otra de discos, y muestra los resultados juntos en la lista del navegador, mientras enseña *Conectando*, *DNS*, *Abriendo* y *Enviando GET*.
3. Sobre un resultado: **RETURN** lo descarga, **F** hace otra búsqueda, **ESC** o **BACKSPACE** vuelven al navegador normal.
4. La descarga va a `FHUNT`, con el nombre en formato 8.3 y la etiqueta del mapper que File-Hunter conoce, por ejemplo `[SCC].rom`. Se comprueba el CRC al terminar. Si el fichero ya está en `FHUNT` con el mismo tamaño no se vuelve a bajar: la carpeta hace de caché.
5. Al terminar, se lanza solo, como cualquier ROM o disco de la tarjeta.

Un fichero descargado se queda en `FHUNT` para siempre: la siguiente vez está en el navegador como uno más.

### Límites

- La tarjeta tiene que ser **FAT16**. Con FAT32 el menú lo dice y no descarga.
- La carpeta `FHUNT` tiene que existir; se crea desde MSX-DOS con `MKDIR FHUNT`.
- Los nombres se escriben en 8.3. Dos ficheros distintos con el mismo nombre corto se pisan; el menú pregunta antes de sobrescribir si el tamaño cambia.

### Mensajes

| Mensaje | Qué pasa |
|---|---|
| FH: sin UNAPI | El MSX no ve el driver de red. El módulo no está, no arrancó, o el cable de RX está mal |
| FH: sin red (tecla W) | El módulo está pero no conectado a ninguna red |
| FH: fallo DNS / sin conexion | La red está, internet no, o File-Hunter no responde |
| FH: sin resultados | Ningún fichero con ese texto |
| FH: timeout de descarga / respuesta API rara | La descarga se cortó. Reintentar |
| FH: error SD / SD llena / CRC MAL | Problema al escribir en la tarjeta. Comprobar la tarjeta, capítulo 03 |
| Falta FHUNT (MKDIR en DOS) | No existe la carpeta |
| FH: la SD es FAT32 (v1 solo FAT16) | La partición no es FAT16 |

## 4. Diagnóstico rápido

Si algo no va, en este orden:

1. **La pantalla del módulo.** Si dice *Sin WiFi*, la red no está configurada o no llega; tecla W. Si dice *Conectado*, la red está bien.
2. **El punto de actividad** de la pantalla, o el LED de red de la tira de diagnóstico si se ha montado. Si no parpadea cuando el MSX usa la red, el problema es el cable o el firmware, no la WiFi.
3. **Los cables TX y RX cruzados.** Es el error más común al montar: el TX del FPGA va al RX del módulo, IO17, y el RX del FPGA al TX del módulo, IO16. En el 138 los pines `esp_*` del J10 son copia de los del 60K y no se han contrastado contra el esquemático de la Console 138K (pendiente de verificar en placa): si con los cables bien puestos sigue sin haber actividad, ese es el siguiente sospechoso.
4. **La alimentación.** Con el módulo alimentado desde el J10 y a la vez por USB-C puede portarse raro; una sola fuente.
