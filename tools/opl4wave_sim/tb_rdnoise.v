// ============================================================================
// tb_rdnoise.v — UNA NOTA SONANDO NO PUEDE CAMBIAR POR QUE LA CPU LEA UN REGISTRO POR 7Fh (15/10/2026)
//
// Caso de uso real (traza de openMSX de "Dutch Moonsound Veterans HDD", 15/10/2026): mientras suena la musica, el
// reproductor MoonBlaster Wave RELEE por 7Fh los registros 68h-7Fh (KEY/PAN, lectura-modificacion-escritura); un cargador
// que verifique la RAM de muestras leeria 06h (MEMDAT), que es un caso mas. Con el RTL de la Z1.2.8 cada lectura llevaba
// la direccion de la CPU a las RAM de FNUM y de LFO aunque el registro no fuese suyo (REG_RD ? ... sin su SEL): el motor
// cargaba el OCT/FNUM/PRVB de OTRO slot en un CYCLE0_CE, la fase de la nota saltaba y la salida sonaba a ruido mientras
// durasen las lecturas.
//
// QUE HACE: 6 voces (slots 0-5, onda cuadrada de 8 bits, F-number y octava distintos en cada una) mas 18 slots sin sonar con
// F-number y octava muy distintos (los valores que quedan de otra cancion: son los que se cuelan). Se vuelca pcm_l UNA VEZ POR
// MUESTRA (indexada por el contador de muestras SCNT del motor, asi dos corridas son comparables aunque la DDR3 falsa tarde
// distinto) durante 12 ms, con la CPU releyendo sin parar el registro +reg (hex) por 7Fh, o sin leer nada (+modo=0). run_rdnoise.sh
// compara los volcados contra el de modo 0: tienen que ser IDENTICOS para todo registro que no sea de las RAM de FNUM/LFO.
//
// +out=ruta : fichero del volcado ("indice_de_muestra pcm_l" por linea); +reg=XX ; +modo=0|1
// Ejecutar: cd tools/opl4wave_sim && ./run_rdnoise.sh   (con un .v distinto del motor como argumento: control negativo)
// ============================================================================
`timescale 1ns/1ps

module tb_rdnoise;

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

// ---- volcado de pcm_l una vez por muestra, indexado por SCNT ----
integer fd, nrd = 0, nmu = 0, scnt0;
reg     capt = 0;
always @(posedge clk_eng) begin
    if (capt && dut.u_engine.SLOT1_CE && dut.u_engine.SLOT == 5'd23) begin
        // fin del ultimo slot de la muestra (una vez por muestra)
        $fdisplay(fd, "%0d %0d", dut.u_engine.SCNT - scnt0, pcm_l);
        nmu = nmu + 1;
    end
end

integer s, modo, rg;
reg [1023:0] ruta;
real t0;
initial begin
    if (!$value$plusargs("modo=%d", modo)) modo = 0;
    if (!$value$plusargs("reg=%h", rg)) rg = 8'h06;
    if (!$value$plusargs("out=%s", ruta)) ruta = "rdnoise.txt";
    fd = $fopen(ruta, "w");
    for (s = 0; s < 4194304; s = s + 1) wavemem[s] = 8'h00;
    // onda 0: cuadrada de 8 bits +-127, 64 muestras en bucle, ataque instantaneo, sin LFO, RR=15
    wavemem[0] = 8'h00; wavemem[1] = 8'h01; wavemem[2] = 8'h00;
    wavemem[3] = 8'h00; wavemem[4] = 8'h00;
    wavemem[5] = 8'hFF; wavemem[6] = 8'hC0;
    wavemem[7] = 8'h00; wavemem[8] = 8'hF0; wavemem[9] = 8'h00; wavemem[10] = 8'hFF; wavemem[11] = 8'h00;
    for (s = 0; s < 32; s = s + 1) wavemem[22'h100 + s] = 8'h7F;
    for (s = 32; s < 64; s = s + 1) wavemem[22'h100 + s] = 8'h81;

    #500 rst_n = 1; #1000 eng_rst_n = 1; #60000;
    outp(8'hC6, 8'h05); outp(8'hC7, 8'h03);

    // 18 slots que no suenan, con F-number y octava muy distintos de los de las voces (lo que dejo otra cancion)
    for (s = 6; s < 24; s = s + 1) begin
        wreg(8'h20 + s, 8'h5A + 8'h0B * s);
        wreg(8'h38 + s, ((s % 2) ? 8'h08 : 8'h00) | (s[2:0] << 4) | (s[1:0] + 8'd1));   // OCT distinta, PRVB en los impares
        wreg(8'h50 + s, 8'hFF);
    end
    // 6 voces: octava y F-number distintos, onda 0, KEY ON
    for (s = 0; s < 6; s = s + 1) begin
        wreg(8'h20 + s, 8'h10 * s + 8'h30);
        wreg(8'h38 + s, (s[2:0] << 4) | (s[1:0] + 8'd1));
        wreg(8'h50 + s, 8'h01);
        wreg(8'h08 + s, 8'h00); waitld;
    end
    for (s = 0; s < 6; s = s + 1) wreg(8'h68 + s, 8'h80);

    #4000000;                                           // 4 ms de calentamiento
    scnt0 = dut.u_engine.SCNT;
    capt = 1;
    t0 = $realtime;
    if (modo == 1) begin
        outp(8'h7E, rg);
        while ($realtime - t0 < 12.0e6) begin inp(8'h7F); nrd = nrd + 1; end
    end else
        #12000000;
    capt = 0;
    $fclose(fd);
    $display("modo=%0d reg=%h lecturas=%0d muestras volcadas=%0d", modo, rg, nrd, nmu);
    $finish;
end

initial begin
    #80000000;                // 80 ms
    $display("FAIL: timeout global");
    $finish;
end

endmodule
