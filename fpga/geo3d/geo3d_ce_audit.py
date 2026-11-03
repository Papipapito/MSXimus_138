#!/usr/bin/env python3
"""geo3d_ce_audit.py -- auditoria del clock enable de geo3d (GEO3D_CE) sobre el netlist de GowinSynthesis.

POR QUE. El multiciclo 2/1 de constraints/msx_geo3d.sdc solo es verdad para un registro que NO captura en
el ciclo sin CE. Eso pasa si el CE llega a su pin de enable (CE de un DFF*E, CEA/CEB/OCE de una BSRAM, CE
del registro de un DSP). La sintesis puede, en cambio, dejar el pin CE = VCC y meter el CE en el D (un mux
de "mantener"): ese registro captura en TODOS los ciclos y su D tiene que asentarse en UNO. Cuales salen
asi lo decide la sintesis y cambia de un netlist a otro (17/10: 7 FF del motor en el PnR de prueba, 5
OTROS en la sintesis del diseno entero), asi que no vale una lista fija en el SDC.

QUE HACE (sobre el .vg JERARQUICO: modulos geo3d_bus, geo3d_engine y geo3d_core):
  1. cada FF del motor y del core recibe el CE (por su pin CE o por el D); ninguno sin CE;
  2. los FF del motor/core con el CE SOLO en el D necesitan un set_max_delay de un ciclo en su D (en
     Gowin manda sobre el multiciclo, SUG940 3.8). Con --emit se escriben esas lineas (nombre exacto de
     cada FF) al final del SDC indicado; sin --emit se comprueba que el SDC ya las cubre;
  3. el lado motor de geo3d_bus (rst_e, req_seen, ack_r, e_wr, e_rd, ce_s, cmd_t, cmd_num_e, cmd_data_e)
     recibe el CE, el lado bus no, y los suyos con el CE solo en el D no son destino de ningun multiciclo;
  4. cada registro USADO de cada DSP (parametro *_CLK distinto de BYPASS) y cada CEA/CEB de cada BSRAM
     (y su OCE si lleva registro de salida, READ_MODE = 1) tiene el CE. Los defparam se leen por modulo,
     tambien los de nombre escapado. Cualquier otra primitiva con reloj (pROM, SSRAM...) es fallo.
Sale con 0 si todo cuadra; con 1 si no (en --emit, solo por 1, 3 o 4: lo de 2 lo arregla el propio --emit).

Uso:
  python fpga/geo3d/geo3d_ce_audit.py <impl/gwsynthesis/project.vg> [<sdc>]          (comprobar)
  python fpga/geo3d/geo3d_ce_audit.py <project.vg> <sdc> --emit [--periodo 11.300]   (lo usa build.tcl)
"""
import re
import sys
from collections import defaultdict

PREFIJO = {"geo3d_bus": "u_geo3d/", "geo3d_engine": "u_geo3d/u_engine/", "geo3d_core": "u_geo3d/u_engine/u_core/"}
LADO_MOTOR_BUS = ("rst_e", "req_seen", "ack_r", "e_wr", "e_rd", "ce_s", "cmd_t", "cmd_num_e", "cmd_data_e")
CELL = re.compile(r"(?ms)^\s*(\w+)\s+(\\\S+|\w+)\s*\((.*?)\)\s*;")
PIN = re.compile(r"\.(\w+)\(\s*(.*?)\s*\)\s*(?:,|$)", re.S)
COMB = re.compile(r"^(LUT\d|MUX2\w*|ALU|INV|AND\w*|OR\w*|XOR\w*)$")
SALIDAS = ("F", "O", "COUT", "SUM")
SEMILLA = re.compile(r"^\\?(geo_ce|ce)(\[|$|_eng)")
MARCA = "# ---- geo3d_ce_audit.py --emit: FF del motor con el CE solo en el D (su D, a UN ciclo) ----"


def bus_split(n):
    n = n.strip()
    if n.startswith("{") and n.endswith("}"):
        return [x.strip() for x in n[1:-1].split(",")]
    return [n]


def nombre_rtl(inst):
    """guard_0_s2 -> guard ; \\vx[1]_1_s0 -> vx ; isend_s4 -> isend"""
    s = inst.lstrip("\\")
    s = re.sub(r"_s\d+$", "", s)
    s = re.sub(r"(_\d+)+$", "", s)
    s = re.sub(r"\[.*$", "", s)
    return s


