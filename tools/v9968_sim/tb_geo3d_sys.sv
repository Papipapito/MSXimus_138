// ============================================================================
// tb_geo3d_sys.sv — tb_geo3d_int + el lado del Z80 entero: es tb_geo3d_int (glue + geo3d_bus + vdp completo con VRAM
// perfecta) con las operaciones del estimulo "de sistema" que graba tools/geo3d_demo/run_kanon_rom.py de una ROM:
//   V reg val  registro del VDP (por 99h, como haria el Z80; R#32-58 = comandos propios del Z80: HMMM, LRMM)
//   C          esperar CE = 0 (S#2 por 99h)
//   X addr b   byte de VRAM por 98h (la direccion se pone por R#14 + 99h solo cuando no es la siguiente)
//   A i r g b  entrada de paleta por 9Ah (R#16)
//   D y0       volcar la pagina que se acaba de mostrar (212 x 128 bytes desde la linea y0) a +frames=
// y las de siempre (W sel b / R / K / F n). Salida +got= identica a tb_geo3d_int (L/M/K/F) para el diff con el
// modelo de Alex. Se corre con run_geo3d_sys_vl.sh. 29/09/2026.
// Origen: tb_geo3d_int.sv (27/09), el enganche de top_zynq.v reproducido pieza a pieza:
//   Z80 (tareas) -> v9968_cpu_glue (csw_n/csr_n, mode 1 = 99h, 4 = 9Ch, 5 = 9Dh, 7 = 9Fh)
//              -> bus valid/ready -> { geo3d_bus (hit en mode 5/7) | vdp completo (VRAM perfecta) }
//   geo3d_bus.cmd_* -> vdp.ext_cmd_* (LINE/LRMM en vdp_command con CE = 0)
// Estimulo = el de sim/tb_bus.v de geo3d (gen_scenes.py: W sel byte / R = esperar RUN / K = contadores / F = cuadro);
// salida = mismo registro (L/M/K/F) para diff con scenes_expect.txt. Ademas cuenta escrituras de comando con CE = 1
// (violaciones) y comprueba que el VDP sigue respondiendo (S#0 por 99h) despues de cada cuadro.
// Se corre con run_geo3d_int_vl.sh (verilado con --timing). 27/09/2026.
// 138K (18/10/2026): copia del banco de la Zynq con el enganche de top.v del 138K bajo +define+GEO3D_CE (el motor a
// clk con el clock enable 1/2 de cinco replicas y el reset local de una etapa, como tb_geo3d_int.sv); sin el define,
// el de la Zynq (motor a clk_43 = clk/2 en fase). +maxpoll=N cambia el tope de sondeos de RUN (400000).
// ============================================================================
`timescale 1ns/1ps
module tb_geo3d_sys;
    localparam real CLK_HALF = 5.8207;
    logic clk = 0, clk_43 = 0, rst_n = 0;
    always #(CLK_HALF) clk = ~clk;
    always @(posedge clk) clk_43 <= ~clk_43;          // /2 en fase, como CLKOUT1 de la PLL

    // ---- lado Z80 del glue ----
    logic       csw_n = 1, csr_n = 1;
    logic [2:0] mode = 0;
    logic [7:0] cdo = 0;
    wire  [7:0] cdi_r;
    wire        wait_n;
    // ---- bus valid/ready ----
    wire  [2:0] b_addr;
    wire        b_ioreq, b_write, b_valid, b_ready;
    wire  [7:0] b_wdata, b_rdata;
    wire        b_rdata_en;
    v9968_cpu_glue u_glue (
        .clk_86(clk), .rst_n(rst_n), .csw_n(csw_n), .csr_n(csr_n), .mode(mode), .cdo(cdo), .cdi_r(cdi_r),
        .wait_n(wait_n), .bus_address(b_addr), .bus_ioreq(b_ioreq), .bus_write(b_write), .bus_valid(b_valid),
        .bus_ready(b_ready), .bus_wdata(b_wdata), .bus_rdata(b_rdata), .bus_rdata_en(b_rdata_en)
    );

    // ---- geo3d ----
    wire       geo_hit, geo_ready, geo_rdata_en, geo_busy, geo_cmd_wr, geo_cmd_ce;
    wire [7:0] geo_rdata, geo_cmd_data;
    wire [5:0] geo_cmd_num;
`ifdef GEO3D_CE
    // el generador de top.v (138K): toggle maestro + cinco replicas que cargan ~geo_ce_m, y el reset local.
    // +define+GEO3D_CE_FASE_B arranca el toggle en la otra fase (la fase del CE frente al bus no esta fijada).
