# Port de bugfixes del V9968 upstream (hra1129/V9968_Cartridge) al arbol MSXimus th9958

- **Arbol destino**: `C:\Users\alber\proyectosAI\msx\MSX_up_th9958` (rama th9958, HEAD ff33f99). NO tocado: todo el trabajo se hizo sobre una copia en scratchpad y se entrega como parches.
- **Upstream**: clon local `C:\Users\alber\proyectosAI\msx\V9968_Cartridge`, HEAD 5978d18. Verificado que los commits intermedios no listados (700071a, 91702ee, 2632cdd, 9587cd8, 886df18, 17455ac) **no tocan** el RTL de `src/v9968` (solo el arbol `_for_28MHz`, artefactos de sintesis o el rename puro).
- **Generacion de registros**: nuestro arbol usa la generacion VIEJA de R#20/R#21 (R#20=[S16][EVR][ECOM][EPAL][SCOL][ILNS][SVNS][HS], R#21[0]=fakeID, R#21[7]=CEIE). Los fixes post-0683e7e se **adaptaron** a esta generacion (detalle por fix).
- **Simulacion**: Icarus 12.0 + Verilator 5.020 en WSL (Ubuntu-24.04). Logs completos en `evidencia/`.

## Orden de aplicacion de los parches (git apply desde la raiz del repo)

```
git apply 01_eebc87f_vr_bit_s2.patch
git apply 02_7298638_s10_cmd_int.patch
git apply 03_4148742_blink_period.patch
git apply 90_bancos_upfix.patch          # bancos nuevos (opcional pero recomendado)
```

Verificado: los 4 aplican en secuencia sobre ff33f99 y el resultado es **byte a byte identico** al arbol validado en simulacion (CRLF de `vdp_cpu_interface.v` preservado; el parche 02 se genero binario-seguro).

---

## Fix 1 — eebc87f «Bugfix VR bit on S#2» — PORTADO (parche 01)

