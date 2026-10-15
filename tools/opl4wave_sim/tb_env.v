// ============================================================================
// tb_env.v — envolvente del motor PCM OPL4 con el motor entero (13/10/2026)
//
// Dos notas con una onda cuadrada sintetica de 8 bits (+-127) en un slot, con los parametros de envolvente de
// la cabecera de la onda (bytes 8-10):
//  fase 1  OCT=-4, RC=0, AR=15, D2R=1 (el "pad" grave de Surrec que moria): con OCT+RC sin recortar la tasa
//          efectiva salia como 63 y la nota se apagaba en ~4 ms. Debe seguir sonando a los 30 ms con el nivel
//          que tenia (la tasa real es 4: un paso cada 2048 muestras; a los 0,5 s habra bajado 5 unidades, ver
//          tb_envfn.v). Se lee max |pcm| en 1,5-2,0 ms y en 29,5-30,0 ms tras el key-on.
//  fase 2  AR=9, RC=15, octava 3: el ataque canon (env += (~env * inc) >> 4, un paso de envolvente cada 8
//          muestras y el incremento 0/1 alterno) tarda ~24 ms en llegar al nivel pleno; antes no llevaba el
//          >>4 y terminaba en el primer paso para cualquier AR.
//  fases 3-6 (15/10/2026) DL: el nivel de la envolvente se lee DENTRO del motor (EVOL de OP5 del slot 0, una muestra por
//          periodo de muestreo; unidad 3/32 dB: 20h = 3 dB, el dl_tab de openMSX/libvgm). AR=15, D2R=0, octava 0, RC=15:
//          cuando la caida de D1R llega al codo DL, D2R=0 deja el EVOL fijo en ese valor.
//   3      DL=4 (12 dB), D1R=12 (0,5/muestra): el codo es EVOL=080h (antes 100h = 24 dB: DL era a 6 dB por paso)
//   4      DL=15 (93 dB), D1R=14 (2/muestra): el codo es EVOL=3E0h (antes 3C0h)
//   5      DL cambiado EN CALIENTE: empieza con DL=15 y D1R=12; a los 11,6 ms (EVOL ~100h) se escribe DL=2 (40h, por
//          debajo del EVOL actual): con >= pasa a D2R en el paso siguiente y el EVOL queda fijo; con == (antes) no
//          se cumplia nunca y la nota seguia cayendo a D1R hasta 3FFh
//   6      DL=0: el EVOL no se mueve del 0 (pasa a D2R=0 en cuanto acaba el ataque)
//
// +fase=1..6 elige la fase (run_env.sh las lanza en paralelo); por defecto la 1.
// medio periodo de clk_eng: 13.333 = 37,5 MHz (60K y Zynq); el 138K va a 36 MHz
// (-Ptb_env.ENG_HALF=13.889, lo pone su run_env.sh)
parameter real ENG_HALF = 13.333;
// Ejecutar: cd tools/opl4wave_sim && ./run_env.sh
// ============================================================================
`timescale 1ns/1ps

module tb_env;

reg clk_x1 = 0;
always #6.734 clk_x1 = ~clk_x1;        // 74.25 MHz (FSM DDR3)
reg clk_eng = 0;
always #(ENG_HALF) clk_eng = ~clk_eng; // motor (37,5 MHz en 60K y Zynq, 36 en el 138K)
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

// ---- captura de pcm_l por muestra (una por cambio de pcm_h3) ----
localparam MAXN = 3000;
integer    sv [0:MAXN-1];           // pcm_l
real       st [0:MAXN-1];           // instante (ns)
integer    nc = 0;
reg        capt = 0;
reg        pcm_seen = 0;
always @(posedge clk_host) begin
    pcm_seen <= dut.pcm_h3;
    if (dut.pcm_h3 !== pcm_seen && capt && nc < MAXN) begin
        sv[nc] = pcm_l;
        st[nc] = $realtime;
        nc = nc + 1;
    end
end

// ---- captura del EVOL del slot 0 DENTRO del motor (15/10/2026): en cada SLOT1_CE, OP5 aun lleva el resultado del slot
// anterior (OP5[41:37] = SLOT, OP5[17:8] = EVOL); una muestra por periodo de muestreo (44,1 kHz) ----
integer    ev [0:MAXN-1];
real       et [0:MAXN-1];
integer    ne = 0;
always @(posedge clk_eng) begin
    if (dut.u_engine.SLOT1_CE && dut.u_engine.OP5[41:37] == 5'd0 && capt && ne < MAXN) begin
        ev[ne] = dut.u_engine.OP5[17:8];
        et[ne] = $realtime;
        ne = ne + 1;
    end
end

integer errors = 0;
integer i, j, fase;
real    t_key;

function integer iabs(input integer v);
    begin iabs = (v < 0) ? -v : v; end
endfunction

// maximo de |pcm| de las muestras capturadas entre t0 y t1 (ms tras el key-on)
function integer maxabs(input real t0, input real t1);
    integer k, m;
    begin
        m = 0;
        for (k = 0; k < nc; k = k + 1)
            if ((st[k] - t_key) / 1.0e6 >= t0 && (st[k] - t_key) / 1.0e6 < t1 && iabs(sv[k]) > m) m = iabs(sv[k]);
        maxabs = m;
    end
endfunction

// EVOL en la ultima muestra anterior a t ms tras el key-on
function integer evol_at(input real tms);
    integer k, r;
    begin
        r = -1;
        for (k = 0; k < ne; k = k + 1)
            if (et[k] >= t_key && (et[k] - t_key) / 1.0e6 <= tms) r = ev[k];
        evol_at = r;
    end
endfunction

// instante (ms tras el key-on) de la primera muestra de EVOL >= thr, contando desde que la nota ha arrancado (antes del
// key-on el slot esta en silencio con EVOL = 3FFh: primera muestra con EVOL < 10h); -1 si no llega
function real ms_first_ge(input integer thr);
    integer k, k0;
    real    r;
    begin
        r = -1.0;
        k0 = -1;
        for (k = 0; k < ne && k0 < 0; k = k + 1)
            if (et[k] >= t_key && ev[k] < 12'h010) k0 = k;
        for (k = (k0 < 0 ? ne : k0); k < ne && r < 0.0; k = k + 1)
            if (ev[k] >= thr) r = (et[k] - t_key) / 1.0e6;
        ms_first_ge = r;
    end
endfunction

integer a_ini, a_fin, kk, fin, t_ok;
integer e_w, e_a, e_b;
real    ms, t_knee;
initial begin
    if (!$value$plusargs("fase=%d", fase)) fase = 1;
    // header de la onda 0: 8 bits, cuadrada +-127 de 64 muestras en 0x100
    for (i = 0; i < 4194304; i = i + 1) wavemem[i] = 8'h00;
    wavemem[0]  = 8'h00;
    wavemem[1]  = 8'h01;   // start = 0x000100
    wavemem[2]  = 8'h00;
    wavemem[3]  = 8'h00;   // loop = 0
    wavemem[4]  = 8'h00;
    wavemem[5]  = 8'hFF;   // end = -64 (64 muestras)
    wavemem[6]  = 8'hC0;
    wavemem[7]  = 8'h00;
    if (fase == 1) begin
        wavemem[8]  = 8'hF0;   // AR=15, D1R=0
        wavemem[9]  = 8'h01;   // DL=0, D2R=1
        wavemem[10] = 8'h0F;   // RC=0, RR=15
    end else if (fase == 2) begin
        wavemem[8]  = 8'h90;   // AR=9, D1R=0
        wavemem[9]  = 8'h00;   // DL=0, D2R=0
        wavemem[10] = 8'hFF;   // RC=15, RR=15
    end else if (fase >= 3 && fase <= 6) begin
        wavemem[8]  = (fase == 4) ? 8'hFE : 8'hFC;                              // AR=15; D1R=14 (2/muestra) en la 4, D1R=12 (0,5/muestra) en las demas
        wavemem[9]  = (fase == 3) ? 8'h40 : (fase == 6) ? 8'h00 : 8'hF0;        // DL=4 / DL=0 / DL=15; D2R=0
        wavemem[10] = 8'hFF;                                                    // RC=15, RR=15
    end else begin
        $display("FAIL: fase %0d desconocida", fase); $finish;
    end
    wavemem[11] = 8'h00;
    for (i = 0; i < 32; i = i + 1) wavemem[22'h100 + i] = 8'h7F;
    for (i = 32; i < 64; i = i + 1) wavemem[22'h100 + i] = 8'h81;

    #500  rst_n = 1;
    #1000 eng_rst_n = 1;
    #60000;                   // barrido de reset del motor (768 CE)

    outp(8'hC6, 8'h05);
    outp(8'hC7, 8'h03);       // NEW/NEW2
    wreg(8'h20, 8'h00);       // F-num low / WTN[8]=0
    wreg(8'h38, (fase == 1) ? 8'hC0 : (fase == 2) ? 8'h30 : 8'h00);   // fase 1: octava -4 (1100b); fase 2: octava 3 (semiondas cortas); fases 3-6: octava 0
    wreg(8'h50, 8'h01);       // TL=0, LD=1 (directo)
    wreg(8'h08, 8'h00);       // wave 0: dispara la carga del header
    i = 0;
    inp(8'hC4); inp(8'h7E);
    while (rdv[1] && i < 100) begin
        #10000; inp(8'hC4); inp(8'h7E); i = i + 1;
    end
    if (rdv[1]) begin $display("FAIL: LD no se limpia"); errors = errors + 1; end
    nc = 0; ne = 0; capt = 1;
    t_key = $realtime;
    wreg(8'h68, 8'h80);       // KEY on, pan centro

    if (fase == 1) begin
        $display("== 1. nota OCT=-4 RC=0 D2R=1: sigue sonando a los 30 ms ==");
        #30500000;            // 30,5 ms
        capt = 0;
        a_ini = maxabs(1.5, 2.0); a_fin = maxabs(29.5, 30.0);
        $display("  max |pcm| a 1,5-2,0 ms = %0d; a 29,5-30,0 ms = %0d (%0d muestras capturadas)", a_ini, a_fin, nc);
        if (a_ini < 3000) begin $display("FAIL: la nota no suena al principio"); errors = errors + 1; end
        if (a_fin * 100 < a_ini * 90) begin $display("FAIL: la nota se ha apagado (queda %0d %% del nivel)", a_fin * 100 / ((a_ini > 0) ? a_ini : 1)); errors = errors + 1; end
    end

    if (fase == 2) begin
        $display("== 2. ataque con AR=9 ==");
        #45000000;            // 45 ms
        capt = 0;
        // nivel pleno = maximo de las muestras positivas entre 38 y 45 ms; el ataque acaba en la primera
        // muestra positiva que lo alcanza (99 %)
        fin = 0;
        for (kk = 0; kk < nc; kk = kk + 1)
            if ((st[kk] - t_key) / 1.0e6 >= 38.0 && sv[kk] > fin) fin = sv[kk];
        t_ok = -1;
        for (kk = 0; kk < nc && t_ok < 0; kk = kk + 1)
            if (sv[kk] * 100 >= fin * 99) t_ok = kk;
        ms = (t_ok >= 0) ? (st[t_ok] - t_key) / 1.0e6 : 1.0e3;
        $display("  nivel pleno = %0d; lo alcanza a los %0.2f ms del key-on (esperado 20-28 ms)", fin, ms);
        $display("  nivel a 1 ms = %0d, a 5 ms = %0d, a 10 ms = %0d, a 20 ms = %0d", maxabs(0.8, 1.2), maxabs(4.8, 5.2), maxabs(9.8, 10.2), maxabs(19.8, 20.2));
        if (fin < 3000) begin $display("FAIL: la nota no suena"); errors = errors + 1; end
        if (!(ms >= 20.0 && ms <= 28.0)) begin $display("FAIL: el ataque no dura lo que debe"); errors = errors + 1; end
    end

    if (fase == 3) begin
        $display("== 3. DL=4 (12 dB), D1R=12: el codo es EVOL=080h ==");
        #20000000;            // 20 ms
        capt = 0;
        t_knee = ms_first_ge(12'h080);
        e_a = evol_at(12.0); e_b = evol_at(20.0);
        $display("  EVOL llega a 080h a los %0.2f ms (esperado 5,6-6,1: 0,5 por muestra); EVOL a los 12 ms = %0d, a los 20 ms = %0d (codo 080h = 128)", t_knee, e_a, e_b);
        if (!(t_knee >= 5.6 && t_knee <= 6.1)) begin $display("FAIL: el EVOL no cruza 080h a tasa 48"); errors = errors + 1; end
        if (!(e_b >= 12'h080 && e_b <= 12'h083)) begin $display("FAIL: el codo de DL=4 no esta en 080h (12 dB)"); errors = errors + 1; end
        if (e_a != e_b) begin $display("FAIL: pasado el codo el EVOL debe quedar fijo (D2R=0)"); errors = errors + 1; end
    end

    if (fase == 4) begin
        $display("== 4. DL=15 (93 dB), D1R=14: el codo es EVOL=3E0h ==");
        #20000000;            // 20 ms
        capt = 0;
        t_knee = ms_first_ge(12'h3C0);
        e_a = evol_at(15.0); e_b = evol_at(20.0);
        $display("  EVOL llega a 3C0h a los %0.2f ms (esperado 10,6-11,3: 2 por muestra); EVOL a los 15 ms = %0d, a los 20 ms = %0d (codo 3E0h = 992)", t_knee, e_a, e_b);
        if (!(t_knee >= 10.6 && t_knee <= 11.3)) begin $display("FAIL: el EVOL no cruza 3C0h a tasa 56"); errors = errors + 1; end
        if (!(e_b >= 12'h3E0 && e_b <= 12'h3E7)) begin $display("FAIL: el codo de DL=15 no esta en 3E0h (93 dB)"); errors = errors + 1; end
        if (e_a != e_b) begin $display("FAIL: pasado el codo el EVOL debe quedar fijo (D2R=0)"); errors = errors + 1; end
    end

    if (fase == 5) begin
        $display("== 5. DL=15 -> DL=2 en caliente (EVOL ~100h): pasa a D2R y el EVOL queda fijo ==");
        #11600000;            // 11,6 ms: ~512 muestras a 0,5/muestra
        e_w = evol_at(11.6);
        wreg(8'hB0, 8'h20);   // DL=2 (40h), D2R=0
        #14400000;            // hasta ~26 ms
        capt = 0;
        e_a = evol_at(18.0); e_b = evol_at(26.0);
        $display("  EVOL al escribir DL=2 = %0d; a los 18 ms = %0d, a los 26 ms = %0d (esperado fijo, a lo sumo %0d)", e_w, e_a, e_b, e_w + 8);
        if (e_w < 12'h0C0 || e_w > 12'h200) begin $display("FAIL: el EVOL no estaba en D1R cerca de 100h al escribir DL"); errors = errors + 1; end
        if (e_a != e_b) begin $display("FAIL: el EVOL sigue cayendo tras escribir un DL por debajo del EVOL (la comparacion no es >=)"); errors = errors + 1; end
        if (e_b < e_w || e_b > e_w + 8) begin $display("FAIL: el EVOL debia quedar en el valor que tenia al escribir DL"); errors = errors + 1; end
    end

    if (fase == 6) begin
        $display("== 6. DL=0: el EVOL no se mueve del 0 ==");
        #20000000;            // 20 ms
        capt = 0;
        e_a = evol_at(2.0); e_b = evol_at(20.0);
        $display("  EVOL a los 2 ms = %0d, a los 20 ms = %0d (esperado 0..2)", e_a, e_b);
        if (e_b < 0 || e_b > 2) begin $display("FAIL: con DL=0 el EVOL debe quedar en 0 (pasa a D2R=0 al acabar el ataque)"); errors = errors + 1; end
        a_fin = maxabs(19.0, 20.0);
        $display("  max |pcm| a 19-20 ms = %0d (la nota suena a pleno nivel)", a_fin);
        if (a_fin < 3000) begin $display("FAIL: la nota no suena"); errors = errors + 1; end
    end

    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #90000000;                // 90 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
