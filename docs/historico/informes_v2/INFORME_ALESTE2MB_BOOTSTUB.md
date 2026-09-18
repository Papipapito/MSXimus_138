# Aleste 2 (ROM v8 Ricbit, 2 MB) no arranca en el MSXimus — diagnóstico

**Fecha:** 27/07/2026 · **Build analizada:** v2.0.1 (_158) · **Método:** traza en openMSX (FS-A1WSX + ROM en slot 1) contrastada contra el RTL del MSXimus.

---

## 1. Veredicto en una línea

**No es la megaram, no es el ancho de banco, no es el tamaño de 2 MB y no es un warm-reset del core.**

La causa raíz es el **`boot_stub` del menú**: deja la **página 2 (0x8000–0xBFFF) mapeada a la megaram** al llamar al INIT del cartucho, mientras que la BIOS real (verificado en openMSX, y quien hace la conmutación es la **ROM de BIOS auténtica**, no el emulador) entra al INIT con **página 2 = RAM**.

Aleste 2 es una conversión de disco: al pulsar ESPACIO usa **0x8000–0xBFFF como buffer de 16 KB** para cargar su cargador real desde el "disco" virtual, luego lo copia a 0x4000 y salta ahí. **Nunca reprograma la página 2** — asume la RAM que la BIOS le dejó. En el MSXimus ese buffer cae sobre la megaram (protegida contra escritura), la escritura se traga, y el `LDIR` copia a 0x4000 basura de ROM que el Z80 ejecuta.

Componente a tocar: **`MSXnano/fpga/src/msxnano_menu/src/menu_main.asm`** (`boot_stub`, líneas 2032–2047). **Es un cambio de ensamblador: NO hace falta resintetizar la FPGA**, solo reconstruir el menú y reflashear el pack (`fm_logo_menu.bin` @ 0x6C000).

---

## 2. Qué hace el juego exactamente (traza openMSX)

### 2.1 Fase de bienvenida (INIT del cartucho, `0x4010`)

```
4010  ld hl,#648D / ld de,#EC60 / ld bc,#00F2 / ldir   ; BDOS falso -> RAM pag.3 (0xEC60)
401B  ld hl,#657F / ld de,#F100 / ld bc,#0053 / ldir   ; rutinas de banco -> RAM (0xF100)
4026  call #F129                                       ; SONDEO DE MAPPER (ver 2.2)
4029  call #006F                                       ; INITXT
402C..404D  imprime los textos ("Konami8 mapper" / "Ascii16 mapper" / "PUSH SPACE")
404D  call #40BE                                       ; espera GTTRIG (ESPACIO)
4050  call #409A                                       ; RSLREG->EXPTBL/SLTTBL: guarda su
                                                        ; propio slot en (0xED4E)
4053  ld a,7 / call #0141                              ; SNSMAT fila 7 (tecla SELECT)
406A  ld de,#C000 / ld bc,#0100 / ldir                 ; stub de 256 B -> RAM 0xC000
4072  ld a,#C3 / ld (#F37D),a / ld hl,#EC60 / ld (#F37E),hl  ; hook "BDOS" -> 0xEC60
408D  di / jp #C01F
```

### 2.2 Sondeo dual de mapper (`0x65A8`, copiado a `0xF129`)

```
65A8  ld a,#01 / ld (#6000),a     ; escribe 1 en 0x6000
65AD  ld a,(#4000) / cp #41       ; ¿sigue leyendo 'A' (cabecera AB)?
65B2  jr z,#65B9                  ;  sí -> Konami-SCC  (ED51 = 0)
65B4  ld a,#01 / ld (#ED51),a     ;  no -> ASCII16     (ED51 = 1)
65B9  xor a / ld (#6000),a
```

Rutina de conmutación de banco (`0x65BE`, copiada a **`0xF13F`**), `A` = **bloque de 16 KB**:

```
65BE  ld hl,#ED51 / bit 0,(hl) / jr nz,#65CE
65C5  add a,a      / ld (#5000),a      ; Konami-SCC: banco 8K = 2N -> 0x4000-0x5FFF
65C9  inc a        / ld (#7000),a      ;             banco 8K = 2N+1 -> 0x6000-0x7FFF
65CE  ld (#6000),a                     ; ASCII16:    bloque 16K = N -> 0x4000-0x7FFF
```