**Que hace el upstream**: el bit VR (S#2 bit6, `status_vsync`) subia en una rama propia dentro de `w_h_count_end` al FINAL de la linea 211/191, ~56 µs despues del pulso `intr_frame`. La MSX Diagnostics Cartridge lee S#2 nada mas atender la INT de frame y, al ver VR=0, detectaba un TMS9918. El fix pone `ff_vsync <= 1` en el mismo evento `w_intr_frame_timing` y mueve el clear de `pos_y==3FE` a `3FF` (ademas elimina la rama 211/191, ahora redundante).

**Adaptacion**: directa — nuestro `vdp_timing_control_ssg.v` tenia el bloque `ff_vsync` pre-eebc87f literal y `w_intr_frame_timing` con la misma definicion que el upstream. Los clones MSXimus (_120/_125b) de ese fichero no se tocan. El commit upstream tambien reestructura los `w_*_active` de `vdp_command.v`, pero ese hunk queda **superseded** por 18b4594 (ver Fix 5) y en nuestro arbol el estado neto ya es el final: **no se toca `vdp_command.v`**.

**Consumidores**: `status_vsync` solo llega a S#2 bit6 via `vdp_cpu_interface` (verificado con grep); el vsync de video (`display_vs`) es otra senal — el fix no puede mover un solo pixel.

**Validacion (banco nuevo `tb_upfix_s2vr.sv`, solo el SSG, 4 configs 192/212 x 60/50 Hz, 5 frames por config, actividad exigida >0)**:

| medida | ANTES | DESPUES |
|---|---|---|
| delta intr_frame → subida de VR | **4832 ciclos** (56,2 µs) en las 4 configs | **1 ciclo** (11,6 ns) en las 4 configs |
| pos_y en la bajada de VR | 0x3FE | 0x3FF (= upstream) |
| frames/flancos observados | 5/4/5 por config | 5/4/5 por config |

Logs: `evidencia/s2vr_ANTES.log`, `evidencia/s2vr_DESPUES.log`.

**Regresion**: `tb_ssgblink` (P=0 y P=17) con el SSG antes/despues del fix — salida IDENTICA (el camino del blink no se mueve): `evidencia/ssgblink_ANTES.log` vs `evidencia/ssgblink_DESPUES_fix1.log`. Bateria Verilator completa en verde (ver al final).

---

## Fix 2 — 7298638 «leer S#10 borraba el interrupt de fin de comando» — PORTADO (parche 02)

**Que hace el upstream**: quedaba una rama legada en el bloque de interrupts que, al leer el status register con el puntero en 10, hacia `ff_command_end_interrupt <= 0`. El unico clear legitimo es la escritura del puerto 4 con bit2=1. (El mismo commit toca `tangnano20k_vdp_cartridge.v` — el top del CARTUCHO de HRA, dominios de reset: no aplica a nuestro top, y de paso corrige un comentario copy-paste.)

**Adaptacion**: nuestro `vdp_cpu_interface.v` tenia la rama calcada (lineas 937-940). OJO generaciones: el commit upstream es post-0683e7e, pero esta rama es identica en ambas; lo unico dependiente de generacion es COMO se arma el CEIE — en la nuestra es **R#21[7]** (upstream nuevo: R#20[6]) y el banco lo ejercita asi. Se elimino la rama y se corrigio el comentario del clear por puerto 4 (mismo hunk que upstream). El buffer de pre-lectura _149 (mismo fichero) no se toca.

**Validacion (banco nuevo `tb_upfix_s10.sv`, solo `vdp_cpu_interface`, 16 transacciones de bus, 13 comprobaciones)**:

| comprobacion | ANTES | DESPUES |
|---|---|---|
| leer S#10 no borra el flag | **MAL** (el bug) | OK |
| int_n sigue bajo tras leer S#10 | **MAL** (el bug) | OK |
| leer S#2 no toca el flag | MAL (cascada del bug) | OK |
| puerto4 bit2 borra el flag / int_n vuelve | OK | OK |
| S#0/S#1 borran frame/linea; puerto4 bits0/1 | OK | OK |
| S#10 lee 0xFF (default del case) | 0xFF | 0xFF |

Logs: `evidencia/s10_ANTES.log`, `evidencia/s10_DESPUES.log`.

**Regresion del fichero tocado**: `tb_t2cpuread` (Z80 + v9968_cpu_glue + pila completa; el gran usuario del `vdp_cpu_interface` con la pre-lectura _149), tras el fix: **0 bytes equivocados de 120 lecturas (0,0%) a 3,58 y a 5,37 MHz, latencia constante 3 ciclos (35 ns)** — clavado a la referencia _149 de ORIGEN.txt. Log: `evidencia/t2cpuread_DESPUES_fix12.log`.

---

## Fix 3 — 4148742 «direccion de la tabla de blink + periodo» — PARCIALMENTE YA PRESENTE; el periodo se PORTA (parche 03)

El commit upstream tiene 2 hunks:

**Hunk 1 (direccion de la tabla, `w_color_t2` `[7:3]` → `[7:2]`)**: **YA PRESENTE** en nuestro arbol. Nuestro parche local _127F llego al mismo resultado por la via del HW (rayas verticales con periodo de 8 caracteres, foto 4310): el `[7:3]` ademas dejaba la concatenacion en 17 bits sobre un wire de 18 (el bit alto de la base a 0 = tabla en otra direccion). El diff completo de `vdp_timing_control_screen_mode.v` contra el upstream 5978d18 solo difiere en comentarios MSXimus: `evidencia/fix4_fix3h1_identidad_screen_mode.diff`. **Nada que portar.**

**Hunk 2 (periodo: `w_10frame = (ff_blink_base == 4'd9)` → `4'd4`)**: **SE PORTA — y la medida contradice la nota de ORIGEN.txt**. La clave es la INTERACCION con el off-by-one de la recarga de `ff_blink_counter` que el propio _149 midio («el periodo real es (N+1)*10, no N*10»): cada fase dura (N+1) tics de `w_10frame`, no N. Con el tic a 10 frames (4'd9) las fases de R#13=0x11 duran **20 frames** — blink a MITAD de velocidad del datasheet (166,9 ms/unidad) y de openMSX (que cuenta N*10 frames exactos). Con el tic upstream a 5 frames (4'd4), (N+1)*5 = **10 frames exactos** para 0x11 = clavado al datasheet/openMSX en el caso comun. Eso es lo que HRA quiso decir con «ブリンク周期が半分になっていたのを修正»: el suyo iba a mitad de velocidad y lo corrigio.

**Medida (`tb_ssgblink`, R#13=0x11, 25 campos)**:

| RTL | rachas (campos por estado) | fase |
|---|---|---|
| 4'd9 (nuestro, ANTES) | `9(0) [cola 15(1)]` — 1 conmutacion a ~10 y ninguna mas en 25 campos | 20 campos ((N+1)*10 = mitad de velocidad) |
| 4'd4 (upstream, DESPUES) | `4(0) 10(1) [cola 10(0)]` | **10 campos = datasheet (166,9 ms) / openMSX (N*10)** |

- R#13=0x00 (MSX-DOS/BASIC): blink=0 los 25 campos en AMBOS arboles — sin cambio (`ssgblink_ANTES.log` / `ssgblink_DESPUES_fix3_P0_16_17_34.log`).
- R#13=0x10 (el menu del MSXimus): el estado final es el mismo — con OFF=0 la pagina queda RETENIDA con blink activo. Medido: ANTES `9(0) + cola 15(1)` retenido; DESPUES `4(0) + cola 20(1)` retenido. Solo cambia la cuenta atras inicial hasta la retencion (~10→~5 campos, cosmetico de arranque). Logs: `ssgblink_ANTES_P16_34.log` / `ssgblink_FINAL_P16.log`.
- R#13=0x22 (N=2), medido DESPUES: `4(0) 15(1) 5(0)` → fase de **15 campos = (N+1)*5** frente a los 20 del datasheet — **residual conocido** del off-by-one de recarga que HRA no arreglo (ANTES: sin conmutacion en la ventana de 25 campos → fase ≥20 medida; 30 segun el modelo (N+1)*10 — peor: +50% frente a −25%). Es el comportamiento upstream tal cual; la alternativa «de libro» (dejar 4'd9 y arreglar la recarga para que la fase sea N*10 exacto a TODOS los N) se aparta del upstream y NO se aplica — queda anotada por si algun dia se contrasta con un V9938 real. Log: `ssgblink_FINAL_P34.log`.
- Doble verificacion: la corrida independiente de las 4 P sobre el mismo arbol dio rachas identicas (P=0 `24(0)`, P=16 `4(0)/20(1)`, P=17 `4(0)/10(1)/10(0)`, P=34 `4(0)/15(1)/5(0)`).

⚠️ **Nota para Albert**: este es el unico port donde la evidencia CONTRADICE una nota previa de ORIGEN.txt (la de _149 que daba el 4'd9 por correcto). La nota de _149 razonaba con la unidad de 10 frames pero sin conectar el off-by-one (N+1) que ella misma habia medido; el criterio de este port es la cadencia EXTERNA medida contra datasheet/openMSX. Si se prefiere mantener 4'd9, basta con no aplicar el parche 03 (es independiente de 01/02).

**Sobre el PENDIENTE MENOR de ORIGEN.txt (celda fila 1 col 51, byte 0x0810 bit 4, blink a 0 con blink forzado)**: este commit upstream **NO lo explica** — su hunk de direccion ya estaba aplicado (_127F) cuando _149 midio ese pendiente, y el hunk de periodo no toca que celdas capturan el bit. Demostrado con la pila completa: `tb_t2cursor` tras fixes 1+2 y tras 1+2+3 da EXACTAMENTE el mismo resultado que en _149 — 394/395 celdas con el mapeo exacto y la MISMA unica celda mal (`fila 1 col 51: core=0 esperado=1, byte 0x0810=0x3C bit 4`). El pendiente sigue abierto y NO es de esta familia de fixes (huele a captura tardia del byte de blink en ese par concreto, como ya anotaba ORIGEN). Logs: `t2cursor_DESPUES_fix12.log`, `t2cursor_FINAL_fixes123.log`.

---

## Fix 4 — 55e0632 «BLINK en SCREEN0 WIDTH80 (TEXT2)» — YA PRESENTE, NO-OP

El fix upstream corrige el selector `w_blink_pattern` que comparaba las tres ramas contra `2'd0` (dos ramas muertas). Nuestro parche local **_127E es exactamente el mismo cambio** (`2'd0/2'd1/2'd2`), reportado en su dia como TangCartMSX issue #1. Identidad textual verificada en el diff contra upstream 5978d18 (`evidencia/fix4_fix3h1_identidad_screen_mode.diff`: solo difieren comentarios). **Nada que portar; no hay parche.**

Ejercicio en simulacion: el mapeo caracter→byte/bit de la tabla de blink lo valida celda a celda `tb_t2cursor` (fase B con blink forzado y tabla llena de basura): **394/395 celdas exactas** en el arbol final, con la unica excepcion del PENDIENTE MENOR ya conocido (ver Fix 3) — identico a la referencia _149. Ademas los 4 OK historicos se mantienen: R#13=0 apaga el blink (0 de 395 celdas), cursor visto, SIN residuo tras mover el cursor por el puerto CPU, y patron del caracter 255 reescrito. Log: `t2cursor_FINAL_fixes123.log`.

---

## Fix 5 — 18b4594 «rotacion LRMM: quita c_lrmm de sx_active» — VERIFICADO NO-OP

Cadena upstream: 9e3eb6d anadio `c_lrmm` a `w_sy_active` (portado en _152) → eebc87f, al inlinear los `w_*_active` dentro de `ff_start`, anadio ademas `c_lrmm` a `sx_active` (regresion) → 18b4594 lo quita con el comentario «SX のオーバーフロー判定 (LRMM は意図的に外してある)» (excluido A PROPOSITO).

Estado neto de nuestro arbol vs upstream 5978d18 — **identico termino a termino** (`evidencia/fix5_noop_lrmm_sx_active.txt`):
- `sx_active`: lmmm, hmmm, ymmm, lmcm, srch — **sin** lrmm ✓
- `sy_active`: lmmm, hmmm, ymmm, lmcm, **lrmm** ✓ (_152)
- `dx_active`/`dy_active`: identicos ✓

Diferencia puramente estructural: upstream inlinea las expresiones en el `always @(ff_start)`; nosotros mantenemos wires `w_*_active` latcheados en el MISMO `ff_start` — mismo valor en el mismo flanco. **No se toca nada.** La bateria (sc8cmd_full ejercita los comandos con actividad 336k+ turnos) queda como red.

---

## NO portados (analisis)

### 0683e7e «Register R#20, R#21 Modified» — NO (decision de usuario)
Cambio de generacion del mapa de registros: elimina `ff_ext_command_mode`/`ff_vram256k_mode`/`ff_fakeID` y crea `ff_v9958_mode` (R#21[0]); R#20[5]=flat_interlace, R#20[6]=CEIE; `reg_ext_command_mode = reg_vram256k_mode = ~ff_v9958_mode`. Ademas cambia los gates del acarreo de `ff_vram_address` de `ff_vram256k_mode` a `!ff_v9958_mode`. Adoptarlo cambiaria el ABI visible del software (los dos DEVCON.COM difieren exactamente en esto: R#20=0xFF generacion vieja / 0x9F nueva). Se mantiene la generacion vieja tal como esta decidido. **Dato util**: EPAL sigue siendo R#20[4] en AMBAS generaciones (el hunk de R#20 del upstream no toca `ff_ext_palette_mode <= ff_1st_byte[4]`).

### 167b7cf «Sprite Mode2 con PaletteSet# cuando EPAL=1» — NO (feature, riesgo de placement); dependencia de generacion: NINGUNA real
Evaluada la dependencia que se pedia: la feature solo depende de `reg_ext_palette_mode` = **R#20[4] = EPAL, identico en nuestra generacion** — NO esta atada al mapa nuevo de R#20/21. Es decir, seria portable en el futuro sin adoptar 0683e7e. No se porta ahora porque: (a) es una FEATURE nueva, no un bugfix, y no la usa nada de lo que corre en el MSXimus; (b) mete 154 lineas en `vdp_sprite_makeup_pixel.v` + plumbing en 4 ficheros mas, y `vdp_sprite_makeup_pixel` es familia cronica de placement (riesgo de gate en plena campana DEVCON); (c) reescribe el mux de `color` en `vdp_sprite_info_collect.v` (equivalente logico, pero mas superficie de regresion de sprites justo cuando los sprites mode3 acaban de estabilizarse en _151).

### 5978d18 «clone FF para timing» — NO (ya tenemos los nuestros); cobertura comparada
Sus clones vs los nuestros (_120/_125b):
- `ff_screen_mode_clone` en `vdp_command.v` con consumidores w_next/w_512pixel/w_address_s_pre/w_address_d_pre → **YA IDENTICO** en nuestro arbol (_125b, convergencia total).
- `ff_v_count_clone` + `ff_screen_pos_x_clone` con syn_preserve en el SSG y ruteo del clone a u_screen_mode/u_sprite → **YA CUBIERTO y SUPERADO**: nosotros ademas tenemos `ff_screen_pos_x_sprite` (_120, la resta del scroll pre-registrada) y syn_maxfan en la familia reincidente.
- **Unico camino suyo sin equivalente nuestro**: registra `intr_line` (`ff_intr_line`, +1 ciclo de 85,9 MHz en el pulso del line interrupt — 11,6 ns, semanticamente inocuo). Nuestra matriz de timing nunca ha senalado ese cono (comparador `w_intr_line_y`); se anota como relajacion de reserva si el gate se queja algun dia. Tambien registra `vdp_video_out.v` un comentario DVI/LCD (cosmetico).
- Veredicto: **no portar nada**; nuestro conjunto de clones cubre todo lo suyo salvo `ff_intr_line` (no necesario hoy).

---

## Bateria de regresion global (Verilator, pila completa con shim+SDRAM)

Corrida A (baseline ff33f99) vs corrida B (fixes 1+2) — **logs BIT-EXACTOS banco a banco** (unica diferencia: la ruta del fichero en el mensaje de `$finish`). Es lo esperado: ninguno de estos bancos lee S#2/S#10 ni usa blink.

| banco | BASELINE | CON FIXES 1+2 | CON FIXES 1+2+3 (final) |
|---|---|---|---|
| tb_scroll | quiet=192 v=624 h=576 (REPRODUCIDO) | identico bit a bit | quiet=192 v=624 h=576 — identico |
| tb_sc8cmd_full | OK (336k+ turnos) | identico bit a bit | OK, TURNOS identicos (787289/45787/370344) |
| tb_sc5line | OK (ce_colgados=0, diffs=0) | identico bit a bit | OK (ce_colgados=0, diffs=0) |
| tb_cpu_bulk | OK (fallos=0/8192) | identico bit a bit | OK (fallos=0/8192) |

Logs: `evidencia/bateria_BASE_*.log`, `evidencia/bateria_*.log`, `evidencia/bateria_FINAL_*.log`.

## Bancos nuevos entregados (parche 90)

- `tools/v9968_sim/tb_upfix_s2vr.sv` + `run_upfix_s2vr.sh` — alineamiento VR/intr_frame, 4 configs, con contadores de actividad.
- `tools/v9968_sim/tb_upfix_s10.sv` + `run_upfix_s10.sh` — protocolo completo de clears de interrupts por status/puerto4, CEIE=R#21[7].
Los runners toman `W` de `UPFIX_W` si esta en el entorno (para correr sobre copias). Copias sueltas en `bancos/` por comodidad.

## Contenido del entregable (`scratchpad\upfixes\`)

- `INFORME.md` — este documento.
- `01_eebc87f_vr_bit_s2.patch`, `02_7298638_s10_cmd_int.patch`, `03_4148742_blink_period.patch`, `90_bancos_upfix.patch` — aplicar en ese orden con `git apply` desde la raiz del repo (verificado: reproducen byte a byte el arbol validado; el 03 es opcional/independiente si se prefiere conservar 4'd9).
- `evidencia/` — todos los logs ANTES/DESPUES citados.
- `bancos/` — copias sueltas de los bancos nuevos (tambien van dentro del parche 90).
- `work/` — la copia de trabajo completa ya parcheada y validada (fpga/ + tools/v9968_sim/), por si se quiere inspeccionar o re-simular sin aplicar nada.

## Resumen ejecutivo

| # | commit upstream | veredicto | parche |
|---|---|---|---|
| 1 | eebc87f (VR bit S#2) | PORTADO — VR pasa de +56,2 µs a +11,6 ns respecto al intr_frame | 01 |
| 2 | 7298638 (leer S#10 borraba cmd-end int) | PORTADO — adaptado a CEIE=R#21[7] | 02 |
| 3 | 4148742 (tabla blink + periodo) | hunk direccion YA PRESENTE (_127F); hunk periodo PORTADO con evidencia (contradice nota _149; ver seccion) | 03 |
| 4 | 55e0632 (BLINK TEXT2) | YA PRESENTE (_127E identico) — no-op | — |
| 5 | 18b4594 (LRMM sx_active) | VERIFICADO NO-OP — estado neto identico al upstream | — |
| — | 0683e7e (R#20/21) | NO portar (decision de usuario; ABI del software) | — |
| — | 167b7cf (PaletteSet# sprites) | NO portar (feature + riesgo placement); SIN dependencia real de la generacion nueva | — |
| — | 5978d18 (clones FF) | NO portar (los nuestros lo cubren); unico camino no cubierto: registro de intr_line (reserva) | — |

El PENDIENTE MENOR de la celda 0x0810 queda demostrado como NO relacionado con estos fixes y sigue abierto.
