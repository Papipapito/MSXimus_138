// ============================================================================
// tb_mstimer.sv - banco del CRONOMETRO DE MILISEGUNDOS de la V3.5d.
//
// Comprueba lo unico que puede salir mal de verdad: que la foto de los 24 bits
// se CONGELA al pedir el byte 0 (indice 25) y que los tres bytes que se leen
// despues son de ESE MISMO instante, aunque el contador siga corriendo. Si no
// fuera atomico, un acarreo entre lectura y lectura daria un salto de 256 ms
// (o de 65 s) justo en medio de una medida, y saldrian tiempos absurdos --
// exactamente la clase de fallo que ya nos comio una noche con el JIFFY.
//
// El contador vive DENTRO de top.v (no es un modulo), asi que aqui va una
// REPLICA LITERAL de ese bloque conectada al sdc_ioport de verdad.
// ⚠️ SI SE TOCA UNO, TOCAR EL OTRO: top.v, "V3.5d: CRONOMETRO LIBRE".
//
// Uso: wsl.exe -d Ubuntu-24.04 bash -lc "cd .../tools/sd_tb && bash run.sh"
// ============================================================================
`timescale 1ns/1ps
module tb_mstimer;
    reg clk = 0; always #18.5185 clk = ~clk;      // 27 MHz
    reg rstn = 0;

    // --- bus, como lo ve el modulo de puertos ---
    reg       sel = 0;
    reg [3:0] addr = 0;
    reg       rd_n = 1, wr_n = 1;
    reg [7:0] din = 0;
    wire       cmd_wr, data_sel, data_wr, buf_ack;
    wire [3:0] saddr_wr;
    wire [7:0] cmd_val, saddr_val, data_val, count;
    wire [8:0] ptr;
    wire [4:0] sdio_idx;

    sdc_ioport dut (.clk(clk), .rstn(rstn), .sel(sel), .addr(addr), .rd_n(rd_n), .wr_n(wr_n),
                    .din(din), .force1(1'b0), .cmd_wr(cmd_wr), .cmd_val(cmd_val),
                    .saddr_wr(saddr_wr), .saddr_val(saddr_val), .data_sel(data_sel),
                    .data_wr(data_wr), .data_val(data_val), .ptr(ptr), .buf_ack(buf_ack),
                    .count(count), .info_idx(sdio_idx));

    // ---- REPLICA LITERAL del bloque de top.v (ver aviso de arriba) ----
    reg [14:0] ms_div = 15'd0;
    reg [23:0] ms_cnt = 24'd0;
    reg [23:0] ms_snap = 24'd0;
    reg [4:0]  ms_idx_d = 5'd0;
    always @(posedge clk or negedge rstn) begin
        if (~rstn) begin
            ms_div   <= 15'd0;
            ms_cnt   <= 24'd0;
            ms_snap  <= 24'd0;
            ms_idx_d <= 5'd0;
        end else begin
            if (ms_div == 15'd26999) begin
                ms_div <= 15'd0;
                ms_cnt <= ms_cnt + 24'd1;
            end else
                ms_div <= ms_div + 15'd1;
            ms_idx_d <= sdio_idx;
            if (sdio_idx == 5'd25 && ms_idx_d != 5'd25) ms_snap <= ms_cnt;
        end
    end
    // lo que devolveria una lectura de #4E (los indices del cronometro)
    wire [7:0] info_dout = (sdio_idx == 5'd25) ? ms_snap[7:0]   :
                           (sdio_idx == 5'd26) ? ms_snap[15:8]  :
                           (sdio_idx == 5'd27) ? ms_snap[23:16] :
                           (sdio_idx == 5'd28) ? 8'h54 : 8'hFF;

    integer errors = 0;
    task check; input cond; input [8*76-1:0] msg;
        begin if (cond) $display("  OK   %0s", msg);
              else begin $display("  FAIL %0s (t=%0t)", msg, $time); errors = errors + 1; end end
    endtask

    // un ciclo de E/S del Z80: ~22 ciclos de clk_27m con IORQ activo
    task io_out; input [3:0] a; input [7:0] d;
        begin @(posedge clk); addr = a; din = d; sel = 1; wr_n = 0;
              repeat (22) @(posedge clk); sel = 0; wr_n = 1; repeat (8) @(posedge clk); end
    endtask
    reg [7:0] got;
    task io_in; input [3:0] a;
        begin @(posedge clk); addr = a; sel = 1; rd_n = 0;
              repeat (20) @(posedge clk); got = info_dout;   // el Z80 lo toma al final
              repeat (2) @(posedge clk); sel = 0; rd_n = 1; repeat (8) @(posedge clk); end
    endtask

    reg [23:0] leido;
    reg [23:0] t1, t2;
    integer k;
    initial begin
        $display("=== tb_mstimer ===");
        repeat (5) @(posedge clk); rstn = 1; repeat (5) @(posedge clk);

        // --- el contador cuenta 1 ms cada 27000 ciclos ---
        repeat (27000) @(posedge clk);
        check(ms_cnt == 24'd1, "27000 ciclos = 1 ms");
        repeat (27000*9) @(posedge clk);
        check(ms_cnt == 24'd10, "270000 ciclos = 10 ms");

        // --- firma: un core con cronometro contesta 'T' en el indice 28 ---
        io_out(4'hE, 8'd28);
        io_in(4'hE);
        check(got == 8'h54, "indice 28: firma 'T' (0x54)");

        // --- lectura atomica: pedir el 25 congela; el contador sigue ---
        io_out(4'hE, 8'd25);
        t1 = ms_snap;
        io_in(4'hE);  leido[7:0]   = got;
        repeat (27000*3) @(posedge clk);         // pasan 3 ms EN MEDIO de la lectura
        io_out(4'hE, 8'd26);
        io_in(4'hE);  leido[15:8]  = got;
        repeat (27000*3) @(posedge clk);         // y otros 3 ms
        io_out(4'hE, 8'd27);
        io_in(4'hE);  leido[23:16] = got;
        check(leido == t1, "los tres bytes son de la MISMA foto pese a los 6 ms de por medio");
        check(ms_cnt > t1 + 24'd5, "y mientras tanto el contador ha seguido corriendo");

        // --- volver a pedir el 25 hace una foto NUEVA ---
        t2 = ms_cnt;
        io_out(4'hE, 8'd25);
        io_in(4'hE);  leido[7:0] = got;
        io_out(4'hE, 8'd26);
        io_in(4'hE);  leido[15:8] = got;
        io_out(4'hE, 8'd27);
        io_in(4'hE);  leido[23:16] = got;
        check(leido != t1, "pedir el 25 otra vez saca una foto NUEVA");
        check(leido >= t2, "y la foto nueva no es anterior al momento de pedirla");

        // --- el acarreo del byte 0 al 1 no puede partir una lectura ---
        // se coloca el contador a mano justo antes de un acarreo de 8 bits
        // (esperarlo de verdad serian 255 ms de simulacion)
        @(posedge clk);
        ms_cnt = 24'h0000FE;
        @(posedge clk);
        io_out(4'hE, 8'd25);
        t1 = ms_snap;
        io_in(4'hE);  leido[7:0] = got;
        repeat (27000*2) @(posedge clk);         // el contador cruza el acarreo
        io_out(4'hE, 8'd26);
        io_in(4'hE);  leido[15:8] = got;
        io_out(4'hE, 8'd27);
        io_in(4'hE);  leido[23:16] = got;
        check(leido == t1, "acarreo en medio: la foto no se parte (era el riesgo real)");

        // --- leer otros indices no toca la foto ---
        t1 = ms_snap;
        io_out(4'hE, 8'd12);
        io_in(4'hE);
        io_out(4'hE, 8'd28);
        io_in(4'hE);
        check(ms_snap == t1, "leer otros indices no rehace la foto");

        if (errors == 0) $display("=== tb_mstimer: TODO OK ===");
        else             $display("=== tb_mstimer: %0d FALLOS ===", errors);
        $finish;
    end

    initial begin
        #40000000;
        $display("FAIL: tope de tiempo");
        $finish;
    end
endmodule