def glob_gowin(pat):
    """* y ? de Gowin: no cruzan niveles de jerarquia (medido el 17/10)."""
    r = ""
    for ch in pat:
        r += "[^/]*" if ch == "*" else "[^/]" if ch == "?" else re.escape(ch)
    return re.compile("^" + r + "$")


def patron_sdc(nombre):
    """Nombre exacto para get_pins: los corchetes de los nombres escapados van como '?'."""
    return re.sub(r"[\[\]]", "?", nombre)


def leer_sdc(path):
    mcp_to, maxd_to = [], []
    if not path:
        return mcp_to, maxd_to
    for ln in open(path, encoding="utf-8", errors="replace"):
        ln = ln.strip()
        if ln.startswith("#"):
            continue
        m = re.search(r"-to\s+\[get_pins\s+\{([^}]*)\}\]", ln)
        if not m:
            continue
        pats = [glob_gowin(p) for p in m.group(1).split()]
        if ln.startswith("set_multicycle_path"):
            mcp_to += pats
        elif ln.startswith("set_max_delay"):
            maxd_to += pats
    return mcp_to, maxd_to


def main():
    args = [a for a in sys.argv[1:]]
    emit = "--emit" in args
    periodo = "11.300"
    if "--periodo" in args:
        periodo = args[args.index("--periodo") + 1]
        args.remove("--periodo")
        args.remove(periodo)
    args = [a for a in args if a != "--emit"]
    vg = args[0]
    sdc = args[1] if len(args) > 1 else None
    if emit and not sdc:
        print("ERROR: --emit necesita el SDC donde escribir")
        return 1
    mcp_to, maxd_to = leer_sdc(sdc)
    src = open(vg, encoding="utf-8", errors="replace").read()
    mods = {m[0]: m[2] for m in re.findall(r"(?ms)^module\s+(\w+)\s*\((.*?)\)\s*;(.*?)^endmodule", src)}
    falta = [m for m in PREFIJO if m not in mods]
    if falta:
        print(f"ERROR: el netlist no tiene los modulos {falta} (sin geo3d, o netlist aplanado)")
        return 1
    fallos, nuevas = 0, []
    for mod, pre in PREFIJO.items():
        # defparam DEL MODULO: van dentro de cada module del .vg y los nombres de instancia se repiten
        # entre modulos (n927_s1, cx_4_s0...), asi que un diccionario global mezclaria parametros ajenos
        defp = defaultdict(dict)
        # (un nombre escapado acaba en un espacio: "defparam \x[0]_s0 .INIT=...")
        for inst, k, v in re.findall(r'defparam\s+(\\\S+\s|[^\s.]+)\s*\.(\w+)\s*=\s*"?([^";]*)"?\s*;', mods[mod]):
            defp[inst.strip()][k] = v
        cells = []
        for m in CELL.finditer(mods[mod]):
            typ, inst, pins = m.groups()
            if typ in ("input", "output", "wire", "inout", "assign", "reg"):
                continue
            cells.append((typ, inst, {p: bus_split(n) for p, n in PIN.findall(pins)}))
        cargas = defaultdict(list)
        for i, (typ, inst, pd) in enumerate(cells):
            for p, nets in pd.items():
                for n in nets:
                    cargas[n].append((i, p))
        semillas = [n for n in cargas if SEMILLA.match(n)]
        visto, pila, llega = set(), list(semillas), defaultdict(set)
        while pila:
            n = pila.pop()
            if n in visto:
                continue
            visto.add(n)
            for i, p in cargas.get(n, []):
                typ, inst, pd = cells[i]
                if COMB.match(typ):
                    for op in SALIDAS:
                        pila.extend(pd.get(op, []))
                elif typ.startswith("DFF"):
                    llega[inst].add(p)
        ffs = [c[1] for c in cells if c[0].startswith("DFF")]
        print(f"===== {mod} ({pre}): {len(ffs)} FF; semillas del CE: {semillas}")
        if not semillas:
            fallos += 1
            print("   *** el CE no entra en este modulo ***")
        n_ce = n_d = 0
        for inst in ffs:
            nom = nombre_rtl(inst)
            es_motor = mod != "geo3d_bus" or nom in LADO_MOTOR_BUS
            ps = llega.get(inst, set())
            if not es_motor:
                if ps:
                    fallos += 1
                    print(f"   *** lado bus con el CE del motor: {inst} {sorted(ps)}")
                continue
            if "CE" in ps:
                n_ce += 1
                continue
            if not ps:
                fallos += 1
                print(f"   *** SIN CE: {pre}{inst}")
                continue
            n_d += 1
            pin = f"{pre}{inst.lstrip(chr(92))}/D"
            if mod == "geo3d_bus":
                malo = any(p.match(pin) for p in mcp_to)
                print(f"   CE solo en D (lado motor del bus): {pin} -> "
                      f"{'*** ES DESTINO DE MULTICICLO ***' if malo else 'no es destino de multiciclo: OK'}")
                fallos += malo
            elif emit:
                nuevas.append(f"set_max_delay -to [get_pins {{{patron_sdc(pin)}}}] {periodo}")
                print(f"   CE solo en D: {pin} -> set_max_delay {periodo} (--emit)")
            else:
                ok = any(p.match(pin) for p in maxd_to)
                print(f"   CE solo en D: {pin} -> {'cubierto por set_max_delay' if ok else '*** SIN set_max_delay ***'}")
                if not ok:
                    fallos += 1
                    nuevas.append(f"set_max_delay -to [get_pins {{{patron_sdc(pin)}}}] {periodo}")
        print(f"   FF del grupo con el CE en su pin CE: {n_ce}; con el CE solo en el D: {n_d}")
        for typ, inst, pd in cells:
            if any(c in pd for c in ("CLK", "CLKA", "CLKB")) and not (
                    typ.startswith(("DFF", "MULT")) or typ in ("SDPB", "DPB", "SDPX9B", "DPX9B", "SP", "SPX9")):
                fallos += 1
                print(f"   *** {typ} {inst}: primitiva con reloj que este auditor no sabe comprobar (pROM, SSRAM...)")
                continue
            if typ.startswith("MULT"):
                if not any(k.endswith("_CLK") for k in defp[inst]):
                    fallos += 1
                    print(f"   *** DSP {inst} ({typ}) sin defparam *_CLK: no se puede auditar")
                ce = list(reversed(pd.get("CE", [])))
                for k, v in sorted(defp[inst].items()):
                    if not k.endswith("_CLK") or v == "BYPASS":
                        continue
                    reg = k[:-4]
                    sel = defp[inst].get(reg + "_CE", "CE0")
                    idx = int(sel[-1]) if sel[-1].isdigit() else 0
                    net = ce[idx] if idx < len(ce) else "?"
                    ok = net in visto
                    fallos += not ok
                    print(f"   DSP {inst} ({typ}) registro {reg} {sel} <- {net}: {'OK' if ok else '*** SIN CE ***'}")
            elif typ in ("SDPB", "DPB", "SDPX9B", "DPX9B", "SP", "SPX9"):
                # OCE* solo cuenta con el registro de salida (READ_MODE* = 1): la sintesis absorbe ahi un
                # registro del motor (18/10: tcur <= trd en tmem, OCE <- tcur_63_15)
                pm = defp[inst]
                oce = [p for p, rm in (("OCE", "READ_MODE"), ("OCEA", "READ_MODE0"), ("OCEB", "READ_MODE1"))
                       if pm.get(rm, "1'b0").strip().endswith("1")]
                for p in ["CEA", "CEB", "CE"] + oce:
                    if p in pd:
                        net = pd[p][0]
                        ok = net in visto
                        fallos += not ok
                        print(f"   BSRAM {inst} ({typ}) {p} <- {net}: {'OK' if ok else '*** SIN CE ***'}")
    if emit:
        with open(sdc, "a", encoding="utf-8", newline="\n") as f:
            f.write("\n" + MARCA + "\n")
            for ln in nuevas:
                f.write(ln + "\n")
        print(f"\n--emit: {len(nuevas)} lineas set_max_delay anadidas a {sdc}")
    elif nuevas:
        print("\nLineas que faltan en el SDC:")
        for ln in nuevas:
            print("   " + ln)
    print("\nRESULTADO:", "OK" if fallos == 0 else f"{fallos} FALLO(S)")
    return 0 if fallos == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
