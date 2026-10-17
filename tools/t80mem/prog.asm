; prog.asm - programa del banco t80mem (MSXimus_138, commit e402652)
; Todas las formas de escritura en memoria del Z80, con un dato DISTINTO en
; cada escritura (si la SDRAM capturase el dato de la escritura anterior o el
; de la siguiente, el banco lo ve). El programa corre DESDE la SDRAM (las
; lecturas de opcode y de datos pasan por memory_ctrl, como en placa).
; Fin: OUT (0FFh),A y HALT.

        org 0000h
        jp main

        org 0038h
rst38:  ld (8A20h), a           ; escritura dentro de la rutina del RST
        ret

        org 0040h
main:   di
        ld sp, 0F000h

; --- B1: LD (HL),A seguidas, A distinto en cada una (256) ---
        ld hl, 8000h
        ld b, 0
        ld a, 1
b1:     ld (hl), a
        inc a
        inc hl
        djnz b1

; --- B2: la misma direccion dos veces seguidas (gana la segunda) ---
        ld hl, 8100h
        ld b, 64
        ld c, 0
b2:     ld (hl), c
        ld a, c
        cpl
        ld (hl), a
        inc c
        inc hl
        djnz b2

; --- B3: inmediatos, (nn), (BC), (DE), (IX+d), (IY+d), 16 bits ---
        ld hl, 8180h
        ld (hl), 0A5h
        inc hl
        ld (hl), 5Ah
        ld a, 3Ch
        ld (8182h), a
        ld hl, 1234h
        ld (8184h), hl
        ld de, 5678h
        ld (8186h), de
        ld bc, 9ABCh
        ld (8188h), bc
        ld sp, 0DEF0h
        ld (818Ah), sp
        ld sp, 0F000h
        ld ix, 8190h
        ld iy, 81A0h
        ld (ix+0), 11h
        ld (ix+1), 22h
        ld (ix+7Fh), 33h
        ld (iy-10h), 44h
        ld b, 77h
        ld (ix+2), b
        ld c, 88h
        ld (iy+3), c
        ld h, 0C1h
        ld (ix+5), h
        ld bc, 81B0h
        ld a, 99h
        ld (bc), a
        ld de, 81B1h
        ld a, 66h
        ld (de), a
        ld ix, 0CAFEh
        ld (81B2h), ix
        ld iy, 0BEEFh
        ld (81B4h), iy

; --- B4: pila: PUSH seguidos, EX (SP),rr, CALL, RST ---
        ld sp, 8300h
        ld hl, 0102h
        ld de, 0304h
        ld bc, 0506h
        ld a, 07h
        push hl
        push de
        push bc
        push af
        push ix
        push iy
        ld hl, 0A0Bh
        ex (sp), hl
        ex (sp), ix
        ex (sp), iy
        call sub1
        ld a, 5Eh
        rst 38h
        ld sp, 0F000h

; --- B5: LDIR / LDDR ---
        ld hl, 8000h
        ld de, 8400h
        ld bc, 256
        ldir
        ld hl, 80FFh
        ld de, 85FFh
        ld bc, 256
        lddr

; --- B6: lectura-modificacion-escritura: INC/DEC (HL) e (IX+d) ---
        ld hl, 8400h
        ld b, 0
b6:     inc (hl)
        inc (hl)
        dec (hl)
        inc hl
        djnz b6
        ld ix, 8500h
        ld b, 32
b6b:    inc (ix+0)
        dec (ix+1)
        inc ix
        djnz b6b

; --- B7: RLD / RRD ---
        ld hl, 8600h
        ld (hl), 12h
        ld a, 34h
        rld
        ld (8601h), a
        ld hl, 8602h
        ld (hl), 56h
        ld a, 78h
        rrd
        ld (8603h), a

; --- B8: SET/RES/rotaciones sobre (HL) e (IX+d) ---
        ld hl, 8610h
        ld (hl), 0
        set 0, (hl)
        set 7, (hl)
        res 0, (hl)
        inc hl
        ld (hl), 81h
        rlc (hl)
        inc hl
        ld (hl), 81h
        sra (hl)
        inc hl
        ld (hl), 0F0h
        srl (hl)
        ld ix, 8620h
        ld (ix+3), 0FFh
        res 4, (ix+3)
        set 1, (ix+4)
        rr (ix+3)

; --- B9: el dato recien salido de la ALU, escrito enseguida ---
        ld hl, 8700h
        ld b, 0
        xor a
b9:     add a, b
        ld (hl), a
        xor 5Ah
        inc hl
        ld (hl), a
        inc hl
        djnz b9

; --- B10: relectura: suma de 8400h-84FFh -> 8A00h ---
        ld hl, 8400h
        ld b, 0
        ld de, 0
b10:    ld a, (hl)
        add a, e
        ld e, a
        ld a, d
        adc a, 0
        ld d, a
        inc hl
        djnz b10
        ld (8A00h), de

; --- fin ---
        ld a, 0AAh
        out (0FFh), a
fin:    halt
        jr fin

sub1:   ld (8A10h), a
        push hl
        pop hl
        ret

        end