**Nuestro hardware supera este sondeo en los DOS modos forzados** (comprobado contra el RTL):
en modo SCC la escritura a 0x6000 no decodifica nada → 0x4000 sigue devolviendo `'A'` → detecta Konami;
en ASCII16 pone reg0=2/reg1=3 → 0x4000 devuelve `0xEB` (≠ `'A'`) → detecta ASCII16.
Por eso Albert ve el texto correcto ("Konami8 mapper" / "Ascii16 mapper") en cada caso.

### 2.3 Lector de sectores (`0x64A5` → `0xEC78`) — el "disco" está en la ROM

```
64A5  di
64B7  ld a,(#ED4E) / ld hl,#4000 / call #0024   ; ENASLT pag.1 -> slot del cartucho
64C0  xor a / call #F13F                        ; bloque 16K 0 (tabla de sectores)
64C4  ld hl,(#ED4C) / add hl,hl / ld de,#42CD / add hl,de
64CC  ld e,(hl)/inc hl/ld d,(hl)/ex de,hl       ; entry = tabla[sector]  (16 bit)
64D0  add hl,hl / ld d,l / ld e,#00 / add hl,hl / add hl,hl
64D6  ld a,d / and #3F / add a,#40 / ld d,a     ; DE = 0x4000 + (entry&0x1F)*512
64DC  ld a,h / inc a / call #F13F               ; bloque16K = (entry>>5) + 1
64E1  ld hl,(#ED49) / ex de,hl / ld bc,#0200 / ldir   ; copia 1 sector (512 B)
6502  jr nz,#64C0                               ; siguiente sector
6504  ld a,(#D003) / cp #FF / jr z / ... call #0024    ; restaura pag.1 al slot de RAM
```

Análisis estático de la tabla (offset ROM `0x02CD`, 3 discos de 1440 sectores):

| dato | valor |
|---|---|
| bloques de 16 KB usados | **1 … 75** (75 distintos) |
| bloques ≥ 64 (2.º MB) | 64, 65, 66, 67, 68, 69, 70, 71, 72, 73, 74, 75 |
| byte más alto leído | ~ROM `0x12F000` (≈ 1,21 MB de los 2 MB) |

### 2.4 **El momento crítico: lo que ocurre al pulsar ESPACIO**

`jp #C01F` → prepara el BDOS falso (SETDMA 0xD030, etc.) → carga 2 sectores en 0xC100 →
`jp #C106`, que es **el cargador real, extraído del disco virtual**:

```
C110  di
C111  ld hl,#C9C9 / ld (#FD9A),hl / ...      ; mata los hooks de interrupción
C12A  ld hl,#0080          ; sector 128
C12D  ld de,#8000          ; <<<<<< DESTINO = 0x8000  (PÁGINA 2)
C130  ld b,#20             ; 32 sectores = 16 KB
C133  call #D033           ; lee 16 KB SOBRE 0x8000-0xBFFF
C136  jr c,#C133
C138  ld hl,#8000 / ld de,#4000 / ld bc,#4000 / ldir   ; <<<<<< copia 16 KB 0x8000 -> 0x4000
C143  xor a / call #D030
C147  call #C1C2 / call #C179   (#C179: in a,(#A8) ... manipula slots)
C176  di / jp #4000        ; <<<<<< EJECUTA lo que acaba de copiar
```

**Aquí está todo.** El juego usa 0x8000–0xBFFF como buffer de staging y **no ejecuta ningún
ENASLT sobre la página 2** en todo el camino. Confía en la RAM que le dejó la BIOS.

---

## 3. La divergencia, medida

### 3.1 openMSX (= BIOS real) en el instante `PC = 0x4010` (primera instrucción del INIT)

```
isBreaked = 1 ; PC = 0x4010 ; disasm 4010 = "ld hl,#648D"  (código del cartucho)

0000: slot 0.0   BIOS
4000: slot 1     CARTUCHO
8000: slot 3.0   RAM        <<<<<<<<<<<<<<
C000: slot 3.0   RAM
```

Y después de ESPACIO, en la ejecución buena: `0000/4000/8000/C000 = slot 3.0` — **las 4 páginas en RAM**, SCREEN 5 con la intro dibujándose.

### 3.2 MSXimus — `boot_stub` (`menu_main.asm:2032`)

