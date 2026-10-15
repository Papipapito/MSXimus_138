// ============================================================================
// tb_memmode.v — modo de acceso a memoria (reg 02h bit 0) del motor PCM OPL4 (15/10/2026)
//
// El manual del YMF278B (reg 02h) dice: "All the channels can not generate the sound in this mode". Hasta hoy el motor seguia sumando los
// slots con el WD congelado (MEM_D no cambia sin lecturas de ondas): la salida era un continuo de ~1700 con un chasquido al entrar y otro al
// salir. Ahora la muestra que sale vale 0 mientras dura el modo (y 2 muestras mas despues, que es lo que tardan en renovarse los datos);
// las envolventes y las fases siguen corriendo, asi que al volver a 0 la musica reanuda donde toca.
//
// Ojo: el pegamento (opl4_pcm.v) saca las muestras del motor por un FIFO de 16 con ~8 muestras de colchon (~0,2 ms): lo que el motor
// calla en el instante t se oye en pcm_l ~9 muestras despues, por eso las medidas empiezan 0,4 ms tras el OUT y los indices de las
// muestras mudas van desplazados ~9 respecto a los del OUT.
// Dos slots con una onda cuadrada sintetica de 8 bits (+-127, como tb_tl.v: no hace falta la YRW801), KEY ON (TL 0 y TL 8). A los 20 ms:
//  +mode=1  CONTROL: el mismo trafico de OUT 03h-06h SIN entrar en modo memoria (el chip lo ignora): la musica sigue igual.
//  +mode=2  OUT 02h = 11h (modo memoria, bits 4:2 como estaban), +nbytes bytes pseudoaleatorios a la RAM de ondas por 03h/04h/05h/06h
//           (0x200000...), OUT 02h = 10h. Comprueba: durante la carga pcm_l vale 0 EXACTO; antes y despues suena (nivel de ANTES); los bytes
//           llegaron a la RAM; el modo esta activo en el motor mientras dura.
//  +mode=3  PULSO CORTO: OUT 02h = 11h y 02h = 10h seguidos (~12 us, menos que una muestra de salida).
//  +dump=fichero  escribe "indice valor" de cada muestra de pcm_l (primera linea "# ent=k sal=k"); run_memmode.sh compara las tres pasadas:
//           toda muestra de las pasadas 2 y 3 es 0 o es IGUAL a la del control en el mismo indice (ni DC ni datos rancios), las muestras mudas
//           son las del modo mas 2, y se mide el salto de entrada y de salida.
// Ejecutar: cd tools/opl4wave_sim && ./run_memmode.sh [motor.v]
// ============================================================================
`timescale 1ns/1ps

module tb_memmode;

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
integer    n_rd = 0, n_wr = 0;
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
            if (p_we) begin wavemem[p_addr] <= p_dat; n_wr = n_wr + 1; end
            else begin
                mem_rdata <= wavemem[p_addr];
                mem_rword[7:0]  <= wavemem[{p_addr[21:1], 1'b0}];
                mem_rword[15:8] <= wavemem[{p_addr[21:1], 1'b1}];
                n_rd = n_rd + 1;
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

// ---- captura del pcm_l (una muestra por cambio de pcm_h3) ----
localparam MAXN = 4000;
integer sv [0:MAXN-1];
real    st [0:MAXN-1];
integer NS = 0;
reg     pcm_seen = 0;
always @(posedge clk_host) begin
    pcm_seen <= dut.pcm_h3;
    if (dut.pcm_h3 !== pcm_seen && NS < MAXN) begin
        sv[NS] = pcm_l;
        st[NS] = $realtime;
        NS = NS + 1;
    end
end

// ---- estadisticas de las muestras con t0 <= t < t1 ----
integer errors = 0;
integer k, nn, nz, vmax, vmin;
real    ssq, rms;
task stats(input real t0, input real t1, input [95:0] nm);
begin
    nn = 0; nz = 0; ssq = 0; vmax = -99999; vmin = 99999;
    for (k = 0; k < NS; k = k + 1) if (st[k] >= t0 && st[k] < t1) begin
        nn = nn + 1; ssq = ssq + 1.0 * sv[k] * sv[k];
        if (sv[k] != 0) nz = nz + 1;
        if (sv[k] > vmax) vmax = sv[k];
        if (sv[k] < vmin) vmin = sv[k];
    end
    rms = (nn > 0) ? $sqrt(ssq / nn) : 0.0;
    if (nn == 0) begin vmax = 0; vmin = 0; end
    $display("  %-8s n=%5d muestras (%0d no nulas)  rms=%8.1f  max=%6d  min=%6d", nm, nn, nz, rms, vmax, vmin);
end
endtask

task check(input integer cond, input [1023:0] msg);
begin
    if (!cond) begin $display("FAIL: %0s", msg); errors = errors + 1; end
end
endtask

integer i, ldn, mode, nbytes, k0, k1, fd, nbad;
integer seed = 32'h1badf00d;
reg [7:0] byt;
reg [7:0] bv [0:8191];
real t_key, t_mem0, t_mem1;
real rms_antes, rms_despues;
reg [1023:0] dumpf;
integer have_dump;

task setslot(input integer s, input [9:0] fnum, input [3:0] oct, input [7:0] tlreg);
begin
    wreg(8'h20 + s, {fnum[6:0], 1'b0});        // F-num low / WTN[8]=0
    wreg(8'h38 + s, {oct, 1'b0, fnum[9:7]});
    wreg(8'h50 + s, tlreg);                    // TL, LD = 1
    wreg(8'h08 + s, 8'h00);                    // onda 0: dispara la carga de la cabecera
    ldn = 0; inp(8'hC4); inp(8'h7E);
    while (rdv[1] && ldn < 400) begin #10000; inp(8'hC4); inp(8'h7E); ldn = ldn + 1; end
    if (rdv[1]) begin $display("FAIL: LD no se limpia (slot %0d)", s); errors = errors + 1; end
end
endtask

initial begin
    if (!$value$plusargs("mode=%d", mode)) mode = 2;
    if (!$value$plusargs("nbytes=%d", nbytes)) nbytes = 1024;
    have_dump = $value$plusargs("dump=%s", dumpf);
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
    outp(8'hC6, 8'h05);
    outp(8'hC7, 8'h03);       // NEW/NEW2
    wreg(8'h02, 8'h10);       // wavetblhdr = 4 (bits 4:2 = 100), bit 0 = 0: como deja el driver del DMV
    setslot(0, 10'h000, 4'd2, 8'h01);         // TL = 0 (nivel pleno), octava 2 (16 muestras por periodo)
    setslot(1, 10'h155, 4'd3, 8'h11);         // octava 3, TL = 8 (-3 dB): la suma de las dos cuadradas no se anula nunca
    wreg(8'h68, 8'h80);       // KEY ON los dos, pan centro
    wreg(8'h69, 8'h80);
    t_key = $realtime;
    $display("== modo=%0d nbytes=%0d : KEY ON de dos slots a t=%0.3f ms ==", mode, nbytes, t_key / 1.0e6);
    #(20.0e6 - ($realtime - t_key));            // a los 20 ms
    t_mem0 = $realtime; k0 = NS;
    if (mode == 2) wreg(8'h02, 8'h11);          // modo memoria: bit 0 = 1, bits 4:2 como estaban
    if (mode == 3) begin wreg(8'h02, 8'h11); wreg(8'h02, 8'h10); end
    if (mode == 1 || mode == 2) begin
        wreg(8'h03, 8'h20); wreg(8'h04, 8'h00); wreg(8'h05, 8'h00);     // direccion 0x200000
        for (i = 0; i < nbytes; i = i + 1) begin
            byt = $random(seed);
            bv[i] = byt;
            wreg(8'h06, byt);
        end
    end
    if (mode == 2) begin
        check(dut.u_engine.MEMMODE[0] === 1'b1, "el motor no esta en modo memoria al acabar la carga");
    end
    t_mem1 = $realtime; k1 = NS;
    if (mode == 2) wreg(8'h02, 8'h10);          // bit 0 = 0
    #15.0e6;

    $display("  carga de %0.3f ms (t=+%0.3f ms .. +%0.3f ms); escrituras a la RAM de ondas: %0d; lecturas de ondas del motor: %0d",
             (t_mem1 - t_mem0) / 1.0e6, (t_mem0 - t_key) / 1.0e6, (t_mem1 - t_key) / 1.0e6, n_wr, n_rd);
    stats(t_key + 14.0e6, t_key + 19.5e6, "ANTES");
    rms_antes = rms;
    check(rms_antes > 1000.0 && vmax > 4000, "la musica de ANTES no suena");
    if (mode == 2) begin
        stats(t_mem0 + 0.4e6, t_mem1, "DURANTE");
        check(nn > 100, "pocas muestras durante la carga");
        check(nz == 0, "durante el modo memoria la salida no es 0 exacto");
        nbad = 0;
        for (i = 0; i < nbytes; i = i + 1) if (wavemem[22'h200000 + i] !== bv[i]) nbad = nbad + 1;
        $display("  bytes de la carga que llegaron a la RAM de ondas: %0d de %0d", nbytes - nbad, nbytes);
        check(nbad == 0, "la carga por 03h-06h no llego entera a la RAM de ondas");
        check(n_wr == nbytes, "numero de escrituras a la RAM distinto del de bytes enviados");
    end
    if (mode == 1) begin
        stats(t_mem0 + 0.4e6, t_mem1, "DURANTE");
        check(rms > 1000.0, "control: la musica deberia seguir sonando durante el trafico");
        check(n_wr == 0, "control: sin modo memoria el chip no debe escribir en la RAM de ondas");
    end
    stats(t_mem1 + 3.0e6, t_mem1 + 13.0e6, "DESPUES");
    rms_despues = rms;
    check(rms_despues > 1000.0 && vmax > 4000, "la musica de DESPUES no suena");
    $display("  rms ANTES %0.1f, rms DESPUES %0.1f", rms_antes, rms_despues);

    if (have_dump) begin
        fd = $fopen(dumpf, "w");
        $fdisplay(fd, "# ent=%0d sal=%0d", k0, k1);
        for (k = 0; k < NS; k = k + 1) $fdisplay(fd, "%0d %0d", k, sv[k]);
        $fclose(fd);
    end
    if (errors == 0) $display("*** TODOS LOS TESTS PASAN ***");
    else             $display("*** %0d ERRORES ***", errors);
    $finish;
end

initial begin
    #120000000;               // 120 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
