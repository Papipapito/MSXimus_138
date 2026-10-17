# t80mem: el dato de la CPU hacia la SDRAM

Banco del registro `cpu_dout_ram` de la v3.8.4 de la 138K (commit `e402652`): el dato que la CPU escribe en la SDRAM se registra a 54 MHz antes del cruce a 108 (`cpu1/DO → mem1/SdrDat`). Comprueba que el ciclo de más no cambia ninguna escritura y mide cuánto margen queda.

Piezas reales, sin tocar: el T80 del core (`fpga/G80A`, traducido a Verilog con la síntesis de GHDL), `memory_ctrl` (`fpga/src/memory.v`) y el modelo de la W9825G6KH de `tools/sdr16_tb`. Copiado de `fpga/top.v`, con los `define` de la build: la cadencia de 3,58 MHz y la del turbo de 5,37 (el máximo del core), `turbo_eff`, la FSM de esperas, el freno de M1, la petición de RAM registrada y `cpu_din` registrado. Del VDP, el DOTSTATE de `vdp_ssg`.

`prog.asm` hace todas las formas de escritura del Z80 (seguidas, a la misma dirección, inmediatos, índices, pila, `CALL`/`RST`, `LDIR`/`LDDR`, lectura-modificación-escritura, `RLD`/`RRD`, bits, el dato recién salido de la ALU) con un dato distinto en cada una: 2312 escrituras. Corre desde la SDRAM, como en placa. El banco comprueba que cada escritura se captura una vez en `SdrDat` con su dato y su dirección, que `DO` no se mueve con /WR bajo y que al final la SDRAM es igual que una memoria sombra. El margen es el tiempo mínimo entre el último cambio de `ram_din` y la captura.

`DLY` es el número de etapas de registro a 54 MHz entre `cpu_dout` y `ram_din`: 0 es antes del commit, 1 es el core, y más sirve para medir el margen.

## Uso

En el WSL (Ubuntu-24.04), con Icarus Verilog 12, python3 y GHDL 4.1 (`gen_t80.sh` dice dónde lo busca; `pasmo`, solo para `asm.sh`). Lo que se genera va a `$T80MEM_WORK` (por defecto `~/t80mem_work`), fuera del repositorio.

```
bash run.sh                       la matriz minima: DLY=1 a 3,58 y 5,37 MHz en dos fases (PASS)
                                  y el control negativo DLY=10 a 5,37 y DLY=13 a 3,58 (FAIL); unos 2 min
bash matrix.sh jobs2.txt 8        otra lista, 8 en paralelo
bash build.sh 1 && bash run1.sh 1 1 0 1 1 1 prueba
```

Cada línea de una lista: `DLY turbo ideal p27 vph rph etiqueta [plusargs]`. `turbo` 1 = 5,37 MHz; `ideal` 1 = la CPU lee de la sombra (la referencia); `p27` es la fase de `clk_27m` frente a `clk_54m`, `vph` el arranque del DOTSTATE y `rph` la suelta del reset. Las listas:

| Lista | Qué |
|---|---|
| `jobs_min.txt` | La de `run.sh` |
| `jobs1.txt` | DLY 0 y 1 a las dos velocidades, y la referencia `ideal` |
| `jobs2.txt` | DLY 0 y 1 con las fases de reloj cambiadas |
| `jobs3.txt` | El sondeo del margen: DLY 9 y 10 a 5,37, 12 y 13 a 3,58 |
| `jobs4.txt` | La retención: de la captura al siguiente cambio de `ram_din` |

## Resultados (17/10/2026)

| Caso | Resultado | Margen mínimo (ciclos de 54 MHz) |
|---|---|---|
| DLY=1 a 3,58 MHz, todas las fases | PASS, 2312/2312 | 11,5 |
| DLY=1 a 5,37 MHz | PASS, 2312/2312 | 9,5 o 8,5 según la fase |
| DLY=0, antes del commit | PASS | 12,5 a 3,58 y 9,5 a 5,37 |
| DLY=9 a 5,37 y DLY=12 a 3,58 | PASS | 0,5 |
| DLY=10 a 5,37 (fase b) y DLY=13 a 3,58 | FAIL: captura el dato de la escritura anterior | |

Con DLY=1 la retención mínima es de 29,5 ciclos a 5,37 MHz y 41,5 a 3,58.
