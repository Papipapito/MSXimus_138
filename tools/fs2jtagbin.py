#!/usr/bin/env python3
"""fs2jtagbin.py - convierte el .fs de Gowin (texto, una palabra de bits por linea) en el _jtag.bin de la entrega.

El _jtag.bin es el segmento del core de los .UPD (docs/tecnica/11-actualizacion.md): las lineas de datos del .fs
(solo '0' y '1') concatenadas y empaquetadas MSB primero. Se ignoran las lineas de cabecera ('//...') y vacias.

Verificado contra una entrega: msximus138_v3.8.4_dado5569.fs -> 5.096.124 bytes, md5 39c7b6eb5df8... (el del
_jtag.bin publicado el 17/10/2026).

Uso:  python tools/fs2jtagbin.py entrada.fs [salida_jtag.bin]
      (sin salida: <entrada sin .fs>_jtag.bin al lado)
"""
import hashlib
import os
import sys


def convierte(ruta_fs):
    salida = bytearray()
    with open(ruta_fs, 'r') as f:
        for ln in f:
            ln = ln.strip()
            if not ln or ln.startswith('//'):
                continue
            if set(ln) - set('01') or len(ln) % 8:
                raise ValueError('linea de datos no valida: %r' % ln[:40])
            salida += int(ln, 2).to_bytes(len(ln) // 8, 'big')
    return bytes(salida)


def main():
    if len(sys.argv) not in (2, 3):
        sys.exit(__doc__)
    entrada = sys.argv[1]
    destino = sys.argv[2] if len(sys.argv) == 3 else os.path.splitext(entrada)[0] + '_jtag.bin'
    datos = convierte(entrada)
    with open(destino, 'wb') as f:
        f.write(datos)
    print('%s: %d bytes, md5 %s' % (destino, len(datos), hashlib.md5(datos).hexdigest()))


if __name__ == '__main__':
    main()
