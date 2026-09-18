# Cierre de la campaña "últimos bugs del V9968" — MSXimus

Fecha: 2026-07-28 · HEAD de referencia: `8e1c467` (_161e, camino de audio en tres etapas)
Repo: `C:\Users\alber\proyectosAI\msx\MSX_up` (NO modificado: todo va en `.patch`)
Parches: `C:\Users\alber\AppData\Local\Temp\claude\C--Users-alber\8d6fc485-fa87-43bb-a6d5-f5fe1500a986\scratchpad\v9968fix\`

Siete frentes: seis bugs del informe del niquelado (#1, #2, #16, #17, #18, #19) más el glitch del logo MSX2+ que estaba en la lista de limitaciones del README. **Ninguno se ha sintetizado con Gowin** (la máquina estaba horneando) y **ninguno se ha visto en placa**: todo lo de abajo es simulación (Icarus + Verilator bajo WSL).

---

## 1. Tabla resumen

| # | Bug | Veredicto | Qué se arregló | Ficheros de RTL tocados | Verificador adversarial | Riesgo |
|---|---|---|---|---|---|---|
| **#1** | Doble ejecución / livelock del bus de la CPU | **ARREGLADO** (con condición) | El latch de `vdp_cpu_interface.v` aceptaba con `bus_valid && ff_bus_ready` **crudo** mientras el maestro (`v9968_cpu_glue.v`) solo da la transferencia por hecha con el `bus_ready` gateado. Los dos lados no coincidían en QUÉ ciclo era la transferencia → doble ejecución y, en el peor caso, **livelock** (bus atascado + VRAM machacada). El efecto más destructivo medido no es el "salto +1" de las lecturas sino el **OUT al puerto 1 duplicado**, que toggla `ff_2nd_access` dos veces y desincroniza el par de bytes (46 de 48 fases con R#7 pegado en el valor viejo). Fix de 3 líneas: `wire w_bus_accept = bus_valid & bus_ready;` y el latch acepta con eso. Bit-idéntico en tráfico normal. | `fpga/v9968/vdp_cpu_interface.v` (+19/−1) · `fpga/v9968/ORIGEN.txt` · bancos nuevos `tools/v9968_sim/tb_cpuif_dbl.sv` + `run_cpuif_dbl.sh` | **DUDOSO.** Diagnóstico y fix correctos y sin regresión (logs byte-idénticos, verificados por el revisor). PERO el revisor **reprodujo** el "residuo hermano" que el autor documentó y declinó parchear: con la pre-lectura lanzada en el mismo ciclo de la aceptación, la transacción se pierde en silencio. A LAT=200 (placa ≈190): original OK=13/PERDIDAS=102/DOBLES=115 → parcheado OK=27/**PERDIDAS=203**/DOBLES=0. El parche mata la doble ejecución **y duplica las pérdidas silenciosas**, que producen EL MISMO desincronizado del par de bytes que se pretendía cerrar. La cura de UNA LÍNEA que el propio autor escribe y descarta (`&& !w_bus_accept` en la rama de la pre-lectura) sube el barrido a 230/230, 0 pérdidas, 0 dobles, y es neutra en los 5 modos del banco del autor. | **MEDIO** mientras falte esa línea; BAJO con ella. Gate: un nivel de LUT más en el enable del latch, 0 FF nuevos, camino del bus de la CPU (no las familias crónicas de placement). **No cubre**: bug #26 del glue (descarta flancos de `csw_n/csr_n` sin cola ni /WAIT, sigue vivo >2,5 µs) ni la rancidez de lecturas cuando la latencia supera el presupuesto del Z80. |
| **#2** | Deadlock de la caché de comandos al abortar un flush | **ARREGLADO** (dos parches) | `vdp_command_cache.v`: un R#46 (start, legal sin esperar CE=0) que cae con un flush **ya drenado** (típico tras POINT/SRCH/LMCM, que no ensucian) ponía `ff_busy=1` sin nadie que lo bajara → `cache_vram_ready=0` **para siempre**. Fix: 1 línea `ff_busy <= 1'b0;` en el estado `3'd1`, único punto por el que pasan TODOS los flushes. El esbozo A del informe está **refutado** (dejaba el mismo deadlock si lo que había en vuelo era una lectura). **HALLAZGO NUEVO #2b**: con la caché ya sana el "rectángulo fantasma" SIGUE — el `w_cache_flush_end` del comando abortado apaga el `ff_command_execute` del comando NUEVO (`vdp_command.v:1115`) y congela sus contadores; también clobbrea `reg_ny` (:822) y `ff_border_detect` (:1124). Fix: cualificar los tres con `&& (ff_state == c_state_finish)`. | **P1**: `fpga/v9968/vdp_command_cache.v` (1 línea) + `tools/v9968_sim/tb_cmdcache.sv`/`run_cmdcache.sh` · **P2 (#2b)**: `fpga/v9968/vdp_command.v` (3 sitios) + `tb_cmdghost.sv`/`run_cmdghost.sh` | **CONFIRMADO** (el más sólido de la campaña). El revisor rehízo el A/B, escribió dos escenarios adversariales propios ([F] R#46 en el mismo ciclo del `rdata_en` con caché sucia, [G] el maestro mantiene `valid` desde dentro del flush) y ambos pasan. Aporta una **demostración** de la neutralidad de timing (llegar a `3'd1` con `ff_busy==1` ⟺ el flush no emitió ni una escritura) y un argumento extra a favor del P2: HRA **ya** cualifica ese mismo `w_cache_flush_end` con `ff_state==c_state_finish` para `ff_command_end` (`vdp_command.v:346`). Huecos nombrados: la batería del repo no ejecuta ni una vez la línea parcheada (solo comandos de escritura), y `tb_cmdghost` no barre k negativo. | **BAJO.** P1: 0 lógica combinacional nueva. P2: un comparador de 6 bits sobre `ff_state` (que ya lleva `syn_maxfan=4`) para tres FF de control. **Dependencia dura: con SOLO el P1 el rectángulo fantasma NO desaparece.** Residuales preexistentes en el mismo camino: #16 y #17 (abajo) y una tercera vía de pérdida de lectura (respuesta descartada en silencio mientras `ff_flush_state != 0`). |
| **#16** | Respuesta de lectura huérfana tras abortar | **ARREGLADO** | La respuesta de una lectura ya aceptada llega 14–90+ ciclos después; si entre medias hay `start`, la rama `command_vram_rdata_en` **resucita** la entrada `cache#0` —que ya es del comando NUEVO— con la dirección ABORTADA. Medido: el byte del comando nuevo acaba escrito en la dirección vieja (`VRAM WR addr=30000 … data=…5c`) + `rdata_en` espurio que pisa `ff_read_pixel/ff_read_byte`. Fix: dos contadores de 2 bits (`ff_read_pending`/`ff_read_discard`) en un **always propio** (la aceptación hay que verla EN EL CABLE) y la rama de respuesta gateada con `ff_read_discard == 2'd0`. | `fpga/v9968/vdp_command_cache.v` (líneas 115, 695, 757) + `tb_cmdcache_abort.sv` | **CONFIRMADO.** El revisor verificó la procedencia (md5 del fichero parcheado), rehizo la batería (idéntica) y escribió 5 escenarios adversariales que el banco del autor no cubría: **ADV-A** (lectura emitida pero JAMÁS aceptada + start → el contador NO se arma; era el riesgo nº1, un falso positivo se habría comido la respuesta buena = CE=1 permanente), **ADV-C** (dos abortos encadenados: HEAD entrega el byte equivocado, parcheado correcto → el parche es **más fuerte** de lo que el informe afirma), **ADV-E** (desborde del contador: degrada al comportamiento de HEAD, **no cuelga**). Reparo menor: el comentario del RTL dice "≤2 en vuelo"; en realidad tolera 4 (3 descartes). | **BAJO.** +4 FF, un término más en el enable de la última rama; no toca ningún camino de dirección/dato. Residual real (no hipotético): **respuestas fuera de orden** — la cabecera de `vdp_vram_interface.v` documenta que el shim sirve fuera de orden y ni el banco del autor ni el del revisor lo modelan; si la nueva llega antes que la huérfana se descarta la buena → corrupción, no cuelgue. Cerrarlo exige un bit de generación en `vram_tag/vram_rtag`. |
| **#17** | Strobe `rdata_en` colgado tras abortar | **ARREGLADO** (con reservas) | Si el R#46 cae en el único ciclo en que `ff_cache_vram_rdata_en` está alto y además hay flush sucio, las ramas de mayor prioridad lo tapan durante TODO el flush; al acabar, el motor ve `ready=1`, da su petición por aceptada y espera **para siempre** un `rdata_en` que ya nadie generará (CE=1 hasta el siguiente R#46). Fix: 1 línea `ff_cache_vram_rdata_en <= 1'b0;` en la rama del start. Medido: 236 cuelgues en 5 latencias → 0. No hace falta blindar también `cache_flush_start`. | `fpga/v9968/vdp_command_cache.v` (rama start, ~línea 171) + `tb_cmdcache17.sv` | **DUDOSO.** El revisor confirmó mecanismo, ausencia de pérdida de dato y neutralidad ciclo a ciclo, y **amplió** la prueba (abortos encadenados a espaciado realista: PRE 335 cuelgues → POST 0). Dos huecos medidos: **(A)** el parche quita el único rescate *accidental* de `ff_busy` (el `ff_busy <= 1'b1` de la rama start-sucia del FIX ABORTO no tiene bajador garantizado): 15 casos de "caché encallada" que solo aparecen en POST, todos con 2–4 ciclos entre dos R#46 — **inalcanzable para el Z80**, desaparece a espaciado realista. **(B)** el beneficio solo está demostrado con un comando de LECTURA detrás: con LMMV/HMMV la clase #17 va 46→46 porque el que manda es el CE prematuro (= bug **#2b**). No se puede vender como "el fin del comando fantasma" sin el #2b. | **BAJO** con #2b y #16 aplicados; engañoso sin ellos. Cero lógica nueva (solo añade `start`, ya la señal de máxima prioridad, al enable de un FF de 1 bit). Deja un peligro latente nombrado: `ff_busy <= 1'b1` sin bajador garantizado (candidato a ticket propio). |
| **#18** | Scroll horizontal de sprites vs. splits de R#27 | **ARREGLADO** (con corrección pendiente) | La resta del scroll de sprites del _120 usaba `reg_horizontal_offset_l` (**R#27 vivo**) mientras el FONDO usa el latcheado, que solo se carga una vez cada DOS líneas → un split de R#27 llegaba antes a los sprites que al fondo (hasta **7 px** de desalineo, ráfagas de ~2 líneas). Fix: wire `w_horizontal_offset_l_next` (función de próximo estado del latch) restado en `ff_screen_pos_x_sprite`, conservando el registro que el _120 añadió por timing. Corrige además una afirmación **falsa** del ORIGEN.txt ("bit-exacto … incluso en el cambio de R#27"). | `fpga/v9968/vdp_timing_control_ssg.v` · `fpga/v9968/ORIGEN.txt` · nuevos `tools/v9968_sim/tb_hscroll_sprite.sv`, `gen_ssg_variants.py`, `run_hscroll.sh` | **DUDOSO.** El revisor confirmó el diagnóstico leyendo el core (asimetría real: `vdp_timing_control_ssg.v:155-163/432` vs `vdp_timing_control_screen_mode.v:226-227`), reprodujo el A/B (fix vs ref: 0 desajustes en 1,03 M ciclos con vivo≠latcheado) **y encontró que la frase "BIT-EXACTO" que el parche deja escrita en el RTL y en ORIGEN.txt es FALSA**: durante la aserción del reset el mux devuelve el valor viejo, no 0 → 1 ciclo de divergencia. Impacto en placa nulo, pero es el mismo tipo de sobre-afirmación que este parche viene a corregir del _120. Variante de UN token (`!reset_n ? 3'd0 : …`) probada en verde con 0 desajustes. Además: `run_hscroll.sh` devuelve 0 aunque imprima `*** FALLO ***`. | **MEDIO.** **No es cosmético**: cualquier demo/juego con splits de R#27 por línea verá los sprites moverse hasta 7 px respecto a las builds actuales (hacia lo correcto, alineado con el fondo y con el V9958/upstream). Gate: un mux de 3 bits en el operando del restador, destino FF (no reintroduce el cono que el _120 vino a romper); salida documentada si el ruter protesta = el truco del _120f. |
| **#19** | Snap del coeficiente bilineal a `8'd63` | **INERTE** | **No se toca nada.** Con `c_numerator == reg_denominator == 192` el acumulador Bresenham es un punto fijo (`w_hold` siempre 0, `ff_numerator ≡ 0`) → `ff_coeff ≡ 0` con snap o sin él desde el commit de bordes `6d15c0b`: cambiar `8'd63` por `8'd255` sería un **NO-OP**. Y la consecuencia visual que el esbozo atribuía al bug ("1 de cada 3 fronteras con columna fantasma al 25 %") es **FALSA incluso para el RTL anterior**: el coeff 63 aparecía en 41 280 ciclos y en NINGUNO `tap0 != tap1` (cae siempre en la columna de HOLD). El _142 hacía lo que prometía. | `fpga/v9968/vdp_video_out.v` — **+57 líneas, TODAS de comentario, 0 de código** | **CONFIRMADO** ("sin cambio funcional que verificar"). | **CERO.** Netlist idéntica, no requiere resintesis ni prueba en HW. La conclusión depende de tres invariantes enumeradas en el propio comentario (`c_numerator == reg_denominator`, `c_start_numerator = 0`, el `8'd192` que cablea `vdp.v`); si alguna cae, el valor correcto del snap es `8'd255`, no `8'd63`. |
| **LOGO** | Glitch del logo MSX2+ | **ARREGLADO** (con reservas) | **NO es entrelazado de vídeo** (R#9 = 0x00 en las cinco capturas de la FS-A1WSX): es el "entrelazado" de **PÁGINAS del scroll SP2**. La BIOS pinta el logo en SCREEN 5 página 1 y lo anima con R#25=0x03 (SP2\|MSK) vía registro indirecto R#17→R#26/R#27; SP2 reparte los 512 px en dos páginas y el core cambia de página **una vez por línea activa**. El productor de prefetch del shim (+2 lineal) no genera C+1 tras el cruce → **exactamente 1 miss por línea = 185–193/frame**. Fix "_163 ECO DE CRUCE DE PÁGINA": reutiliza el eco de arranque del _135 (zona segura, drenaje solo con backend ocioso) para encolar las dos palabras que faltarán, reconociendo el cruce **sin mirar ningún bit de página**. Con UN solo tiro la frontera solo se corre una palabra (corrección honesta del propio autor): hacen falta DOS. | `fpga/src/v9968_vram_shim.v` (2 FF `xg_cred`/`xg_snd`, una rama `else-if`, rearme en hblank) · `fpga/v9968/ORIGEN.txt` (nota cruzada; **el core de HRA no se toca**) · nuevos `tools/v9968_sim/tb_logo.sv`, `run_logo.sh` | **DUDOSO.** El revisor confirmó el diagnóstico en el fuente (bit de página SP2 = bit 15 de byte = bit 13 del vector en SCREEN 5), el techo de daño (el drenaje escribe `pww`, **nunca** contesta a un consumidor → no puede devolver dato malo) y que el banco no está inerte. Cuatro huecos: **(1)** la justificación de generalidad es **falsa y comprobable** — en SC7/8 `w_blink_page` cae en el bit 14 del vector (no el 12), que es el **selector de stream**, así que allí lo cubre el _135 y esta rama ni dispara (benigno **por suerte, no por diseño**); **(2)** ningún banco de regresión enciende SP2 → "byte a byte idéntico" solo prueba que la lógica está dormida; **(3)** el banco escribe R#8=0x2A (**sprites apagados**) cuando la captura que él mismo cita dice 0x28 (encendidos): los "3 miss/frame" están medidos con el backend más desahogado que el caso real; **(4)** R#26 solo barre 8..16 de 32 columnas, nunca la frontera en el borde de línea. | **MEDIO-BAJO.** Resultados: miss 185–193 → 3/frame (−98,3 %), píxeles malos ~4300 → 48–112/frame (−97,8 %); 5 frames de control sin SP2 **idénticos**; `tb_sc8cmd_full`, `tb_sc5line`, `tb_cpu_bulk` y `tb_scroll` byte a byte iguales. Riesgos: ocupación del `ecq` (2 empujes/línea más sobre una cola de 3 usables; si en placa aprieta, el guardia `!ecq_full` **descarta en silencio** → volvería el glitch, nunca corrupción; cura = ecq a 8 plazas o prioridad al eco de cruce). Modos de patrones (SC0/1/2, menú TEXT2) sin medir: `tb_screen1` hace timeout igual antes y después. |

---

## 2. ORDEN DE APLICACIÓN recomendado

### 2.1 El solape real

**Tres parches tocan `fpga/v9968/vdp_command_cache.v`** y **tres tocan `fpga/v9968/ORIGEN.txt`**. Son dos situaciones muy distintas:

| Fichero | Parches | ¿Se pisan? |
|---|---|---|
| `fpga/v9968/vdp_command_cache.v` | #2 (P1), #16, #17 | **NO se pisan textualmente.** Los hunks caen en zonas disjuntas: #17 en la rama `start` (~línea 171), #2 en el estado de cierre de flush `3'd1` (~línea 304), #16 en las líneas 115 (declaraciones), 695 (`else if( command_vram_rdata_en )`) y 757 (always nuevo al final). `git apply` recalcula los offsets solo. Los tres verificadores lo comprobaron por separado, y el de #16 va más allá: **son compatibles SEMÁNTICAMENTE**, no solo textualmente — ninguno cambia el significado de `start == aborto`. |
| `fpga/v9968/vdp_command.v` | #2 (P2, bug #2b) | Único. Sin solape. |
| `fpga/v9968/vdp_cpu_interface.v` | #1 | Único. |
| `fpga/v9968/vdp_timing_control_ssg.v` | #18 | Único. |
| `fpga/v9968/vdp_video_out.v` | #19 | Único (solo comentarios). Si algún día se parchea el magnificador cerca de la línea 395, aplicar este **primero**. |
| `fpga/src/v9968_vram_shim.v` | LOGO | Único. No toca nada del agente de audio (`ganancia`). |
| **`fpga/v9968/ORIGEN.txt`** | **#1, #18, LOGO** | **SÍ SE PISAN — conflicto seguro.** Los tres añaden un bloque de bitácora, y **#1 y #18 usan los dos la etiqueta `_162`**. Además el parche de #2 **no** toca ORIGEN.txt a propósito (deja la entrada redactada para que la ponga el orquestador) y el de #17 tampoco. |

### 2.2 Orden

```
0.  RENUMERAR LAS ETIQUETAS DE BUILD (antes de aplicar nada)
    HEAD = _161e (el agente 'ganancia' sigue commiteando en el camino de audio).
    #1   -> _162  (4 apariciones: 3 comentarios en el .v + el bloque de ORIGEN)
    #18  -> _163  (3 apariciones: 2 comentarios en el .v + el bloque de ORIGEN)
    LOGO -> _164  (renombrar el bloque "_163 ECO DE CRUCE DE PAGINA")
    Es un sed; hacerlo AHORA evita dos bloques "_162" contradictorios en el árbol.

1.  bug19/bug19_comentario.patch                 (vdp_video_out.v — solo comentario, riesgo 0)
2.  bug17/bug17_vdp_command_cache.patch          (rama start, ~L171)
3.  bug2_cachebusy/bug2_cachebusy.patch          (cierre de flush, ~L304)
4.  bug16/bug16_vdp_command_cache.patch          (L115 / L695 / L757)
5.  bug2_cachebusy/bug2b_command_execute.patch   (vdp_command.v — OBLIGATORIO con el 3)
6.  bug1/bug1_cpuif_doble_disparo.patch          (+ la línea extra, ver 2.3)
7.  bug18/bug18_v9968_scroll_sprites_162.patch   (+ el término de reset, ver 2.3)
8.  sp2eco/v9968_logo_sp2_163.patch              (último: es el único de fpga/src/)
```

**Por qué ese orden dentro de `vdp_command_cache.v` (2→3→4):** de menor a mayor número de línea del primer hunk **no** es lo que importa (git recalcula), pero sí conviene que el que añade más líneas al final del fichero (#16, con su `always` nuevo de ~57 líneas) entre el último: así los `--check` intermedios son más legibles y, si hay que rebasar algo a mano, el diff de contexto queda limpio. Si prefieres orden alfabético o cualquier otro, **también funciona**; lo verificado es que los tres aplican sobre HEAD y que #2 aplica también después de #16/#17.

**Conflictos previsibles y cómo se resuelven:**

- **ORIGEN.txt (pasos 6, 7, 8)**: el 6 y el 7 chocarán si los dos bloques van al mismo sitio del fichero. Aplicar el de #1 primero, luego el de #18 **con `git apply --3way`** o pegar el bloque a mano; el de LOGO añade una nota cruzada y suele caer aparte. Al terminar, añadir **a mano** la entrada de #2/#2b y la de #17, que sus autores dejaron redactadas pero no parcheadas.
- **Cabecera de ORIGEN.txt**: sigue diciendo que solo `vdp_vram_interface.v` y `vdp.v` están parcheados y "el resto, INTACTO". Ya era falso en HEAD (`vdp_command_cache.v` lleva FIX ABORTO) y esta campaña lo deja mucho más falso: **hay que reescribirla** — es el invariante de trazabilidad contra upstream del propio proyecto.
- **`git status` sucio**: uno de los agentes vio 13 borrados sin stage con nombres extraños en `fpga/` (`fpga/0`, `fpga/el`, `fpga/grupo`, `fpga/CH340`…) y ~70 untracked. `fpga/v9968/` está limpio. Revisarlo **antes** de commitear (los ficheros raros del listado de la raíz —`1`, `2][7`, `300`, `degrada`, `ff_1st_byte`, `n_glue)`— son basura de redirecciones de shell).

### 2.3 Dependencias de contenido (más importantes que el orden)

1. **#2 P1 → #2 P2 (bug #2b): DURA.** Con solo el P1 el bloqueo duro de la caché desaparece pero **el rectángulo fantasma NO**. Medido: RTL tal cual 12/15 · +P1 12/15 (caché sana, motor congelado) · +P1+P2 **15/15**.
2. **#17 → #2b: DURA en la práctica.** El #17 solo cierra el síntoma cuando el comando que aborta es de **lectura** (POINT). Con LMMV/HMMV el que manda es el CE prematuro del #2b.
3. **#17 ↔ #16: complementarios.** Son mutuamente excluyentes por caso (si el strobe está alto, la respuesta que lo generó ya llegó) y quedan 2 cuelgues de 130 con solo el #17. **Entran juntos o no entran.**
4. **#1 necesita su línea extra.** Sin `&& !w_bus_accept` en la rama que lanza la pre-lectura, el parche cambia 115 dobles ejecuciones por 101 pérdidas silenciosas adicionales — el mismo síntoma que iba a curar. Copia probada por el revisor en `…\scratchpad\adv\fix2\vdp_cpu_interface.v`. **Alternativa mínima aceptable**: aplicar tal cual pero **reescribir** el párrafo "RESIDUO CONOCIDO (NO tocado, NO demostrado)" de ORIGEN.txt, porque está demostrado, es alcanzable con la latencia de placa y el parche lo vuelve determinista.
5. **#18 necesita el término de reset.** Cambiar la asignación a `assign w_horizontal_offset_l_next = ( !reset_n ) ? 3'd0 : ( ff_v_count[0] && w_h_count_end ) ? reg_horizontal_offset_l : ff_horizontal_offset_l;` — o quitar la palabra "bit-exacto" del RTL y de ORIGEN.txt y documentar la excepción del ciclo de reset. Un token contra una afirmación falsa en el árbol.
6. **LOGO necesita dos correcciones de texto** antes de commitear: el bit de página en SC7/8 es el **14**, no el 12, y la cobertura de SC7/8 la da el **_135**, no esta rama.

---

## 3. Plan de validación en placa

Nada de esto se ha visto en hardware. Regresión mínima común a **toda** la tanda: arrancar, entrar al menú (TEXT2), cargar una ROM y un disco, y mirar el **COM11** (los `drops` S1/wq deben seguir en 0 y `bgmiss` debe **bajar**).

### #1 — bus de la CPU
- **VRAMSOK2**: es el testigo histórico del "salto ±1" del puerto CPU (~0,1–0,3 %). Es la prueba discriminante: si el residuo baja, el fix está haciendo lo suyo.
- **LDIRVM / LDIRMV** a pelo (bloques grandes, BASIC o un pequeño .COM): no debe perderse ni corromperse un byte.
- **Cargador de ROMs del menú** (miles de bytes por el puerto 0): tiempo de carga y checksum.
- **DEVCON.COM** y la demo **ru66-v9968** de herraa1: el síntoma que este bug produce es el **par de bytes desincronizado** → registros que no llegan a su sitio (R#7 pegado). Si al arrancar la ru66 los colores/bordes se estabilizan, es este.
- Turbo: probar también a **5,37 MHz (WSX)**, que es donde el presupuesto del Z80 aprieta más.

### #2 + #2b + #16 + #17 — motor de comandos y su caché
Todos comparten síntoma (**rectángulo fantasma / comando colgado con CE=1**), así que se validan juntos:
- **DEVCON.COM** (el examen final del V9968) — las dos versiones si hace falta; recuerda que difieren en UN byte (entrada "14"=R#20: 0xFF para nuestra RTL vieja).
- **Suite de tests de HRA** (V9968DM, VDPTEST2) — comandos encadenados y POINT/SRCH/LMCM.
- **Software que reescribe R#46 sin esperar CE=0**: es el disparador exacto. Rutinas que encadenan comandos a pelo, y juegos con mucho blitting — **Aleste 2** (el caso que cerró la campaña de la DRAM) y **Metal Gear 2**.
- **SCREEN 5 / SCREEN 8 con LMMM/HMMM/LMMV** y el **smoothscroll SC5/SC8** de la batería.
- Qué mirar: nada de rectángulos a medio pintar, ningún cuelgue con el VDP ocupado eternamente, y que el **borde** de los comandos (`ff_border_detect`) siga correcto.

### #18 — sprites vs. splits de R#27
- **Parodius** (smoothscroll ya validado en HW): sprites contra el fondo, sin desalineo.
- **Aleste 2** (parallax + sprites) — el A/B más visible.
- **R-Type** con el parche de smooth-scroll (ojo: su jitter de ISR ~15 % de frames es del parche, no del core).
- Batería de scroll SC5/SC8 del proyecto.
- Qué mirar: hasta **7 px** de diferencia respecto a la build _161x, y debe ir **hacia lo correcto** (sprites alineados con el fondo, como en un V9958 real). Si algo se ve peor que antes, es que el juego dependía del desalineo — improbable, pero anótalo.

### #19 — nada
Netlist idéntica. No requiere prueba.

### LOGO MSX2+
- **Entrar a BASIC** en la Console 60K y mirar el logo: el glitch de medio segundo debe desaparecer o quedar casi imperceptible (simulación: 185–193 → 3 misses/frame).
- **Menú (TEXT2)** y SCREEN 1 justo después de salir del logo: es el flanco **sin medir** (el `stride` es pegajoso entre cambios de modo y la rama disparará todas las líneas; el argumento de inocuidad es estructural, no medido).
- **SCREEN 5/8 con scroll** y las escenas duras de las demos.
- **COM11**: `bgmiss` debe **bajar** y los drops S1/wq seguir en 0. Si vuelve el glitch sin corrupción, es el `ecq` lleno → subir a 8 plazas o dar prioridad al eco de cruce.

---

## 4. Lo que queda abierto en el V9968

**De la sección de limitaciones del README** (`README.md:81-87`):
- **Scroll de dos páginas en SCREEN 7 y 8, y scroll hacia atrás**: sin pulir. La campaña **no lo toca** — y el hallazgo del LOGO lo ilumina: en SC7/8 el bit de página cae en el bit 14 del vector (= selector de stream del shim), así que el cruce de página allí es un cambio de stream cubierto por el _135, no la discontinuidad de SCREEN 5. Es el sitio por donde entrar la próxima vez.
- **Líneas residuales** en las escenas más duras de las demos (4–10 misses/frame). El fix del LOGO baja los del SP2, no estos.
- **El logo MSX2+**: el README lo da por "diagnosticado, fix aparcado por rutado". **Esta campaña lo reabre con otro fix** (2 FF en la zona segura en vez de ~100 FF y un mux del productor que atascaron al ruter 62 min en la _154). Actualizar el README **solo tras el veredicto en placa**.
- **El core sigue en la foto de enero de 2026**.

**De `fpga/v9968/ORIGEN.txt` (fixes upstream que faltan):**
- `0683e7e` **R#20/R#21 modificados** — decisión de Albert: mapa viejo en la v2.0, **migración prevista para la v2.1** con las demos parcheadas. Coste: 26 líneas de RTL + 2 bytes de software (DEVCON.COM offset 14883, V9968DM.COM offset 0x377). Cuidado: el comentario del upstream **miente** en el árbol nuevo; en el nuestro aún es cierto.
- `167b7cf` **Sprite Mode2 con PaletteSet# cuando EPAL=1** — FEATURE nueva, 154 líneas de `vdp_sprite_makeup_pixel.v`. **Sin portar.**
- `5978d18` **clone FF para relajar timing** — no portado; nuestros clones _120/_125b cubren todo lo suyo **salvo el registro de `intr_line`** (reserva anotada por si el gate vuelve a quejarse).
- Migración a **th9958** documentada como plan (rama `th9958`), con la lista de qué tomar limpio y qué re-aplicar.

**Residuos técnicos que esta campaña deja nombrados y NO cierra:**
- **Bug #26 del glue**: `v9968_cpu_glue.v` descarta flancos de `csw_n/csr_n` sin cola ni /WAIT; corrompe a latencias >2,5 µs. Vivo.
- **Rancidez de lecturas** cuando la latencia de VRAM supera el presupuesto del Z80 (límite conocido del _149).
- **Respuestas de VRAM fuera de orden**: el tag `{consumidor, byte_sel}` no lleva número de secuencia; ni el banco del autor ni el del revisor lo modelan. Cerrarlo exige un bit de generación que viaje hasta el shim.
- **`ff_busy <= 1'b1` sin bajador garantizado** en la rama start-sucia del FIX ABORTO: el #17 le quita el rescate accidental. Merece ticket propio.
- **Tercera vía de pérdida de lectura**: una respuesta que llegue mientras `ff_flush_state != 0` se descarta en silencio. Preexistente y ortogonal a #16/#17.
- **`tb_sc8cmd_full` está ROJO en HEAD** (`fallos_vram=7428`), probablemente por una referencia `s8r_frame.txt` desfasada. Es el **único** banco de la batería que machaca comandos, así que **hoy no sirve como puerta verde de regresión**. Arreglarlo o regenerar la referencia.
- **`tb_screen1` hace timeout** (preexistente, idéntico antes y después) y **`tb_sprite3` corre "en verde" con todos los contadores a 0** (banco inerte sin sus `define`s). Ninguno vale como evidencia.
- **Cero síntesis Gowin** en toda la campaña, con CLS al 84 %. Los siete parches tienen su salida documentada si el ruter protesta, pero **el impacto real en el gate está sin medir**.
- La **cabecera de ORIGEN.txt** miente sobre qué ficheros están parcheados.

---

## 5. Recomendación (3 líneas)

1. **Aplica YA, en un solo commit**: #2 (P1) + **#2b** + #16 + #17 — es el bloque coherente que mata el rectángulo fantasma y los cuelgues del motor, dos verificadores CONFIRMADOS y los otros dos con huecos acotados e inalcanzables por el Z80; y #19, que es solo comentario y riesgo cero.
2. **Aplica también, pero con su corrección de una línea cada uno**: #1 (con `&& !w_bus_accept` en la rama de la pre-lectura, o el bug se convierte en pérdida silenciosa) y #18 (con `!reset_n ? 3'd0 :`, o quita la palabra "bit-exacto" del árbol) — sin esas líneas, el parche deja escrita en el repo una afirmación que su propio verificador ha refutado.
3. **Deja fuera de este commit** el parche del LOGO hasta corregir la nota del bit (14, no 12), rebajar la afirmación sobre SC7/8 y **rehacer `tb_logo` con R#8=0x28** (sprites encendidos, como los deja la BIOS) más el barrido completo de R#26 0..31: el arreglo pinta muy bien, pero está medido con el backend más desahogado que el caso que dice arreglar.
