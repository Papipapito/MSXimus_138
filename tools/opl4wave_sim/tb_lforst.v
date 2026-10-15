// ============================================================================
// tb_lforst.v — BIT DE RESET DEL LFO (68h+slot, bit 5) DEL MOTOR PCM OPL4 (15/10/2026)
//
// Canon (openMSX YMF278.cc writeReg, registro 68h+slot): bit 5 = 1 -> lfo_active = false y lfo_cnt = 0 (el LFO de ESE
// slot se queda parado en fase 0: ni vibrato ni tremolo); bit 5 = 0 -> lfo_active = true (cuenta desde donde estaba, que
// tras un reset es 0). El reset de un slot NO puede tocar a los demas.
//
// QUE HACE (opl4_pcm + motor, DDR3 falsa): los 24 slots con KEY ON, F-number y octava iguales, LFO a la velocidad maxima
// (80h+slot = 3Fh: LFO 7, VIB 7) y tremolo maximo (E0h+slot = 07h), y 68h+k = A0h (KEY ON + reset del LFO) solo en el slot
// +k (y +k2 si se pide); en los demas 80h. Sin cargar cabecera de onda: el LFO, el vibrato y el tremolo no dependen de la
// muestra. Despues de calentar 3 ms se mide durante 25 ms, MIRANDO DENTRO DEL MOTOR, por slot:
//   - DATA del LFO en la RAM de LFO (LFO_RAM.mem[slot][7:0]): maximo alcanzado (parado = 0);
//   - ALFO que entra en OP5 (tremolo en unidades de EVOL): maximo (parado = 0);
//   - PHASE que entra en OP2 (incremento de fase, con el vibrato): minimo y maximo (parado = constante).
// Esperado: el slot (o slots) con reset tiene los tres a 0/constante; los otros 23 (22) tienen el LFO en marcha. Con el RTL
// anterior (OP1_LFORST <= REG_PAN_Q[5], el PAN leido con la direccion de OP6.SLOT = SLOT-6) el reset caia en el slot k+6
// (modulo 24: incluido el salto 23 -> 0).
// Fase dinamica (solo con +k): se suelta el reset de k (68h+k = 80h) y a los 6 ms su LFO ha vuelto a contar DESDE 0 (DATA
// entre 4 y 16; los demas siguen en marcha); se vuelve a poner y a 1 ms su DATA es 0 otra vez.
// +solo=J: solo suena el slot J (los demas con TL = 7Fh), con onda cuadrada de 8 bits y su cabecera cargada, y se mide la
// salida pcm_l: el pico por ventana de 2 ms debe ser plano si J tiene el reset y bajar (tremolo) si no.
// +rd=XX: durante la medida la CPU relee SIN PARAR el registro XX (hex) por 7Fh. Con registros de la BSRAM de slot (50h, 70h,
// 98h...) el barrido de rt_mem pierde alguna vez el octavo paso (el del reset del LFO y el DAMP) y ese slot ve el reset a 0
// durante una muestra: su DATA llega a 1 (ALFO 1, vibrato 0) y vuelve a 0; se tolera 1. 03h y 38h no tocan nada.
//
// Ejecutar: cd tools/opl4wave_sim && ./run_lforst.sh   (+k=N +k2=M +solo=J +rd=XX; run_lforst.sh barre los casos)
// ============================================================================
`timescale 1ns/1ps

module tb_lforst;

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
    .mem_wdata(mem_wdata), .mem_rdata(mem_rdata), .mem_rword(mem_rword), .mem_done_t(mem_done_t),
    .vid_diag(4'd0)
);

// ---- DDR3 falsa (la de tb_damp) ----
reg [7:0] wavemem [0:4194303];
reg        p_pend = 0, p_we;
reg [21:0] p_addr;
reg [7:0]  p_dat;
reg [5:0]  p_cnt, p_lat;
reg        mem_req_d = 0;
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

// ---- tareas de Z80 (las de tb_damp) ----
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
    #93;
    rdv = wave_dout;
    @(negedge clk_host); rd_n = 1; iorq_n = 1;
    #1500;
end
endtask

task wreg(input [7:0] r, input [7:0] v);
begin outp(8'h7E, r); outp(8'h7F, v); end
endtask

task waitld;
integer q;
begin
    q = 0;
    inp(8'hC4); inp(8'h7E);
    while (rdv[1] && q < 100) begin #10000; inp(8'hC4); inp(8'h7E); q = q + 1; end
    if (rdv[1]) $display("FAIL: LD no baja");
end
endtask

// ---- sondas dentro del motor ----
// DATA del LFO del slot s (celda de LFO_RAM: {LOAD_POS[21:18], DIV[17:8], DATA[7:0]})
function [7:0] lfo_data(input integer s);
begin lfo_data = dut.u_engine.LFO_RAM.mem[s][7:0]; end
endfunction

integer    k, k2, solo, rd, nrd = 0, errors, ok_s, nstop, tol;
real       t_rd0;
reg        capt = 0;
integer    cmax [0:23];      // DATA del LFO maximo por slot
integer    amax [0:23];      // ALFO maximo por slot
integer    pmin [0:23];      // PHASE minimo por slot
integer    pmax [0:23];      // PHASE maximo por slot
integer    nobs [0:23];      // muestras observadas por slot
integer    i, s, sl, ci;

always @(posedge clk_eng) begin
    if (capt && dut.u_engine.SLOT1_CE) begin
        // OP2 y OP5 valen lo de este slot hasta el flanco que los renueva; se leen en ese mismo flanco
        sl = dut.u_engine.OP2[44:40];                         // OP2.SLOT
        if (dut.u_engine.OP2[35:13] < pmin[sl]) pmin[sl] = dut.u_engine.OP2[35:13];   // OP2.PHASE
        if (dut.u_engine.OP2[35:13] > pmax[sl]) pmax[sl] = dut.u_engine.OP2[35:13];
        nobs[sl] = nobs[sl] + 1;
        sl = dut.u_engine.OP5[41:37];                         // OP5.SLOT
        if (dut.u_engine.OP5[7:0] > amax[sl]) amax[sl] = dut.u_engine.OP5[7:0];       // OP5.ALFO
        if (dut.u_engine.SLOT == 5'd23) begin
            for (ci = 0; ci < 24; ci = ci + 1)
                if (lfo_data(ci) > cmax[ci]) cmax[ci] = lfo_data(ci);
        end
    end
end

// pico de |pcm_l| por ventana de 2 ms (para +solo)
integer    pk [0:15];
integer    npk = 0, cur_pk = 0;
real       t_win;
always @(posedge clk_eng) begin
    if (capt && solo >= 0) begin
        if (pcm_l > cur_pk)  cur_pk = pcm_l;
        if (-pcm_l > cur_pk) cur_pk = -pcm_l;
        if ($realtime - t_win >= 2.0e6 && npk < 16) begin
            pk[npk] = cur_pk; npk = npk + 1; cur_pk = 0; t_win = $realtime;
        end
    end
end

// ---- principal ----
integer snap [0:23];
reg [7:0] reg68;
integer pkmin, pkmax;
reg expect_rst;

task snapshot;
integer q;
begin for (q = 0; q < 24; q = q + 1) snap[q] = lfo_data(q); end
endtask

initial begin
    errors = 0;
    if (!$value$plusargs("k=%d", k)) k = -1;
    if (!$value$plusargs("k2=%d", k2)) k2 = -1;
    if (!$value$plusargs("solo=%d", solo)) solo = -1;
    if (!$value$plusargs("rd=%h", rd)) rd = -1;
    for (i = 0; i < 24; i = i + 1) begin cmax[i] = 0; amax[i] = 0; pmin[i] = 32'h7FFFFFFF; pmax[i] = 0; nobs[i] = 0; end
    for (i = 0; i < 4194304; i = i + 1) wavemem[i] = 8'h00;
    // onda 0 (solo para +solo): cuadrada de 8 bits +-127, 64 muestras en bucle; byte 7 = LFO 7 / VIB 7, byte 11 = AM 7
    wavemem[0] = 8'h00; wavemem[1] = 8'h01; wavemem[2] = 8'h00;           // inicio 000100h
    wavemem[3] = 8'h00; wavemem[4] = 8'h00;                               // bucle 0
    wavemem[5] = 8'hFF; wavemem[6] = 8'hC0;                               // fin -64 muestras
    wavemem[7] = 8'h3F; wavemem[8] = 8'hF0; wavemem[9] = 8'h00; wavemem[10] = 8'hFF; wavemem[11] = 8'h07;
    for (i = 0; i < 32; i = i + 1) wavemem[22'h100 + i] = 8'h7F;
    for (i = 32; i < 64; i = i + 1) wavemem[22'h100 + i] = 8'h81;

    #500 rst_n = 1; #1000 eng_rst_n = 1; #60000;
    outp(8'hC6, 8'h05); outp(8'hC7, 8'h03);

    for (s = 0; s < 24; s = s + 1) begin
        wreg(8'h20 + s, 8'h00);                        // F-number 200h, octava 0
        wreg(8'h38 + s, 8'h04);
        wreg(8'h50 + s, (solo >= 0 && s != solo) ? 8'hFF : 8'h01);   // TL=7Fh (silencio) o TL=0, LD=1
        if (solo >= 0 && s == solo) begin
            wreg(8'h08 + s, 8'h00); waitld;            // la cabecera pisa 80h/98h/B0h/C8h/E0h con sus bytes 7..11
        end
        wreg(8'h80 + s, 8'h3F);                        // LFO 7, VIB 7
        wreg(8'hE0 + s, 8'h07);                        // AM 7
    end
    // Tras el reset del chip el LFO de cada slot cuenta con la velocidad 0 (1013 muestras por paso, 23 ms): hasta que ese
    // contador llegue a 0 la velocidad programada no se ve. Reset del LFO en todos los slots para que arranquen YA con la
    // velocidad de 80h; luego el estado final (KEY ON en todos y reset solo en +k / +k2).
    for (s = 0; s < 24; s = s + 1) wreg(8'h68 + s, 8'h20);
    #300000;
    for (s = 0; s < 24; s = s + 1) begin
        reg68 = 8'h80;
        if (s == k || s == k2) reg68 = 8'hA0;          // KEY ON + reset del LFO
        wreg(8'h68 + s, reg68);
    end

    #3000000;                                           // 3 ms de calentamiento
    t_win = $realtime;
    capt = 1;
    if (rd >= 0) begin                                  // la CPU relee sin parar el registro +rd por 7Fh durante la medida
        outp(8'h7E, rd);
        t_rd0 = $realtime;
        while ($realtime - t_rd0 < 25.0e6) begin inp(8'h7F); nrd = nrd + 1; end
    end else
        #25000000;                                      // 25 ms de medida
    capt = 0;
    if (rd >= 0) $display("  la CPU ha releido el registro %h por 7Fh %0d veces durante la medida", rd, nrd);

    // ---- resultado por slot ----
    // Con la CPU releyendo registros de la BSRAM de slot (+rd=50, 70, 68, 98...) REG_RD roba el puerto de lectura y el barrido
    // a veces no llega al octavo paso: ese slot toma el reset como 0 durante UNA muestra y su DATA llega a 1 (ALFO 1 = 0,09 dB,
    // vibrato 0). Se tolera 1.
    tol = (rd >= 0) ? 1 : 0;
    nstop = 0;
    for (s = 0; s < 24; s = s + 1) begin
        expect_rst = (s == k || s == k2);
        if (nobs[s] < 500) begin $display("FAIL: slot %0d con solo %0d observaciones", s, nobs[s]); errors = errors + 1; end
        if (expect_rst) begin
            ok_s = (cmax[s] <= tol) && (amax[s] <= tol) && (pmin[s] == pmax[s]);
            if (!ok_s) begin
                $display("FAIL: slot %0d debia tener el LFO parado y tiene DATA<=%0d, ALFO<=%0d, PHASE %0d..%0d", s, cmax[s], amax[s], pmin[s], pmax[s]);
                errors = errors + 1;
            end
        end else begin
            ok_s = (cmax[s] >= 20) && (amax[s] >= 10) && (pmax[s] - pmin[s] >= 8);
            if (!ok_s) begin
                $display("FAIL: slot %0d debia tener el LFO en marcha y tiene DATA<=%0d, ALFO<=%0d, PHASE %0d..%0d", s, cmax[s], amax[s], pmin[s], pmax[s]);
                errors = errors + 1;
            end
        end
        if (cmax[s] <= tol) nstop = nstop + 1;
    end
    $display("  reset pedido en k=%0d k2=%0d; slots con el LFO parado: %0d (esperado %0d)", k, k2, nstop, ((k >= 0) ? 1 : 0) + ((k2 >= 0) ? 1 : 0));
    for (s = 0; s < 24; s = s + 1)
        if (cmax[s] <= tol || s == k || s == k2)
            $display("    slot %2d: DATA max %0d, ALFO max %0d, PHASE %0d..%0d", s, cmax[s], amax[s], pmin[s], pmax[s]);
    if (k < 0 && nstop != 0) begin $display("FAIL: hay slots con el LFO parado sin pedirlo"); errors = errors + 1; end

    // ---- salida pcm_l (solo con +solo) ----
    if (solo >= 0) begin
        pkmin = 32'h7FFFFFFF; pkmax = 0;
        for (i = 1; i < npk; i = i + 1) begin if (pk[i] < pkmin) pkmin = pk[i]; if (pk[i] > pkmax) pkmax = pk[i]; end
        $write("  pcm_l del slot %0d solo: pico por ventana de 2 ms:", solo);
        for (i = 0; i < npk; i = i + 1) $write(" %0d", pk[i]);
        $display("  (min %0d, max %0d)", pkmin, pkmax);
        if (pkmax < 1000) begin $display("FAIL: el slot solo no suena"); errors = errors + 1; end
        else if (solo == k || solo == k2) begin
            if ((pkmax - pkmin) * 100 > pkmax * 2) begin $display("FAIL: el slot con reset debe sonar plano (variacion > 2 %%)"); errors = errors + 1; end
        end else begin
            if ((pkmax - pkmin) * 100 < pkmax * 10) begin $display("FAIL: el slot sin reset debe oscilar por el tremolo (variacion < 10 %%)"); errors = errors + 1; end
        end
    end

    // ---- fase dinamica: soltar y volver a poner el reset de k ----
    if (k >= 0 && solo < 0) begin
        wreg(8'h68 + k, 8'h80);                         // suelta el reset: el LFO vuelve a contar desde 0
        #6000000;
        snapshot;
        $display("  tras soltar el reset del slot %0d y 6 ms: DATA = %0d (esperado 4..16); vecinos %0d y %0d en marcha", k, snap[k], snap[(k + 6) % 24], snap[(k + 18) % 24]);
        if (!(snap[k] >= 4 && snap[k] <= 16)) begin $display("FAIL: el LFO soltado no cuenta desde 0"); errors = errors + 1; end
        if (!(snap[(k + 6) % 24] >= 40 && snap[(k + 18) % 24] >= 40)) begin $display("FAIL: soltar el reset de k ha tocado a otros slots"); errors = errors + 1; end
        wreg(8'h68 + k, 8'hA0);                         // vuelve a ponerlo
        #1000000;
        snapshot;
        $display("  tras volver a poner el reset y 1 ms: DATA del slot %0d = %0d (esperado 0)", k, snap[k]);
        if (snap[k] != 0) begin $display("FAIL: el reset no vuelve a parar el LFO"); errors = errors + 1; end
        if (!(snap[(k + 6) % 24] >= 40 && snap[(k + 18) % 24] >= 40)) begin $display("FAIL: volver a poner el reset de k ha tocado a otros slots"); errors = errors + 1; end
    end

    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #150000000;               // 150 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
