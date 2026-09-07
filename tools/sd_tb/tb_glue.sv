// ============================================================================
// tb_glue.sv - el "pegamento" de top.v entre el bus, sdc_ioport y sd_reader.
//
// INVARIANTE QUE COMPRUEBA: en el PRIMER flanco en que sd_reader ve rstart=1,
// rcount ya vale lo que tiene que valer. sd_reader elige CMD17 o CMD18 mirando
// rcount EN ESE MISMO FLANCO (IDLING: set_cmd(... rcount>1 ? 18 : 17 ...)).
//
// El fallo que caza (07/09, doble check de la V3.5d): al registrar
// sd_win_cmd_wr, la orden por la VENTANA ponia rstart desde el bus un ciclo
// ANTES de que force1 pusiera count=1 en el modulo. Tras un cluster por
// puertos (count=64), la lectura de la FAT por ventana salia como CMD18. Ni
// tb_sd (rcount es un reg del banco) ni tb_sdio (force1 aislado) lo veian:
// solo se ve con el pegamento entero.
//
// Es una REPLICA LITERAL de esos trozos de top.v. ⚠️ SI SE TOCA UNO, TOCAR EL
// OTRO: top.v, "sd_win_cmd_wr" y el bloque "V3.5c: la misma orden y el mismo
// LBA, por los puertos".
// ============================================================================
`timescale 1ns/1ps
module tb_glue;
    parameter OLD = 0;                            // 1 = el pegamento de ANOCHE (rstart desde el bus): debe FALLAR
    reg clk = 0; always #18.5185 clk = ~clk;      // clk_27m
    reg rstn = 0;

    // ---- el bus, como lo ve top.v ----
    reg        bus_iorq_n = 1, bus_mreq = 0, bus_wr_n = 1, bus_rd_n = 1, bus_m1_n = 1;
    reg [15:0] bus_addr = 0;
    reg [7:0]  cpu_dout = 0;
    reg        config_ok = 1;                     // dispositivo #48 seleccionado
    localparam SDC_CMD = 16'h7E01;                // cualquier direccion de la ventana

    // ---- replica: decode registrado de la ventana y el strobe de la orden ----
    reg sd_cs_w = 0;
    always @(posedge clk) sd_cs_w <= bus_mreq && (bus_addr[15:8] == 8'h7E);
    reg       sd_win_cmd_wr  = 0;
    reg [7:0] sd_win_cmd_val = 0;
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin sd_win_cmd_wr <= 0; sd_win_cmd_val <= 0; end
        else begin
            sd_win_cmd_wr <= sd_cs_w && ~bus_wr_n && (bus_addr == SDC_CMD);
            if (sd_cs_w && ~bus_wr_n && (bus_addr == SDC_CMD)) sd_win_cmd_val <= cpu_dout;
        end
    end

    // ---- replica: seleccion registrada del dispositivo y el modulo real ----
    reg sdio_sel = 0;
    always @(posedge clk) sdio_sel <= config_ok && (bus_iorq_n == 0) && (bus_m1_n == 1) && (bus_addr[7:4] == 4'h4);
    wire       sdio_cmd_wr, sdio_data_sel, sdio_data_wr, sdio_ack;
    wire [7:0] sdio_cmd_val, sdio_saddr_val, sdio_data_val, sdio_count;
    wire [3:0] sdio_saddr_wr;
    wire [8:0] sdio_ptr;
    wire [4:0] sdio_idx;
    sdc_ioport u_sdio (.clk(clk), .rstn(rstn), .sel(sdio_sel), .addr(bus_addr[3:0]),
        .rd_n(bus_rd_n), .wr_n(bus_wr_n), .din(cpu_dout), .force1(sd_win_cmd_wr),
        .cmd_wr(sdio_cmd_wr), .cmd_val(sdio_cmd_val), .saddr_wr(sdio_saddr_wr),
        .saddr_val(sdio_saddr_val), .data_sel(sdio_data_sel), .data_wr(sdio_data_wr),
        .data_val(sdio_data_val), .ptr(sdio_ptr), .buf_ack(sdio_ack), .count(sdio_count),
        .info_idx(sdio_idx));

    // ---- replica: los strobes de arranque (sin la parte de done/timeout) ----
    reg ff_sd_rstart = 0, ff_sd_wstart = 0, ff_sd_init = 0;
    reg clr = 0;                                  // hace de sd_done_edge
    always @(posedge clk) begin
        if (sdio_cmd_wr) begin
            ff_sd_rstart <= ff_sd_rstart | sdio_cmd_val[0];
            ff_sd_wstart <= ff_sd_wstart | sdio_cmd_val[1];
            ff_sd_init   <= ff_sd_init   | sdio_cmd_val[7];
        end
        if (clr) begin ff_sd_rstart <= 0; ff_sd_wstart <= 0; end
        if (!OLD && sd_win_cmd_wr) begin
            ff_sd_rstart <= ff_sd_rstart | sd_win_cmd_val[0];
            ff_sd_wstart <= ff_sd_wstart | sd_win_cmd_val[1];
            ff_sd_init   <= ff_sd_init   | sd_win_cmd_val[7];
        end
        if (OLD && sd_cs_w && ~bus_wr_n && (bus_addr == SDC_CMD)) begin   // asi estaba anoche
            ff_sd_rstart <= ff_sd_rstart | cpu_dout[0];
            ff_sd_wstart <= ff_sd_wstart | cpu_dout[1];
            ff_sd_init   <= ff_sd_init   | cpu_dout[7];
        end
    end

    // ---- el "sd_reader" minimo: en el primer flanco con rstart=1, que ve? ----
    reg rstart_d = 0;
    reg [7:0] count_seen = 8'hEE;
    reg       seen = 0;
    always @(posedge clk) begin
        rstart_d <= ff_sd_rstart;
        if (ff_sd_rstart && !rstart_d) begin count_seen <= sdio_count; seen <= 1; end
    end

    integer errors = 0;
    task check; input cond; input [8*76-1:0] msg;
        begin if (cond) $display("  OK   %0s", msg);
              else begin $display("  FAIL %0s (t=%0t)", msg, $time); errors = errors + 1; end end
    endtask
    task io_out; input [7:0] a; input [7:0] d;           // OUT del Z80 (~22 clk)
        begin @(posedge clk); #1 bus_addr = {8'h00, a}; cpu_dout = d; bus_iorq_n = 0; bus_wr_n = 0;
              repeat (22) @(posedge clk); #1 bus_iorq_n = 1; bus_wr_n = 1;
              @(posedge clk); #1 cpu_dout = 8'hAA; repeat (7) @(posedge clk); end
    endtask
    task mem_out; input [15:0] a; input [7:0] d;         // escritura en la ventana (~22 clk)
        begin @(posedge clk); #1 bus_addr = a; cpu_dout = d; bus_mreq = 1; bus_wr_n = 0;
              repeat (22) @(posedge clk); #1 bus_mreq = 0; bus_wr_n = 1;
              @(posedge clk); #1 cpu_dout = 8'hAA; repeat (7) @(posedge clk); end
    endtask
    task clear_start;                                    // el FSM acaba: suelta rstart
        begin @(posedge clk); #1 clr = 1; @(posedge clk); #1 clr = 0; seen = 0; count_seen = 8'hEE;
              repeat (4) @(posedge clk); end
    endtask

    initial begin
        $display("=== tb_glue ===");
        repeat (5) @(posedge clk); rstn = 1; repeat (5) @(posedge clk);

        // 1) orden por PUERTOS con 64 bloques: el FSM debe ver count = 64
        io_out(8'h4D, 8'd64);
        io_out(8'h47, 8'h01);
        repeat (4) @(posedge clk);
        check(seen && count_seen == 8'd64, "puertos: OUT #4D,64 + OUT #47,1 -> el FSM ve count=64 (CMD18)");
        clear_start;

        // 2) EL CASO DEL FALLO: count se quedo en 64 y llega una orden por la VENTANA
        mem_out(SDC_CMD, 8'h01);
        repeat (4) @(posedge clk);
        check(seen, "ventana: la orden llega (rstart sube)");
        check(count_seen == 8'd1, "ventana tras puertos: el FSM ve count=1 EN EL MISMO FLANCO (CMD17, no CMD18)");
        check(sdio_count == 8'd1, "ventana: count queda en 1 (force1)");
        clear_start;

        // 3) el dato de la orden por ventana llega entero (bit7 = init)
        mem_out(SDC_CMD, 8'h80);
        repeat (4) @(posedge clk);
        check(ff_sd_init == 1'b1 && !seen, "ventana: OUT #80 pone init y NO rstart");

        // 4) escritura por ventana (bit1) tras una sesion de puertos con count=3
        io_out(8'h4D, 8'd3);
        mem_out(SDC_CMD, 8'h02);
        repeat (4) @(posedge clk);
        check(ff_sd_wstart == 1'b1 && sdio_count == 8'd1, "ventana: escritura -> wstart y count=1");

        if (errors == 0) $display("=== tb_glue: TODO OK ===");
        else             $display("=== tb_glue: %0d FALLOS ===", errors);
        $finish;
    end
endmodule
