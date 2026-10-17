# 07. Síntesis y campañas

Cómo se convierte el RTL en un `.fs` que se pueda entregar. En el 138K no falta sitio (el chip va al 57 % de sus celdas lógicas y el place and route de un dado tarda entre 15 y 27 minutos), pero el dominio de 86 MHz del V9968 sigue siendo una lotería por sí mismo y, hasta la v3.8.4, el dato de la CPU hacia la SDRAM también lo era, así que el procedimiento sigue siendo el del 60K: tirar varios dados y quedarse con el que pasa. Sale de `tools/lanzar_campana.ps1`, `tools/encadenar_campanas.ps1`, `tools/gate_check.ps1` y de lo aprendido en las campañas del porte (apartado 6).

## 1. Herramientas

| | |
|---|---|
| Gowin EDA | Edición **Standard con licencia**, versión **1.9.12.03**, en `C:\Gowin\Gowin_V1.9.12.03_x64`. La Education no soporta el 138K. La era v3 del core nació sin SSRAM (esa versión lo retiró de la GW5AT-60 a propósito por un problema del silicio) y el porte lo hereda: todo va en BSRAM y registros |
| `fpga/build.tcl` | El guion de síntesis: dispositivo `GW5AST-138B GW5AST-LV138PG484AC1/I0` (para un chip de versión C, los montados desde julio de 2025, `GW5AST-138C`; mira la serigrafía del SOM), lista de ficheros, interruptores `USE_V9968` y `USE_VRAM_DDR3`, y las opciones del place and route |
| `fpga/top.v` | Los `` `define `` de la cabecera eligen qué entra en el core; los tres `localparam` del mapa de flash (pack en `0x500000`, configuración en `0x580000`, YRW801 en `0x600000`) |
| `fpga/constraints/msx_console138k.cst/.sdc` | Pines (copia bola a bola del 60K, con `IO_TYPE=SSTL15/SSTL15D` en la DDR3, `LVCMOS33` en `s1/s2/fan_en_o` y sin las `INS_LOC` del DLL/PLL) y relojes. El `clk_86` del V9968 vive aparte, en `msx_v9968.sdc` |
| `fpga/pll138/` | Los PLL del 138: el GW5AST no tiene `PLLA`, son `PLL` + `PLL_INIT` en cascada (`pll_27` → `pll_main`, `pll_86`, `pll_ddr3` → `pll_74`) |
| `tools/lanzar_campana.ps1` | Lanza una campaña: una copia del árbol por dado, todas en paralelo. Su `-Root` apunta por defecto al repositorio del 138 |
| `tools/encadenar_campanas.ps1` | Tira campañas de cinco dados una tras otra hasta que un dado pasa el gate, con `place_option` 1 (el `build.tcl` del repositorio) o 2 (una copia con `place_option 2`); la `p138m` y la `v384138a` salieron así, con la 2. Su `-Root` apunta por defecto al repositorio del 60K: en el 138 hay que pasárselo |
| `tools/gate_check.ps1` | Decide si un bitstream se puede entregar |
| El MCP `gowin` | `gowin_timing`, `gowin_resources` y `gowin_compare` para leer los informes sin abrir la herramienta |

## 2. Las dos líneas de build

Un solo código fuente, dos configuraciones:

| Línea | Qué es | Ocupación | Rutado | Dados que entregan |
|---|---|---|---|---|
| **Completa** | Producción. Todo el audio dentro | Unos 57 % de CLS, 116 de 340 BSRAM | De 15 a 27 min por dado (7 en la v1; 21-27 en la v3.8.4) | En la v1 y la v2, uno de cada tres (el dominio de 86 MHz); desde la v3.7, 7 de 45 pasan el gate y se entregan 2 (el 86 y los cruces de la CPU); con el registro de la v3.8.4, 4 de 5 |
| **Ligera** (`-Slim`) | Desarrollo del V9968. Sin MoonSound, sin Y8950 ni ADPCM, sin OPLL | Sin medir en el 138 | Sin medir en el 138 | (pendiente de verificar) |

La ligera nació en el 60K, donde al 90 % de ocupación el rutado tardaba entre 13 y 23 veces más que al 66 % y cada intento de arreglo costaba hora y media. En el 138 la completa ruta en minutos, así que la ligera pierde su razón principal y queda como instrumento de diagnóstico: un fallo que reproduce en la ligera es de lógica; uno que solo aparece en la completa es de contención de memoria, porque el audio grande es un cliente más de la DDR3 y de la SDRAM.

Lo que la ligera **no** puede validar: cualquier defecto cuya magnitud dependa de la presión de memoria. Esos se revalidan en la completa antes de darlos por curados. El camino de memoria del V9968 no cambia entre las dos líneas.

## 3. Una campaña

```powershell
.\tools\lanzar_campana.ps1 -Campana p138k -Dados 4363,4373,4391,4397,4409
```

El lanzador copia el árbol `fpga/` una vez por dado al directorio temporal, `%LOCALAPPDATA%\Temp\claude\campanas\<nombre>\bx_c1`, `bx_c2`..., nunca dentro del repositorio, y en cada copia:

1. Activa los interruptores que el repositorio deja apagados: descomenta `ENABLE_V9968_VDP` y `ENABLE_VRAM_DDR3` en `top.v` y pone `USE_V9968 1` y `USE_VRAM_DDR3 1` en `build.tcl`. En la línea ligera además comenta los ocho `define` del audio grande, que van juntos porque dependen entre sí.
2. Comprueba que todo ha quedado como debe y aborta si no.
3. Escribe el **dado** en `PERIOD_MS` de `fpga/src/dbg_uart.v`. Los dados son números primos: perturban el placement sin cambiar la función, porque solo tocan el periodo de la telemetría del `dbg_uart` (con la opción `DIETA_V36H`, un latido mínimo). El dado tiene que seguir en el netlist: si se podara, todos los dados darían el mismo bitstream. Y tiene que entrar en una comparación `>=`, no `==`: con una igualdad contra constante la estructura del comparador es la misma para cualquier valor (solo cambia el contenido de las LUT) y el placer devuelve la misma colocación con dados distintos. Se descubrió en el 60K el 17 de septiembre, cuando tres campañas de la dieta dieron 0 de 15 y varios dados repetían exactamente el mismo número de redes sin rutar: dos síntesis con dados distintos diferían en 390 líneas de netlist con `==` y en 85.000 con `>=`.

**Menos lógica no es mejor rutado.** Es una lección del 60K, al 96-98 % de CLS: la *dieta* de la v3.6h quitó un 5 % de LUT (telemetría, tira WS2812, ventilador por temperatura, segundo PSG, un decodificador de teclado) y el placer 1 pasó de rutar 9 de 16 dados a 0 de 13; el mismo día, el netlist completo volvió a rutar 3 de 5. Allí lo que manda es la congestión local, no el área total, y quitar bloques periféricos cambia dónde cae lo denso. La dieta se quedó como opción apagada (`DIETA_V36H`) y el 138, al 57 %, no la necesita.
4. Lanza la síntesis y el place and route.

Varios dados porque la temporización es una lotería. En la v1 y la v2 el dominio de 86 MHz del V9968 (el shim de la VRAM) cerraba en uno de cada tres, más o menos: la p138g cerró 3 de 3, la p138h 2 de 3 y la p138i 1 de 3. Desde la v3.7 se sumó el cruce del dato de la CPU hacia la SDRAM y pasaron 7 de 45, hasta que la v3.8.4 lo registró (4 de 5). Las campañas fueron de tres o cinco dados hasta la pf138i y son de cinco desde la v38b138. El rutado en sí termina siempre y limpio; no es la lotería de nets sin conectar del 60K, es la de la temporización de ese dominio, y no dice nada del diseño.

Dos reglas de operación que no son negociables en el PC de desarrollo: las síntesis se lanzan en primer plano y se vigilan, nunca desde agentes en segundo plano, y no se corre nada pesado en paralelo con ellas.

## 4. El gate: qué se acepta

Cuando la campaña ha terminado del todo, no cuando aparece el `.fs`, porque Gowin escribe el bitstream antes que los informes:

```powershell
.\tools\gate_check.ps1 -Campana $env:LOCALAPPDATA\Temp\claude\campanas\p138k
```

Un dado pasa si cumple las dos:

- **Cero violaciones de setup.**
- Toda violación de **hold** está dentro de la IP DDR3 de Gowin, que no se puede tocar, o va a un pin de BSRAM con menos de 50 ps de holgura negativa.

Lo segundo tiene explicación medida en el 60K: allí el skew entre una columna de lógica y una fila de BSRAM es de 0,19 a 0,20 ns constante, y el tiempo de hold del pin de BSRAM es de 0,037 ns. Esa combinación produce holds de unas decenas de picosegundos que el router, que ya lleva la corrección de hold activada por defecto, no puede alargar más. Es el suelo del silicio; todos los bitstreams entregados del 60K lo llevan. El gate del 138 conserva el mismo criterio (el suelo del GW5AST no se ha medido aparte; pendiente de verificar con más campañas). Un hold entre dos biestables de lógica, o mayor de 50 ps, sí es un cambio de régimen y merece otro dado.

**El gate no mide margen.** Un dado que pasa puede tener el peor camino de setup a 0,01 ns. En el 60K la regla de entrega es mirar el informe de temporización y exigir que el peor setup quede por encima de 0,4 ns. En el 138 ese margen está metido en la restricción: desde la p138h el `clk_86` del V9968 está **sobre-restringido a 11,30 ns** en `msx_v9968.sdc` (el periodo real es 11,64 ns, 85,9 MHz), porque el rutador de Gowin cumple el periodo que se le pide y para. Así, un dado que pasa el gate contra 11,30 lleva ya unos 0,34 ns de margen real, y un "gate OK con 0,07 ns" contra 11,30 son unos 0,41 ns reales. Aun así se mira siempre el informe: los dados que pasan por los pelos se guardan como respaldo, no se entregan (v1: se entregó el 3389, con 0,07 ns contra 11,30, y quedó el 3373, con 0,014, de respaldo).

Un artefacto conocido, y que el 138 hereda: el informe dice que `clk_54m` no alcanza su frecuencia aunque no haya ninguna violación de setup (el 3389 lo lleva). Es una peculiaridad del análisis estático de Gowin con este árbol de relojes y se ignora.

## 5. Qué se aprendió del chip

Del 138, en sus propias campañas:

- **No hay `PLLA`.** El GW5AST tiene el primitivo `PLL` (mismos parámetros y divisores, sin mDRP) y dos límites que el PLLA del 60K no tenía: VCO de 650 a 1.300 MHz y PFD de 19 a 81,25 MHz. Desde el pad de 50 MHz no salen 108/54/27 ni 371,25 exactos, así que los relojes van en **cascada**: `pll_27` (50 / 2 × 27, VCO 675) da 27,000 MHz exactos; de ahí `pll_main` (× 40, VCO 1.080) saca 108, 54, 27, 135 y **36 MHz para el motor OPL4**, que ya no puede ser 37,5 (la cadencia de 44,1 kHz queda en 14112/15000); `pll_86` (VCO 945) da 85,9; `pll_ddr3` (VCO 891) da los 297 de la DDR3 y presta su `CLKOUT1` de 74,25 sin gatear a `pll_74` (× 10) para los 74,25 y 371,25 del HDMI. El `pll_stop` de la IP DDR3 va directo a `ENCLK2` del PLL, sin la danza mDRP del 60K. La p138a (sin PLLA), la p138d (VCO fuera de rango, gate OK pero no entregable) y la p138e (PFD) son el precio de aprenderlo.
- **El cst quiere `SSTL15` sin sufijo `_I`, `LVCMOS33` en el banco 5** (`s1/s2/fan_en_o`) **y ninguna `INS_LOC` de sitio del 60K.** Campañas p138b y p138c.
- **La salida del OPLL se registra en `clk_27m` antes del mezclador** (`jt2413_wav_r27`). El árbol de sumas del acumulador del OPLL en 54 MHz hacia `snd_mix` en 27 MHz pide unos 22 ns contra los 18,5 de la relación entre relojes; en el 60K cabía por poco y en la p138f los tres dados lo rechazaron a -4,3 ns. El registro añade 37 ns de retardo, inaudible.
- **Lo que manda es la temporización, no el área**: al 57 % de CLS, en la v1 y la v2 el peor camino de cada dado era siempre el shim de la VRAM del V9968, con márgenes de 0,013 a 0,07 ns contra el periodo restringido. De ahí la sobre-restricción a 11,30 ns.
- **El dato de la CPU hacia la SDRAM, registrado a 54 MHz** (v3.8.4, `cpu_dout_ram`). Desde la v3.7, muchos de los dados que cerraban el 86 caían por `cpu1/DO → mem1/SdrDat`, un cruce 54 → 108 de 9,26 ns que depende de dónde coloque el placer la CPU respecto a la SDRAM: los cinco de la `v38b138` y los peores de la `p138l` y la `p138m`. El registro cuesta un ciclo de 54 MHz que el ciclo de escritura del Z80 absorbe (banco `tools/t80mem`, [capítulo 08](08-simulacion.md)); con él, la `v384138a` pasó 4 de 5.

Del 60K, y que el porte hereda con el código:

- **El 98 % de CLS no es falta de área, es congestión.** Los nodos más cargados son IORQ_n y WR_n del Z80: cualquier decodificador combinacional que cuelgue de ellos aparece en el peor camino de la siguiente campaña. La respuesta sistemática es registrar las salidas de los módulos de E/S y convertir las órdenes en pulsos con el dato ya capturado. En el 138 no aprieta, pero el RTL ya viene registrado así.
- **Los muxes en cascada se aplanan.** Una cascada de diez ternarios que devuelven lo mismo en todas las ramas es un OR plano; el decodificador de slots se reescribió así.
- **Los cruces 54 → 108 MHz** entre el bus y el controlador de memoria son los que más margen pierden; el último fue el término de refresco `cpu_run`, registrado en la 3.6d, retirado en la 3.6e y cerrado del todo en la 3.7 (registro a 54 MHz más doble biestable a 108 MHz, commit 82b1b9c), que es lo que lleva la 3.7 del 138. La v3.8.4 del 138 hizo lo mismo con el dato de la CPU (arriba).
- **La BSRAM del 60K está al 100 %**; la DMA de la SD se diseñó con ese límite. En el 138 quedan 224 bloques libres, pero el RTL es común a las dos placas y no cuenta con ellos.
- **Un core aislado no predice la build.** Un módulo que cierra temporización solo puede no cerrar dentro del top; lo que vale es la campaña.

## 6. Las campañas del 138

| Campaña | Versión | Resultado |
|---|---|---|
| p138a | v1 (el porte de la V3.5d) | `ERROR RP0008`: no hay recurso PLLA |
| p138b, p138c | v1 | Correcciones del cst: `IO_TYPE`, `INS_LOC`, banco 5 a 3,3 V |
| p138d | v1 | Gate OK, pero con el VCO fuera de rango: no se entrega |
| p138e | v1 | `ERROR PA2078`: PFD fuera de rango |
| p138f | v1 | Cascada de PLL. Place and route limpio, cero avisos de PLL, los tres dados rechazados por el cruce OPLL → mezclador |
| p138g (3359/3361/3371) | v1 | Los tres pasan el gate; peor camino el shim de VRAM con 0,013-0,029 ns. Primera entrega, el 3361 (hoy en `files/20260907/superados/`) |
| p138h (3373/3389/3391) | **v1** | `clk_86` a 11,30 ns. 3389 gate OK con 0,07 ns (~0,41 reales), entregado en `files/20260907/`; 3373 respaldo (0,014); 3391 rechazado |
| p138i (3463/3467/3469) | **v2** = la v1 + Game Master 2 | 3469 gate OK con 0,006 ns (~0,35 reales), entregado en `files/20260909/`; 3463 y 3467 rechazados |
| p138j (4339/4349/4357) | **v3.7** = porte de la V3.7b del 60K por merge (DMA de la SD, mandos HID por USB-A, espera a la DDR3, generación C del V9968, mezclador por fuente, motor de reintentos de la DDR3) | 0 de 3: 4339 −1,12 y 4349 −0,76 en el 86 (contra 11,30); 4357 cerraba el 86 pero `cpu1/DO → mem1/SdrDat` a −4,5 ns |
| p138k (4363/4373/4391/4397/4409) | la misma v3.7 | **4391 GATE OK**, 0,034 ns contra 11,30 (~0,37 ns real), entregado en `files/20260918/`; 4373 −0,05 (`cpu1/IORQ`); 4363, 4397, 4409 rechazados. PnR 15-19 min por dado |
| pz138a (4457/4463/4481), pz138b (4483/4493/4507/4513/4517) | El porte de la Zynq (ASCII16-X, megaram de 8 MB, Plain 0000h), rama `port-zynq-2409`, que no se publicó | pz138a, 0 de 3: el 86 (−0,75 y −0,85) y `cpu1` → SDRAM (−1,61). pz138b, 3 de 5 con 0,009 a 0,020 ns: no se entregó, sin placa en la que probarlo |
| pz138r (4567/4583/4591), pz138r2 (4597/4603) | Lo mismo con el arreglo de las rayas de arranque del shim de la VRAM | 1 de 5: el 4597, con 0,000 ns, sin entregar; los otros cuatro, por `cpu1/u0/DO` → `mem1/SdrDat` y `u_sdio/info_idx` |
| pf138g (4933/4937/4943), pf138h (4987/4993/4999), pf138i (5119/5147/5153) | 3.7.4 y 3.7.5 (`cpu_din` por grupos, el mando sin la izquierda fantasma y, en la pf138i, las escrituras de configuración registradas), rama `port-fixes-2809` | 1 de 9: el 4987, con 0,044 ns, sin entregar; los demás, por el 86 y por `cpu1/u0/DO` → `mem1/SdrDat` |
| v38b138 (5261/5273/5279/5281/5297) | V3.8 sin el registro del dato de la CPU (OSD con color y puente de la flash; mapa de 16 MB) | 0 de 5: los cinco por `cpu1/u0/DO` → `mem1/SdrDat` (54 → 108); el 5261 solo por ese camino (−1,487 ns), los demás además por el V9968. La entrega del 1 de octubre (`files/20261001/`) lleva solo el firmware del BL616 |
| p138l (5303/5309/5323/5333/5347) | **v3.7-8mb** = la v3.7 con el mapa de flash dentro de los 8 MB | 0 de 5: 5333 casi (−0,056 en `cpu1/IORQ_n` a 54 MHz, medio ciclo, y −0,088 en el 86); 5303, 5309, 5323 y 5347 rechazados por `cpu1/DO`, `u_sdio/info_idx` y el 86 |
| p138m (5503/5507/5519/5521/5527), place_option 2 | la misma v3.7-8mb | **5519 GATE OK**, 0,006 ns contra 11,30 (~0,35 ns real, como el 3469 de la v2), entregado en `files/20261017/`; los otros cuatro, por `cpu1/DO` → `mem1/SdrDat` (54 → 108) y `cpu1/IORQ` |
| v384138a (5531/5557/5563/5569/5573), place_option 2 | **v3.8.4** = la V3.8.4 del 60K con el mapa de 8 MB y el dato de la CPU registrado a 54 MHz antes del cruce a 108 | **4 de 5 GATE OK**: 5569 con 0,143 ns contra 11,30 (~0,48 ns real), entregado en `files/20261017/`; respaldo 5531 (0,098); 5563 (0,029) y 5557 (0,018); 5573 rechazado por el 86 (−0,45). PnR de 21 a 27 min por dado |

Ninguno de estos bitstreams se ha validado en una placa 138K: la v1 y la v2 se entregaron sin probar; la v3.7 se grabó el 16 de octubre de 2026 en una y se quedó en negro por el mapa de flash de 16 MB (de ahí la v3.7-8mb); la v3.7-8mb y la v3.8.4 están sin probar.

## 7. Entregar

Cada entrega va a `files/<fecha>/`, fuera de git, y lleva:

- El `.fs` y su `_jtag.bin`, siempre en pareja, con el dado en el nombre (`msximus138_<versión>_dado<n>.fs`).
- Un `LEEME_138_<versión>.txt` con qué cambia, los resultados de la campaña dado a dado con el peor camino de cada uno, los hashes, la versión de chip con la que se compiló (B o C) y qué probar en placa. Como el pack de BIOS es el mismo fichero que en el 60K y solo cambia dónde se graba, el LEEME repite las direcciones del 138: bitstream en `0x000000` (5.096.124 bytes, unos 4,9 MB, en la v3.8.4, frente a los 2,47 MB del 60K), pack en `0x500000`, configuración en `0x580000`, YRW801 en `0x600000`.
- Si hay respaldo, el segundo dado con su nombre.

El `_jtag.bin` sale del `.fs` con el conversor del proyecto. Es el segmento del core de los `.UPD` ([capítulo 11](11-actualizacion.md)) y, en el 60K, lo que se flashea por el BL616; en la Console 138K el camino conocido es el Gowin Programmer en modo flash externa, con el `.fs` en `0x000000` (el firmware del BL616 de la v3.8.4 es el del panel F12, sin probar en placa). La release de GitHub lleva solo el `.fs`, y `mi_release/<versión>/` lo mismo que la release: el `.fs`, sin el `_jtag.bin`, que se queda en `files/<fecha>/`.

Una advertencia de placa, aprendida en el 60K y que en el 138 está pendiente de verificar: el USB del PC puede falsear las pruebas, porque alimenta el BL616 y altera el arranque (y, con él enchufado, el BL616 hace de puente JTAG y no hay panel F12). Las pruebas de placa se hacen con un alimentador de solo corriente.
