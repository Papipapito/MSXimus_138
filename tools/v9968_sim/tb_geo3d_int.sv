// ============================================================================
// tb_geo3d_int.sv — INTEGRACION de geo3d en el MSXimus Z: el enganche de top_zynq.v reproducido pieza a pieza:
//   Z80 (tareas) -> v9968_cpu_glue (csw_n/csr_n, mode 1 = 99h, 4 = 9Ch, 5 = 9Dh, 7 = 9Fh)
//              -> bus valid/ready -> { geo3d_bus (hit en mode 5/7) | vdp completo (VRAM perfecta) }
//   geo3d_bus.cmd_* -> vdp.ext_cmd_* (LINE/LRMM en vdp_command con CE = 0)
// Estimulo = el de sim/tb_bus.v de geo3d (gen_scenes.py: W sel byte / R = esperar RUN / K = contadores / F = cuadro);
// salida = mismo registro (L/M/K/F) para diff con scenes_expect.txt. Ademas cuenta escrituras de comando con CE = 1
// (violaciones) y comprueba que el VDP sigue respondiendo (S#0 por 99h) despues de cada cuadro.
// Se corre con run_geo3d_int_vl.sh (verilado con --timing). 27/09/2026.
// 138K (17/10/2026): con +define+GEO3D_CE (GEO3D_CE=1 run_geo3d_int_vl.sh ...) el enganche es el de top.v del 138K:
// el motor a clk con el clock enable 1/2 (cinco replicas en fase de geo_ce) y el reset local de una etapa. Sin el
// define, el de la Zynq (motor a clk_43 = clk/2 en fase). El registro de comandos tiene que salir IGUAL en los dos.
// ============================================================================
`timescale 1ns/1ps
module tb_geo3d_int;
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
    // el generador de top.v (138K): toggle maestro + cinco replicas que cargan ~geo_ce_m, y el reset local
    logic       geo_ce_m = 1'b0;
    logic [4:0] geo_ce   = 5'd0;
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
    reg [8*4-1:0] op;
    reg [7:0] st, k0, k1, k2, k3, k4, k5;
    reg [8*200-1:0] stim_name, got_name;
    initial begin
        if (!$value$plusargs("stim=%s", stim_name)) stim_name = "scenes_stim.txt";
        if (!$value$plusargs("got=%s",  got_name))  got_name  = "geo3d_int_got.txt";
        // 17/10: tope de sondeos de RUN por cuadro. 400000 basta para las escenas de alambre; las de caras
        // (gen_face_scenes) y texturas (gen_tex_scenes) tienen cuadros mas largos (+maxpoll=4000000).
        if (!$value$plusargs("maxpoll=%d", maxpoll)) maxpoll = 400000;
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
        $fclose(fo);
        $display("tb_geo3d_int: cuadros %0d, comandos %0d, escrituras con CE=1: %0d, sondeos RUN max: %0d, S#2 raros: %0d",
                 frames, ncmd, violations, maxcyc, vdp_bad);
        if (violations == 0 && vdp_bad == 0) $display("##### INTEGRACION geo3d: SIN VIOLACIONES (comparar got con expect) #####");
        else $display("##### INTEGRACION geo3d: FALLOS #####");
        $finish;
    end
endmodule
