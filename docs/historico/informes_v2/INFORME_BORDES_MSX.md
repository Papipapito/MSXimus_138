# Bordes laterales del V9968 en el MSXimus — análisis, parche propuesto y evidencia

**Fecha:** 2026-07-28 · **Repos:** solo lectura; el parche NO está aplicado.
**Entregables en este directorio:** `bordes.patch` (verificado con `git apply --check`: aplica limpio),
`sim_antes_fullstack.txt`, `sim_despues_fullstack.txt`, `sim_linebuffer_dump.txt`,
bancos `tb_geom2.sv` / `tb_lbdump.sv` / `tb_geomfast2.sv` (derivados de los de la campaña _147).

---

## 1. Anatomía del problema (medida, no supuesta)

Sonda + volcado COMPLETO del line buffer del upscan (`tb_lbdump.sv`, pila completa
vdp.v + shim + backend, SCREEN1, línea activa 100):

```
ÁRBOL ACTUAL (c_left_pos=32, c_read_start=30):
   [   0..  29]   30 muestras  BORDE (backdrop azul)
   [  30.. 541]  512 muestras  CONTENIDO (256 px x 2)
   [ 542.. 619]   78 muestras  BORDE
   [ 620..1023]  404 muestras  SIN ESCRIBIR
```

Dos hechos clave:

1. **El borde del VDP existe y es real**: el V9968 pinta el color de backdrop en
   TODA la línea fuera del área activa (`vdp_timing_control_screen_mode.v:620-629`,
   `w_screen_in_active=0 → ff_pattern* <= w_backdrop_color`). No hay que "fabricar"
   borde: hay 30 muestras a la izquierda y 78 a la derecha ya escritas en el buffer.
2. **La ventana no tiene sitio**: el magnificador lee 512 muestras (ratio 2/3 →
   768 columnas nativas → 1280 px con el patrón 2,2,1) y el contenido de un modo de
   256 px son EXACTAMENTE 512 muestras. Con `c_read_start=30` se muestra solo
   contenido; el `16` histórico enseñaba 14 muestras de borde izquierdo a costa de
   comerse 7 px de contenido por la derecha. Es un juego de suma cero: **con la
   ventana actual, borde y contenido completo son incompatibles**.

Medida del estado actual en pantalla (pila completa, `sim_antes_fullstack.txt`):

| Modo (ANTES) | Borde izq | Borde der | Píxel MSX en pantalla |
|---|---|---|---|
| SCREEN1 | **0 px** (marcador pegado a col 0) | banda ~40 px | 5 px uniforme |
| SCREEN0 W40 (TEXT1) | ~37-39 px | ~41-43 px | 5 px uniforme |
| SCREEN0 W80 (TEXT2) | ~35-37 px | ~43-45 px | **3,2 alternado** |
| SCREEN5 | ~2-4 px | 0 px | 5 px uniforme |
| SCREEN7 | ~5-7 px | 0 px | **8,2 alternado** (patrón de test, ver §6) |

Los modos de TEXTO ya tenían borde (su contenido son 480 muestras, sobran 32) —
por eso el menú "se ve bien". Los modos de 256 px (SCREEN 1/2/4/5/8), que son los
de los juegos, **no tienen borde a la izquierda y muestran una banda asimétrica
a la derecha**: exactamente la foto de Albert.

---

## 2. Cuánta ventana hace falta

Referencia purista: **openMSX renderiza el frame como 320×240 puntos MSX:
32 puntos de borde por lado + 256 de contenido** (y 240 líneas verticales, que el
MSXimus ya muestra bien). Para replicarlo:

```
ventana = 2·(256 + 32 + 32) = 640 muestras      (hoy: 512)
```

¿Caben en el line buffer? Con `c_left_pos=32` NO (solo hay 30 muestras de borde
izquierdo escritas). Subiendo `c_left_pos` a 94 el buffer captura la línea entera:

```
PARCHEADO (c_left_pos=94, medido):
   [   0..  91]   92 muestras  BORDE      ← 64 necesarias, sobran 28
   [  92.. 603]  512 muestras  CONTENIDO
   [ 604.. 681]   78 muestras  BORDE      ← 64 necesarias, sobran 14
   [ 682..1023]  342 muestras  SIN ESCRIBIR
```

La ventana de lectura queda `[28, 667]` = 64 + 512 + 64. Margen para SET ADJUST
(±8 px = ±16 muestras): el borde queda entre 50 y 80 muestras por lado — nunca
negativo, nunca se recorta contenido, sin desbordar el buffer (684 < 1024).

---

## 3. Cómo re-escalar sin romper la nitidez — alternativas MEDIDAS

La lección _147 manda: cualquier ratio se evalúa en las 4 familias × las 2 fases
de `ce86`. Barrido con `tb_geomfast2.sv` (upscan+video_out reales, 6 variantes ×
2 fases, histograma de px de pantalla por píxel MSX):

