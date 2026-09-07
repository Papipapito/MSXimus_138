// ============================================================================
// tb_megaram.sv — la megaram de 4 MB (V3.5) contra la de 2 MB (V3.1) como
// ORACULO, mas los modos nuevos contra un modelo escrito aqui.
//
//  A) EQUIVALENCIA: con map_ext=0, para Konami4 / SCC / ASCII8 / ASCII16, con y
//     sin SRAM, miles de operaciones aleatorias (escrituras a registros de
//     banco/modo, escrituras y lecturas de datos en 0000-FFFF): megaram_req,
//     megaram_wrt y megaram_addr[20:0] tienen que ser IDENTICOS a los de la
//     V3.1, ciclo a ciclo. Y addr[21] tiene que ser 0 salvo en ASCII16 con el
//     bit 7 del registro puesto (la unica diferencia deliberada: antes aliasaba).
//  B) MITAD ALTA (map_ext[4]) en modo SCC con escritura habilitada: addr[21]=1 y
//     el resto identico.
//  C) NEO-8: 6 registros de 12 bits en 5000/5800/6000/6800/7000/7800 (+1 nibble
//     alto), ventanas de 8K en 0000-BFFF: addr = {reg[8:0], a[12:0]}.
//  D) NEO-16: 3 registros en 5000/6000/7000, ventanas de 16K: {reg[7:0], a[13:0]}.
//  E) En NEO no hay SRAM ni escritura a datos (ROM), y los registros no se
//     tocan desde fuera de 5000-7FFF.
// ============================================================================
`timescale 1ns/1ps

module tb_megaram;
    reg clk = 1'b0;
    always #18.5 clk = ~clk;

    reg        rst_n = 1'b0;
    reg [15:0] bus_addr = 16'h0000;
    reg [7:0]  cpu_dout = 8'h00;
    reg        bus_rd_n = 1'b1;
    reg        bus_wr_n = 1'b1;
    reg        scc_req = 1'b0;
    reg        scc_wrt = 1'b0;
    reg [1:0]  map_sel = 2'b10;
    reg        map_linear = 1'b0;
    reg [7:0]  sram_cfg = 8'h00;
    reg [7:0]  map_ext = 8'h00;

    wire        n_req, n_wrt, n_sd, n_mp, n_win;
    wire [21:0] n_addr;
    wire        o_req, o_wrt, o_sd, o_mp, o_win;
    wire [20:0] o_addr;

    megaram_scc dut (
        .clk_27m(clk), .bus_reset_n(rst_n), .bus_addr(bus_addr), .cpu_dout(cpu_dout),
        .bus_rd_n(bus_rd_n), .bus_wr_n(bus_wr_n), .scc_req(scc_req), .scc_wrt(scc_wrt),
        .map_sel(map_sel), .map_linear(map_linear), .sram_cfg(sram_cfg), .map_ext(map_ext),
        .megaram_req(n_req), .megaram_wrt(n_wrt), .megaram_addr(n_addr),
        .scc_sound_disable(n_sd), .scc_mode_plus(n_mp), .sccplus_win_en(n_win)
    );
    megaram_scc_old gold (
        .clk_27m(clk), .bus_reset_n(rst_n), .bus_addr(bus_addr), .cpu_dout(cpu_dout),
        .bus_rd_n(bus_rd_n), .bus_wr_n(bus_wr_n), .scc_req(scc_req), .scc_wrt(scc_wrt),
        .map_sel(map_sel), .map_linear(map_linear), .sram_cfg(sram_cfg),
        .megaram_req(o_req), .megaram_wrt(o_wrt), .megaram_addr(o_addr),
        .scc_sound_disable(o_sd), .scc_mode_plus(o_mp), .sccplus_win_en(o_win)
    );

    integer errors = 0;
    integer nops = 0;
    reg        last_req, last_wrt;      // lo que se vio DURANTE el ultimo ciclo de bus
    reg [21:0] last_addr;
    integer seed = 12345;
    reg [7:0] a16_hi;     // ultimo bit7 escrito en un registro ASCII16 (por ventana)
    reg [1:0] a16_hi_w;   // {ventana 8000, ventana 4000}

    task check;
        input cond;
        input [8*96-1:0] msg;
        begin
            if (!cond) begin
                errors = errors + 1;
                if (errors < 30) $display("  FAIL %0s  (t=%0t addr=%04x dout=%02x rd=%b wr=%b)", msg, $time, bus_addr, cpu_dout, ~bus_rd_n, ~bus_wr_n);
            end
        end
    endtask

    // un ciclo de bus: aplica, deja asentar dos flancos, compara, retira
    task bus_op;
        input [15:0] a;
        input [7:0]  d;
        input        is_wr;
        begin
            @(negedge clk);
            bus_addr = a; cpu_dout = d;
            bus_rd_n = is_wr ? 1'b1 : 1'b0;
            bus_wr_n = is_wr ? 1'b0 : 1'b1;
            scc_req  = 1'b1;
            scc_wrt  = is_wr;
            @(negedge clk);           // los modos registrados (ff_*) ya estan estables (map_sel es fijo por test)
            #1;
            nops = nops + 1;
            last_req = n_req; last_wrt = n_wrt; last_addr = n_addr;
            // ---- comparacion con el oraculo (solo con map_ext=0) ----
            if (map_ext == 8'h00) begin
                check(n_req == o_req, "req distinto del oraculo");
                check(n_wrt == o_wrt, "wrt distinto del oraculo");
                if (n_req) check(n_addr[20:0] == o_addr, "addr[20:0] distinto del oraculo");
                check(n_sd == o_sd && n_mp == o_mp && n_win == o_win, "scc_sound_disable/mode_plus/win distintos");
                if (n_req) begin
                    if (map_sel == 2'b11 && dut.sram_hit == 1'b0)
                        check(n_addr[21] == ((bus_addr[15:14] == 2'b01) ? a16_hi_w[0] : (bus_addr[15:14] == 2'b10) ? a16_hi_w[1] : n_addr[21]),
                              "ASCII16: addr[21] = bit7 del registro");
                    else
                        check(n_addr[21] == 1'b0, "addr[21] deberia ser 0 fuera de ASCII16/NEO/hi");
                end
            end
            @(posedge clk); #1;       // el flanco que registra la escritura (ambos modulos)
            @(negedge clk);
            scc_req = 1'b0; scc_wrt = 1'b0; bus_rd_n = 1'b1; bus_wr_n = 1'b1;
            @(negedge clk);
        end
    endtask

    task do_reset;
        begin
            @(negedge clk); rst_n = 1'b0;
            repeat (3) @(negedge clk);
            rst_n = 1'b1;
            repeat (3) @(negedge clk);
            a16_hi_w = 2'b00;
        end
    endtask

    // ---- estimulo aleatorio para un modo ----
    task random_ops;
        input integer n;
        integer k, r;
        reg [15:0] a;
        reg [7:0]  d;
        reg        w;
        begin
            for (k = 0; k < n; k = k + 1) begin
                r = $random(seed);
                d = $random(seed);
                // 1/3 escrituras a direcciones "de registro", 1/3 escrituras a datos, 1/3 lecturas
                case (r[1:0])
                    2'd0: begin
                        case (r[5:2])
                            4'd0: a = 16'h5000; 4'd1: a = 16'h7000; 4'd2: a = 16'h9000; 4'd3: a = 16'hB000;
                            4'd4: a = 16'h6000; 4'd5: a = 16'h6800; 4'd6: a = 16'h7800; 4'd7: a = 16'h8000;
                            4'd8: a = 16'hA000; 4'd9: a = 16'h7FFE; 4'd10: a = 16'hBFFE; 4'd11: a = 16'h7FFF;
                            4'd12: a = 16'h5001; 4'd13: a = 16'h6001; 4'd14: a = 16'h7001; default: a = 16'h9800;
                        endcase
                        a = a + { 8'h00, r[9:6], 3'b000 } ; // un poco de jitter dentro del bloque
                        w = 1'b1;
                    end
                    2'd1: begin a = $random(seed); w = 1'b1; end
                    default: begin a = $random(seed); w = 1'b0; end
                endcase
                if (w && map_sel == 2'b11 && a[15:12] == 4'h6 && a[11] == 1'b0) a16_hi_w[0] = d[7];
                if (w && map_sel == 2'b11 && a[15:12] == 4'h7 && a[11] == 1'b0 && a[10:1] != 10'h3FF) a16_hi_w[1] = d[7];
                bus_op(a, d, w);
            end
        end
    endtask

    reg [11:0] neo_model [0:5];
    integer t, q;
    reg [15:0] ra;
    reg [21:0] expect_addr;

    initial begin
        $display("=== tb_megaram: V3.5 (4 MB, NEO) contra V3.1 (2 MB) ===");

        // ---------------- A) equivalencia en los modos clasicos ----------------
        for (t = 0; t < 8; t = t + 1) begin
            map_ext = 8'h00;
            map_sel = t[1:0];
            sram_cfg = (t >= 4) ? 8'h04 : 8'h00;    // con SRAM (ASCII) o sin ella
            do_reset();
            random_ops(4000);
            $display("  A) map_sel=%b sram_cfg=%02x : %0d ops, fallos acumulados %0d", map_sel, sram_cfg, nops, errors);
        end
        // ASCII16 con el modo "valor==0x10" (Hydlide) y bit7 alto
        map_sel = 2'b11; sram_cfg = 8'h01; do_reset();
        bus_op(16'h6000, 8'h10, 1); bus_op(16'h4000, 8'hAA, 1); bus_op(16'h8123, 8'h00, 0);
        a16_hi_w[0] = 1'b1; bus_op(16'h6000, 8'h83, 1); bus_op(16'h5555, 8'h00, 0);
        a16_hi_w[1] = 1'b1; bus_op(16'h7000, 8'h81, 1); bus_op(16'h9000, 8'h00, 0);
        check(last_addr[21] == 1'b1, "ASCII16 bit7: addr[21]=1 en la ventana 8000 (banco 0x81)");
        $display("  A) ASCII16 bit7 -> addr[21]: fallos acumulados %0d", errors);

        // ---------------- B) mitad alta para el cargador (modo SCC) ----------------
        map_sel = 2'b10; sram_cfg = 8'h00; map_ext = 8'h00; do_reset();
        bus_op(16'h7FFE, 8'h00, 1);           // mode_a = 0 (banco se fija con WE off)
        bus_op(16'h5000, 8'h2A, 1);           // reg0 = 0x2A
        bus_op(16'h7FFE, 8'h10, 1);           // write enable
        map_ext = 8'h10; repeat (3) @(negedge clk);
        bus_op(16'h4123, 8'h5A, 1);
        check(last_wrt == 1'b1, "B) escritura de datos con WE en modo SCC");
        check(last_addr == { 1'b1, 8'h2A, 13'h0123 }, "B) addr = {1, reg0, offset} con map_ext[4]=1");
        map_ext = 8'h00; repeat (3) @(negedge clk);
        bus_op(16'h4123, 8'h5A, 1);
        check(last_addr == { 1'b0, 8'h2A, 13'h0123 }, "B) addr = {0, reg0, offset} con map_ext[4]=0");
        $display("  B) mitad alta: fallos acumulados %0d", errors);

        // ---------------- C) NEO-8 ----------------
        map_sel = 2'b01; sram_cfg = 8'h04; map_ext = 8'h01; do_reset();
        repeat (3) @(negedge clk);
        for (q = 0; q < 6; q = q + 1) neo_model[q] = 12'h000;
        // reset: todo a 0 -> cualquier ventana apunta al banco 0
        bus_op(16'h0100, 8'h00, 0); check(last_req && last_addr == 22'h000100, "C) NEO-8 reset: ventana 0 -> banco 0");
        bus_op(16'hA100, 8'h00, 0); check(last_req && last_addr == 22'h000100, "C) NEO-8 reset: ventana 5 -> banco 0");
        // programar los 6 registros con valores de 12 bits (byte bajo en par, nibble alto en impar)
        for (q = 0; q < 6; q = q + 1) begin
            neo_model[q] = { q[3:0], 8'h10 + q[7:0] * 8'h21 };
            ra = 16'h5000 + q * 16'h0800;
            bus_op(ra,     neo_model[q][7:0], 1);
            bus_op(ra + 1, { 4'h0, neo_model[q][11:8] }, 1);
        end
        for (q = 0; q < 6; q = q + 1) begin
            ra = q * 16'h2000 + 16'h0ABC;
            expect_addr = { neo_model[q][8:0], ra[12:0] };
            bus_op(ra, 8'h00, 0);
            check(last_req == 1'b1, "C) NEO-8 lectura: req");
            check(last_addr == expect_addr, "C) NEO-8 lectura: addr = {reg[8:0], a[12:0]}");
        end
        // escritura de datos en NEO = ROM: no hay wrt (mode_a[4]=0 tras reset)
        bus_op(16'h8ABC, 8'h55, 1); check(last_wrt == 1'b0, "C) NEO-8: escribir datos no genera wrt");
        // un registro fuera de 5000-7FFF no cambia nada (p.ej. 9000h)
        bus_op(16'h9000, 8'hFF, 1); bus_op(16'h9001, 8'h0F, 1);
        bus_op(16'h8ABC, 8'h00, 0); check(last_addr == { neo_model[4][8:0], 13'h0ABC }, "C) NEO-8: 9000h no es registro");
        // SRAM apagada en NEO aunque sram_cfg != 0
        check(dut.sram_mode == 1'b0, "C) NEO-8: sram_mode=0 con sram_cfg!=0");
        $display("  C) NEO-8: fallos acumulados %0d", errors);

        // ---------------- D) NEO-16 ----------------
        map_sel = 2'b11; sram_cfg = 8'h00; map_ext = 8'h01; do_reset();
        repeat (3) @(negedge clk);
        for (q = 0; q < 3; q = q + 1) begin
            neo_model[q] = { 4'h0, 8'h07 + q[7:0] * 8'h50 };
            ra = 16'h5000 + q * 16'h1000;
            bus_op(ra,     neo_model[q][7:0], 1);
            bus_op(ra + 1, 8'h00, 1);
        end
        for (q = 0; q < 3; q = q + 1) begin
            ra = q * 16'h4000 + 16'h1234;
            expect_addr = { neo_model[q][7:0], ra[13:0] };
            bus_op(ra, 8'h00, 0);
            check(last_req == 1'b1, "D) NEO-16 lectura: req");
            check(last_addr == expect_addr, "D) NEO-16 lectura: addr = {reg[7:0], a[13:0]}");
        end
        // 5800/6800/7800 se ignoran en NEO-16
        bus_op(16'h5800, 8'hEE, 1); bus_op(16'h1234, 8'h00, 0);
        check(last_addr == { neo_model[0][7:0], 14'h1234 }, "D) NEO-16: 5800h se ignora");
        $display("  D) NEO-16: fallos acumulados %0d", errors);

        // ---------------- E) volver a clasico tras NEO: sin residuos ----------------
        map_ext = 8'h00; map_sel = 2'b10; do_reset(); random_ops(1000);
        $display("  E) vuelta a SCC tras NEO: fallos acumulados %0d", errors);

        if (errors == 0) $display("=== tb_megaram: TODO OK (%0d operaciones) ===", nops);
        else             $display("=== tb_megaram: %0d FALLOS ===", errors);
        $finish;
    end
endmodule
