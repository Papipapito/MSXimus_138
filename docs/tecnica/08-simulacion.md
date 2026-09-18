# 08. Simulación

Los bancos de pruebas que hay en `tools/`, qué cubre cada uno y cómo se corren. Son los mismos bancos que en el MSXimus 60K, porque el RTL que prueban es el mismo; la única pieza que cambia en el porte es el stub del PLL de la DDR3 (más abajo). La regla general del proyecto: nada entra en una campaña de síntesis sin haber pasado por su banco, porque una campaña cuesta decenas de minutos y un banco cuesta un minuto. En el 138, además, la simulación es de momento la única verificación que hay: ningún bitstream del porte se ha probado todavía en una placa 138K.

## 1. Entorno

Todo se simula en **WSL, distribución Ubuntu-24.04**, que no es la distribución por defecto de la máquina. Ahí están Icarus Verilog, Verilator y GHDL. Desde Windows:

```bash
wsl.exe -d Ubuntu-24.04 bash -lc "cd /mnt/c/Users/alber/proyectosAI/msx/MSXimus_138/tools/sd_tb && bash run.sh"
```

Dos trampas al invocar desde el terminal de Windows: las variables de shell llegan vacías si se meten en la línea, y una ruta `/mnt/c/...` suelta se reescribe a `C:/Program Files/Git/mnt/c/...`. La forma segura es meter el guion en un fichero y llamar a ese fichero.

Los bancos se lanzan en primer plano y se espera a que el proceso termine. Un vigía que dispare al ver aparecer un fichero de salida lee volcados a medio escribir; ha pasado.

## 2. Los bancos, por subsistema

### La SD y la DMA: `tools/sd_tb/`

`run.sh` corre la suite entera, en Icarus, contra un modelo de tarjeta SD que responde a las órdenes reales con CRC:

| Banco | Qué cubre |
|---|---|
| `tb_sd` ×3 | El lector a 6,75 MHz con el tiempo de salida de la tarjeta de norma (14 ns), a 6,75 MHz con una tarjeta lenta y pista larga (60 ns), y a 2,25 MHz como referencia. Inicialización, lectura, escritura y multibloque |
| `tb_sdio` | Los puertos 47h-4Fh |
| `tb_mstimer` | El cronómetro de milisegundos y su foto atómica |
| `tb_glue` | El pegamento entre el bus del Z80, los puertos y la ventana de memoria |
| `tb_gm2` | El Game Master 2 en el slot 1: sus registros de banco y la SRAM |
| `tb_sddma` | La DMA entera con una réplica del controlador de memoria: registro de destino, CMD17, CMD18 de cuatro bloques con medida de velocidad, espera con el bus ocupado, orden normal tras una DMA, guarda del refresco, modo lógico cruzando de página y contadores de mapper contra una cuenta por software |

El resultado de cada prueba se imprime como OK o FALLO y el guion se para al primer fallo. La velocidad que da `tb_sddma` para CMD18, 638 KB/s, es la que luego marcó la placa del 60K: 640. En el 138 la cifra de placa está pendiente de medir.

### La memoria: `tools/sdr16_tb/`

`memory_tb.v` valida el controlador de SDRAM de 16 bits con las pruebas T1 a T10 y W1 a W4: lecturas y escrituras de la CPU en todas las fases del divisor, los puertos secundarios de ondas y de VRAM, y el refresco. Cualquier cambio en `memory.v` se pasa por aquí; una variante que mejoraba la corrección pero bajaba a la mitad la lectura sostenida en turbo se rechazó gracias a esta suite.

### La megaram: `tools/megaram_tb/`

`tb_megaram.sv` recorre los mappers Konami, Konami-SCC, ASCII8, ASCII16, NEO-8 y NEO-16, los registros de 9 bits, la mitad alta por el puerto 46h y la SRAM por el 43h, y compara contra la versión anterior del módulo (`megaram_old.v`) para asegurar que nada que funcionaba deja de hacerlo.

### El SCC: `tools/scc_tb/`

Tres variantes: el banco del módulo Verilog, el mismo con habilitación a 27 MHz, y el del VHDL original con GHDL, que sirvió para comprobar que la reescritura en Verilog es bit-exacta antes de sustituirlo.

### El V9968: `tools/v9968_sim/`

La colección más grande, porque ahí se cazaron, en el 60K, los errores de integración de julio y agosto de 2026:

| Guion | Qué hace |
|---|---|
| `elab_check.sh` | Elaboración con Verilator del core y sus piezas |
| `run_678_shim.sh`, `run_678_full.sh` | Los modos SCREEN 6, 7 y 8 con el shim solo y con el core entero, con volcados de VRAM que `png_from_dump.py` convierte en imagen y `diff_png.py` compara píxel a píxel con la referencia |
| `reg_sp.sh`, `reg_integra.sh` | Regresión de sprites y de integración |
| `check_all.sh` | Todo lo anterior seguido |
| `tb_skip1` | El salto de dirección de VRAM del router de respuestas: 14 fallos por mil se reprodujeron y quedaron en cero |
| `tb_sprite3`, `tb_textgeom` | Sprites del modo 3 con la escena de la demo ru66, y la geometría del texto de 80 columnas. El segundo es obligatorio tras cualquier cambio en el shim: una vez se flasheó sin él y el texto se rompió sin que ningún banco de sprites lo viera |
| `alias_idx.py` | Búsqueda exhaustiva de la función de índice de la caché del shim que evita que la tabla de sprites y una línea de patrones se desalojen mutuamente |
| `ddr3_ip_model.sv` | Un modelo de la IP DDR3 de Gowin para simular el backend sin la IP real |
| `tb_ddr3_backend.sv`, `run_ddr3_backend.sh` | El camino bk/bk2 → bridges → backend DDR3 → modelo de la IP (T1 a T9: lecturas sueltas y combinadas, escrituras con máscara, ráfagas, coherencia de caché, martilleo y el watchdog) y, desde la 3.7b, el motor de reintentos escalonado: el modelo falla las 18 primeras calibraciones y el banco exige que la 19.ª calibre con exactamente dos resets del PLL. Es el único banco que cambia en el porte, ver abajo |
| `gen_stim.py`, `gen_ssg_variants.py` | Generadores de estímulos |

`ru66_preload.svh` precarga la VRAM con la escena de la demo ru66 para los bancos que la necesitan.

#### El stub del PLL del 138 en el banco del backend

El backend real (`fpga/src/v9968_ddr3_backend.v`) instancia el envoltorio del PLL de la DDR3, y en el 138 ese envoltorio no es el del 60K: el GW5AST no tiene PLLA, así que `fpga/pll138/pll_ddr3.v` es un PLL + PLL_INIT con puerto `init_clk` (los 50 MHz del pad), habilitaciones `enclk0`/`enclk2` (el `pll_stop` de la IP va directo a `enclk2`, sin la danza mDRP del 60K) y una salida `clkout1` de 74,25 MHz que en el 60K no existía. Como el modelo de la IP autogenera su propio reloj, el banco no necesita el PLL de verdad: al final de `tb_ddr3_backend.sv` hay un stub de `pll_ddr3` con exactamente esa interfaz (`lock` a 1, salidas de reloj a 0) que sustituye al del 60K (`mdclk`/`mdopc`/`mdrdo`). El stub de `pll_mDRP_intf` sigue definido en el fichero pero ya no lo instancia nadie. `run_ddr3_backend.sh` apunta al repo del 138 y el resultado esperado es `*** DDR3 BACKEND: TODO OK ***` con `pll_resets=2`.

Lo que el banco no cubre es lo que de verdad cambia en silicio: si con `pll_stop → ENCLK2` la IP calibra en el GW5AST igual que calibraba con el mDRP en el 60K está pendiente de verificar en placa.

### Audio: `tools/opl3_sim/` y `tools/opl4wave_sim/`

El OPL3 se simula con Verilator desde C++: `run_vgm.sh` reproduce un VGM contra el core y saca un WAV, y `tb_opl3_storm` bombardea el interfaz de host. `opl4wave_sim` guarda los volcados con que se depuró el motor PCM y su caché. Ninguno de los dos modela el reloj del motor OPL4, que en el 138 es de 36 MHz en vez de 37,5 (capítulo 01): el cambio de velocidad está pendiente de escuchar en placa.

### Pequeños: `mouse_sim`, `fan_sim`, `turbo_cadence_equiv`, `dbg_uart_tb`

El ratón MSX por el puerto de joystick, el control del ventilador, la equivalencia de la cadencia del turbo con y sin el freno de M1, y la UART de depuración.

## 3. Programas de prueba para el MSX

Tres ROMs pequeñas escritas con MSXgl, con su `build.sh`:

| ROM | Prueba |
|---|---|
| `msxtest` | Batería general de audio y periféricos, con una voz ADPCM inyectada |
| `opl4test` | El MoonSound: FM y ondas |
| `scctest2` | Los dos SCC |

Se cargan desde el menú como cualquier ROM. Complementan el menú de pruebas de la tecla T, que vive en la BIOS.

## 4. Cómo verificar contra openMSX

Para todo lo que es MSX estándar, openMSX es la referencia: los tests de V9958 de HRA! se corren en él y se comparan cuadro a cuadro con el MSXimus. Para el V9968 solo existe el fork de buppu3, en generación A (capítulo 05). El MCP de openMSX de este entorno admite una sola instancia: cerrar la anterior antes de abrir otra.

## 5. Qué no tiene banco

- El bus entero con el T80: las pruebas de integración se hacen en placa, y en el 138 están por hacer.
- El HDMI: el puente se validó en placa en el 60K y con la plantilla de nand2mario; en el 138 cuelga del `clkout1` del PLL de la DDR3 y de `pll_74`, pendiente de placa.
- El USB: el host HID se validó con dispositivos reales en el 60K.
- La DDR3 real: el modelo de la IP cubre el protocolo, no la calibración analógica, que fue la saga de julio de 2026 en el 60K. En el 138 la calibración con el PLL + PLL_INIT en cascada es lo primero que hay que mirar cuando haya placa.