```asm
boot_stub:
    ld   sp, #F380
    ld   a, #02          ; página 1 (0x4000) -> slot 2
    ld   hl, #4000
    call ENASLT
    ld   a, #02          ; página 2 (0x8000) -> slot 2   <<<<<< AQUÍ ESTÁ EL BUG
    ld   hl, #8000
    call ENASLT
    xor  a  / ld (#5000),a      ; bancos canónicos 0,1,2,3 (aún en modo SCC)
    ld a,1  / ld (#7000),a
    ld a,2  / ld (#9000),a
    ld a,3  / ld (#B000),a
    ld a,#D4 / out (#40),a / ld a,(MAP_SWIO) / out (#41),a   ; mapper real vía SWIO
    ...
    ld hl,(#4002) / push bc / ei / jp (hl)      ; CALL INIT
```

Con `MEG_SLOT equ #02` y `ocm_update` forzando `config1_ff[7:6] <= 2'b10`, el slot 2 **es** la megaram.
Resultado: el INIT arranca con **página 1 Y página 2 = megaram**, y así se queda.

### 3.3 Estado de la megaram durante el juego (`launch_rom`, `menu_main.asm:1941`)

```asm
ld a,#80 / ld (#7FFE),a     ; megaram_mode_a = 0x80
```

⇒ `megaram_mode_a[4] = 0`, `megaram_mode_b[4] = 0`, `sram_cfg (#43) = 0` (Aleste2 no tiene tag SRAM).

En `megaram.v`, `megaram_sel_memory` con esos valores:

```verilog
( bus_rd_n == 0 ) ? 1 :                                  // lecturas: SÍ
( bus_wr_n == 0 && sram_wr_ok == 1 ) ? 1 :               // sram_mode = 0 -> NO
( bus_wr_n == 0 && ... && megaram_mode_a[4] == 1 ) ...   // = 0 -> NO
( bus_wr_n == 0 && ... && megaram_mode_b[4] == 1 ) ...   // = 0 -> NO
                                                    0;   // => TODA escritura descartada
```

**Las 16 KB que el juego escribe en 0x8000–0xBFFF se pierden en el vacío.**

### 3.4 Reproducción del fallo dentro de openMSX (contraprueba)

Rompí en `PC = 0x4010`, inyecté en 0xE000 `3E D4 / D3 A8 / C3 10 40` (`ld a,#D4 ; out (#A8),a ; jp #4010`)
— es decir, puse **página 2 = cartucho** justo antes del INIT, exactamente como el MSXimus — y continué.

* Pantalla de bienvenida: **idéntica y correcta**.
* Al pulsar ESPACIO:

```
0000: slot 0.0    4000: slot 3.0(RAM)    8000: slot 1 (CARTUCHO)    C000: slot 3.0
PC = 0x4727   SP = 0xE5E0      (4 s después)  PC = 0x4418   SP = 0xD134
```

El juego salta a 0x4000 y ejecuta basura; **SP se desploma** (E5E0 → D134): tormenta de `RST 38h`/`CALL`
sin retorno. **Fallo reproducido en el emulador con el único cambio de la página 2.** Con la página 2
en RAM, la misma ROM, el mismo build y el mismo savestate avanzan perfectamente.

---

## 4. Por qué DOS síntomas distintos

Lo que el `LDIR 0x8000→0x4000` copia (y por tanto lo que el Z80 ejecuta) depende del modo:

### ASCII16 forzado → **REINICIO**

* En ASCII16 nuestro decodificador de escritura solo mira `bus_addr[15:12] == 0110/0111` (0x6000/0x7000).
  Las escrituras del juego a 0x8000–0xBFFF **no** tocan ningún registro.
* `megaram_reg2/reg3` conservan el 2 y el 3 que dejó el `boot_stub` ⇒ 0x8000–0xBFFF muestra de forma
  estable los segmentos 8K 2 y 3 = **ROM 0x4000–0x7FFF = bloque 16K 1 = el sector de arranque FAT
  del disco virtual** (`EB FE 90 "ALESTE20" ...` seguido de FAT: casi todo `0x00` y `0xFF`).
* Se copia eso a 0x4000 y se salta: `NOP`-sled sobre los `0x00` y luego una ristra de `0xFF` = **`RST 38h`
  encadenados** → la pila crece sin control → se machaca la RAM baja y el `RET` acaba en `0x0000`
  → **arranque en frío aparente**.

