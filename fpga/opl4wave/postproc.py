#!/usr/bin/env python3
# Post-proceso del ymf278b_gowin.v generado por sv2v:
# El motor de srg320 usa tipos `bit` (2 estados, init 0) SIN reset explicito
# en varios contadores (CLK_DIV, CYCLE_NUM, RST_N_OLD...). sv2v los convierte
# a `reg` (4 estados, init X) y la simulacion se queda en X para siempre.
# En silicio (Altera y Gowin) los registros arrancan a 0, asi que añadir
# `= 0` a cada reg escalar reproduce la semantica `bit` en sim y no cambia
# nada en sintesis (0 es el power-up por defecto de Gowin).
import re, sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.readlines()

pat = re.compile(r"^(\s*reg\s+(?:signed\s+)?(?:\[[^\]]+\]\s*)?)([A-Za-z_][A-Za-z0-9_$]*)\s*;\s*$")
out, patched, in_func = [], 0, 0
for ln in lines:
    if re.match(r"\s*(function|task)\b", ln):
        in_func += 1
    elif re.match(r"\s*(endfunction|endtask)\b", ln):
        in_func -= 1
    m = pat.match(ln) if not in_func else None
    if m:  # solo escalares/vectores sin inicializador (las memorias llevan [..] tras el nombre)
        out.append(f"{m.group(1)}{m.group(2)} = 0;\n")
        patched += 1
    else:
        out.append(ln)

# 2) hoist de locals de bloques `always ... begin : nombre` a nivel de modulo:
#    Verilog-2005 no admite inicializadores ahi y GowinSynthesis es quisquilloso.
#    Los nombres son unicos en todo el fichero (verificado), asi que basta
#    mover la declaracion delante del always.
hoisted, final, i = 0, [], 0
while i < len(out):
    ln = out[i]
    m = re.match(r"(\s*)always\b.*begin\s*:\s*\w+", ln)
    if m:
        decls = []
        j = i + 1
        while j < len(out) and re.match(r"\s*reg\s+(?:signed\s+)?(?:\[[^\]]+\]\s*)?\w+(\s*=\s*0)?\s*;\s*$", out[j]):
            decls.append(out[j].strip())
            j += 1
        for d in decls:
            final.append(f"{m.group(1)}{d}\n")
            hoisted += 1
        final.append(ln)
        i = j
    else:
        final.append(ln)
        i += 1

# 3) la cabecera con el aviso BSD-3 de srg320/MAME (13/10/2026): el generado es lo que se
#    sintetiza y se distribuye, y la clausula 2 de la BSD pide el aviso en lo que se redistribuye.
CABECERA = """// ============================================================================
// ymf278b_gowin.v - motor PCM/wavetable del OPL4 (YMF278B). GENERADO por sv2v
// desde opl4wave/YMF278B_pkg.sv + YMF278B.sv (convert.sh + postproc.py): no
// editar a mano. Es el fichero que entra en la sintesis (fpga/build.tcl).
//
// license:BSD-3-Clause  (motor PCM derivado del ymf278b.cpp de MAME)
//
// Origen: srg320 / Arcade-PsikyoSH2_MiSTer (rtl/PSH2/YMF278B.sv), BSD-3-Clause
// por su autor (cabecera upstream //license:BSD-3-Clause, commit 5379b34b,
// 14/07/2026; permiso explicito por correo del 13/07/2026). Derivado del
// ymf278b.cpp de MAME, BSD-3-Clause, titulares R. Belmont / Olivier Galibert /
// hap. Primitivas de RAM rehechas por el proyecto MSXimus (era v3: BSRAM con
// barrido por slot) y relectura de los registros de slot a la primera
// (05/10/2026). Ver UPSTREAM.md.
// ============================================================================
"""
with open(path, "w", encoding="utf-8", newline="\n") as f:
    f.write(CABECERA)
    f.writelines(final)
print(f"postproc: {patched} regs inicializados a 0, {hoisted} locals izados en {path}")
