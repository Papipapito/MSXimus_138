// ============================================================================
// tb_amwrap.v — suma LEVEL + TL + ALFO del motor PCM OPL4 (15/10/2026)
//
// LevelAddTLALFO sumaba en 11 bits y ENVOLVIA: con LEVEL = 3FFh (slot ocioso) y TL = 3FFh (TL = 7Fh, FFh en el chip) mas un ALFO
// >= 2 (el slot conserva de su ultimo instrumento un AM con LFO activo) la suma pasaba de 800h y salia ALFO-2, un nivel de ~0 dB: un slot
// MUDO sonaba a casi plena escala con el dato rancio del bus de ondas (el slot ocioso no lee memoria: WD es el ultimo byte leido por los
// slots que si suenan). En la demo de MBWave (_MBFADE de intro1: TL = 7Fh a los slots ociosos) era ruido de banda ancha durante 2,7 s.
// Canon (openMSX YMF278.cc:533-536): min(env_vol + AM, MAX_ATT_INDEX) y el TL aparte; nunca desborda.
//
// Onda cuadrada sintetica de 8 bits (+-127) como en tb_tl.v (no hace falta la YRW801). El slot 0 es siempre un "pad" con TL=0 y sin AM:
// suena todo el rato y deja su ultimo byte en MEM_D (el dato rancio que oirian los slots ociosos). Los slots 1 y 2 son los de prueba, con
// LFO rapido (reg 80h = 38h) y AM=7 (reg E0h = 07h, 11,9 dB de profundidad) salvo donde se diga.
//
// Fases (+fase=N; run_amwrap.sh las lanza en paralelo). El LFO del slot arranca al acabar el ataque.
//  1. EL FALLO: slot 1 con AM, KEY OFF + DAMP (EVOL -> 3FFh); con TL=0 y despues con TL=7Fh su salida es 0 EXACTO mientras el pad suena.
//     Con el motor anterior (suma de 11 bits) la segunda ventana suena a ~5700: es el control negativo.
//  2. KEY ON con TL=7Fh (FFh) y AR=9 (ataque lento): EVOL baja de 280h a 0 con AM activo y la salida del slot es 0 todo el rato.
//  3. EVOL entre 3C0h y 3FFh con TL=0: el DAMP recorre la rampa final de la envolvente; mientras LEVEL >= 3C0h la salida es 0.
//     Ademas la funcion LevelAddTLALFO contra min(LEVEL+TL+ALFO, 3FFh) para todos los LEVEL, todos los TL (4 por paso de TL, mas 3FFh) y
//     ALFO representativos; y contra la suma de 11 bits anterior: solo difiere con TL = 3FFh y LEVEL+ALFO >= 401h.
//  4. Nota normal (TL=0, EVOL en ataque AR=10): slot 1 sin AM y slot 2 con AM=7, misma onda. El tremolo sigue funcionando: ALFO crece con
//     el LFO, LEVEL = EVOL+ALFO y la salida del slot 2 sigue la formula de nivel (cociente de picos contra la atenuacion esperada).
//     Imprime CHECKSUM: con el motor anterior debe salir IGUAL (con TL=0 la suma de 11 bits no desborda nunca).
// En todas las fases un marcador comprueba en CADA muestra de CADA slot: LEVEL == min(EVOL+TL+ALFO, 3FFh) y que LEVEL >= 3C0h calla
// el slot (VolCalc) y que la salida del slot es la formula de VolCalc + Atten15.
//
// Ejecutar: cd tools/opl4wave_sim && ./run_amwrap.sh [motor.v]
// ============================================================================
`timescale 1ns/1ps

module tb_amwrap;

reg clk_x1 = 0;
always #6.734 clk_x1 = ~clk_x1;        // 74.25 MHz (FSM DDR3)
reg clk_eng = 0;
always #13.333 clk_eng = ~clk_eng;     // 37.5 MHz (CLKOUT4 del PLLA)
reg clk_host = 0;
always #9.26 clk_host = ~clk_host;     // 54 MHz

reg rst_n = 0, eng_rst_n = 0;

reg iorq_n = 1, rd_n = 1, wr_n = 1, m1_n = 1;
reg [7:0] a = 0, din = 0;
wire wave_rd;
wire [7:0] wave_dout;
wire wave_wait_n;
wire [1:0] wave_status;
wire signed [15:0] pcm_l, pcm_r;

wire        mem_req, mem_we;
wire [21:0] mem_addr;
wire [7:0]  mem_wdata;
reg  [7:0]  mem_rdata = 0;
reg  [15:0] mem_rword = 0;
reg         mem_done_t = 0;

opl4_pcm dut (
    .rst_n(rst_n), .clk_host(clk_host),
    .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n),
    .addr(a), .din(din),
    .wave_rd(wave_rd), .wave_dout(wave_dout), .wave_wait_n(wave_wait_n),
    .wave_status(wave_status),
    .pcm_l(pcm_l), .pcm_r(pcm_r),
    .clk_eng(clk_eng), .eng_rst_n(eng_rst_n),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr),
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_rword(mem_rword), .mem_done_t(mem_done_t)
);

// ---- memoria de ondas falsa: latencia DDR3 20-24 ciclos ----
reg [7:0] wavemem [0:4194303];
reg        p_pend = 0, p_we;
reg [21:0] p_addr;
reg [7:0]  p_dat;
reg [5:0]  p_cnt, p_lat;
reg mem_req_d = 0;
always @(posedge clk_x1) begin
    mem_req_d <= mem_req;
    if (mem_req && !mem_req_d) begin
        p_pend <= 1; p_we <= mem_we; p_addr <= mem_addr; p_dat <= mem_wdata;
        p_cnt <= 0; p_lat <= 6'd20 + ({$random} % 5);
    end
    else if (p_pend) begin
        p_cnt <= p_cnt + 1;
        if (p_cnt == p_lat) begin
            if (p_we) wavemem[p_addr] <= p_dat;
            else begin
                mem_rdata <= wavemem[p_addr];
                mem_rword[7:0]  <= wavemem[{p_addr[21:1], 1'b0}];
                mem_rword[15:8] <= wavemem[{p_addr[21:1], 1'b1}];
            end
            mem_done_t <= ~mem_done_t;
            p_pend <= 0;
        end
    end
end

// ---- tareas Z80 ----
task outp(input [7:0] p, input [7:0] v);
begin
    @(negedge clk_host); a = p; din = v; iorq_n = 0; wr_n = 0;
    #420; @(negedge clk_host); wr_n = 1; iorq_n = 1;
    #2500;
end
endtask

reg [7:0] rdv;
task inp(input [7:0] p);
begin
    @(negedge clk_host); a = p; iorq_n = 0; rd_n = 0;
    #460;
    while (!wave_wait_n) @(posedge clk_host);
    #5; rdv = wave_dout;
    #80; @(negedge clk_host); rd_n = 1; iorq_n = 1;
    #1500;
end
endtask

task wreg(input [7:0] r, input [7:0] v);
begin outp(8'h7E, r); outp(8'h7F, v); end
endtask

// ---- acceso a las etapas del motor (campos de OP5, OP6 y OP7 en el .v generado) ----
wire        ce1      = dut.u_engine.SLOT1_CE;
wire [41:0] op5      = dut.u_engine.OP5;           // {SLOT[41:37], RST, KON, KOFF, WD[33:18], EVOL[17:8], ALFO[7:0]}
wire [33:0] op6      = dut.u_engine.OP6;           // {SLOT[33:29], RST, KON, KOFF, WD[25:10], LEVEL[9:0]}
wire [23:0] op7      = dut.u_engine.OP7;           // {SLOT[23:19], RST, KON, KOFF, SD[15:0]}
wire [16:0] tl_q     = dut.u_engine.TL_RAM_Q;      // {TL_INT[16:10], TL_FRAC[9:0]}

// ---- modelo de referencia de la cadena de nivel y volumen (independiente del RTL) ----
function integer ref_level(input integer evol, input integer tl_q17, input integer alfo);
    integer tl, s;
begin
    tl = ((tl_q17 >> 10) == 127) ? 1023 : (tl_q17 >> 8);       // TL_INT = 7Fh es silencio (FFh en el chip); si no, {TL_INT, TL_FRAC[9:8]}
    s  = evol + tl + alfo;
    ref_level = (s > 1023) ? 1023 : s;
end
endfunction

function integer ref_sd(input integer wd, input integer level);   // VolCalc + Atten15 (-15 dB por slot)
    integer m, p, r;
begin
    if (level >= 960) ref_sd = 0;                              // LEVEL[9:6] == Fh: silencio
    else begin
        m = 64 + (63 - (level & 63));                          // mantisa 40h..7Fh
        p = (wd * m) >>> 7;                                    // MULT[22:7]
        r = p >>> (level >> 6);                                // 6 dB por cada 40h
        ref_sd = (r * 23170) >>> 17;                           // Atten15: x0,1768
    end
end
endfunction

// ---- marcador: en CADA SLOT1_CE (una muestra de un slot) ----
integer errors = 0;
integer sb_n = 0, sb_lvl_err = 0, sb_sil_err = 0, sb_sd_err = 0;
integer sb_wrap = 0;                      // muestras cuya suma en bruto pasa de 7FFh (lo que la suma de 11 bits envolvia)
integer sb_in3c0 = 0;                     // muestras (slot 1) con LEVEL entre 3C0h y 3FEh
integer sb_first_err = 1, sb_first_sd = 1;
reg     sb_on = 0;
reg     e_valid = 0;  integer e_slot, e_level;           // lo que debe salir de OP5 -> OP6 en este flanco
reg     p_valid = 0;  integer p_slot, p_level, p_wd;     // OP6 antes del flanco anterior = lo que OP7 tiene ahora
reg     [4:0] sl6, sl7;
integer win_on = 0;                       // 1: acumulando picos y estadisticas de la ventana
integer pk [0:31];                        // pico de |SD| por slot en la ventana
integer alfo_max [0:31];
integer evol_min [0:31];
integer evol_max [0:31];
integer lvl_min [0:31];
integer sdv;
integer k;
integer raw;
reg [31:0] hsh = 32'd0;                   // CHECKSUM de las salidas de los slots 1 y 2 y del pcm_l en la ventana de la fase 4

task win_reset;
begin
    for (k = 0; k < 32; k = k + 1) begin pk[k] = 0; alfo_max[k] = 0; evol_min[k] = 99999; evol_max[k] = 0; lvl_min[k] = 99999; end
end
endtask

initial win_reset;

always @(posedge clk_eng) begin
    if (ce1 && sb_on) begin
        // (a) OP6 y OP7 recien cargados (resultado del flanco anterior)
        sl6 = op6[33:29]; sl7 = op7[23:19];
        if (e_valid) begin
            if (op6[9:0] !== e_level[9:0] || sl6 !== e_slot[4:0]) begin
                sb_lvl_err = sb_lvl_err + 1;
                if (sb_first_err) begin
                    $display("FAIL: slot %0d: LEVEL = %03X, esperado min(EVOL+TL+ALFO,3FF) = %03X (t=%0t)", e_slot, op6[9:0], e_level, $time);
                    sb_first_err = 0;
                end
            end
        end
        if (p_valid) begin
            sdv = $signed(op7[15:0]);
            if (sl7 !== p_slot[4:0]) begin
                sb_sd_err = sb_sd_err + 1;
                if (sb_first_sd) begin $display("FAIL: OP7 trae el slot %0d y se esperaba el %0d (t=%0t)", sl7, p_slot, $time); sb_first_sd = 0; end
            end
            if (p_level >= 960 && sdv != 0) begin
                sb_sil_err = sb_sil_err + 1;
                if (sb_first_err) begin
                    $display("FAIL: slot %0d: LEVEL = %03X >= 3C0 pero SD = %0d (deberia callar) (t=%0t)", p_slot, p_level, sdv, $time);
                    sb_first_err = 0;
                end
            end
            if (sdv != ref_sd(p_wd, p_level)) begin
                sb_sd_err = sb_sd_err + 1;
                if (sb_first_sd) begin $display("FAIL: slot %0d: SD = %0d, VolCalc+Atten15(WD=%0d, LEVEL=%03X) = %0d (t=%0t)", p_slot, sdv, p_wd, p_level, ref_sd(p_wd, p_level), $time); sb_first_sd = 0; end
            end
            if (win_on) begin
                if (sdv > pk[sl7]) pk[sl7] = sdv;
                if (-sdv > pk[sl7]) pk[sl7] = -sdv;
                if (sl7 == 1 || sl7 == 2) hsh = {hsh[30:0], hsh[31]} ^ {16'd0, sdv[15:0]} ^ {27'd0, sl7};
            end
        end
        // (b) lo que OP5 y el TL darian en ESTE flanco (OP6 lo tendra en el siguiente)
        raw = op5[17:8] + (((tl_q[16:10]) == 7'h7F) ? 1023 : tl_q[16:8] ) + op5[7:0];
        if (raw > 2047) sb_wrap = sb_wrap + 1;
        e_level = ref_level(op5[17:8], tl_q, op5[7:0]);
        e_slot  = op5[41:37];
        e_valid = 1;
        sb_n = sb_n + 1;
        if (win_on) begin
            if (op5[7:0] > alfo_max[op5[41:37]]) alfo_max[op5[41:37]] = op5[7:0];
            if (op5[17:8] < evol_min[op5[41:37]]) evol_min[op5[41:37]] = op5[17:8];
            if (op5[17:8] > evol_max[op5[41:37]]) evol_max[op5[41:37]] = op5[17:8];
            if (e_level < lvl_min[op5[41:37]]) lvl_min[op5[41:37]] = e_level;
            if (op5[41:37] == 5'd1 && e_level >= 960 && e_level < 1023) sb_in3c0 = sb_in3c0 + 1;
        end
        // OP6 pre-flanco = lo que OP7 recibe en este flanco
        p_valid = 1; p_slot = op6[33:29]; p_level = op6[9:0]; p_wd = $signed(op6[25:10]);
    end
end

// captura del pcm_l (una vez por cambio de pcm_h3), solo para el CHECKSUM
reg pcm_seen = 0;
integer n_pcm = 0;
reg     pcm_hash_on = 0;
always @(posedge clk_host) begin
    pcm_seen <= dut.pcm_h3;
    if (dut.pcm_h3 !== pcm_seen && pcm_hash_on) begin
        hsh = {hsh[30:0], hsh[31]} ^ {16'd0, pcm_l[15:0]} ^ 32'h8000_0000;
        n_pcm = n_pcm + 1;
    end
end

integer i, j, fase;

task setslot(input integer s, input [7:0] tlreg, input [7:0] ar_d1r, input [7:0] lfo, input [7:0] am);
begin
    wreg(8'h20 + s, 8'h00);        // F-num low / WTN[8]=0
    wreg(8'h38 + s, 8'h30);        // octava 3
    wreg(8'h50 + s, tlreg);        // TL / LD
    wreg(8'h08 + s, 8'h00);        // onda 0: dispara la carga de la cabecera
    i = 0;
    inp(8'hC4); inp(8'h7E);
    while (rdv[1] && i < 100) begin #10000; inp(8'hC4); inp(8'h7E); i = i + 1; end
    if (rdv[1]) begin $display("FAIL: LD no se limpia (slot %0d)", s); errors = errors + 1; end
    wreg(8'h98 + s, ar_d1r);       // AR / D1R (la cabecera trae AR=15; fase 2: AR=9, fase 4: AR=10)
    wreg(8'h80 + s, lfo);          // LFO / VIB
    wreg(8'hE0 + s, am);           // AM
end
endtask

// ventana de medida de ms_a a ms_b (ms desde t0); deja los picos y estadisticas en pk[], alfo_max[], evol_min[]...
real t0;
task ventana(input real ms_a, input real ms_b);
begin
    if ((t0 + ms_a * 1.0e6) > $realtime) #((t0 + ms_a * 1.0e6) - $realtime);
    win_reset; win_on = 1;
    #((ms_b - ms_a) * 1.0e6);
    win_on = 0;
end
endtask

task check(input integer cond, input [1023:0] msg);
begin
    if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
end
endtask

integer l, t, al, d, ndiff, nbad, nsil, ntl, rr, ali;
real    ratio, expect_r;
integer pk1a, pk2a;
reg [9:0] fn, fo;
reg [10:0] sum11;
initial begin
    if (!$value$plusargs("fase=%d", fase)) fase = 1;
    // cabecera de la onda 0: 8 bits, cuadrada +-127 de 64 muestras en 0x100, AR=15 D1R=0 DL=0 D2R=0 RC=15 RR=15 (como tb_tl.v)
    for (i = 0; i < 4194304; i = i + 1) wavemem[i] = 8'h00;
    wavemem[0]  = 8'h00;
    wavemem[1]  = 8'h01;   // start = 0x000100
    wavemem[2]  = 8'h00;
    wavemem[3]  = 8'h00;   // loop = 0
    wavemem[4]  = 8'h00;
    wavemem[5]  = 8'hFF;   // end = -64 (64 muestras)
    wavemem[6]  = 8'hC0;
    wavemem[7]  = 8'h00;
    wavemem[8]  = 8'hF0;   // AR=15, D1R=0
    wavemem[9]  = 8'h00;   // DL=0, D2R=0
    wavemem[10] = 8'hFF;   // RC=15, RR=15
    wavemem[11] = 8'h00;
    for (i = 0; i < 32; i = i + 1) wavemem[22'h100 + i] = 8'h7F;
    for (i = 32; i < 64; i = i + 1) wavemem[22'h100 + i] = 8'h81;

    #500  rst_n = 1;
    #1000 eng_rst_n = 1;
    #60000;                   // barrido de reset del motor (768 CE)
    sb_on = 1;
    outp(8'hC6, 8'h05);
    outp(8'hC7, 8'h03);       // NEW/NEW2

    // -------------------------------------------------------------------- fase 1: el fallo
    if (fase == 1) begin
        $display("== 1. slot ocioso con AM y TL=7Fh mientras otro slot suena ==");
        setslot(0, 8'h01, 8'hF0, 8'h00, 8'h00);          // pad: TL=0, sin AM
        setslot(1, 8'h01, 8'hF0, 8'h38, 8'h07);          // slot de prueba: AM=7, LFO rapido
        wreg(8'h68, 8'h80); wreg(8'h69, 8'h80);          // KEY ON los dos
        t0 = $realtime;
        #((t0 + 3.0e6) - $realtime);
        wreg(8'h69, 8'h00); wreg(8'h69, 8'h40);          // slot 1: KEY OFF + DAMP -> EVOL = 3FFh en ~11 ms
        ventana(16.0, 21.0);
        $display("  slot 1 ocioso (EVOL=%03X) con TL=0: pico slot 1 = %0d, pico pad = %0d, ALFO max slot 1 = %0d", evol_max[1], pk[1], pk[0], alfo_max[1]);
        check(pk[1] == 0,  "slot 1 ocioso con TL=0 no calla");
        check(pk[0] > 1000, "el pad no suena: el banco no prueba nada");
        check(evol_min[1] == 1023, "EVOL del slot 1 no ha llegado a 3FF");
        sb_wrap = 0;
        wreg(8'h51, 8'hFF);                              // TL del slot 1 = 7Fh, LD=1
        ventana(22.0, 27.0);
        $display("  slot 1 ocioso con TL=7Fh: pico slot 1 = %0d, pico pad = %0d, ALFO max slot 1 = %0d, muestras con suma > 7FFh = %0d", pk[1], pk[0], alfo_max[1], sb_wrap);
        check(pk[1] == 0,  "slot 1 ocioso con TL=7Fh y AM SUENA (suma de LEVEL+TL+ALFO desbordada)");
        check(pk[0] > 1000, "el pad no suena: el banco no prueba nada");
        check(alfo_max[1] >= 2, "ALFO < 2 con TL=7Fh");
        check(sb_wrap > 0, "ninguna muestra pasa de 7FFh: el banco no ejercita el desbordamiento");
    end

    // -------------------------------------------------------------------- fase 2: KEY ON con TL=7Fh
    if (fase == 2) begin
        $display("== 2. KEY ON con TL=7Fh y EVOL en ataque (AR=9) con AM ==");
        setslot(0, 8'h01, 8'hF0, 8'h00, 8'h00);          // pad
        setslot(1, 8'hFF, 8'h90, 8'h38, 8'h07);          // TL=7Fh LD=1, AR=9, AM=7, LFO rapido
        wreg(8'h68, 8'h80); wreg(8'h69, 8'h80);
        t0 = $realtime;
        ventana(0.5, 32.0);
        $display("  EVOL slot 1: %03X .. %03X, ALFO max = %0d, pico slot 1 = %0d, pico pad = %0d", evol_max[1], evol_min[1], alfo_max[1], pk[1], pk[0]);
        check(pk[1] == 0, "slot 1 con TL=7Fh SUENA durante el ataque");
        check(pk[0] > 1000, "el pad no suena: el banco no prueba nada");
        check(evol_min[1] == 0, "EVOL del slot 1 no ha llegado a 0 (el ataque no termino)");
        check(evol_max[1] >= 10'h200, "EVOL del slot 1 no empieza en el ataque");
        check(alfo_max[1] >= 10, "ALFO del slot 1 < 10: el AM no esta activo");
    end

    // -------------------------------------------------------------------- fase 3: EVOL en 3C0h..3FFh y funcion exhaustiva
    if (fase == 3) begin
        $display("== 3. EVOL entre 3C0h y 3FFh con TL=0 (rampa del DAMP) y la funcion LevelAddTLALFO exhaustiva ==");
        setslot(0, 8'h01, 8'hF0, 8'h00, 8'h00);          // pad
        setslot(1, 8'h01, 8'hF0, 8'h38, 8'h07);          // TL=0, AM=7
        wreg(8'h68, 8'h80); wreg(8'h69, 8'h80);
        t0 = $realtime;
        #((t0 + 3.0e6) - $realtime);
        wreg(8'h69, 8'h00); wreg(8'h69, 8'h40);          // KEY OFF + DAMP
        ventana(3.0, 24.0);
        $display("  slot 1: EVOL %03X .. %03X, LEVEL min %03X, muestras con LEVEL entre 3C0h y 3FEh = %0d", evol_max[1], evol_min[1], lvl_min[1], sb_in3c0);
        check(evol_max[1] == 1023, "EVOL del slot 1 no llega a 3FF");
        check(sb_in3c0 > 0, "la rampa no pasa por ninguna muestra de 3C0h..3FEh: no se ejercita ese tramo");
        // un instante tras la rampa: slot 1 ocioso con TL=0 callado
        ventana(24.0, 28.0);
        check(pk[1] == 0, "slot 1 ocioso (EVOL=3FF, TL=0) no calla");
        check(pk[0] > 1000, "el pad no suena");

        // funcion exhaustiva (sin reloj): LEVEL 0..3FF x TL (508 valores {TL_INT 0..7E, frac 0..3} + 3FF) x ALFO representativos
        nbad = 0; ndiff = 0; nsil = 0; ntl = 0;
        for (t = 0; t < 1024; t = t + 1) begin
            if (t < 508 || t == 1023) begin
                ntl = ntl + 1;
                for (l = 0; l < 1024; l = l + 1) begin
                    for (ali = 0; ali < 8; ali = ali + 1) begin
                        al = (ali == 0) ? 0 : (ali == 1) ? 1 : (ali == 2) ? 2 : (ali == 3) ? 3 : (ali == 4) ? 19 : (ali == 5) ? 64 : (ali == 6) ? 126 : 127;
                        fn = dut.u_engine.YMF278B_PKG_LevelAddTLALFO(l[9:0], t[9:0], al[7:0]);
                        rr = l + t + al; if (rr > 1023) rr = 1023;
                        if (fn !== rr[9:0]) nbad = nbad + 1;
                        // la suma de 11 bits anterior
                        sum11 = {1'b0, l[9:0]} + {1'b0, t[9:0]} + {3'b000, al[7:0]};
                        fo = !sum11[10] ? sum11[9:0] : 10'h3FF;
                        if (fn !== fo) begin
                            ndiff = ndiff + 1;
                            if (!(t == 1023 && (l + al) >= 1025)) nsil = nsil + 1;     // difiere fuera del caso esperado
                        end
                        // un termino mudo nunca se resucita: LEVEL+ALFO >= 3C0h o TL = 3FFh => resultado >= 3C0h
                        if (((l + al) >= 960 || t == 1023) && fn < 10'h3C0) nbad = nbad + 1;
                    end
                end
            end
        end
        // ALFO completo (0..127) con TL = 0, 1F8h y 3FFh
        for (al = 0; al < 128; al = al + 1) begin
            for (l = 0; l < 1024; l = l + 1) begin
                for (ali = 0; ali < 3; ali = ali + 1) begin
                    t = (ali == 0) ? 0 : (ali == 1) ? 10'h1F8 : 10'h3FF;
                    fn = dut.u_engine.YMF278B_PKG_LevelAddTLALFO(l[9:0], t[9:0], al[7:0]);
                    rr = l + t + al; if (rr > 1023) rr = 1023;
                    if (fn !== rr[9:0]) nbad = nbad + 1;
                end
            end
        end
        $display("  LevelAddTLALFO: %0d valores de TL x 1024 LEVEL x 8 ALFO + ALFO 0..127 x 1024 x 3 TL: %0d distintas de min(LEVEL+TL+ALFO,3FF)", ntl, nbad);
        $display("  contra la suma de 11 bits anterior: %0d combinaciones distintas, %0d fuera del caso TL=3FFh con LEVEL+ALFO >= 401h", ndiff, nsil);
        check(nbad == 0, "LevelAddTLALFO no es min(LEVEL+TL+ALFO,3FF) o resucita un termino mudo");
        check(nsil == 0, "LevelAddTLALFO difiere de la suma de 11 bits anterior fuera de TL=3FFh con LEVEL+ALFO >= 401h");
        check(ndiff > 0, "el banco no distingue la suma nueva de la anterior");
    end

    // -------------------------------------------------------------------- fase 4: nota normal, tremolo
    if (fase == 4) begin
        $display("== 4. nota normal (TL=0, EVOL en ataque AR=10): slot 1 sin AM, slot 2 con AM=7 ==");
        setslot(0, 8'h01, 8'hF0, 8'h00, 8'h00);          // pad
        setslot(1, 8'h01, 8'hA0, 8'h38, 8'h00);          // AR=10, sin AM
        setslot(2, 8'h01, 8'hA0, 8'h38, 8'h07);          // AR=10, AM=7
        wreg(8'h69, 8'h80); wreg(8'h6A, 8'h80); wreg(8'h68, 8'h80);   // KEY ON (el pad el ultimo, da igual)
        t0 = $realtime;
        pcm_hash_on = 1;
        hsh = 32'd0;
        // ocho ventanas de 6 ms; el LFO tarda ~20 ms en arrancar tras el KEY ON y despues avanza un paso de ALFO cada ~0,6 ms
        for (d = 0; d < 8; d = d + 1) begin
            ventana(2.0 + 6.0 * d, 8.0 + 6.0 * d);
            pk1a = pk[1]; pk2a = pk[2];
            ratio = (pk1a > 0) ? (1.0 * pk2a / pk1a) : 0.0;
            // los picos estan en el nivel minimo de la ventana: cociente esperado = VolCalc(nivel minimo slot 2) / VolCalc(nivel minimo slot 1)
            expect_r = (ref_sd(32512, lvl_min[1]) > 0) ? (1.0 * ref_sd(32512, lvl_min[2]) / ref_sd(32512, lvl_min[1])) : 0.0;
            $display("  %5.1f-%5.1f ms: slot 1 pico %5d (EVOL %03X..%03X)  slot 2 pico %5d (EVOL %03X..%03X, ALFO max %0d)  cociente %0.3f, esperado %0.3f",
                     2.0 + 6.0 * d, 8.0 + 6.0 * d, pk1a, evol_max[1], evol_min[1], pk2a, evol_max[2], evol_min[2], alfo_max[2], ratio, expect_r);
            if (pk1a > 1000) check(ratio > expect_r - 0.04 && ratio < expect_r + 0.04, "el cociente de picos no es la atenuacion esperada del tremolo");
            if (d == 7) begin
                // ataque acabado (EVOL = 0 en los dos): el slot 1 esta a plena escala y el 2 atenuado por el ALFO
                check(evol_min[1] == 0 && evol_min[2] == 0, "el ataque no ha terminado a los 44 ms");
                check(alfo_max[2] >= 40, "el LFO no ha avanzado: ALFO max < 40");
                check(lvl_min[1] == 0, "slot 1 (sin AM, EVOL=0, TL=0) no esta a nivel 0");
                check(pk1a > 5000 && pk2a < pk1a, "el tremolo no atenua el slot 2 respecto al 1");
            end
        end
        pcm_hash_on = 0;
        $display("  CHECKSUM fase 4 = %08X (%0d muestras de pcm_l); con el motor anterior debe salir igual", hsh, n_pcm);
        check(alfo_max[2] > alfo_max[1], "el AM del slot 2 no modula mas que el del slot 1");
    end

    // -------------------------------------------------------------------- marcador comun
    sb_on = 0;
    $display("  marcador: %0d muestras de slot, %0d con LEVEL distinto de min(EVOL+TL+ALFO,3FF), %0d con LEVEL>=3C0h y salida no nula, %0d con salida distinta de VolCalc+Atten15 (suma > 7FFh: %0d)",
             sb_n, sb_lvl_err, sb_sil_err, sb_sd_err, sb_wrap);
    check(sb_lvl_err == 0, "LEVEL no es min(EVOL+TL+ALFO, 3FF) en alguna muestra");
    check(sb_sil_err == 0, "un slot con LEVEL >= 3C0h no calla");
    check(sb_sd_err == 0, "la salida de un slot no es VolCalc+Atten15 de su LEVEL");
    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #140000000;               // 140 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