### Konami-SCC forzado → **NO PASA NADA**

* En modo SCC nuestro decodificador **sí** tiene registros dentro de la página 2:
  `0x9000–0x97FF → megaram_reg2` (solo protegido por `mode_b[4]==0`) y `0xB000–0xB7FF → megaram_reg3`
  (protegido por `mode_a[6]==0`; `mode_a` = 0x80 ⇒ bit6 = 0 ⇒ **abierto**).
* La pasada de escritura de 16 KB mete 2048 bytes por 0x9000–0x97FF y 2048 por 0xB000–0xB7FF:
  **reg2 y reg3 se reprograman miles de veces con datos del juego**. Al terminar apuntan a dos
  segmentos de 8 KB arbitrarios de los 2 MB.
* El `LDIR` copia 16 KB de datos comprimidos/gráficos y salta ahí: el Z80 ejecuta código plausible
  que casi siempre cae en un bucle cerrado o `di`+`halt` → **pantalla congelada, máquina viva**.
* Efecto lateral comprobable: si en algún instante `megaram_reg2[5:0] == 0x3F`, `megaram_scc_a` se
  activa y **0x9800–0x9FFF pasa a ser la ventana de sonido del SCC** → esas escrituras entran en la
  wave RAM. **Predicción falsable: en modo SCC debería oírse un chirrido/ruido breve al pulsar ESPACIO.**

**El "reinicio" NO es un warm-reset del core.** `config_reset` exige `OUT (#40),#48` (→ `config_ok`)
seguido de `OUT (#42)` con bit7. El `boot_stub` hace `out (#40),#D4` antes de llamar al INIT, así que
`config0_ff = 0x2B ≠ 0xB7` ⇒ `config_ok = 0` y el puerto #42 queda inerte. Además, en los 2 MB de ROM
solo hay 1 `OUT (#40),A` y 6 `OUT (#42),A`, todos dentro de bloques de datos gráficos, no de código.

---

## 5. Respuesta al aviso de openMSX ("ROM > 512 kB no soportada por un SCC real")

**(a) ¿Truncamos a 6 bits?** **No.** `megaram.v` usa el registro de banco **completo de 8 bits**:

```verilog
5'b01010: megaram_reg0 <= cpu_dout;       // 0x5000, 8 bits
assign megaram_addr = ... { megaram_reg0, bus_addr[12:0] };   // 8+13 = 21 bits = 2 MB
assign ram_addr = ... { 2'b10, megaram_addr[20:0] };          // banco C de SDRAM, 2 MB
```

Nuestro camino SCC llega a los 2 MB exactos, igual que openMSX. **Esa hipótesis queda descartada.**

**(b) Enmascarado.** openMSX hace `bloque % (tamaño/8192)`; con una ROM de 2 MB eso son 256 bloques
(potencia de 2) ⇒ equivale a `& 0xFF`, **idéntico** a nuestro `{reg, addr[12:0]}` de 21 bits.
No hay diferencia de aliasing. En ASCII16, openMSX enmascara `& 0x7F` y nosotros usamos
`cpu_dout[6:0]`: también idéntico.

**(c) ¿Pide bancos ≥ 64?** **Sí**: bloques de 16 KB **64 a 75** están en la tabla de sectores.
Pero **el fallo ocurre mucho antes**: el primer `call #F13F` tras ESPACIO pide el bloque **1**
(verificado con breakpoint: `A=0x00`, luego `A=0x01`). El juego muere en la primera carga de 16 KB.

### Veredicto sobre el fix del bit 6 (commit `b6ab040`)

> **Correcto y necesario, pero insuficiente — y no era la causa de estos dos síntomas.**

Necesario porque el juego sí usa bloques 64–75 (el 2.º MB): con el código antiguo
(`{cpu_dout[7], cpu_dout[5:0]}`) esos bloques aliasaban sobre el primer megabyte y la carga
habría fallado *más adelante*. Insuficiente porque el juego nunca llega a pedirlos.
**Mantenerlo.** No se ha podido validar en HW todavía porque el bug de la página 2 lo tapa.

---

## 6. Parche propuesto

