# Carcasa "mini MSX" para la Tang Console 60K + pantallita Waveshare — catálogo comentado

Investigación web (jul-2026). Objetivo: alojar la **Sipeed Tang Console 60K** (placa base "console" + SOM Mega 60K encima) y la **Waveshare ESP32-C6-LCD-1.3** (LCD 1.3" 240x240) como display frontal, conectada por cable plano de 4 hilos, dentro de una carcasa imprimible con estética de MSX clásico en miniatura.

---

## 1. Dimensiones confirmadas (el dato clave)

| Pieza | Dato | Fuente |
|---|---|---|
| Placa Tang Console (la "dock" donde pincha el SOM) | **65 × 56 mm** | [CNX Software](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/), [Hackster](https://www.hackster.io/news/sipeed-takes-on-the-mighty-mister-with-its-tang-console-fpga-development-board-112a417b3ec6) |
| Altura del conjunto placa+SOM | No publicada en texto; **sacarla del STEP oficial** (abajo) | — |
| Conectores a recortar | HDMI, 2× USB3-A, 2× USB-C, conector LCD 40P, altavoz, 2× PMOD, 2× 2x20P | Wiki Sipeed / CNX |
| Planos y 3D oficiales | Mechanical drawing: `dl.sipeed.com/shareURL/TANG/Console/04_Mechanical_drawing` · 3D: `.../05_3D_file` | [Wiki Sipeed](https://wiki.sipeed.com/hardware/en/tang/tang-console/mega-console.html) |
| Carcasa oficial del bundle | Acrílico estilo NES (no imprimible, referencia estética) | [Time Extension](https://www.timeextension.com/news/2025/01/usd69-fpga-tang-console-can-double-as-a-retro-gaming-handheld) |
| ESP32-C6-LCD-1.3: pantalla | 1.3" IPS 240×240, ST7789V2, SPI 4 hilos | [docs.waveshare.com](https://docs.waveshare.com/ESP32-C6-LCD-1.3) |
| ESP32-C6-LCD-1.3: conexión | Header GPIO **9 pines paso 2.54 mm** (encaja con tu plan de cable plano de 4 hilos) | docs.waveshare.com |
| ESP32-C6-LCD-1.3: PCB | Dims exactas solo en el plano-imagen "Product_Size" de la wiki (no legible por texto); área activa de un 1.3" cuadrado ≈ **23.4 × 23.4 mm** (geometría) | docs.waveshare.com |

**Conclusión de encaje**: la 60K es pequeña (65×56 mm). Cualquier mini-MSX a escala 1:2 (~25 cm de ancho, siendo un MSX real ~50 cm) la traga con holgura enorme; incluso a ~1:3 cabría. El problema nunca será el volumen, sino los **recortes de puertos** y el anclaje.

---

## 2. Catálogo

### A. Minis MSX imprimibles

| # | Modelo | Plataforma | Enlace | Licencia | Formato | Veredicto |
|---|---|---|---|---|---|---|
| 1 | **MSX Philips VG-8020 (escala 1:2)** — amandris | Thingiverse + Cults3D | [thing:3564052](https://www.thingiverse.com/thing:3564052) · [Cults3D (gratis)](https://cults3d.com/en/3d-model/gadget/amandris) | **CC-BY** (etiqueta "No AI") — remezclable con atribución | **14 STL** (base, teclado, teclas, tapa trasera, tapa cartucho, pies…) + decals al agua en PDF | **El mejor candidato directo**: pensado para meter una Raspberry Pi + electrónica (emulador MSX), interior hueco; pega: solo STL, los recortes de puertos van a golpe de editor de malla |
| 2 | **The MSX Mini Replica** (VG-8020 1:2, diseño de Gustavo Miguélez) | Blog propio | [themsxmini.blogspot.com](https://themsxmini.blogspot.com/) | Carcasa usada "bajo permiso escrito" — **ficheros NO publicados** | — | Solo referencia estética/prueba de concepto (RetroPie dentro, HDMI 720p); no descargable |
| 3 | Omega MSX Computer Case — charlesmouse | Thingiverse | [thing:5233265](https://www.thingiverse.com/thing:5233265) | ver página | STL | Tamaño completo (para el Omega MSX2+ real con teclado): NO es mini, no aplica |
| 4 | Spectravideo SVI-728 Retropie case | Thingiverse (vía Yeggi) | [yeggi "msx case"](https://www.yeggi.com/q/msx+case/) | ver página | STL | Carcasa estilo MSX1 para RPi pero a tamaño grande; estética SVI, no Philips/Panasonic |
| 5 | Miniaturas-llavero MSX (Hotbit HB-8000, Sony Hit-Bit…) | STLFinder/varios | [stlfinder "sony msx"](https://www.stlfinder.com/3dmodels/sony-msx/) | varias | STL | Sólidas, decorativas: no sirven como carcasa |
| 6 | Amstrad CPC464mini retro computer | MakerWorld | [modelo 821842](https://makerworld.com/en/models/821842-amstrad-cpc464mini-retro-computer) | ver página | 3MF/STL | No es MSX, pero es el patrón de calidad de "micro-ordenador retro en mini con hueco para SBC": útil como referencia técnica |
| 7 | Mini NES Raspberry Pi Case (NESPi) — daftmike | Thingiverse | [thing:1727668](https://www.thingiverse.com/thing:1727668) | ver página | STL | Vía alternativa "consola": casa con la estética NES de la carcasa oficial de Sipeed, pero deja de "parecer un MSX" |

### B. Específico Tang Console 60K

| # | Modelo | Plataforma | Enlace | Licencia | Formato | Veredicto |
|---|---|---|---|---|---|---|
| 8 | **Tang Retro Console PCB (STEP oficial de la placa)** — usuario 源源圆球 | MakerWorld | [modelo 1031373](https://makerworld.com/en/models/1031373-tang-retro-console-pcb) | descarga libre | **STEP** | **ORO**: el modelo 3D de la PCB subido expresamente para que la comunidad diseñe carcasas (Sipeed montó un concurso de carcasas regalando una consola al ganador — [RetroShell](https://shop.retroshell.com/2025/01/25/sipeed-introduces-tang-console-a-69-fpga-device-with-retro-gaming-capabilities/)); importas la placa en CAD y los cortes salen exactos |
| 9 | Planos + 3D oficiales Sipeed | dl.sipeed.com | [04_Mechanical_drawing](https://dl.sipeed.com/shareURL/TANG/Console/04_Mechanical_drawing) · [05_3D_file](https://dl.sipeed.com/shareURL/TANG/Console/05_3D_file) | libre | DWG/PDF + 3D | Fuente canónica de cotas; complementa al #8 |
| 10 | Console enclosure for Tang Nano **20K** — Silicon Dioxide Studios | Printables | [modelo 1446342](https://www.printables.com/model/1446342-console-enclosure-for-sipeed-tang-nano-20k-fpga) | gratis (ver página) | STL | Es para la TN20K, no para la 60K → **no vale aquí, pero es un bonus directo para tu MSXnano** |
| 11 | Case for Tang Nano 9K — Alexander K | Printables | [modelo 1047221](https://www.printables.com/model/1047221-case-for-sipeed-tang-nano-9k) | gratis | STL | No aplica (9K); solo inventario |

**No existe (a jul-2026) ninguna carcasa comunitaria imprimible publicada específica de la Tang Console 60K** en Printables/MakerWorld/Thingiverse — el hueco que dejó el concurso de Sipeed lo cubre el STEP del #8. TangCore (nand2mario) tampoco referencia carcasas en su repo.

### C. Montura para la Waveshare ESP32-C6-LCD-1.3

| # | Modelo | Plataforma | Enlace | Veredicto |
|---|---|---|---|---|
| 12 | (ninguno específico del 1.3") | — | búsquedas en [Yeggi](https://www.yeggi.com/q/esp32+c6/), MakerWorld, Printables | **No hay case/bezel publicado para el 1.3"** (placa nueva); todo lo que aparece es del hermano **1.47"** |
| 13 | Cases del ESP32-C6-LCD-**1.47** (referencia) | MakerWorld / Cults3D / Thingiverse | [1839340](https://makerworld.com/en/models/1839340-waveshare-esp32-c6-touch-lcd-1-47-case) · [1301018](https://makerworld.com/en/models/1301018-esp32-lcd-1-47-case) · [458740](https://makerworld.com/en/models/458740-waveshare-esp32-c6-case) · [Cults3D edge](https://cults3d.com/en/3d-model/gadget/enclosure-edge-for-waveshare-esp32-c6-1-47-rectangle-lcd-sdlw01-28563) · [thing:7065147](https://www.thingiverse.com/thing:7065147) | PCB distinta: no compatibles directamente; sirven para copiar el truco de clip/bisel. Un bezel propio es trivial: ventana de ~23.5 mm + bolsillo para la placa, cotas del plano "Product_Size" de la wiki |

---

## 3. TOP 3 razonado

1. **Diseño propio: contorno VG-8020 escalado + STEP oficial de la PCB (#8/#9)**. Tienes el contorno del VG-8020 ya trabajado en KiCad→STEP/DXF (proyecto msxnano-board8020): escalarlo a ~1:2–1:2.5 alrededor de los 65×56 mm e importar el STEP de la placa da recortes de puertos exactos a la primera. Único camino con encaje garantizado y estética 100% Philips.
2. **Adaptar el VG-8020 1:2 de amandris (#1)**. La estética ya está resuelta y probada (es la base visual del "MSX Mini"), licencia CC-BY remezclable, interior pensado para SBC. Coste: solo STL (retocar recortes en malla o remodelar la tapa trasera), y la pantalla frontal habría que integrarla en la zona del slot de cartucho.
3. **Vía "consola mini" (#7/#10 como patrones)**. Rápida y funcional, casa con la carcasa NES oficial de Sipeed, pero pierde el "parece un MSX" que pide Albert; dejarla como plan C.

## 4. La vía de diseño propio, en 3 líneas

Mejor **escalar tu contorno VG-8020** que adaptar un STL ajeno: tu activo ya está en STEP/DXF paramétrico (oro para CAD), mientras que lo publicado es malla. La 60K es tan pequeña que el escalado no tiene restricción de volumen, solo de posición de puertos, y eso se resuelve importando el STEP oficial de la PCB (#8). De amandris conviene "robar" (con atribución CC-BY) lo caro de modelar: teclado, teclas, proporciones y sus decals al agua.

## 5. Recomendación final

**Híbrido**: carcasa propia con tu contorno VG-8020 escalado (~25 cm de ancho a 1:2, o más compacta a 1:2.5) alrededor del STEP de la Tang Console (MakerWorld 1031373 + planos dl.sipeed.com), tomando de amandris (CC-BY) teclado/teclas/decals para el acabado. La **ESP32-C6-LCD-1.3 como display frontal** en la posición del slot de cartucho o del logo, con bezel propio (ventana ~23.5 mm; no existe montura publicada, y las del 1.47" no encajan) y su header de 9 pines a 2.54 mm alimentando el cable plano de 4 hilos hacia el dock. Verificar la altura apilada placa+SOM en el STEP antes de fijar la altura de la carcasa — es el único dato que no está publicado en texto.

---

### Fuentes principales
- Sipeed Tang Console: [CNX Software](https://www.cnx-software.com/2025/05/27/sipeed-tang-console-a-gowin-gw5ast-gw5at-board-with-60k-or-138k-lut-for-fpga-development-and-retro-gaming/) · [Hackster](https://www.hackster.io/news/sipeed-takes-on-the-mighty-mister-with-its-tang-console-fpga-development-board-112a417b3ec6) · [Wiki Sipeed](https://wiki.sipeed.com/hardware/en/tang/tang-console/mega-console.html) · [Time Extension](https://www.timeextension.com/news/2025/01/usd69-fpga-tang-console-can-double-as-a-retro-gaming-handheld) · [RetroShell (concurso carcasas)](https://shop.retroshell.com/2025/01/25/sipeed-introduces-tang-console-a-69-fpga-device-with-retro-gaming-capabilities/)
- STEP de la PCB: [MakerWorld 1031373](https://makerworld.com/en/models/1031373-tang-retro-console-pcb)
- Mini MSX: [Thingiverse thing:3564052](https://www.thingiverse.com/thing:3564052) · [Cults3D amandris](https://cults3d.com/en/3d-model/gadget/amandris) · [The MSX Mini Replica](https://themsxmini.blogspot.com/) · [MSX Resource Center (hilo VG-8020)](https://www.msx.org/forum/msx-talk/hardware/3d-printed-philips-vg-8020)
- Pantalla: [docs.waveshare.com/ESP32-C6-LCD-1.3](https://docs.waveshare.com/ESP32-C6-LCD-1.3) (esquema PDF: files.waveshare.com/wiki/ESP32-C6-LCD-1.3/ESP32C6-1.3.pdf)
- TangCore sin carcasas: [github.com/nand2mario/tangcore](https://github.com/nand2mario/tangcore)
