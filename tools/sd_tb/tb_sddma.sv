// tb_sddma.sv - banco de la DMA de lectura SD -> RAM (V3.6, fpga/src/sd_dma.sv)
//
// Monta lo mismo que top.v alrededor del SD: sdc_ioport (puertos #47-#4F) y
// sd_reader contra el modelo de tarjeta, el dpram del sector (aqui un array de
// dos puertos), el sd_dma nuevo y una REPLICA del controlador de RAM (la secuencia
// seq0-4 de memory.v con su ventana dl&dh y su ram_busy). El "Z80" son los tasks
// io_out del banco de pegamento. Dos relojes de verdad: 27 y 54 MHz desfasados
// medio periodo, como los hermanos del PLLA.
//
// Comprueba: el registro de destino por #4F; una orden CMD17 con DMA (la CPU se
// congela con el bus en reposo, el bloque acaba en la RAM en el destino, la CPU
// se suelta); un CMD18 de 4 bloques contiguos; y que si el bus no esta en reposo
// la DMA espera. Imprime lo que tarda cada bloque en vaciarse.
`timescale 1ns/1ps
module tb_sddma;
    reg clk54 = 1'b0; always #9.2593  clk54 = ~clk54;
    reg clk27 = 1'b0; always #18.5185 clk27 = ~clk27;
    reg rstn = 1'b0;

    // ---- el bus, como lo ve top.v ----
    reg        bus_iorq_n = 1, bus_mreq = 0, bus_wr_n = 1, bus_rd_n = 1, bus_m1_n = 1;
    reg [15:0] bus_addr = 0;
    reg [7:0]  cpu_dout = 0;
    reg        hold_bus = 0;                       // 1 = "la CPU esta en un ciclo": la DMA debe esperar

    // ---- puertos #47-#4F ----
    reg sdio_sel = 0;
    always @(posedge clk27) sdio_sel <= (bus_iorq_n == 0) && (bus_m1_n == 1) && (bus_addr[7:4] == 4'h4);
    wire       sdio_cmd_wr, sdio_data_sel, sdio_data_wr, sdio_ack;
    wire [7:0] sdio_cmd_val, sdio_saddr_val, sdio_data_val, sdio_count;
    wire [3:0] sdio_saddr_wr;
    wire [8:0] sdio_ptr;
    wire [5:0] sdio_idx;
    wire [22:0] sdio_dma_addr;
    wire        sdio_dma_log;
    sdc_ioport u_sdio (.clk(clk27), .rstn(rstn), .sel(sdio_sel), .addr(bus_addr[3:0]),
        .rd_n(bus_rd_n), .wr_n(bus_wr_n), .din(cpu_dout), .force1(1'b0),
        .cmd_wr(sdio_cmd_wr), .cmd_val(sdio_cmd_val), .saddr_wr(sdio_saddr_wr),
        .saddr_val(sdio_saddr_val), .data_sel(sdio_data_sel), .data_wr(sdio_data_wr),
        .data_val(sdio_data_val), .ptr(sdio_ptr), .buf_ack(sdio_ack), .count(sdio_count),
        .info_idx(sdio_idx), .dma_addr(sdio_dma_addr), .dma_log(sdio_dma_log));

    // ---- replica del pegamento: strobes y LBA ----
    reg        ff_sd_rstart = 0, ff_sd_wstart = 0, ff_sd_init = 0;
    reg [31:0] ff_sd_sector = 0;
    wire       rbusy, rdone, blk_rdy, outen, crc_error, rcrc_error, timeout_error;
    wire [8:0] outaddr;
    wire [7:0] outbyte;
    wire [3:0] card_stat;
    wire [1:0] card_type;
    reg        rdone_d = 0, tmo_d = 0;
    always @(posedge clk27) begin
        rdone_d <= rdone;
        tmo_d   <= timeout_error;
        if (sdio_cmd_wr) begin
            ff_sd_rstart <= ff_sd_rstart | sdio_cmd_val[0];
            ff_sd_wstart <= ff_sd_wstart | sdio_cmd_val[1];
            ff_sd_init   <= ff_sd_init   | sdio_cmd_val[7];
        end
        if (sdio_saddr_wr[0]) ff_sd_sector[ 7: 0] <= sdio_saddr_val;
        if (sdio_saddr_wr[1]) ff_sd_sector[15: 8] <= sdio_saddr_val;
        if (sdio_saddr_wr[2]) ff_sd_sector[23:16] <= sdio_saddr_val;
        if (sdio_saddr_wr[3]) ff_sd_sector[31:24] <= sdio_saddr_val;
        if ((rdone && !rdone_d) || (timeout_error && !tmo_d)) begin
            ff_sd_rstart <= 0; ff_sd_wstart <= 0;
        end
    end

    // ---- el dpram del sector: puerto A (CPU, sin usar aqui) y puerto B (tarjeta y DMA) ----
    reg  [7:0] sbuf [0:511];
    wire       dma_buf_rd;
    wire [8:0] dma_buf_addr;
    wire       wren_b = ff_sd_rstart && outen;
    wire       rden_b = (ff_sd_wstart && outen) || dma_buf_rd;
    wire [8:0] address_b = dma_buf_rd ? dma_buf_addr : outaddr;
    reg  [7:0] q_b = 8'h00;
    always @(posedge clk27) begin
        if (wren_b) sbuf[address_b] <= outbyte;
        if (rden_b) q_b <= sbuf[address_b];
    end

    // ---- sd_reader + tarjeta ----
    wire sdclk, sdcmd, sddat0;
    pullup (sdcmd); pullup (sddat0);
    wire dma_ack;
    wire [21:0] c_size; wire [2:0] c_size_mult; wire [3:0] read_bl_len;
    wire [7:0] mid; wire [15:0] oid; wire [39:0] pnm; wire [31:0] psn;
    sd_reader #(.CLK_DIV(3'd2), .FAST_DIV(16'd0), .SIMULATE(1)) sd1 (
        .rstn(rstn), .clk(clk27), .sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0),
        .card_stat(card_stat), .card_type(card_type),
        .rstart(ff_sd_rstart), .rsector(ff_sd_sector), .rbusy(rbusy), .rdone(rdone),
        .outen(outen), .outaddr(outaddr), .outbyte(outbyte),
        .wstart(ff_sd_wstart), .inbyte(q_b),
        .c_size(c_size), .c_size_mult(c_size_mult), .read_bl_len(read_bl_len),
        .mid(mid), .oid(oid), .pnm(pnm), .psn(psn),
        .crc_error(crc_error), .rcrc_error(rcrc_error), .timeout_error(timeout_error),
        .init(ff_sd_init),
        .rcount(sdio_count), .buf_ack(sdio_ack | dma_ack), .blk_rdy(blk_rdy));
    sd_card_model card (.sdclk(sdclk), .sdcmd(sdcmd), .sddat0(sddat0));

    // ---- replica del controlador de RAM (memory.v, seq0-4) ----
    reg  [7:0]  ram [0:(1<<20)-1];               // 1 MB modelado (direcciones bajas)
    reg  [2:0]  vcnt = 0;                         // fases dl/dh: dl&dh en 0-1, ~dl&~dh en 6-7
    always @(posedge clk54) vcnt <= vcnt + 3'd1;
    wire dl = ~vcnt[2];
    wire dh = ~vcnt[1];
    wire        dma_ram_req;
    wire [22:0] dma_ram_addr;
    wire [7:0]  dma_ram_din;
    reg  [2:0]  seq = 0;
    reg         ram_busy = 0;
    reg  [22:0] sdram_addr = 0;
    reg         sdram_write = 0;
    reg  [7:0]  sdram_din = 0;
    integer     nwrites = 0;
    always @(posedge clk54) begin
        case (seq)
            3'd0: if (dma_ram_req && dl && dh) begin seq <= 3'd1; ram_busy <= 1; end
            3'd1: begin sdram_addr <= dma_ram_addr; sdram_write <= dma_ram_req; sdram_din <= dma_ram_din; seq <= 3'd2; end
            3'd2: if (!dl && !dh) seq <= 3'd3;
            3'd3: begin if (sdram_write) begin ram[sdram_addr[19:0]] <= sdram_din; nwrites = nwrites + 1; end ram_busy <= 0; seq <= 3'd4; end
            3'd4: if (!dma_ram_req) seq <= 3'd0;
            default: seq <= 3'd0;
        endcase
    end

    // ---- la DMA ----
    wire dma_active, dma_frz, dma_rfsh_ok;
    reg  [7:0] mreg0 = 8'd3, mreg1 = 8'd2, mreg2 = 8'd1, mreg3 = 8'd0;   // registros del mapper (FC-FF)
    wire [15:0] cnt_scc, cnt_kon, cnt_a8, cnt_a16;
    wire [7:0] dma_blocks;
    wire bus_idle = bus_iorq_n && !bus_mreq && bus_rd_n && bus_wr_n && (ram_busy == 0) && !hold_bus;
    sd_dma dut (
        .clk(clk54), .rstn(rstn),
        .start(sdio_cmd_wr && sdio_cmd_val[2] && sdio_cmd_val[0]),
        .dest(sdio_dma_addr), .logical(sdio_dma_log),
        .mreg0(mreg0), .mreg1(mreg1), .mreg2(mreg2), .mreg3(mreg3),
        .cnt_en(sdio_cmd_val[3]), .cnt_rst(sdio_cmd_val[4]),
        .bus_idle(bus_idle),
        .blk_rdy(blk_rdy), .rbusy(rbusy), .sd_err(rcrc_error | timeout_error),
        .buf_q(q_b), .ram_busy(ram_busy),
        .active(dma_active), .frz(dma_frz),
        .buf_addr(dma_buf_addr), .buf_rd(dma_buf_rd), .ack(dma_ack),
        .ram_req(dma_ram_req), .ram_addr(dma_ram_addr), .ram_din(dma_ram_din),
        .blocks(dma_blocks), .rfsh_ok(dma_rfsh_ok),
        .cnt_scc(cnt_scc), .cnt_kon(cnt_kon), .cnt_a8(cnt_a8), .cnt_a16(cnt_a16));

    // ---- guardia del refresco: rfsh_ok nunca con ram_req, y >= 40 ciclos antes del 1er byte ----
    integer rfsh_viol = 0; integer rfsh_win = 0;
    always @(posedge clk54) begin
        if (dma_rfsh_ok && dma_ram_req) rfsh_viol = rfsh_viol + 1;
        if (dma_rfsh_ok) rfsh_win = rfsh_win + 1;
    end
    // ---- medidas: cuanto tarda en vaciarse cada bloque (blk_rdy alto -> ack) ----
    real t_rdy = 0; real t_drain_max = 0; real t_drain_last = 0;
    reg  blk_rdy_d = 0;
    always @(posedge clk54) begin
        blk_rdy_d <= blk_rdy;
        if (blk_rdy && !blk_rdy_d) t_rdy = $realtime;
        if (dma_ack && blk_rdy) begin
            t_drain_last = $realtime - t_rdy;
            if (t_drain_last > t_drain_max) t_drain_max = t_drain_last;
        end
    end

    // ---- utilidades ----
    integer errors = 0;
    task check; input cond; input [8*84-1:0] msg;
        begin if (cond) $display("  OK   %0s", msg);
              else begin $display("  FAIL %0s (t=%0t)", msg, $time); errors = errors + 1; end end
    endtask
    task io_out; input [7:0] a; input [7:0] d;            // OUT del Z80 (~22 clk27)
        begin @(posedge clk27); #1 bus_addr = {8'h00, a}; cpu_dout = d; bus_iorq_n = 0; bus_wr_n = 0;
              repeat (22) @(posedge clk27); #1 bus_iorq_n = 1; bus_wr_n = 1;
              @(posedge clk27); #1 cpu_dout = 8'hAA; repeat (7) @(posedge clk27); end
    endtask
    task set_lba; input [31:0] s;
        begin io_out(8'h48, s[7:0]); io_out(8'h49, s[15:8]); io_out(8'h4A, s[23:16]); io_out(8'h4B, s[31:24]); end
    endtask
    task set_dest; input [22:0] d;
        begin io_out(8'h4F, 8'h80); io_out(8'h4F, d[7:0]); io_out(8'h4F, d[15:8]); io_out(8'h4F, {1'b0, d[22:16]}); end
    endtask
    task set_dest_log; input [15:0] a;                     // destino LOGICO (bit7 del byte alto)
        begin io_out(8'h4F, 8'h80); io_out(8'h4F, a[7:0]); io_out(8'h4F, a[15:8]); io_out(8'h4F, 8'h80); end
    endtask
    // cuenta esperada de patrones sobre sectores seguidos (misma tabla que classify_addr)
    integer e_scc, e_kon, e_a8, e_a16;
    task expect_counts; input integer sec0; input integer n;
        integer k, i; reg [7:0] b2, b1, b0;
        begin
            e_scc = 0; e_kon = 0; e_a8 = 0; e_a16 = 0; b2 = 0; b1 = 0;
            for (k = 0; k < n; k = k + 1) for (i = 0; i < 512; i = i + 1) begin
                b0 = card.mem[((sec0 + k) % 16)*512 + i];
                if (b2 == 8'h32) begin
                    if (b1 == 8'h00) begin
                        if (b0 == 8'h50 || b0 == 8'h90 || b0 == 8'hB0 || b0 == 8'h70) e_scc = e_scc + 1;
                        if (b0 == 8'h40 || b0 == 8'h80 || b0 == 8'hA0 || b0 == 8'h60) e_kon = e_kon + 1;
                        if (b0 == 8'h68 || b0 == 8'h78 || b0 == 8'h60 || b0 == 8'h70) e_a8  = e_a8  + 1;
                        if (b0 == 8'h60 || b0 == 8'h70) e_a16 = e_a16 + 1;
                    end else if (b1 == 8'hFF && b0 == 8'h77) e_a16 = e_a16 + 1;
                end
                b2 = b1; b1 = b0;
            end
        end
    endtask
    task wait_frz; input want; input integer maxclk; output ok;
        integer n;
        begin n = 0; while (dma_frz != want && n < maxclk) begin @(posedge clk54); n = n + 1; end ok = (dma_frz == want); end
    endtask
    task wait_card_idle; input integer maxclk;
        integer n;
        begin n = 0; while ((sd1.sdcmd_stat != 5'd17 || rbusy) && n < maxclk) begin @(posedge clk27); n = n + 1; end end
    endtask
    function integer cmp_block; input integer dest; input integer sec;   // bytes distintos
        integer k, m;
        begin m = 0; for (k = 0; k < 512; k = k + 1) if (ram[dest + k] !== card.mem[(sec % 16)*512 + k]) m = m + 1; cmp_block = m; end
    endfunction

    integer i, ok, m;
    real t0, t1;
    initial begin
        $display("=== tb_sddma ===");
        for (i = 0; i < (1<<20); i = i + 1) ram[i] = 8'hEE;
        repeat (5) @(posedge clk27); rstn = 1; repeat (5) @(posedge clk27);

        // ---- tarjeta: init como hace el driver (OUT #47,80) ----
        io_out(8'h47, 8'h80);
        wait_card_idle(4000000);
        check(sd1.sdcmd_stat == 5'd17 && !rbusy, "T0 tarjeta inicializada (IDLING)");

        // ---- T1: registro de destino por #4F ----
        set_dest(23'h7F1234);
        repeat (4) @(posedge clk27);
        check(sdio_dma_addr == 23'h7F1234, "T1 OUT #4F,80 + 3 bytes -> destino 7F1234h");
        io_out(8'h4F, 8'h00);
        repeat (4) @(posedge clk27);
        check(sdio_dma_addr == 23'h7F1234 && sdio_ptr == 9'd0, "T1 OUT #4F,00 sigue rebobinando el puntero y NO toca el destino");
        io_out(8'h4F, 8'h55);
        repeat (4) @(posedge clk27);
        check(sdio_dma_addr == 23'h7F1234, "T1 OUT #4F,55 desarmado: el destino no cambia");

        // ---- T2: CMD17 con DMA (un bloque, sector 3 -> RAM 001000h) ----
        set_dest(23'h001000);
        set_lba(32'd3);
        io_out(8'h4D, 8'd1);
        t0 = $realtime;
        io_out(8'h47, 8'h05);                     // leer + DMA
        wait_frz(1, 4000, ok);
        check(ok, "T2 la CPU se congela tras el OUT (bus en reposo)");
        wait_frz(0, 4000000, ok);
        t1 = $realtime;
        check(ok, "T2 la CPU se suelta al acabar");
        check(!dma_active && !dma_frz, "T2 active y frz a 0 al final");
        check(!rbusy && !ff_sd_rstart, "T2 la orden termino y el strobe se solto");
        check(!rcrc_error && !timeout_error, "T2 sin errores de tarjeta");
        m = cmp_block(23'h001000, 3);
        check(m == 0, "T2 el sector 3 esta entero en RAM 001000h-0011FFh");
        check(dma_blocks == 8'd1, "T2 blocks = 1");
        check(ram[23'h000FFF] == 8'hEE && ram[23'h001200] == 8'hEE, "T2 no escribe fuera del bloque");
        $display("       T2: orden completa %0.1f us (tarjeta + vaciado)", (t1 - t0) / 1000.0);

        // ---- T3: CMD18 de 4 bloques (sectores 5..8 -> RAM 020000h) ----
        set_dest(23'h020000);
        set_lba(32'd5);
        io_out(8'h4D, 8'd4);
        t0 = $realtime;
        io_out(8'h47, 8'h05);
        wait_frz(1, 4000, ok);
        check(ok, "T3 congelada");
        wait_frz(0, 16000000, ok);
        t1 = $realtime;
        check(ok, "T3 suelta al acabar los 4 bloques");
        check(!rbusy && sd1.sdcmd_stat == 5'd17, "T3 sd_reader de vuelta en IDLING (CMD12 contestado)");
        check(!rcrc_error && !timeout_error, "T3 sin errores");
        m = 0; for (i = 0; i < 4; i = i + 1) m = m + cmp_block(23'h020000 + i*512, 5 + i);
        check(m == 0, "T3 los 4 sectores contiguos y correctos en RAM");
        check(dma_blocks == 8'd4, "T3 blocks = 4");
        check(ram[23'h01FFFF] == 8'hEE && ram[23'h020800] == 8'hEE, "T3 no escribe fuera de los 2 KB");
        $display("       T3: 4 bloques en %0.1f us = %0.1f KB/s; vaciado maximo por bloque %0.1f us", (t1 - t0) / 1000.0, 2048.0 / ((t1 - t0) / 1e9) / 1024.0, t_drain_max / 1000.0);

        check(rfsh_viol == 0 && rfsh_win > 1000, "T3 refresco: rfsh_ok nunca con una escritura en vuelo y hubo ventana de espera");

        // ---- T4: el bus NO esta en reposo: la DMA espera hasta que lo este ----
        set_dest(23'h030000);
        set_lba(32'd9);
        io_out(8'h4D, 8'd1);
        hold_bus = 1;
        io_out(8'h47, 8'h05);
        repeat (600) @(posedge clk54);
        check(dma_active && !dma_frz, "T4 con el bus ocupado: active=1 pero frz=0 (espera)");
        hold_bus = 0;
        wait_frz(1, 100, ok);
        check(ok, "T4 al soltar el bus se congela");
        wait_frz(0, 4000000, ok);
        check(ok && cmp_block(23'h030000, 9) == 0, "T4 y el bloque llega bien");

        // ---- T5: orden normal por puertos (sin bit2) tras una DMA: nada se congela ----
        set_lba(32'd2);
        io_out(8'h4D, 8'd1);
        io_out(8'h47, 8'h01);
        repeat (200) @(posedge clk54);
        check(!dma_active && !dma_frz, "T5 OUT #47,01 (sin DMA) no arranca la DMA");
        wait_card_idle(4000000);
        check(!rbusy, "T5 la lectura normal termina");

        // ---- T6: modo LOGICO: 2 bloques en BE00h (pag.2 -> seg mreg2, luego pag.3 -> seg mreg3) ----
        mreg2 = 8'd6; mreg3 = 8'd5;
        set_dest_log(16'hBE00);
        set_lba(32'd10);
        io_out(8'h4D, 8'd2);
        io_out(8'h47, 8'h05);
        wait_frz(1, 4000, ok);
        wait_frz(0, 8000000, ok);
        check(ok, "T6 logico: la CPU se suelta");
        check(cmp_block(6*16384 + 16'h3E00, 10) == 0, "T6 logico: 1er bloque en seg 6 (mreg2) + 3E00h");
        check(cmp_block(5*16384, 11) == 0, "T6 logico: 2o bloque cruza a la pag.3 -> seg 5 (mreg3) + 0");
        check(ram[6*16384 + 16'h3DFF] == 8'hEE && ram[5*16384 + 16'h0200] == 8'hEE, "T6 logico: nada fuera");
        // patron 32 lo hi plantado en la tarjeta para T7: 32 00 50 (SCC), 32 00 60 (kon+a8+a16), 32 FF 77 (a16)
        card.mem[0*512 + 100] = 8'h32; card.mem[0*512 + 101] = 8'h00; card.mem[0*512 + 102] = 8'h50;
        card.mem[1*512 + 200] = 8'h32; card.mem[1*512 + 201] = 8'h00; card.mem[1*512 + 202] = 8'h60;
        card.mem[2*512 + 510] = 8'h32; card.mem[2*512 + 511] = 8'hFF; card.mem[3*512 + 0] = 8'h77;   // cruza el bloque
        card.mem[3*512 + 10]  = 8'h32; card.mem[3*512 + 11]  = 8'h00; card.mem[3*512 + 12]  = 8'h68;
        // ---- T7: contadores: 4 bloques con reset+count (1Dh), luego 1 con count (0Dh), luego 1 sin (05h) ----
        set_dest(23'h040000);
        set_lba(32'd0);
        io_out(8'h4D, 8'd4);
        io_out(8'h47, 8'h1D);
        wait_frz(1, 4000, ok);
        wait_frz(0, 16000000, ok);
        expect_counts(0, 4);
        check(ok && cnt_scc == e_scc && cnt_kon == e_kon && cnt_a8 == e_a8 && cnt_a16 == e_a16, "T7 contadores tras 4 bloques = cuenta por software");
        $display("       T7: scc=%0d kon=%0d a8=%0d a16=%0d (esperado %0d %0d %0d %0d)", cnt_scc, cnt_kon, cnt_a8, cnt_a16, e_scc, e_kon, e_a8, e_a16);
        check(cnt_scc >= 1 && cnt_kon >= 1 && cnt_a8 >= 2 && cnt_a16 >= 2, "T7 los patrones plantados se ven (incluido el que cruza de bloque)");
        set_lba(32'd4);
        io_out(8'h4D, 8'd1);
        io_out(8'h47, 8'h0D);
        wait_frz(1, 4000, ok);
        wait_frz(0, 8000000, ok);
        expect_counts(0, 5);
        check(ok && cnt_scc == e_scc && cnt_kon == e_kon && cnt_a8 == e_a8 && cnt_a16 == e_a16, "T7 sin reset: acumula el 5o bloque");
        set_lba(32'd5);
        io_out(8'h4D, 8'd1);
        io_out(8'h47, 8'h05);
        wait_frz(1, 4000, ok);
        wait_frz(0, 8000000, ok);
        check(ok && cnt_scc == e_scc && cnt_kon == e_kon && cnt_a8 == e_a8 && cnt_a16 == e_a16, "T7 sin bit3: los contadores no cambian");

        if (errors == 0) $display("=== tb_sddma: TODO OK ===");
        else             $display("=== tb_sddma: %0d FALLOS ===", errors);
        $finish;
    end
endmodule
