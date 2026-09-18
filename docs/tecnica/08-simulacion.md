# 08. Simulación

Los bancos de pruebas que hay en `tools/`, qué cubre cada uno y cómo se corren. La regla general del proyecto: nada entra en una campaña de síntesis sin haber pasado por su banco, porque una campaña cuesta una hora y un banco cuesta un minuto.

## 1. Entorno

Todo se simula en **WSL, distribución Ubuntu-24.04**, que no es la distribución por defecto de la máquina. Ahí están Icarus Verilog, Verilator y GHDL. Desde Windows:

```bash
wsl.exe -d Ubuntu-24.04 bash -lc "cd /mnt/c/Users/alber/proyectosAI/msx/MSX_up_v3/tools/sd_tb && bash run.sh"
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

El resultado de cada prueba se imprime como OK o FALLO y el guion se para al primer fallo. La velocidad que da `tb_sddma` para CMD18, 638 KB/s, es la que luego marcó la placa: 640.

### La memoria: `tools/sdr16_tb/`

`memory_tb.v` valida el controlador de SDRAM de 16 bits con las pruebas T1 a T10 y W1 a W4: lecturas y escrituras de la CPU en todas las fases del divisor, los puertos secundarios de ondas y de VRAM, y el refresco. Cualquier cambio en `memory.v` se pasa por aquí; una variante que mejoraba la corrección pero bajaba a la mitad la lectura sostenida en turbo se rechazó gracias a esta suite.

### La megaram: `tools/megaram_tb/`

`tb_megaram.sv` recorre los mappers Konami, Konami-SCC, ASCII8, ASCII16, NEO-8 y NEO-16, los registros de 9 bits, la mitad alta por el puerto 46h y la SRAM por el 43h, y compara contra la versión anterior del módulo (`megaram_old.v`) para asegurar que nada que funcionaba deja de hacerlo.

### El SCC: `tools/scc_tb/`

Tres variantes: el banco del módulo Verilog, el mismo con habilitación a 27 MHz, y el del VHDL original con GHDL, que sirvió para comprobar que la reescritura en Verilog es bit-exacta antes de sustituirlo.

### El V9968: `tools/v9968_sim/`

La colección más grande, porque ahí se cazaron los errores de integración de julio y agosto de 2026:

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
| `gen_stim.py`, `gen_ssg_variants.py` | Generadores de estímulos |

`ru66_preload.svh` precarga la VRAM con la escena de la demo ru66 para los bancos que la necesitan.

### Audio: `tools/opl3_sim/` y `tools/opl4wave_sim/`

El OPL3 se simula con Verilator desde C++: `run_vgm.sh` reproduce un VGM contra el core y saca un WAV, y `tb_opl3_storm` bombardea el interfaz de host. `opl4wave_sim` guarda los volcados con que se depuró el motor PCM y su caché.

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

- El bus entero con el T80: las pruebas de integración se hacen en placa.
- El HDMI: el puente se validó en placa y con la plantilla de nand2mario.
- El USB: el host HID se validó con dispositivos reales.
- La DDR3 real: el modelo de la IP cubre el protocolo, no la calibración analógica, que fue la saga de julio de 2026.