**(a′) Mantener 768 columnas, ratio 5/6 (640 muestras en 768):** REFUTADA.
256 px → `{1:48 2:48 3:144 4:95}` — píxeles de 1 a 4 px mezclados en la MISMA
imagen. El 5/6 no conmuta con el 3/5 del escalador HDMI.

**(b) Ampliar a 960 columnas nativas (ratio 2/3, 640 muestras):** REFUTADA.
256 px quedan perfectos (`{4:239}`) pero TEXT2/SCREEN6/7 caen `{1:x 3:x}` con
**lotería de fase de ce86 otra vez** (960→1280 = ×4/3 no entero por columna).
Además el ring necesitaría 30 BSRAM (+6) y no hay margen en los 1280.

**(c) Modo 4:3:** ya no existe (retirado en _143 por decisión de Albert; el
escalador es full-screen único). Resucitarlo daría pillarbox, no borde.

**(d) ELEGIDA — ventana de 640 muestras, magnificador 1:1, escalador ×2:**

```
640 muestras --(1:1)--> 640 columnas nativas --(x2 EXACTO)--> 1280 px
```

Las dos etapas fraccionarias desaparecen. Cada muestra = 1 columna = 2 px de
pantalla, **independiente de todo alineamiento**: la fase de `ce86` deja de
poder romper nada (la lotería de _147 muere de raíz, `c_active_start=729` pasa a
ser cinturón y tirantes). Resultado por familia (mismo banco, ambas fases):

| Familia | ANTES (768, 2/3 + 3/5) | DESPUÉS (640, 1:1 + ×2) |
|---|---|---|
| 256 px (SCREEN1/2/4/5/8) | `{5:*}` uniforme | `{4:*}` uniforme |
| TEXT1 (W40) | `{5:*}` uniforme | `{4:*}` uniforme |
| TEXT2 (W80) | `{2:*,3:*}` alternado | `{2:*}` **uniforme** ← mejora |
| SCREEN6/7 (512 px) | `{2:*,3:*}` alternado (+lotería) | `{2:*}` **uniforme** ← mejora |

Ninguna familia empeora; dos mejoran. El precio se paga en otra moneda (§5).

---

## 4. EL PARCHE (3 ficheros — `bordes.patch`, aplica limpio con `git apply`)

### 4.1 `fpga/v9968/vdp_upscan.v` (línea 80)
```verilog
-	localparam			c_left_pos		= 11'd32;
+	localparam			c_left_pos		= 11'd94;
```
Desplaza la ventana de escritura del line buffer para capturar la línea entera
(borde incluido). Nota: igual que hoy, las direcciones [0..91] se escriben con
color de borde también vía el wrap benigno de `w_write_pos` (comprobado en el
volcado: TODA la ventana de lectura [28,667] contiene muestras escritas).

### 4.2 `fpga/v9968/vdp_video_out.v` (líneas 78, 146, 149, 158)
```verilog
-	parameter [9:0]	c_read_start = 10'd30,
+	parameter [9:0]	c_read_start = 10'd28,          // 92(contenido) - 64(borde)

-	localparam		active_area_end		= 12'd747 + 12'd1536;	//	fijo (2283)
+	localparam		c_h_active			= 12'd1280;             // 640 cols x 2 clk
+	localparam		active_area_end		= 12'd747 + c_h_active;	//	2027

-	localparam		h_en_end			= h_en_start + 12'd1536;
+	localparam		h_en_end			= h_en_start + c_h_active;	//	2028

-	localparam		c_numerator			= 512 / 4;              // 128 (ratio 2/3)
+	localparam		c_numerator			= 192;                  // == reg_denominator → 1:1
```
Con `c_numerator == reg_denominator` (192, vdp.v línea 557) el acumulador
Bresenham nunca retiene: `w_sub_numerator = 0` siempre, `w_hold = 0`,
`ff_coeff = 0` → el "bilineal" degenera en cablear tap1 (la síntesis lo poda).
`c_active_start=729` y `c_start_numerator=0` NO se tocan.

### 4.3 `fpga/video720/msx2hdmi_v9968.sv` (líneas 117, 242, 398, 471-472)
```verilog
-    localparam RING_W          = 768;
+    localparam RING_W          = 640;
-            rel800 <= rel[5:1] * 15'd768;
+            rel800 <= rel[5:1] * 15'd640;
-    wire [10:0] xinc     = 11'd768;
+    wire [10:0] xinc     = 11'd640;                      // 640→1280 = x2 exacto
-        yy720_r     <= yy[4:0]     * 15'd768;
-        yy720_inc_r <= yy_inc[4:0] * 15'd768;
+        yy720_r     <= yy[4:0]     * 15'd640;
+        yy720_inc_r <= yy_inc[4:0] * 15'd640;
```
La captura es auto-cronometrada (x_cnt arranca en el primer no-blank tras HS),
así que el estrechamiento de `display_en` se absorbe solo. `msx2hdmi.sv` (VDP
clásico V9958) queda INTACTO.

