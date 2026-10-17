"""Arregla el Verilog de GHDL 4.1 para Verilator.
GHDL nombra la salida Q de la instancia 'alu' como 'alu_q', que choca con la senal ALU_Q del T80
(en VHDL no distingue mayusculas). Renombra el cable de la instancia: su declaracion (la 2a), su
conexion .q(alu_q) y la asignacion 'assign alu_nNNN = alu_q;' que lo copia a la senal.
Ademas pone pull-up en los 'z' de BUSAK (el banco nunca cede el bus). Detecta otros duplicados.
"""
import re
import sys
from collections import Counter

src, dst = sys.argv[1], sys.argv[2]
lines = open(src, encoding="utf-8").read().split("\n")

# modulo t80_* : localizar limites
mod_start = next(i for i, l in enumerate(lines) if l.startswith("module t80_0_"))
mod_end = next(i for i in range(mod_start, len(lines)) if lines[i].startswith("endmodule"))
decl = [i for i in range(mod_start, mod_end) if re.fullmatch(r"\s*wire \[7:0\] alu_q;", lines[i])]
assert len(decl) == 2, decl
lines[decl[1]] = lines[decl[1]].replace("alu_q;", "alu_q_inst;")
n_conn = n_asg = 0
for i in range(mod_start, mod_end):
    if re.search(r"\.q\(alu_q\)", lines[i]):
        lines[i] = lines[i].replace(".q(alu_q)", ".q(alu_q_inst)"); n_conn += 1
    m = re.fullmatch(r"(\s*assign alu_n\d+ = )alu_q(; // \(signal\))", lines[i])
    if m:
        lines[i] = m.group(1) + "alu_q_inst" + m.group(2); n_asg += 1
assert n_conn == 1 and n_asg == 1, (n_conn, n_asg)

text = "\n".join(lines)
text = text.replace("1'bz", "1'b1").replace("16'bz", "16'hffff")

# informe de otros nombres declarados dos veces dentro de un mismo modulo
for m in re.finditer(r"^module (\S+)(.*?)^endmodule", text, re.S | re.M):
    names = re.findall(r"^\s*(?:wire|reg)\s*(?:\[[^\]]*\])?\s*(\w+)\s*;", m.group(2), re.M)
    dup = [n for n, c in Counter(names).items() if c > 1]
    if dup:
        print("DUPLICADOS en", m.group(1), dup)
open(dst, "w", encoding="utf-8", newline="\n").write(text)
print("ok: alu_q de la instancia -> alu_q_inst")
