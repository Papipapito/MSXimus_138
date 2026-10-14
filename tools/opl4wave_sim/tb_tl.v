// ============================================================================
// tb_tl.v — TL con LD=0 del motor PCM OPL4 (13/10/2026)
//
// El TL (reg 50h-67h, bits 7:1; bit 0 = LD) con LD=0 se alcanza por interpolacion: el chip mueve el nivel un
// paso de TL cada 27 muestras al atenuar y cada 13,5 al subir (YMF278.cc de openMSX, advance()). Antes el
// motor interpolaba en SENTIDO CONTRARIO: el TL de 17 bits se iba al extremo, daba la vuelta y se quedaba
// oscilando 0 / -48 dB cada 3 muestras (modulacion en anillo a 14,7 kHz) tras CADA escritura con LD=0: se oia
// en los fundidos del MoonBlaster (_MBFADE de MiG, cientos de escrituras por segundo).
//
// Onda cuadrada sintetica de 8 bits (+-127), a octava 3, con AR=15, D1R=0, D2R=0: la envolvente queda plana y el valor de
// las muestras positivas ES el nivel (sin cruces por cero que lo oculten). Solo se miran las muestras positivas:
// los 23 slots ociosos tocan la misma onda con el nivel al maximo y dan 0 en la semionda positiva y -1 cada uno
// (-23 en total) en la negativa. Comprueba:
//  1. fundido de TL 0 a 24 con LD=0: llega al nivel final en ~15 ms (24 pasos x 27 muestras = 14,7 ms) y el
//     nivel baja SIN subidas intermedias (el patron de 3 muestras las tenia a cada paso);
//  2. subida de TL 24 a 0 con LD=0: ~7 ms (24 x 13,5 muestras = 7,3 ms), siempre creciendo, hasta el nivel de TL=0
//     (la interpolacion se detiene al coincidir la parte ENTERA del TL: queda como mucho 1 paso, -0,4 dB);
//  3. TL=7Fh con LD=1: silencio (en el chip TL=7Fh equivale a FFh): ni una muestra positiva y solo el -1 por slot.
// El nivel final de 24 pasos no es exactamente 9 dB (x0,355): VolCalc interpola la mantisa en lineal entre
// potencias de 2 y a 96 unidades de nivel da (127-32)/127/2 = x0,374; el banco espera ese valor.
//
// +fase=1|2|3 elige la fase (cada una arranca de un TL distinto; run_tl.sh las lanza en paralelo); por defecto la 1.
// Ejecutar: cd tools/opl4wave_sim && ./run_tl.sh
// ============================================================================
`timescale 1ns/1ps

module tb_tl;

// medio periodo de clk_eng: 13.333 = 37,5 MHz (60K y Zynq); el 138K va a 36 MHz
// (-Ptb_tl.ENG_HALF=13.889, lo pone su run_tl.sh)
parameter real ENG_HALF = 13.333;

reg clk_x1 = 0;
always #6.734 clk_x1 = ~clk_x1;        // 74.25 MHz (FSM DDR3)
reg clk_eng = 0;
always #(ENG_HALF) clk_eng = ~clk_eng; // motor
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

// ---- captura de |pcm| por muestra (una por cambio de pcm_h3) ----
localparam MAXN = 3000;
integer    sv [0:MAXN-1];           // pcm_l
real       st [0:MAXN-1];           // instante (ns)
integer    av [0:MAXN-1];           // solo las positivas
real       at [0:MAXN-1];
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

integer errors = 0;
integer i, j;
real    t_w;

// Analiza av[0..nc-1] tras una escritura de TL en t_w. dir=-1: debe bajar (fundido), +1: debe subir.
// Imprime el nivel inicial/final, el tiempo hasta quedar a +-1/64 del final y el numero de reversiones.
task analiza(input integer dir, input real tmin_ms, input real tmax_ms, input [255:0] que);
    integer lo, hi, fin, tol, rev, settle, k, maxv, minv;
    real    ms;
begin
    // nos quedamos con las muestras positivas
    k = 0;
    for (lo = 0; lo < nc; lo = lo + 1)
        if (sv[lo] > 0) begin av[k] = sv[lo]; at[k] = st[lo]; k = k + 1; end
    nc = k;
    fin = av[nc-1];
    tol = (fin < 64) ? 1 : fin / 64;
    // instante a partir del cual TODAS las muestras estan a +-tol del final
    settle = 0;
    for (k = nc-1; k >= 0; k = k - 1)
        if (av[k] > fin + tol || av[k] + tol < fin) begin settle = k + 1; k = -1; end
    ms = (settle < nc) ? (at[settle] - t_w) / 1.0e6 : 1.0e3;
    // reversiones: subidas (dir=-1) o bajadas (dir=+1) de mas de 30 LSB entre muestras consecutivas (los slots
    // ociosos meten un salto de 23 LSB en la muestra en que cambian de semionda)
    rev = 0;
    for (k = 1; k < nc; k = k + 1)
        if (dir < 0 ? (av[k] > av[k-1] + 30) : (av[k] + 30 < av[k-1])) rev = rev + 1;
    $display("  %0s: muestras=%0d nivel inicial=%0d final=%0d, llega en %0.2f ms (esperado %0.1f-%0.1f), reversiones=%0d",
             que, nc, av[0], fin, ms, tmin_ms, tmax_ms, rev);
    if (!(ms >= tmin_ms && ms <= tmax_ms)) begin
        $display("FAIL: %0s: tiempo fuera de rango", que); errors = errors + 1;
    end
    if (rev != 0) begin
        $display("FAIL: %0s: el nivel cambia de sentido %0d veces (patron del TL al reves)", que, rev); errors = errors + 1;
    end
end
endtask

integer a0, a24, mx, fase;
reg [7:0] tl0;
initial begin
    if (!$value$plusargs("fase=%d", fase)) fase = 1;
    // header de la onda 0: 8 bits, cuadrada +-127 de 64 muestras en 0x100, AR=15 D1R=0 DL=0 D2R=0 RC=15 RR=15
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

    // la fase 2 arranca en TL=0 directo (referencia) y baja a TL=24 directo antes de medir; la 3 en TL=7Fh directo
    tl0 = (fase == 3) ? 8'hFF : 8'h01;
    outp(8'hC6, 8'h05);
    outp(8'hC7, 8'h03);       // NEW/NEW2
    wreg(8'h20, 8'h00);       // F-num low / WTN[8]=0
    wreg(8'h38, 8'h30);       // octava 3 (8 muestras por periodo: semiondas cortas, el nivel se lee cada ~4 muestras) / F-num hi
    wreg(8'h50, tl0);         // TL inicial, LD=1 (directo)
    wreg(8'h08, 8'h00);       // wave 0: dispara la carga del header
    i = 0;
    inp(8'hC4); inp(8'h7E);
    while (rdv[1] && i < 100) begin
        #10000; inp(8'hC4); inp(8'h7E); i = i + 1;
    end
    if (rdv[1]) begin $display("FAIL: LD no se limpia"); errors = errors + 1; end
    wreg(8'h68, 8'h80);       // KEY on, pan centro
    #1500000;                 // 1,5 ms: ataque terminado y nivel plano

    if (fase == 1) begin
        $display("== 1. fundido TL 0 -> 24 con LD=0 ==");
        nc = 0; capt = 1;
        t_w = $realtime;
        wreg(8'h50, 8'h30);       // TL=24 (24<<1), LD=0
        #22000000;                // 22 ms
        capt = 0;
        analiza(-1, 12.0, 18.0, "fundido 0->24");
        a0 = av[0]; a24 = av[nc-1];
        $display("  nivel(TL=24)/nivel(TL=0) = %0d/%0d = %0.3f (esperado 0.374)", a24, a0, 1.0 * a24 / a0);
        if (!(a24 * 1000 > a0 * 360 && a24 * 1000 < a0 * 390)) begin
            $display("FAIL: la relacion de niveles no es la de 24 pasos de TL"); errors = errors + 1;
        end
    end

    if (fase == 2) begin
        $display("== 2. subida TL 24 -> 0 con LD=0 ==");
        nc = 0; capt = 1;
        #300000;                  // referencia: nivel de TL=0 (0,3 ms)
        capt = 0;
        a0 = 0;
        for (j = 0; j < nc; j = j + 1) if (sv[j] > a0) a0 = sv[j];
        wreg(8'h50, 8'h31);       // TL=24, LD=1 (directo)
        #1500000;
        nc = 0; capt = 1;
        t_w = $realtime;
        wreg(8'h50, 8'h00);       // TL=0, LD=0
        #11000000;                // 11 ms
        capt = 0;
        analiza(+1, 5.0, 10.0, "subida 24->0");
        a24 = av[0]; mx = av[nc-1];
        $display("  nivel final / nivel de TL=0 = %0d/%0d = %0.3f (esperado 0.97-1.00)", mx, a0, 1.0 * mx / a0);
        if (!(mx * 100 >= a0 * 95 && mx <= a0 + 3)) begin
            $display("FAIL: la subida no llega al nivel de TL=0"); errors = errors + 1;
        end
    end

    if (fase == 3) begin
        $display("== 3. TL=7Fh con LD=1: silencio ==");
        nc = 0; capt = 1;
        #500000;
        capt = 0;
        mx = -99999; a0 = 99999;
        for (j = 0; j < nc; j = j + 1) begin
            if (sv[j] > mx) mx = sv[j];
            if (sv[j] < a0) a0 = sv[j];
        end
        $display("  pcm con TL=7Fh: max=%0d min=%0d en %0d muestras (silencio = max<=0 y min>=-24: el -1 de cada slot)", mx, a0, nc);
        if (nc < 10 || mx > 0 || a0 < -24) begin $display("FAIL: TL=7Fh no es silencio"); errors = errors + 1; end
    end

    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #80000000;                // 80 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
