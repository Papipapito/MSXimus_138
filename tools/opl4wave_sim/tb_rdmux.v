// ============================================================================
// tb_rdmux.v — LA LECTURA POR 7Fh DE UN REGISTRO NO PUEDE TOCAR LAS RAM DE OTROS (15/10/2026)
//
// Banco del revisor de la Z1.2.8 (tb_rev_prd.v), con su criterio de aceptacion. Los 24 slots suenan con PRVB (38h+slot bit 3)
// en los pares, RR=15 (tasa 63) y KEY OFF a la vez: la cola cruza -18 dB (EVOL 0C0h) en menos de 1 ms y desde ahi cae a la
// tasa 20 del pseudo-reverb (+1 de EVOL cada 256 muestras), de modo que a los 45 ms del KEY OFF las 12 colas valen 199
// (unidad de EVOL: 3/32 dB). Mientras se miden los ultimos 40 ms, la CPU puede releer SIN PARAR el registro +reg por 7Fh
// (+modo=1; +modo=0 no lee nada). Si el puerto de lectura de la RAM de FNUM (o de LFO) se le da a la CPU aunque el registro
// leido no sea suyo (REG_RD ? ... sin su SEL), OP1/OP4 cargan OCT/FNUM9/PRVB de OTRO slot y la cola pierde el PRVB:
// con el RTL de la Z1.2.8, +reg=03, 50 o 70 dejaban las colas en 471..560 (29 dB de mas).
//  Aceptacion: las 12 colas entre 196 y 203. +info=1 solo imprime (para registros que SI son de esas RAM: 38h-4Fh, 20h-37h,
//  80h-97h; releer el FNUM alto de OTRO slot sin PRVB, p.ej. 39h, sigue quitando el PRVB mientras dura REG_RD, porque ese
//  registro comparte el puerto con el motor).
// Ejecutar: cd tools/opl4wave_sim && ./run_rdmux.sh   (con un .v distinto del motor como argumento: control negativo)
// ============================================================================
`timescale 1ns/1ps
module tb_rdmux;
reg clk_x1 = 0;  always #6.734 clk_x1 = ~clk_x1;
reg clk_eng = 0; always #13.333 clk_eng = ~clk_eng;
reg clk_host = 0; always #9.26 clk_host = ~clk_host;
reg rst_n = 0, eng_rst_n = 0;
reg iorq_n = 1, rd_n = 1, wr_n = 1, m1_n = 1;
reg [7:0] a = 0, din = 0;
wire wave_rd; wire [7:0] wave_dout; wire wave_wait_n; wire [1:0] wave_status;
wire signed [15:0] pcm_l, pcm_r;
wire mem_req, mem_we; wire [21:0] mem_addr; wire [7:0] mem_wdata;
reg [7:0] mem_rdata = 0; reg [15:0] mem_rword = 0; reg mem_done_t = 0;
opl4_pcm dut (.rst_n(rst_n), .clk_host(clk_host), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .m1_n(m1_n),
    .addr(a), .din(din), .wave_rd(wave_rd), .wave_dout(wave_dout), .wave_wait_n(wave_wait_n), .wave_status(wave_status),
    .pcm_l(pcm_l), .pcm_r(pcm_r), .clk_eng(clk_eng), .eng_rst_n(eng_rst_n),
    .mem_req(mem_req), .mem_we(mem_we), .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_rdata(mem_rdata),
    .mem_rword(mem_rword), .mem_done_t(mem_done_t), .vid_diag(4'd0));
reg [7:0] wavemem [0:4194303];
reg p_pend = 0, p_we; reg [21:0] p_addr; reg [7:0] p_dat; reg [5:0] p_cnt, p_lat; reg mem_req_d = 0;
always @(posedge clk_x1) begin
    mem_req_d <= mem_req;
    if (mem_req && !mem_req_d) begin p_pend <= 1; p_we <= mem_we; p_addr <= mem_addr; p_dat <= mem_wdata; p_cnt <= 0; p_lat <= 6'd20 + ({$random} % 5); end
    else if (p_pend) begin
        p_cnt <= p_cnt + 1;
        if (p_cnt == p_lat) begin
            if (p_we) wavemem[p_addr] <= p_dat;
            else begin mem_rdata <= wavemem[p_addr]; mem_rword[7:0] <= wavemem[{p_addr[21:1],1'b0}]; mem_rword[15:8] <= wavemem[{p_addr[21:1],1'b1}]; end
            mem_done_t <= ~mem_done_t; p_pend <= 0;
        end
    end
end
task outp(input [7:0] p, input [7:0] v); begin @(negedge clk_host); a = p; din = v; iorq_n = 0; wr_n = 0; #420; @(negedge clk_host); wr_n = 1; iorq_n = 1; #2500; end endtask
reg [7:0] rdv;
task inp(input [7:0] p); begin @(negedge clk_host); a = p; iorq_n = 0; rd_n = 0; #460; while (!wave_wait_n) @(posedge clk_host); #5; rdv = wave_dout; #80; @(negedge clk_host); rd_n = 1; iorq_n = 1; #1500; end endtask
task wreg(input [7:0] r, input [7:0] v); begin outp(8'h7E, r); outp(8'h7F, v); end endtask
task waitld; integer q; begin q = 0; inp(8'hC4); inp(8'h7E); while (rdv[1] && q < 100) begin #10000; inp(8'hC4); inp(8'h7E); q = q + 1; end if (rdv[1]) $display("FAIL LD"); end endtask
localparam MAXN = 2400;
integer ev [0:24*MAXN-1]; real et [0:24*MAXN-1]; integer ne [0:23];
reg capt = 0; integer s5;
always @(posedge clk_eng) begin
    s5 = dut.u_engine.OP5[41:37];
    if (dut.u_engine.SLOT1_CE && capt && ne[s5] < MAXN) begin
        ev[s5*MAXN + ne[s5]] = dut.u_engine.OP5[17:8]; et[s5*MAXN + ne[s5]] = $realtime; ne[s5] = ne[s5] + 1;
    end
end
function integer first_ge(input integer s, input real t0, input integer thr);
    integer k, r; begin r = -1; for (k = 0; k < ne[s] && r < 0; k = k + 1) if (et[s*MAXN+k] >= t0 && ev[s*MAXN+k] >= thr) r = k; first_ge = r; end
endfunction
function integer first_le(input integer s, input real t0, input integer thr);
    integer k, r; begin r = -1; for (k = 0; k < ne[s] && r < 0; k = k + 1) if (et[s*MAXN+k] >= t0 && ev[s*MAXN+k] <= thr) r = k; first_le = r; end
endfunction
function integer evol_at(input integer s, input real t);
    integer k, r; begin r = -1; for (k = 0; k < ne[s]; k = k + 1) if (et[s*MAXN+k] <= t) r = ev[s*MAXN+k]; evol_at = r; end
endfunction
integer i, s, nrd = 0, tot = 0, mx = 0, mn = 9999, e, modo, rg, info, errors = 0;
real t0;
initial begin
    if (!$value$plusargs("modo=%d", modo)) modo = 0;
    if (!$value$plusargs("reg=%h", rg)) rg = 8'h50;
    if (!$value$plusargs("info=%d", info)) info = 0;
    for (i = 0; i < 24; i = i + 1) ne[i] = 0;
    for (i = 0; i < 4194304; i = i + 1) wavemem[i] = 8'h00;
    wavemem[0] = 8'h00; wavemem[1] = 8'h01; wavemem[2] = 8'h00; wavemem[3] = 8'h00; wavemem[4] = 8'h00; wavemem[5] = 8'hFF; wavemem[6] = 8'hC0;
    wavemem[7] = 8'h00; wavemem[8] = 8'hF0; wavemem[9] = 8'h00; wavemem[10] = 8'hFF; wavemem[11] = 8'h00;
    for (i = 0; i < 32; i = i + 1) wavemem[22'h100 + i] = 8'h7F;
    for (i = 32; i < 64; i = i + 1) wavemem[22'h100 + i] = 8'h81;
    #500 rst_n = 1; #1000 eng_rst_n = 1; #60000;
    outp(8'hC6, 8'h05); outp(8'hC7, 8'h03);
    for (s = 0; s < 24; s = s + 1) begin
        wreg(8'h20 + s, 8'h00); wreg(8'h38 + s, (s % 2 == 0) ? 8'h08 : 8'h00); wreg(8'h50 + s, 8'h01); wreg(8'h08 + s, 8'h00); waitld; end
    for (s = 0; s < 24; s = s + 1) wreg(8'h68 + s, 8'h80);
    #1000000;
    for (s = 0; s < 24; s = s + 1) wreg(8'h68 + s, 8'h00);   // KEY OFF, RR=15: tasa 63 hasta -18 dB y luego PRVB (pares)
    #5000000;
    outp(8'h7E, rg);
    capt = 1; t0 = $realtime;
    if (modo == 1) begin while ($realtime - t0 < 40.0e6) begin inp(8'h7F); nrd = nrd + 1; end end
    else #40000000;
    capt = 0;
    for (s = 0; s < 24; s = s + 2) begin e = evol_at(s, $realtime); tot = tot + e; if (e > mx) mx = e; if (e < mn) mn = e; end
    $display("modo=%0d reg=%h lecturas=%0d; EVOL de las 12 colas con PRVB al cabo de 40 ms: min=%0d max=%0d media=%0d (esperado 196..203)", modo, rg, nrd, mn, mx, tot/12);
    for (s = 0; s < 24; s = s + 2) $write("%0d:%0d ", s, evol_at(s, $realtime)); $display("");
    if (!info) begin
        if (mn < 196 || mx > 203) begin $display("FAIL: las colas con PRVB han perdido el pseudo-reverb (EVOL fuera de 196..203)"); errors = errors + 1; end
        if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
        else             $display("*** %0d ERRORES ***", errors);
    end
    $finish;
end
initial begin #200000000; $display("FAIL timeout"); $finish; end
endmodule
