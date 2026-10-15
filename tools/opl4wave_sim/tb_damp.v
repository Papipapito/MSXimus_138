// ============================================================================
// tb_damp.v — DAMP y pseudo-reverb (PRVB) del motor PCM OPL4 con el motor entero (14/10/2026)
//
// Una onda cuadrada sintetica de 8 bits (+-127) en el slot 0, con la envolvente de la cabecera de la onda (bytes 8-10:
// AR/D1R, DL/D2R, RC/RR; AR=15 = ataque instantaneo) y el nivel de la envolvente leido DENTRO del motor (EVOL de OP5
// del slot 0, una muestra por periodo de muestreo) ademas del pcm_l de salida. Referencia: openMSX YMF278.cc
// compute_decay_rate (DAMP: tasa 48 hasta -12 dB y 63 por debajo, sin correccion de tasa; PRVB: a -18 dB la tasa
// interna pasa a 20, sin correccion) y el manual (DAMP: -12 dB a 5,8 ms, -48 dB a 8,0 ms, -96 dB a 10,9 ms).
// Unidad de EVOL: 3/32 dB (32 = 3 dB; 40h = 6 dB): -12 dB = 080h, -18 dB = 0C0h, -48 dB = 200h, -96 dB = 3FFh.
//
//  DAMP (+fase=1..5): nota sostenida (D2R=0), KEY OFF a los 5 ms con RR=2 (tasa 8: la cola sin DAMP dura decenas de s)
//   1  KEY OFF con DAMP, OCT=0,  RC=15 (sin correccion)       -> 5,8 / 8,0 / 10,9 ms a -12 / -48 / -96 dB
//   2  KEY OFF con DAMP, OCT=-4, RC=0  (correccion recortada a 0) -> igual
//   3  KEY OFF con DAMP, OCT=+3, RC=5  (correccion de +16 a la tasa) -> igual: DAMP ignora RC/OCT
//   4  KEY OFF sin DAMP, OCT=0, RC=15  -> la cola sigue como siempre (tasa 8: EVOL <= 1 a los 15 ms)
//   5  KEY OFF sin DAMP, OCT=+3, RC=5  -> conserva la correccion (tasa 24: EVOL = 4..6 a los 15 ms)
//  11  KEY ON sostenida y, a los 5 ms, 68h = C0h (KEY ON + DAMP: la tecla sigue pulsada, como en MiG) -> igual que la 1
//  12  ataque lento (AR=9) con KEY ON + DAMP desde el principio: el ataque no ve el DAMP (dura lo de siempre, ~23,6 ms:
//      tb_env fase 2) y al llegar EVOL a 0 la nota cae a -96 dB en 10,9 ms
//  PRVB (+fase=6..10): al cruzar -18 dB (EVOL >= 0C0h) la tasa pasa a 20 = +1 de EVOL cada 256 muestras
//   6  PRVB, D2R=12 (tasa 48 = 0,5/muestra, cruza a las 384 muestras = 8,7 ms), DL=0 (pasa a D2R al instante)
//   7  igual que 6 SIN PRVB: la caida sigue a 0,5/muestra (control)
//   8  PRVB por D1R: DL=15 (D1R hasta -90 dB), D1R=12, D2R=0
//   9  PRVB por RR: sostenida, KEY OFF a los 3 ms con RR=12
//  10  PRVB con correccion de tasa (OCT=+3, RC=7, D2R=8: tasa 52 hasta -18 dB, 1 por muestra) -> a -18 dB, tasa 20
//
// +fase=N elige la fase (run_damp.sh las lanza en paralelo).
// Ejecutar: cd tools/opl4wave_sim && ./run_damp.sh   (con un .v distinto del motor como argumento: control negativo)
// ============================================================================
`timescale 1ns/1ps

module tb_damp;

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

// ---- captura de pcm_l por muestra (una por cambio de pcm_h3) ----
localparam MAXN = 4096;
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

// ---- captura del EVOL del slot 0 DENTRO del motor: en cada SLOT1_CE, OP5 aun lleva el resultado del slot anterior
// (OP5[41:37] = SLOT, OP5[17:8] = EVOL); una muestra por periodo de muestreo (44,1 kHz) ----
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
real    t_ref;                      // instante del evento (KEY ON o KEY OFF) al que se refieren los tiempos

function integer iabs(input integer v);
    begin iabs = (v < 0) ? -v : v; end
endfunction

// maximo de |pcm| de las muestras capturadas entre t0 y t1 (ms tras t_ref)
function integer maxabs(input real t0, input real t1);
    integer k, m;
    begin
        m = 0;
        for (k = 0; k < nc; k = k + 1)
            if ((st[k] - t_ref) / 1.0e6 >= t0 && (st[k] - t_ref) / 1.0e6 < t1 && iabs(sv[k]) > m) m = iabs(sv[k]);
        maxabs = m;
    end
endfunction

// indice de la primera muestra de EVOL (desde el indice k0, posterior a t_ref) con EVOL >= thr; -1 si no llega
function integer first_ge_from(input integer k0, input integer thr);
    integer k, r;
    begin
        r = -1;
        for (k = (k0 < 0 ? 0 : k0); k < ne && r < 0; k = k + 1)
            if (et[k] >= t_ref && ev[k] >= thr) r = k;
        first_ge_from = r;
    end
endfunction

function integer first_ge(input integer thr);
    begin first_ge = first_ge_from(0, thr); end
endfunction

// indice de la primera muestra de EVOL (posterior a t_ref) con EVOL < thr: la nota ya ha arrancado (antes del KEY ON
// el slot esta en silencio con EVOL = 3FFh); -1 si no llega
function integer first_lt(input integer thr);
    integer k, r;
    begin
        r = -1;
        for (k = 0; k < ne && r < 0; k = k + 1)
            if (et[k] >= t_ref && ev[k] < thr) r = k;
        first_lt = r;
    end
endfunction

// EVOL en la ultima muestra anterior a t ms tras t_ref
function integer evol_at(input real tms);
    integer k, r;
    begin
        r = -1;
        for (k = 0; k < ne; k = k + 1)
            if (et[k] >= t_ref && (et[k] - t_ref) / 1.0e6 <= tms) r = ev[k];
        evol_at = r;
    end
endfunction

function real ms_of(input integer k);
    begin ms_of = (k >= 0) ? (et[k] - t_ref) / 1.0e6 : -1.0; end
endfunction

// ---- parametros de cada fase ----
reg [7:0] h8, h9, h10;              // bytes 8-10 de la cabecera: AR/D1R, DL/D2R, RC/RR
reg [3:0] oct;
reg       prvb, damp_off, es_damp, atk_test;
reg [7:0] key_on_v, key_off_v;      // valores de 68h al KEY ON y al KEY OFF
real      key_off_ms, fin_ms;       // KEY OFF a los N ms del KEY ON (0 = sin KEY OFF), y fin de la captura

integer k12, k48, k96, kc, a_ini, a_12, a_fin, e15, ec, ef, dlt, ka;
real    t12, t48, t96, tc, ta;
initial begin
    if (!$value$plusargs("fase=%d", fase)) fase = 1;
    // por defecto: AR=15, D1R=0, DL=0, D2R=0 (sostenida), RC=15, RR=2, octava 0
    h8 = 8'hF0; h9 = 8'h00; h10 = 8'hF2; oct = 4'h0; prvb = 0; damp_off = 0; es_damp = 1; atk_test = 0; key_on_v = 8'h80;
    key_off_ms = 5.0; fin_ms = 22.0;
    case (fase)
        1: begin damp_off = 1; end
        2: begin damp_off = 1; oct = 4'hC; h10 = 8'h02; end
        3: begin damp_off = 1; oct = 4'h3; h10 = 8'h52; end
        4: begin damp_off = 0; end
        5: begin damp_off = 0; oct = 4'h3; h10 = 8'h52; end
        6:  begin es_damp = 0; prvb = 1; h9 = 8'h0C; key_off_ms = 0; fin_ms = 42.0; end
        7:  begin es_damp = 0; prvb = 0; h9 = 8'h0C; key_off_ms = 0; fin_ms = 42.0; end
        8:  begin es_damp = 0; prvb = 1; h8 = 8'hFC; h9 = 8'hF0; key_off_ms = 0; fin_ms = 42.0; end
        9:  begin es_damp = 0; prvb = 1; h10 = 8'hFC; key_off_ms = 3.0; fin_ms = 45.0; end
        10: begin es_damp = 0; prvb = 1; oct = 4'h3; h9 = 8'h08; h10 = 8'h72; key_off_ms = 0; fin_ms = 38.0; end
        11: begin damp_off = 1; end
        12: begin es_damp = 0; atk_test = 1; h8 = 8'h90; oct = 4'h3; key_on_v = 8'hC0; key_off_ms = 0; fin_ms = 45.0; end
        default: begin $display("FAIL: fase %0d desconocida", fase); $finish; end
    endcase

    key_off_v = (fase == 11) ? 8'hC0 : damp_off ? 8'h40 : 8'h00;    // KEY OFF con DAMP, KEY ON + DAMP (fase 11) o sin DAMP

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
    wavemem[8]  = h8;
    wavemem[9]  = h9;
    wavemem[10] = h10;
    wavemem[11] = 8'h00;
    for (i = 0; i < 32; i = i + 1) wavemem[22'h100 + i] = 8'h7F;
    for (i = 32; i < 64; i = i + 1) wavemem[22'h100 + i] = 8'h81;

    #500  rst_n = 1;
    #1000 eng_rst_n = 1;
    #60000;                   // barrido de reset del motor (768 CE)

    outp(8'hC6, 8'h05);
    outp(8'hC7, 8'h03);       // NEW/NEW2
    wreg(8'h20, 8'h00);       // F-num low / WTN[8]=0
    wreg(8'h38, {oct, prvb, 3'b000});   // octava, PRVB (bit 3) y F-num alto = 0
    wreg(8'h50, 8'h01);       // TL=0, LD=1 (directo)
    wreg(8'h08, 8'h00);       // wave 0: dispara la carga del header
    i = 0;
    inp(8'hC4); inp(8'h7E);
    while (rdv[1] && i < 100) begin
        #10000; inp(8'hC4); inp(8'h7E); i = i + 1;
    end
    if (rdv[1]) begin $display("FAIL: LD no se limpia"); errors = errors + 1; end
    nc = 0; ne = 0; capt = 1;
    wreg(8'h68, key_on_v);    // KEY on, pan centro (con DAMP en la fase 12)
    t_ref = $realtime;
    $display("== fase %0d ==", fase);

    if (key_off_ms > 0) begin
        #(key_off_ms * 1.0e6);
        a_ini = maxabs(key_off_ms - 2.0, key_off_ms);
        wreg(8'h68, key_off_v);    // KEY OFF con DAMP, sin DAMP o (fase 11) KEY ON + DAMP
        t_ref = $realtime;
        #((fin_ms - key_off_ms) * 1.0e6);
    end else begin
        #(fin_ms * 1.0e6);
        a_ini = 0;
    end
    capt = 0;
    if (key_off_ms > 0) $display("  muestras de pcm = %0d, de EVOL = %0d; nivel antes del KEY OFF = %0d", nc, ne, a_ini);
    else                $display("  muestras de pcm = %0d, de EVOL = %0d", nc, ne);

    if (atk_test) begin
        // el ataque (AR=9, ~23,6 ms) no ve el DAMP; al acabar (EVOL = 0), la nota cae a -96 dB en 10,9 ms
        ka = first_lt(12'h001);
        ta = ms_of(ka);
        k96 = first_ge_from(ka, 12'h3FF);
        t96 = (k96 >= 0 && ka >= 0) ? ms_of(k96) - ta : -1.0;
        $display("  ataque con DAMP: EVOL llega a 0 a los %0.2f ms del KEY ON (esperado ~23,6); de ahi a 3FFh hay %0.2f ms (esperado 10,9)", ta, t96);
        if (!(ta >= 21.0 && ta <= 26.0))     begin $display("FAIL: el DAMP altera el ataque"); errors = errors + 1; end
        if (!(t96 >= 10.6 && t96 <= 11.2))   begin $display("FAIL: tras el ataque el DAMP no cae a -96 dB en 10,9 ms"); errors = errors + 1; end
    end else if (es_damp) begin
        if (a_ini < 3000) begin $display("FAIL: la nota no suena antes del KEY OFF"); errors = errors + 1; end
        if (damp_off) begin
            k12 = first_ge(12'h080); k48 = first_ge(12'h200); k96 = first_ge(12'h3FF);
            t12 = ms_of(k12); t48 = ms_of(k48); t96 = ms_of(k96);
            $display("  %s, RR=2: EVOL llega a -12 dB (080h) a los %0.2f ms, a -48 dB (200h) a los %0.2f ms, a -96 dB (3FFh) a los %0.2f ms (esperado 5,8 / 8,0 / 10,9)", (fase == 11) ? "KEY ON + DAMP" : "KEY OFF con DAMP", t12, t48, t96);
            if (!(t12 >= 5.6 && t12 <= 6.0))   begin $display("FAIL: -12 dB fuera de 5,6-6,0 ms");   errors = errors + 1; end
            if (!(t48 >= 7.8 && t48 <= 8.2))   begin $display("FAIL: -48 dB fuera de 7,8-8,2 ms");   errors = errors + 1; end
            if (!(t96 >= 10.6 && t96 <= 11.1)) begin $display("FAIL: -96 dB fuera de 10,6-11,1 ms"); errors = errors + 1; end
            // la salida de audio sigue a la envolvente: ~1/4 de amplitud a -12 dB y silencio tras -90 dB
            a_12  = (t12 >= 0) ? maxabs(t12, t12 + 0.1) : -1;
            a_fin = (t96 >= 0) ? maxabs(t96 + 0.1, 100.0) : -1;
            $display("  |pcm| a -12 dB = %0d (nivel inicial %0d, esperado ~1/4); tras -96 dB = %0d (silencio <= 30)", a_12, a_ini, a_fin);
            if (!(a_12 >= a_ini / 5 && a_12 <= a_ini * 3 / 10)) begin $display("FAIL: la salida no cae 12 dB a la vez que EVOL"); errors = errors + 1; end
            if (a_fin < 0 || a_fin > 30) begin $display("FAIL: no hay silencio tras -96 dB"); errors = errors + 1; end
        end else begin
            e15 = evol_at(15.0);
            a_fin = maxabs(14.0, 16.0);
            $display("  KEY OFF SIN DAMP, RR=2: EVOL a los 15 ms = %0d; |pcm| a los 14-16 ms = %0d (nivel inicial %0d)", e15, a_fin, a_ini);
            if (fase == 4 && !(e15 >= 0 && e15 <= 1)) begin $display("FAIL: la cola sin DAMP ya no es la de siempre (tasa 8: EVOL <= 1)"); errors = errors + 1; end
            if (fase == 5 && !(e15 >= 4 && e15 <= 6)) begin $display("FAIL: sin DAMP se pierde la correccion de tasa (tasa 24: EVOL = 4..6)"); errors = errors + 1; end
            if (a_fin * 100 < a_ini * 90) begin $display("FAIL: la nota cae sin DAMP"); errors = errors + 1; end
        end
    end else begin
        // PRVB: tiempo hasta -18 dB (0C0h) y subida de EVOL en las 1300 muestras siguientes (29,5 ms)
        kc = first_ge_from(first_lt(12'h040), 12'h0C0);
        tc = ms_of(kc);
        if (kc < 0 || kc + 1300 >= ne) begin
            $display("FAIL: EVOL no llega a -18 dB (0C0h) o la captura es corta (kc=%0d, ne=%0d)", kc, ne); errors = errors + 1;
        end else begin
            ec = ev[kc]; ef = ev[kc + 1300]; dlt = ef - ec;
            $display("  EVOL llega a -18 dB (0C0h) a los %0.2f ms (EVOL=%0d); 1300 muestras (29,5 ms) despues EVOL=%0d (sube %0d)", tc, ec, ef, dlt);
            if (fase == 10) begin
                if (!(tc >= 4.0 && tc <= 4.7)) begin $display("FAIL: sin PRVB la tasa corregida (52) cruza -18 dB a los 4,35 ms"); errors = errors + 1; end
            end else begin
                if (!(tc >= 8.4 && tc <= 9.0)) begin $display("FAIL: a tasa 48 se cruza -18 dB a los 8,7 ms"); errors = errors + 1; end
            end
            if (prvb) begin
                // tasa 20: un +1 cada 256 muestras exactas (paso cada 128 con incrementos 0,1,0,1...)
                if (!(dlt >= 4 && dlt <= 7)) begin $display("FAIL: con PRVB la caida tras -18 dB debe ser de ~5 unidades (tasa 20)"); errors = errors + 1; end
                $display("  ... bajo PRVB tasa 20: 1 unidad cada 256 muestras = %0d en 1300 (esperado 5-6)", dlt);
            end else begin
                if (!(dlt >= 500)) begin $display("FAIL: sin PRVB la caida debe seguir a 0,5 unidades por muestra (>= 500 en 1300)"); errors = errors + 1; end
                $display("  ... sin PRVB sigue a tasa 48: %0d unidades en 1300 (esperado ~650)", dlt);
            end
        end
    end

    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #100000000;               // 100 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
