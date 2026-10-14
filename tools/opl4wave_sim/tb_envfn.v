// ============================================================================
// tb_envfn.v — funciones de la envolvente del motor PCM OPL4 contra openMSX / libvgm (13/10/2026)
//
// Llama a EffRateCalc / EnvStep / EnvInc del motor generado (ymf278b_gowin.v) y las compara con el modelo de
// referencia (YMF278.cc de openMSX y ymf278b.c de libvgm, escrito aqui aparte, no copiado del motor):
//  1. EffRateCalc: tasa efectiva para TODAS las combinaciones de RATE, RC, OCT y FNUM9 (8192). OCT+RC se recorta a
//     [0,15] ("clamping verified with HW tests"); antes se pasaba sin recortar y con octavas negativas la suma
//     envolvia en 7 bits y se tomaba por desbordamiento => tasa 63: la nota moria en ~4 ms.
//  2. EnvStep / EnvInc para las 64 tasas y 32768 valores del contador de muestras (SCNT entero, una cuenta por
//     muestra): paso si eg_cnt[shift-1:0] == 0 con shift = 12 - grupo (minimo 0) e incremento
//     eg_inc[fila + ((eg_cnt >> shift) & 7)]. Antes: SCNT[18:1] (cada paso se veia dos veces) e indice de bits
//     fijos del contador (el incremento quedaba constante 4096 muestras: la envolvente avanzaba a rafagas).
//  3. Una nota con OCT=-4, RC=0, D2R=1 (Surrec: el "pad" grave): 0,5 s de decay con las funciones del motor; la
//     envolvente no puede haber bajado mas de 12 unidades de nivel (1,1 dB). Antes: tasa 63 y silencio a los 6 ms.
//
// Ejecutar: cd tools/opl4wave_sim && ./run_env.sh
// ============================================================================
`timescale 1ns/1ps

module tb_envfn;

wire [20:0] ma;  wire [7:0] mdo;  wire mrd_n, mwr_n;  wire [9:0] mcs_n;
reg clk = 0;
YMF278B dut (
    .CLK(clk), .RST_N(1'b0), .IC_N(1'b0), .EN(1'b1), .CE(1'b1),
    .CS_N(1'b1), .RD_N(1'b1), .WR_N(1'b1), .A(3'd0), .DI(8'd0), .DO(),
    .MA(ma), .MDI(8'h00), .MDO(mdo), .MRD_N(mrd_n), .MWR_N(mwr_n),
    .MCS_N(mcs_n),
    .OUT0_L(), .OUT0_R(), .OUT1_L(), .OUT1_R(), .OUT2_L(), .OUT2_R(),
    .IRQ_N(), .MEM_SLOT(), .MIX_FM(), .SND_EN(3'b111), .CYCLE1_NEXT()
);

// ---- referencia: libvgm ymf278b.c (eg_inc, eg_rate_select, eg_rate_shift, compute_rate) ----
reg [3:0] eg_inc [0:119];   // 15 filas x 8
integer ri;
initial begin
    // fila 0..3: tasas 00..12 (incremento 0 o 1); 4..7: tasa 13; 8..11: tasa 14; 12: tasa 15 (decay); 13: ataque; 14: infinito
    eg_inc[  0] = 0; eg_inc[  1] = 1; eg_inc[  2] = 0; eg_inc[  3] = 1; eg_inc[  4] = 0; eg_inc[  5] = 1; eg_inc[  6] = 0; eg_inc[  7] = 1;
    eg_inc[  8] = 0; eg_inc[  9] = 1; eg_inc[ 10] = 0; eg_inc[ 11] = 1; eg_inc[ 12] = 1; eg_inc[ 13] = 1; eg_inc[ 14] = 0; eg_inc[ 15] = 1;
    eg_inc[ 16] = 0; eg_inc[ 17] = 1; eg_inc[ 18] = 1; eg_inc[ 19] = 1; eg_inc[ 20] = 0; eg_inc[ 21] = 1; eg_inc[ 22] = 1; eg_inc[ 23] = 1;
    eg_inc[ 24] = 0; eg_inc[ 25] = 1; eg_inc[ 26] = 1; eg_inc[ 27] = 1; eg_inc[ 28] = 1; eg_inc[ 29] = 1; eg_inc[ 30] = 1; eg_inc[ 31] = 1;
    eg_inc[ 32] = 1; eg_inc[ 33] = 1; eg_inc[ 34] = 1; eg_inc[ 35] = 1; eg_inc[ 36] = 1; eg_inc[ 37] = 1; eg_inc[ 38] = 1; eg_inc[ 39] = 1;
    eg_inc[ 40] = 1; eg_inc[ 41] = 1; eg_inc[ 42] = 1; eg_inc[ 43] = 2; eg_inc[ 44] = 1; eg_inc[ 45] = 1; eg_inc[ 46] = 1; eg_inc[ 47] = 2;
    eg_inc[ 48] = 1; eg_inc[ 49] = 2; eg_inc[ 50] = 1; eg_inc[ 51] = 2; eg_inc[ 52] = 1; eg_inc[ 53] = 2; eg_inc[ 54] = 1; eg_inc[ 55] = 2;
    eg_inc[ 56] = 1; eg_inc[ 57] = 2; eg_inc[ 58] = 2; eg_inc[ 59] = 2; eg_inc[ 60] = 1; eg_inc[ 61] = 2; eg_inc[ 62] = 2; eg_inc[ 63] = 2;
    eg_inc[ 64] = 2; eg_inc[ 65] = 2; eg_inc[ 66] = 2; eg_inc[ 67] = 2; eg_inc[ 68] = 2; eg_inc[ 69] = 2; eg_inc[ 70] = 2; eg_inc[ 71] = 2;
    eg_inc[ 72] = 2; eg_inc[ 73] = 2; eg_inc[ 74] = 2; eg_inc[ 75] = 4; eg_inc[ 76] = 2; eg_inc[ 77] = 2; eg_inc[ 78] = 2; eg_inc[ 79] = 4;
    eg_inc[ 80] = 2; eg_inc[ 81] = 4; eg_inc[ 82] = 2; eg_inc[ 83] = 4; eg_inc[ 84] = 2; eg_inc[ 85] = 4; eg_inc[ 86] = 2; eg_inc[ 87] = 4;
    eg_inc[ 88] = 2; eg_inc[ 89] = 4; eg_inc[ 90] = 4; eg_inc[ 91] = 4; eg_inc[ 92] = 2; eg_inc[ 93] = 4; eg_inc[ 94] = 4; eg_inc[ 95] = 4;
    for (ri = 96; ri < 104; ri = ri + 1) eg_inc[ri] = 4;     // fila 12
    for (ri = 104; ri < 112; ri = ri + 1) eg_inc[ri] = 8;    // fila 13 (ataque)
    for (ri = 112; ri < 120; ri = ri + 1) eg_inc[ri] = 0;    // fila 14
end

function integer ref_row(input integer rate);
    begin
        if (rate < 4)        ref_row = 14;
        else if (rate < 52)  ref_row = rate & 3;
        else if (rate < 56)  ref_row = 4 + (rate & 3);
        else if (rate < 60)  ref_row = 8 + (rate & 3);
        else                 ref_row = 12;
    end
endfunction

function integer ref_shift(input integer rate);
    integer s;
    begin
        s = 12 - (rate / 4);
        ref_shift = (s < 0) ? 0 : s;
    end
endfunction

function integer ref_rate(input integer rate, input integer rc, input integer oct, input integer fn9);
    integer res, oct_s, oct_rc;
    begin
        oct_s = (oct >= 8) ? oct - 16 : oct;
        if (rate == 0) ref_rate = 0;
        else if (rate == 15) ref_rate = 63;
        else begin
            res = rate * 4;
            if (rc != 15) begin
                oct_rc = oct_s + rc;
                if (oct_rc < 0) oct_rc = 0;
                if (oct_rc > 15) oct_rc = 15;
                res = res + oct_rc * 2 + fn9;
            end
            if (res < 0) res = 0;
            if (res > 63) res = 63;
            ref_rate = res;
        end
    end
endfunction

integer errors = 0, n = 0;
integer rate, rc, oct, fn9, erate, cnt, sh, evol, k, fallos;
reg [6:0] ef;
reg       st;
reg [3:0] inc;
integer   exp_inc;
reg       exp_st;
reg [18:0] c19;

initial begin
    #1;
    // 1. EffRateCalc
    fallos = 0;
    for (rate = 0; rate < 16; rate = rate + 1)
        for (rc = 0; rc < 16; rc = rc + 1)
            for (oct = 0; oct < 16; oct = oct + 1)
                for (fn9 = 0; fn9 < 2; fn9 = fn9 + 1) begin
                    ef = dut.YMF278B_PKG_EffRateCalc(rate[3:0], rc[3:0], oct[3:0], fn9[0]);
                    n = n + 1;
                    if (ef[5:0] !== ref_rate(rate, rc, oct, fn9)) begin
                        fallos = fallos + 1;
                        if (fallos <= 5)
                            $display("  FALLO EffRateCalc(RATE=%0d RC=%0d OCT=%0d FN9=%0d) = %0d, esperado %0d", rate, rc, oct, fn9, ef[5:0], ref_rate(rate, rc, oct, fn9));
                    end
                end
    $display("== 1. EffRateCalc: %0d combinaciones, %0d fallos ==", n, fallos);
    errors = errors + fallos;

    // 2. EnvStep / EnvInc
    fallos = 0; n = 0;
    for (erate = 0; erate < 64; erate = erate + 1) begin
        sh = ref_shift(erate);
        for (cnt = 0; cnt < 32768; cnt = cnt + 1) begin
            c19 = cnt;
            st  = dut.YMF278B_PKG_EnvStep(c19, erate[5:0]);
            inc = dut.YMF278B_PKG_EnvInc(c19, erate[5:0]);
            exp_st  = ((cnt & ((1 << sh) - 1)) == 0);
            exp_inc = eg_inc[ref_row(erate) * 8 + ((cnt >> sh) & 7)];
            n = n + 1;
            if (st !== exp_st || inc !== exp_inc) begin
                fallos = fallos + 1;
                if (fallos <= 5)
                    $display("  FALLO tasa %0d cnt %0d: paso %0d (esperado %0d) inc %0d (esperado %0d)", erate, cnt, st, exp_st, inc, exp_inc);
            end
        end
    end
    $display("== 2. EnvStep/EnvInc: %0d pares (tasa, contador), %0d fallos ==", n, fallos);
    errors = errors + fallos;

    // 3. Surrec: RATE=1 (D2R=1), RC=0, OCT=-4 (12), FNUM9=0 durante 0,5 s (22050 muestras)
    ef = dut.YMF278B_PKG_EffRateCalc(4'd1, 4'd0, 4'd12, 1'b0);
    evol = 0;
    for (cnt = 0; cnt < 22050; cnt = cnt + 1) begin
        c19 = cnt;
        if (dut.YMF278B_PKG_EnvStep(c19, ef[5:0]))
            evol = evol + dut.YMF278B_PKG_EnvInc(c19, ef[5:0]);
        if (evol > 1023) evol = 1023;
    end
    $display("== 3. nota OCT=-4 RC=0 D2R=1: tasa efectiva %0d, tras 0,5 s la envolvente ha bajado %0d unidades (max 12) ==", ef[5:0], evol);
    if (ef[5:0] != 4 || evol > 12) begin $display("FAIL: la nota se apaga"); errors = errors + 1; end

    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

endmodule