**Fichero:** `MSXnano/fpga/src/msxnano_menu/src/menu_main.asm` (repo compartido; **solo lectura** en esta
sesión — no he tocado nada). Sin cambios de RTL ⇒ **sin síntesis ni P&R**, solo `make rom` + reflashear
el pack (`fm_logo_menu.bin` @ 0x6C000).

### 6.1 Constante nueva (junto a `SD_SLOT_31 equ #87`, línea ~390)

```asm
RAM_SLOT_30	equ	#83			; ENASLT slot id: expanded, primary 3, secondary 0 (RAM mapeada)
```

### 6.2 `launch_rom` — decidir el slot de la página 2 (insertar antes de copiar el stub, ~línea 1968)

```asm
	; Página 2 al llamar al INIT: la BIOS real deja RAM ahí (medido en openMSX con la
	; BIOS auténtica de un FS-A1WSX). Solo las ROMs lineales 32K/48K necesitan que la
	; página 2 siga siendo el cartucho.
	ld   a, (MAPPER_ID)
	or   a							; MAP_PLAIN = 0 -> ROM lineal: pag.2 = megaram
	ld   a, MEG_SLOT
	jr   z, .lr_p2ok
	ld   a, RAM_SLOT_30				; megarom: pag.2 = RAM (fiel a la BIOS)
.lr_p2ok:
	ld   (P2_SLOT), a
```

con `P2_SLOT equ #C0DD` (byte libre contiguo a `MAP_SWIO equ #C0DC`; verificar que está libre).

### 6.3 `boot_stub` (líneas 2032–2047) — reordenar

```asm
boot_stub:
	ld   sp, #F380
	ld   a, #02						; página 1 -> slot 2 (megaram)
	ld   hl, #4000
	call ENASLT
	ld   a, #02						; página 2 -> megaram SOLO para fijar reg2/reg3
	ld   hl, #8000
	call ENASLT
	xor  a							; bancos canónicos 0,1,2,3 (el modo aún es SCC)
	ld   (#5000), a
	ld   a, 1
	ld   (#7000), a
	ld   a, 2
	ld   (#9000), a
	ld   a, 3
	ld   (#B000), a
	ld   a, (P2_SLOT)				; <<< NUEVO: #02 (lineal) o #83 (megarom = RAM)
	ld   hl, #8000
	call ENASLT
	ld   a, #D4						; mapper real vía SWIO
	out  (#40), a
	...   (resto igual)
```

**Importante:** la inicialización de bancos 0,1,2,3 debe seguir haciéndose **con la página 2 en la
megaram** (usa 0x9000/0xB000), y el cambio a RAM va **después**.

### 6.4 Variante de riesgo cero (alternativa o complemento)

Si prefieres no cambiar el comportamiento por defecto de toda la biblioteca: reutiliza el mecanismo de
tags de nombre que ya existe (`override_mapper_by_name`) y añade un tag tipo `[P2RAM]` que ponga
`P2_SLOT = RAM_SLOT_30`. Entonces Aleste 2 se arregla renombrando el fichero y **nada más cambia**.
Recomiendo la 6.2/6.3 como defecto (es lo fiel al hardware real) y dejar el tag como escape hatch.

---

## 7. Cómo validarlo

1. **Pre-validación en openMSX (ya hecha, repetible).** Savestate `al2_welcome` guardado.
   - Contraprueba negativa: forzar `out (#A8),#D4` en el breakpoint de `0x4010` ⇒ falla igual que la placa.
   - Contraprueba positiva: sin tocar nada ⇒ SCREEN 5 con la intro.
2. **En placa, tras reflashear SOLO el pack** (no hace falta bitstream nuevo):
   - Forzando **Konami-SCC**: ESPACIO debe llevar a SCREEN 5 con la intro dibujándose.
   - Forzando **ASCII16**: mismo resultado (el juego se autodetecta bien en ambos).
   - Con **autodetección** (v2.0.1 promociona Konami4 → SCC en ROMs ≥ 320 KB): también.
3. **Si tras el parche muere más tarde** (por ejemplo al entrar en el segundo/tercer "disco"),
   entonces sí estaríamos ante el 2.º MB → ahí se valida en HW el fix del bit 6. Bloques a vigilar: 64–75.