**Bonus de recursos:** el ring pasa de 32×768 a 32×640 entradas de 18 bits =
**−4 BSRAM** (24→20 del ring; total del chip 73/118 → 69/118).

---

## 5. Qué se ve en pantalla tras el parche (pila completa, ambas fases de ce86)

`sim_despues_fullstack.txt` — bordes medidos en la captura de salida:

| Modo | Borde izq | Borde der | Contenido | Píxel MSX |
|---|---|---|---|---|
| SCREEN1 | 124-126 px | 130-132 px | 1024 px | 4 px uniforme |
| SCREEN0 W40 | 156-158 px | 162-164 px | 960 px | 4 px uniforme |
| SCREEN0 W80 | 154-156 px | 164-166 px | 960 px | 2 px uniforme |
| SCREEN5 | 124-126 px | 130-132 px | 1024 px | 4 px uniforme |
| SCREEN7 | 122-124 px | 132-134 px | 1024 px | 2 px por muestra, uniforme |

En unidades MSX: **32 puntos de borde por lado** (±1 punto de asimetría por la
fase del pipeline — también existe hoy y es invisible). La geometría del frame
pasa a ser EXACTAMENTE la de openMSX (320 puntos = 32+256+32) a ×4 horizontal y
×3 vertical. Arriba y abajo no cambian (v_en 14..494 ya enseñaba las 240 líneas).

**El precio, con números (sé honesto con Albert):**

1. **El contenido pasa de ~1280 px de ancho a 1024** (píxel MSX de 5 px → 4 px,
   −20%): el borde ocupa ese 20%. Es la definición misma de "verse el borde
   alrededor" en un escalador full-screen; no hay forma de tener ambas cosas.
2. **Aspecto**: el píxel MSX queda 4:3 (4 ancho × 3 alto) en vez del 5:3 actual —
   MENOS estirado y más cerca del 1.25:1 de un CRT 4:3 real. La imagen completa
   (borde incluido) sigue llenando el 16:9, como en el MSXnano.
3. Quien prefiera "pantalla llena sin borde" pierde la opción. Si se quiere
   conmutable por menú habría que muxear `c_numerator`/ventana y dejar RING_W en
   768 (renunciando al ahorro de BSRAM); son ~6 muxes cuasi-estáticos — posible
   follow-up, NO incluido para no mezclar dos cambios.

---

## 6. Validación en banco — resumen de evidencia

* **`tb_geomfast2.sv`** (= tb_geomfast _147 + análisis parametrizado por ancho
  nativo): barrido `c_active_start ∈ {731,729,733} × numerador {0,64} × 2 fases
  × 4 familias`. DESPUÉS: todo `OK` con 729 y 731 en ambas fases (733/fase A
  sigue mala — no se usa). También compilado y re-corrido sobre el árbol con
  `bordes.patch` aplicado de verdad (git apply sobre copia): idéntico.
* **`tb_geom2.sv`** (= tb_textgeom _147 + SCREEN5/SCREEN7 + medición de bordes
  en px de pantalla): pila COMPLETA (vdp.v + shim + modelo SDRAM con latencia
  aleatoria). Tablas de §1 y §5. Los 5 modos × 2 fases, antes y después.
* **`tb_lbdump.sv`**: volcado run-length del line buffer (§1, §2) — demuestra
  que las muestras de borde existen y de qué color son.

**Caveat honesto (SCREEN7):** en la medida full-stack de SCREEN7 mi patrón de
test (relleno `0xF1` plano) produce en el line buffer blancos cada 4 muestras en
vez de cada 2 — un artefacto de interacción patrón/pipeline de medio píxel del
G6 que es IDÉNTICO antes y después (no lo introduce el parche), por lo que la
comparación sigue siendo válida; la evidencia limpia de SCREEN6/7 es el banco
sintético (MODE=3 de `tb_geomfast2`: `{2:495}` uniforme en ambas fases). Si se
quiere cerrar del todo, un A/B en placa con VDPTEST2 o una demo real de SCREEN7
es la prueba definitiva.

**Pendiente de HW (obligatorio antes de dar por bueno):** build completa +
foto de SCREEN1 (borde con `COLOR ,,4` azul para verlo sin ambigüedad), el menú
W80, y un juego de scroll (el smooth-scroll usa R#18/R#27 — SET ADJUST ya está
verificado en banco dentro de rango, pero la placa manda). Riesgo de timing
BAJO: mismos anchos de registro, multiplicadores por constante más pequeña, y
la poda del bilineal QUITA lógica del dominio crítico de 85.9 MHz.

---

## 7. Decisión recomendada

Aplicar `bordes.patch` (opción d): es la única de las cuatro que enseña los 32
puntos de borde por lado SIN recortar contenido, elimina de raíz la sensibilidad
a la fase de `ce86` y la alternancia 3,2 del menú W80 y de SCREEN6/7, ahorra 4
BSRAM, y deja la geometría clavada a la de openMSX. El coste real y único es el
−20% de ancho de contenido (píxel 5→4), que es consustancial a mostrar borde.