`ifdef GEO3D_CE_FASE_B
    logic       geo_ce_m = 1'b1;
    logic [4:0] geo_ce   = 5'h1F;
`else
    logic       geo_ce_m = 1'b0;
    logic [4:0] geo_ce   = 5'd0;
`endif
    logic       geo_rst_n = 1'b0;
    always @(posedge clk) begin
        geo_ce_m  <= ~geo_ce_m;
        geo_ce    <= {5{~geo_ce_m}};
        geo_rst_n <= rst_n;
    end
    geo3d_bus u_geo3d (
        .clk(clk), .clk_eng(clk), .ce_eng(geo_ce), .reset_n(geo_rst_n),
`else
    geo3d_bus u_geo3d (
        .clk(clk), .clk_eng(clk_43), .reset_n(rst_n),
`endif
        .bus_address(b_addr), .bus_ioreq(b_ioreq), .bus_write(b_write), .bus_valid(b_valid), .bus_wdata(b_wdata),
        .hit(geo_hit), .bus_ready(geo_ready), .bus_rdata(geo_rdata), .bus_rdata_en(geo_rdata_en),
        .cmd_wr(geo_cmd_wr), .cmd_num(geo_cmd_num), .cmd_data(geo_cmd_data), .cmd_ce(geo_cmd_ce), .run_busy(geo_busy)
    );
    // ---- el mux de top_zynq.v ----
    wire       v_ready, v_rdata_en;
    wire [7:0] v_rdata;
    wire       v_valid = b_valid & ~geo_hit;
    assign b_ready    = geo_hit ? geo_ready : v_ready;
    assign b_rdata    = geo_rdata_en ? geo_rdata : v_rdata;
    assign b_rdata_en = geo_rdata_en | v_rdata_en;

    // ---- VDP completo con VRAM perfecta (como la pila B de tb_sc8cmd) ----
    wire         v_int_n, v_vwrite, v_vvalid, v_vrefresh, v_hs, v_vs, v_en;
    wire  [17:2] v_vaddr;
    wire  [31:0] v_vwdata;
    wire  [3:0]  v_vmask;
    wire  [4:0]  v_vtag;
    wire  [7:0]  v_r, v_g, v_b;
    logic [31:0] v_vrdata_r = 0;
    logic        v_vrdata_en_r = 0;
    logic [4:0]  v_vrtag_r = 0;
    vdp u_vdp (
        .reset_n(rst_n), .clk(clk), .initial_busy(1'b0),
        .bus_address(b_addr), .bus_ioreq(b_ioreq), .bus_write(b_write),
        .bus_valid(v_valid), .bus_ready(v_ready),
        .bus_wdata(b_wdata), .bus_rdata(v_rdata), .bus_rdata_en(v_rdata_en),
        .int_n(v_int_n),
        .vram_address(v_vaddr), .vram_write(v_vwrite), .vram_valid(v_vvalid), .vram_wdata(v_vwdata),
        .vram_wdata_mask(v_vmask), .vram_rdata(v_vrdata_r), .vram_rdata_en(v_vrdata_en_r),
        .vram_tag(v_vtag), .vram_rtag(v_vrtag_r), .vram_stall(1'b0), .vram_refresh(v_vrefresh),
        .display_hs(v_hs), .display_vs(v_vs), .display_en(v_en), .display_r(v_r), .display_g(v_g), .display_b(v_b),
        .force_highspeed(1'b0), .button(2'b00),
        .ext_cmd_wr(geo_cmd_wr), .ext_cmd_num(geo_cmd_num), .ext_cmd_data(geo_cmd_data), .ext_cmd_ce(geo_cmd_ce),
        .pulse0(), .pulse1(), .pulse2(), .pulse3(), .pulse4(), .pulse5(), .pulse6(), .pulse7()
    );
    logic [31:0] vram_mem [0:65535];
    logic [15:0] p_addr;
    logic [4:0]  p_tag;
    logic [2:0]  p_cnt = 0;
    logic        p_pend = 0;
    always @(posedge clk) begin
        v_vrdata_en_r <= 1'b0;
        if (v_vvalid && v_vwrite) begin
            if (!v_vmask[0]) vram_mem[v_vaddr][ 7: 0] <= v_vwdata[ 7: 0];
            if (!v_vmask[1]) vram_mem[v_vaddr][15: 8] <= v_vwdata[15: 8];
            if (!v_vmask[2]) vram_mem[v_vaddr][23:16] <= v_vwdata[23:16];
            if (!v_vmask[3]) vram_mem[v_vaddr][31:24] <= v_vwdata[31:24];
        end
        else if (v_vvalid && !v_vwrite && !p_pend) begin
            p_pend <= 1'b1; p_addr <= v_vaddr; p_tag <= v_vtag; p_cnt <= 0;
        end
        else if (p_pend) begin
            p_cnt <= p_cnt + 1;
            if (p_cnt == 6) begin
                v_vrdata_r <= vram_mem[p_addr]; v_vrtag_r <= p_tag; v_vrdata_en_r <= 1'b1; p_pend <= 1'b0;
            end
        end
    end

    // ---- registro de los comandos que geo3d mete en el VDP (formato de tb_bus.v) ----
    logic [7:0] vreg [32:58];
    integer     violations = 0, ncmd = 0, fo;
    always @(posedge clk) begin
        if (geo_cmd_wr) begin
            if (geo_cmd_ce) violations = violations + 1;
            vreg[geo_cmd_num] = geo_cmd_data;
            if (geo_cmd_num == 6'd46) begin
                ncmd = ncmd + 1;
                if (geo_cmd_data[7:4] == 4'h3)
                    $fwrite(fo, "M %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\n",
                            vreg[32], vreg[33], vreg[34], vreg[35], vreg[36], vreg[37], vreg[38], vreg[39], vreg[40],
                            vreg[41], vreg[42], vreg[43], vreg[44], vreg[45], vreg[47], vreg[48], vreg[49], vreg[50], geo_cmd_data);
                else
                    $fwrite(fo, "L %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x %02x\n",
                            vreg[36], vreg[37], vreg[38], vreg[39], vreg[40], vreg[41], vreg[42], vreg[43], vreg[44],
                            vreg[45], geo_cmd_data);
            end
        end
    end

    // ---- tareas Z80: un ciclo I/O sobre el glue (csw_n/csr_n) y esperar su /WAIT ----
    task z_wr(input [2:0] m, input [7:0] d);
        begin
            @(negedge clk); mode = m; cdo = d; csw_n = 0;
            repeat (5) @(negedge clk);
            while (!wait_n) @(negedge clk);
            csw_n = 1;
            repeat (4) @(negedge clk);
        end
    endtask
    task z_rd(input [2:0] m, output [7:0] d);
        begin
            @(negedge clk); mode = m; csr_n = 0;
            repeat (5) @(negedge clk);
            while (!wait_n) @(negedge clk);
            d = cdi_r;
            csr_n = 1;
            repeat (4) @(negedge clk);
        end
    endtask
    task vdp_reg(input [5:0] r, input [7:0] d);
        begin z_wr(3'd1, d); z_wr(3'd1, {2'b10, r}); end
    endtask

    integer fi, r, a, b, frames = 0, maxcyc = 0, cyc, k, vdp_bad = 0, maxpoll;
    integer ff, dumps = 0, nx = 0, y, xb, c1, c2, c3, ccyc, maxce = 0;
    reg [17:0] next_addr = 18'h3FFFF;
    reg [8*200-1:0] frames_name;
    reg [8*4-1:0] op;
    reg [7:0] st, k0, k1, k2, k3, k4, k5;
    reg [8*200-1:0] stim_name, got_name;
    initial begin
        if (!$value$plusargs("stim=%s", stim_name)) stim_name = "scenes_stim.txt";
        if (!$value$plusargs("got=%s",  got_name))  got_name  = "geo3d_sys_got.txt";
        if (!$value$plusargs("frames=%s", frames_name)) frames_name = "geo3d_sys_frames.hex";
        if (!$value$plusargs("maxpoll=%d", maxpoll)) maxpoll = 400000;
        ff = $fopen(frames_name, "w");
        for (k = 0; k < 65536; k = k + 1) vram_mem[k] = 32'd0;
        fo = $fopen(got_name, "w");
        repeat (20) @(negedge clk);
        rst_n = 1;
        repeat (200) @(negedge clk);
        // SCREEN 5, pantalla apagada; puerto 4 (9Ch) bit7 = 0 desbloquea R#20/R#21; R#21 = 0 (modo V9968), R#20 = 1 (alta velocidad)
        vdp_reg(6'd0, 8'h06); vdp_reg(6'd1, 8'h00); vdp_reg(6'd2, 8'h1F);
        z_wr(3'd4, 8'h00);
        vdp_reg(6'd21, 8'h00); vdp_reg(6'd20, 8'h01);
        // geo3d ha de contestar: estado con RUN = 0
        z_rd(3'd5, st);
        $display("geo3d estado inicial (9Dh) = %02x (esperado bit0 = 0, no FF)", st);
        if (st === 8'hFF) $display("*** geo3d NO RESPONDE ***");

        fi = $fopen(stim_name, "r");
        while (!$feof(fi)) begin
            r = $fscanf(fi, "%s", op);
            if (r == 1) begin
                if (op[7:0] == "W") begin
                    r = $fscanf(fi, "%d %h", a, b);
                    z_wr(a[0] ? 3'd7 : 3'd5, b[7:0]);
                end else if (op[7:0] == "R") begin
                    cyc = 0; st = 8'h01;
                    while (st[0] && cyc < maxpoll) begin z_rd(3'd5, st); cyc = cyc + 1; end
                    if (st[0]) $display("*** RUN no acaba (cuadro %0d) ***", frames);
                    if (cyc > maxcyc) maxcyc = cyc;
                end else if (op[7:0] == "K") begin
                    z_wr(3'd5, 8'h4A);
                    z_rd(3'd7, k0); z_rd(3'd7, k1); z_rd(3'd7, k2); z_rd(3'd7, k3); z_rd(3'd7, k4); z_rd(3'd7, k5);
                    $fwrite(fo, "K %02x%02x %02x%02x %02x%02x\n", k1, k0, k3, k2, k5, k4);
                end else if (op[7:0] == "V") begin
                    r = $fscanf(fi, "%d %h", a, b);
                    vdp_reg(a[5:0], b[7:0]);
                end else if (op[7:0] == "C") begin
                    ccyc = 0; st = 8'h01;
                    vdp_reg(6'd15, 8'h02);
                    while (st[0] && ccyc < 2000000) begin z_rd(3'd1, st); ccyc = ccyc + 1; end
                    vdp_reg(6'd15, 8'h00);
                    if (st[0]) $display("*** CE no baja (cuadro %0d) ***", dumps);
                    if (ccyc > maxce) maxce = ccyc;
                end else if (op[7:0] == "X") begin
                    r = $fscanf(fi, "%h %h", a, b);
                    if (a[17:0] != next_addr) begin
                        vdp_reg(6'd14, {4'd0, a[17:14]});
                        z_wr(3'd1, a[7:0]); z_wr(3'd1, {2'b01, a[13:8]});
                    end
                    z_wr(3'd0, b[7:0]);
                    next_addr = a[17:0] + 18'd1;
                    nx = nx + 1;
                end else if (op[7:0] == "A") begin
                    r = $fscanf(fi, "%d %d %d %d", a, c1, c2, c3);
                    vdp_reg(6'd16, a[7:0]);
                    z_wr(3'd2, {1'b0, c1[2:0], 1'b0, c3[2:0]}); z_wr(3'd2, {5'd0, c2[2:0]});
                end else if (op[7:0] == "D") begin
                    r = $fscanf(fi, "%d", a);
                    repeat (400) @(negedge clk);       // que se vacie la cola de escrituras del VDP
                    for (y = 0; y < 212; y = y + 1)
                        for (xb = 0; xb < 128; xb = xb + 1)
                            $fwrite(ff, "%02x\n", vram_mem[((a + y) * 128 + xb) >> 2][8 * (xb & 3) +: 8]);
                    dumps = dumps + 1;
                    $display("D %0d t=%0d us", dumps, $time / 1000);   // tiempo simulado (geo3d + VDP; el Z80 aqui no tarda)
                end else if (op[7:0] == "F") begin
                    r = $fscanf(fi, "%d", a);
                    $fwrite(fo, "F %0d\n", a);
                    frames = frames + 1;
                    // el VDP sigue vivo: S#2 por 99h con CE = 0 tras el cuadro
                    vdp_reg(6'd15, 8'h02); z_rd(3'd1, st); vdp_reg(6'd15, 8'h00);
                    if (st === 8'hxx || st[0]) begin vdp_bad = vdp_bad + 1; $display("VDP S#2 raro tras el cuadro %0d: %02x", frames, st); end
                end
            end
        end
        $fclose(fo); $fclose(ff);
        $display("tb_geo3d_sys: RUNs %0d, paginas volcadas %0d, bytes de VRAM por 98h %0d, comandos de geo3d %0d, escrituras con CE=1: %0d, sondeos RUN max: %0d, sondeos CE max: %0d, S#2 raros: %0d",
                 frames, dumps, nx, ncmd, violations, maxcyc, maxce, vdp_bad);
        if (violations == 0 && vdp_bad == 0) $display("##### INTEGRACION geo3d: SIN VIOLACIONES (comparar got con expect) #####");
        else $display("##### INTEGRACION geo3d: FALLOS #####");
        $finish;
    end
endmodule
