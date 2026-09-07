// ============================================================================
// tb_sdio.sv — banco del sdc_ioport (V3.5c/d): puntero autoincrementado,
// buf_ack en el byte 511, rebobinado por #47/#4F, count/force1, info_idx, y
// (V3.5d) que las ordenes salgan como PULSO DE UN CICLO con su dato capturado.
// Un ciclo de E/S del Z80 dura ~22 ciclos de clk_27m: aqui se imita con 'sel'
// mas rd_n/wr_n activos durante N ciclos.
// ============================================================================
`timescale 1ns/1ps
module tb_sdio;
    reg clk = 0; always #18.5185 clk = ~clk;
    reg rstn = 0;
    reg sel = 0; reg [3:0] addr = 0; reg rd_n = 1, wr_n = 1; reg [7:0] din = 0; reg force1 = 0;
    wire cmd_wr, data_sel, data_wr, buf_ack;
    wire [7:0] cmd_val, saddr_val, data_val, count;
    wire [3:0] saddr_wr;
    wire [8:0] ptr;
    wire [4:0] info_idx;

    sdc_ioport dut (.clk(clk), .rstn(rstn), .sel(sel), .addr(addr), .rd_n(rd_n), .wr_n(wr_n), .din(din),
                    .force1(force1), .cmd_wr(cmd_wr), .cmd_val(cmd_val), .saddr_wr(saddr_wr),
                    .saddr_val(saddr_val), .data_sel(data_sel), .data_wr(data_wr), .data_val(data_val),
                    .ptr(ptr), .buf_ack(buf_ack), .count(count), .info_idx(info_idx));

    integer errors = 0;
    integer acks = 0;
    integer cmd_pulses = 0;
    always @(posedge clk) begin
        if (buf_ack) acks = acks + 1;
        if (cmd_wr)  cmd_pulses = cmd_pulses + 1;
    end

    task check; input cond; input [8*76-1:0] msg;
        begin if (cond) $display("  OK   %0s", msg); else begin $display("  FAIL %0s (t=%0t)", msg, $time); errors = errors + 1; end end
    endtask

    // Un OUT del Z80: el dato se pone ANTES de bajar WR y se mantiene hasta
    // DESPUES de soltarlo (hold). Los cambios van con #1 tras el flanco para no
    // competir con el propio flanco, que seria una carrera del banco y no un
    // fallo del diseno.
    task io_out; input [3:0] a; input [7:0] d;
        begin @(posedge clk); #1 addr = a; din = d; sel = 1; wr_n = 0;
              repeat (22) @(posedge clk);
              #1 sel = 0; wr_n = 1;                // WR sube: el decode cae ya
              @(posedge clk); #1 din = 8'hAA;      // y el bus suelta el dato despues
              repeat (7) @(posedge clk); end
    endtask
    task io_in; input [3:0] a;
        begin @(posedge clk); #1 addr = a; sel = 1; rd_n = 0; repeat (22) @(posedge clk);
              #1 sel = 0; rd_n = 1; repeat (8) @(posedge clk); end
    endtask

    reg [8:0] p_before;
    integer i;
    initial begin
        $display("=== tb_sdio ===");
        repeat (5) @(posedge clk); rstn = 1; repeat (5) @(posedge clk);
        check(count == 8'd1, "reset: count = 1");
        check(ptr == 9'd0, "reset: ptr = 0");

        // un IN #4C = un incremento, aunque el ciclo dure 22 clk
        io_in(4'hC);
        check(ptr == 9'd1, "IN #4C: el puntero avanza UNA vez por ciclo");
        @(posedge clk); addr = 4'hC; sel = 1; rd_n = 0; repeat (14) @(posedge clk);
        p_before = ptr;
        check(data_sel == 1'b1 && ptr == p_before, "durante el ciclo: data_sel=1 y ptr quieto");
        sel = 0; rd_n = 1; repeat (10) @(posedge clk);
        check(ptr == 9'd2, "al acabar el ciclo: ptr = 2");

        io_out(4'hF, 8'h00);
        check(ptr == 9'd0, "OUT #4F: ptr = 0");

        // 512 OUT #4C: 512 bytes, un solo buf_ack, ptr vuelve a 0
        acks = 0;
        for (i = 0; i < 512; i = i + 1) io_out(4'hC, i[7:0]);
        check(ptr == 9'd0, "512 OUT #4C: ptr vuelve a 0");
        check(acks == 1, "512 OUT #4C: exactamente UN buf_ack");
        io_out(4'hC, 8'h55);
        check(acks == 1 && ptr == 9'd1, "el byte 513 no genera otro ack");
        check(data_val == 8'h55, "OUT #4C: el dato queda capturado (data_val)");

        // count y force1
        io_out(4'hD, 8'd7);
        check(count == 8'd7, "OUT #4D: count = 7");
        @(posedge clk); force1 = 1; @(posedge clk); force1 = 0; @(posedge clk);
        check(count == 8'd1, "force1 (orden por la ventana): count = 1");
        io_out(4'hD, 8'd64);
        check(count == 8'd64, "OUT #4D: count = 64");

        // V3.5d: la orden es UN pulso de un ciclo, con su dato capturado
        io_out(4'hC, 8'h11); io_out(4'hC, 8'h22);
        cmd_pulses = 0;
        io_out(4'h7, 8'h01);
        check(cmd_pulses == 1, "OUT #47: cmd_wr es UN pulso de un ciclo");
        check(cmd_val == 8'h01, "OUT #47: cmd_val trae el dato de la orden");
        check(ptr == 9'd0, "OUT #47: rebobina el bufer");
        check(cmd_wr == 1'b0, "tras el ciclo: cmd_wr en reposo");

        // el LBA, igual: pulso por byte y dato capturado
        io_out(4'hA, 8'h5A);
        check(saddr_val == 8'h5A, "OUT #4A: saddr_val trae el byte del LBA");
        check(saddr_wr == 4'd0, "tras el ciclo: saddr_wr en reposo");

        io_out(4'hE, 8'd13);
        check(info_idx == 5'd13, "OUT #4E: info_idx = 13");

        io_out(4'hC, 8'h00);
        io_in(4'h7);
        check(ptr == 9'd1, "IN #47 no mueve el puntero");

        if (errors == 0) $display("=== tb_sdio: TODO OK ===");
        else             $display("=== tb_sdio: %0d FALLOS ===", errors);
        $finish;
    end
endmodule