4. **Regresión obligatoria** (juegos que hoy funcionan y dependen del `boot_stub`):
   - Megaroms SCC de dos fases: **Metal Gear 2, SD Snatcher** (hook H.STKE).
   - Megaroms SCC de una fase: **Nemesis 2/3, Salamander, Parodius, F1 Spirit, King's Valley 2, Aleste 1**.
   - ASCII8/16: **Hydlide 2** y **A-Train** (además prueban la SRAM de cartucho).
   - **ROM lineal 32K** cualquiera (verifica la rama `MAP_PLAIN`, que no cambia).
   Todos los megaroms reales calculan su propio slot con `RSLREG`+`EXPTBL` y hacen su `ENASLT` de la
   página 2 (es el patrón canónico de Konami/ASCII), así que el riesgo teórico es bajo — pero hay que medirlo.

---

## 8. Hallazgos secundarios (no bloquean, pero conviene anotarlos)

1. **Asimetría en los cerrojos de `megaram.v` (modo SCC).** Los registros de banco 0, 1 y 3
   (0x5000 / 0x7000 / 0xB000) están protegidos por `megaram_mode_a[6]`, pero el **banco 2**
   (`0x9000–0x97FF`) **solo** por `megaram_mode_b[4]`. Con el cerrojo del menú (`mode_a = 0x80`)
   eso da igual, pero es una inconsistencia real: si alguna vez se usa `mode_a[6]` como cerrojo,
   el banco 2 seguirá abierto. Un cartucho SCC real tampoco protege ninguno, así que lo correcto
   probablemente sea unificar el criterio conscientemente.
2. **Trampa latente con ROMs de 2 MB + tag SRAM.** La SRAM de cartucho vive en los 32 KB altos de la
   megaram (segmentos 252–255 = `0x1F8000–0x1FFFFF`). Para una ROM de 2 MB exactos eso **pisa los
   últimos 32 KB de la ROM**. Aleste 2 no lleva tag SRAM (`out (#43),0`) y además solo usa hasta el
   bloque 75, así que aquí no molesta — pero cualquier ROM de 2 MB con SRAM quedará corrupta al final.
3. **La megaram no filtra por página.** `scc2_req12` solo compara `pri_slot == config_megaram_slot`,
   sin mirar `bus_addr[15:14]`: responde en las 4 páginas (0x0000–0xFFFF), no solo en 0x4000–0xBFFF
   como un cartucho real. Es precisamente lo que convierte el error del `boot_stub` en algo destructivo
   en lugar de inocuo. Filtrar a `bus_addr[15:14] != 2'b00 && != 2'b11` sería más fiel al hardware,
   aunque rompería el espejo de puertos `_140` que hacía arrancar la demo ru66 — **no lo toques sin medir**.
4. **Mapper de RAM: 4 MB, sin problema.** `mapper_reg0..3` de 8 bits, `mapper_addr[21:0]` = 256 segmentos
   de 16 KB en el slot 3-0 (`config_enable_mapper3` + `exp_slotx_num[0]`), puertos `0xFC–0xFF`
   (`bus_addr[7:2] == 6'b111111`). El juego solo hace unos pocos `OUT` a FC/FD/FF en toda la ROM.
   No pide más de lo que tenemos y la detección estándar de tamaño funciona.

---

## 9. Ficheros relevantes

| Fichero | Papel |
|---|---|
| `C:\Users\alber\proyectosAI\msx\MSXnano\fpga\src\msxnano_menu\src\menu_main.asm` | **A PARCHEAR**: `boot_stub` (2032–2047), `launch_rom` (1863–1992), constantes (370–395) |
| `C:\Users\alber\proyectosAI\msx\MSX_up\fpga\src\megaram.v` | Mapper del cartucho. **Fix del bit 6 = correcto, dejarlo.** Ver asimetría del cerrojo (líneas 161–203) |
| `C:\Users\alber\proyectosAI\msx\MSX_up\fpga\top.v` | Mapa SDRAM (2071–2114), mapper RAM (2005–2059), slots megaram (3333–3390), config/warm-reset (3679–3812) |
| `C:\Users\alber\Downloads\Aleste 2 - Compile (1989) [ROM Version] [v8 by Ricbit] [3275].rom` | ROM analizada (2 MB) |
| `...\scratchpad\aleste2mb\aleste2.rom` | Copia con nombre simple (el MCP de openMSX no traga corchetes en la ruta) |
| savestate openMSX `al2_welcome` | Pantalla de bienvenida, listo para pulsar ESPACIO |
