#!/bin/bash
# asm.sh - ensambla prog.asm con pasmo y rehace prog.hex (un byte por linea, para el $readmemh del banco)
set -e
cd "$(dirname "$0")"
pasmo --bin prog.asm prog.bin
python3 -c "
d = open('prog.bin', 'rb').read()
open('prog.hex', 'w', newline='\n').write('\n'.join('%02x' % b for b in d) + '\n')
print(len(d), 'bytes')
"
