// ============================================================================
//  tb_t80mem.v — banco del commit e402652 de MSXimus_138 (V3.8.4, 138K):
//  cpu1/DO -> ram_din registrado a 54 MHz antes del cruce a 108 (mem1/SdrDat).
//
//  Piezas REALES (sin tocar):
//    - T80 / G80a de MSXimus_138/fpga/G80A (traducido a Verilog con GHDL --synth)
//    - memory_ctrl de MSXimus_138/fpga/src/memory.v
//    - modelo W9825G6KH de MSXimus_138/tools/sdr16_tb/w9825_model.v
//  Copiado VERBATIM de fpga/top.v (con los `define de la build: ENABLE_WAIT sin
//  ADAPTIVE, ENABLE_M1_WAIT, ENABLE_TURBO, sin TURBO_SIN_GUARDA_SDRAM):
//    - cadencia 3,58 (/30 de 108 + PINFILTER) y turbo 5,37 (/20 + trago)
//    - turbo_eff (conmutado sin glitch), FSM de waits (wait_io), freno M1 (wait_m1)
//    - peticion registrada como mapper_req3 / scc2_req / gm2_req, ram_write, ram_req
//    - cpu_din registrado a 54 MHz
//  VDP: el DOTSTATE de vdp_ssg (dh/dl a clk_27m), con reinicio de linea.
//
//  DLY = etapas de registro a 54 MHz entre cpu_dout y ram_din:
//    0 = antes del commit; 1 = el commit (cpu_dout_ram); >1 = sondeo del margen.
//
//  Comprobaciones:
//    (a) cada escritura de la CPU (mapper_write sube) se captura UNA vez en
//        SdrDat (ff_sdr_seq==010, CPU, escritura) y el byte capturado es el DO
//        de la CPU de esa escritura, con su direccion;
//    (b) el DO no cambia mientras /WR esta bajo;
//    (c) al final, la SDRAM (modelo) = memoria sombra (lo que la CPU escribio);
//    (d) la imagen 8000h-8FFFh se vuelca para compararla entre variantes y con
//        la referencia +ideal=1 (lecturas de la sombra, sin latencia).
//  Margen: tiempo desde el ultimo cambio de ram_din (y de cpu_dout) hasta la
//  captura en SdrDat, minimo sobre todas las escrituras.
// ============================================================================
`timescale 1ns/1ps

module tb_t80mem;

    parameter DLY = 1;

    // ---------------- parametros de ejecucion (plusargs) ----------------
    reg        turbo = 1'b0;     // +turbo=1 -> 5,37 MHz (turbo_eff sigue a turbo en reset)
    reg        ideal = 1'b0;     // +ideal=1 -> lecturas de la sombra (referencia)
    integer    p27 = 0;          // +p27=0/1 -> fase de clk_27m respecto a clk_54m
    integer    vph = 0;          // +vph=0..3 -> arranque del DOTSTATE (en ciclos de 27)
    integer    rph = 0;          // +rph=N -> suelta del reset global (en ciclos de 54)
    reg        stop_on_err = 1'b1; // +stop=0 -> no parar al 20.o error de dato
    integer    tmo_ns;           // +tmo=N -> perro guardian (ns)
    integer    tmp_i;
    initial if ($value$plusargs("stop=%d", tmp_i)) stop_on_err = tmp_i[0];
    reg [8*128-1:0] dumpname;

    // ---------------- relojes (alineados como el PLL) ----------------
    reg clk_108m = 0, clk_54m = 0, clk_27m = 0;
    integer c = 0;
    initial begin
        if (!$value$plusargs("p27=%d", p27)) p27 = 0;
        #4.63;
        forever begin
            clk_108m = (c % 2) == 0;
            clk_54m  = (c % 4) < 2;
            clk_27m  = ((c + 4*p27) % 8) < 4;
            c = c + 1;
            #4.63;
        end
    end

    // ---------------- resets ----------------
    reg bus_reset_n = 1'b0;      // reset global (memory_ctrl, divisores, FSMs)
    reg cpu_rst_n   = 1'b0;      // RESET_n del T80 (bus_reset_n & reset3_n & flash_idle & esp_boot_ok)
    reg vdp_rst     = 1'b1;

    // ---------------- VDP: DOTSTATE de vdp_ssg.vhd ----------------
    localparam CLOCKS_PER_LINE = 1716;
    reg [1:0]  dotstate = 2'b00;
    reg        VideoDHClk = 1'b0, VideoDLClk = 1'b0;
    reg [10:0] hcnt = 0;
    reg [1:0]  linecnt = 0;
    wire       h_end = (hcnt == CLOCKS_PER_LINE-1) || (linecnt == 2'd2 && hcnt == 11'd857); // fin de linea / media linea (fin de campo)
    always @(posedge clk_27m) begin
        if (vdp_rst) begin
            dotstate <= 2'b00; VideoDHClk <= 1'b0; VideoDLClk <= 1'b0; hcnt <= 0; linecnt <= 0;
        end else begin
            hcnt <= h_end ? 11'd0 : hcnt + 1'b1;
            if (h_end) linecnt <= linecnt + 1'b1;
            if (hcnt == CLOCKS_PER_LINE-1) begin
                dotstate <= 2'b00; VideoDHClk <= 1'b1; VideoDLClk <= 1'b1;
            end else begin
                case (dotstate)
                    2'b00: begin dotstate <= 2'b01; VideoDHClk <= 1'b0; VideoDLClk <= 1'b1; end
                    2'b01: begin dotstate <= 2'b11; VideoDHClk <= 1'b1; VideoDLClk <= 1'b0; end
                    2'b11: begin dotstate <= 2'b10; VideoDHClk <= 1'b0; VideoDLClk <= 1'b0; end
                    2'b10: begin dotstate <= 2'b00; VideoDHClk <= 1'b1; VideoDLClk <= 1'b1; end
                endcase
            end
        end
    end

    // ---------------- bus del Z80 ----------------
    wire        bus_m1_n, bus_mreq_n, bus_iorq_n, bus_rd_n, bus_wr_n, bus_rfsh_n, bus_halt_n;
    wire [15:0] bus_addr;
    wire [7:0]  cpu_dout;
    reg  [7:0]  cpu_din = 8'hFF;
    wire        ex_bus_iorq_n = bus_iorq_n;
    wire        ram_busy;

    // ======== CADENCIA 3,58 (top.v: div30 + PINFILTER dn1 + bus_clk_3m6_54) ========
    reg [4:0] div30_cnt;
    reg       clk_3m6_internal;
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin
            div30_cnt <= 0;
            clk_3m6_internal <= 0;
        end else begin
            if (div30_cnt == 5'd14) begin
                clk_3m6_internal <= ~clk_3m6_internal;
                div30_cnt <= 0;
            end else begin
                div30_cnt <= div30_cnt + 1;
            end
        end
    end
    wire bus_clk_3m6;
    PINFILTER dn1(.clk(clk_54m), .reset_n(1'b1), .din(clk_3m6_internal), .dout(bus_clk_3m6));
    reg bus_clk_3m6_54;
    reg bus_clk_3m6_prev_54;
    always @ (posedge clk_54m) begin
        bus_clk_3m6_54 <= bus_clk_3m6;
        bus_clk_3m6_prev_54 <= bus_clk_3m6_54;
    end
    wire clk_enable_3m6_54  = (bus_clk_3m6_54 == 0 && bus_clk_3m6 == 1);
    wire clk_falling_3m6_54 = (bus_clk_3m6_54 == 1 && bus_clk_3m6 == 0);

    // ======== TURBO 5,37 (top.v: div20 + s5m4 + trago) ========
    reg [4:0] div20_cnt;
    reg       clk_5m4_internal;
    always @(posedge clk_108m or negedge bus_reset_n) begin
        if (~bus_reset_n) begin div20_cnt <= 0; clk_5m4_internal <= 0; end
        else if (div20_cnt >= 5'd9) begin clk_5m4_internal <= ~clk_5m4_internal; div20_cnt <= 0; end
        else div20_cnt <= div20_cnt + 1;
    end
    wire clk_enable_5m4_raw, clk_falling_5m4_raw;
    reg  s5m4_a, s5m4_b;
    always @(posedge clk_54m) begin s5m4_a <= clk_5m4_internal; s5m4_b <= s5m4_a; end
    assign clk_enable_5m4_raw  = (s5m4_b == 0 && s5m4_a == 1);
    assign clk_falling_5m4_raw = (s5m4_b == 1 && s5m4_a == 0);
    reg [7:0] pana_per_cnt   = 0;
    reg       pana_skip_pend = 0;
    wire      pana_skip_now  = (pana_per_cnt == 8'd175) && clk_enable_5m4_raw;
    always @(posedge clk_54m) begin
        if (~bus_reset_n) begin
            pana_per_cnt   <= 0;
            pana_skip_pend <= 0;
        end else begin
            if (clk_enable_5m4_raw) begin
                if (pana_per_cnt == 8'd175) begin
                    pana_per_cnt   <= 0;
                    pana_skip_pend <= 1;
                end else
                    pana_per_cnt <= pana_per_cnt + 1'b1;
            end
            if (pana_skip_pend && clk_falling_5m4_raw)
                pana_skip_pend <= 0;
        end
    end
    wire clk_enable_5m4_54  = clk_enable_5m4_raw  & ~pana_skip_now;
    wire clk_falling_5m4_54 = clk_falling_5m4_raw & ~pana_skip_pend;

    // ======== turbo_eff (top.v) ========
    reg  turbo_eff = 1'b0;
    wire wait_io;
    reg  wait_m1 = 1'b1;
    wire cadence_safe = (bus_clk_3m6 == 1'b0 && bus_clk_3m6_54 == 1'b0) &&
                        (s5m4_a == 1'b0 && s5m4_b == 1'b0);
    wire warm_reset_pending = 1'b0;
    always @ (posedge clk_54m) begin
        if (!(cpu_rst_n))
            turbo_eff <= turbo;
        else if (cadence_safe & wait_io & wait_m1
                 & bus_rd_n & bus_wr_n & bus_mreq_n & ex_bus_iorq_n & (ram_busy == 0))
            turbo_eff <= warm_reset_pending ? 1'b0 : turbo;
    end
    wire clk_enable_cpu_54  = turbo_eff ? clk_enable_5m4_54  : clk_enable_3m6_54;
    wire clk_falling_cpu_54 = turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54;

    // ======== peticion de RAM (top.v: mapper_req3 registrado; mapper_write; any_ram_*) ========
    reg mapper_req = 1'b0;
    always @ (posedge clk_54m)
        mapper_req <= ( bus_rfsh_n == 1 && bus_mreq_n == 0 && (bus_rd_n == 0 || bus_wr_n == 0 ) ) ? 1 : 0;
    wire mapper_read  = mapper_req & ~bus_rd_n;
    wire mapper_write = mapper_req & ~bus_wr_n;
    wire stream_active = 1'b0;
    wire [23:0] ram_addr  = (mapper_req == 1) ? { 8'h00, bus_addr } : 24'h7fffff;
    wire ram_write = (stream_active) ? 1'b0 : (mapper_write & ~bus_wr_n);
    wire ram_req   = (stream_active) ? 1'b0 : mapper_req;

    // ======== el objeto del commit: cpu_dout -> ram_din ========
    reg [7:0] dly_pipe [0:15];
    integer k;
    initial for (k = 0; k < 16; k = k + 1) dly_pipe[k] = 8'h00;
    always @(posedge clk_54m) begin
        dly_pipe[0] <= cpu_dout;
        for (k = 1; k < 16; k = k + 1) dly_pipe[k] <= dly_pipe[k-1];
    end
    wire [7:0] cpu_dout_ram = (DLY == 0) ? cpu_dout : dly_pipe[DLY-1];
    wire [7:0] ram_din = cpu_dout_ram;      // rama de la CPU del mux (stream_active = 0)

    // ======== FSM de waits (top.v, ENABLE_WAIT sin ADAPTIVE ni TURBO_SIN_GUARDA_SDRAM) ========
    reg wait_io_ff = 1;
    reg [6:0] state_wait;
    localparam WAIT_IDLE = 7'd0;
    localparam WAIT_STATE1 = 7'd1;
    localparam WAIT_STATE2 = 7'd3;
    localparam WAIT_STATE3 = 7'd2;
    assign wait_io = wait_io_ff;
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            state_wait <= WAIT_IDLE;
            wait_io_ff <= 1;
        end
        else begin
            case (state_wait)
                WAIT_IDLE: begin
                    if ( ram_write == 1 || (turbo_eff == 1 && bus_mreq_n == 0 && bus_rd_n == 0 && ram_busy == 1) || (ex_bus_iorq_n == 0)&& (bus_rd_n == 0 || bus_wr_n == 0) ) begin
                        wait_io_ff <= 0;
                        state_wait <= WAIT_STATE1;
                    end
                end
                WAIT_STATE1: begin
                    if ( (turbo_eff ? clk_enable_5m4_54 : clk_enable_3m6_54) == 1 ) begin
                        state_wait <= WAIT_STATE2;
                    end
                end
                WAIT_STATE2: begin
                    if ( (turbo_eff ? clk_falling_5m4_54 : clk_falling_3m6_54) == 1 && (turbo_eff == 0 || ram_busy == 0) ) begin
                        wait_io_ff <= 1;
                        state_wait <= WAIT_STATE3;
                    end
                end
                WAIT_STATE3: begin
                    if ( bus_rd_n == 1 && bus_wr_n == 1) begin
                        state_wait <= WAIT_IDLE;
                    end
                end
            endcase
        end
    end

    // ======== freno M1 (top.v, ENABLE_M1_WAIT) ========
    reg  bus_m1_n_prev_54 = 1'b1;
    reg  m1_active = 1'b0;
    reg  m1_masked_en = 1'b0;
    reg  m1_masked_fall = 1'b0;
    always @ (posedge clk_54m) begin
        if (~bus_reset_n) begin
            wait_m1          <= 1'b1;
            bus_m1_n_prev_54 <= 1'b1;
            m1_active        <= 1'b0;
            m1_masked_en     <= 1'b0;
            m1_masked_fall   <= 1'b0;
        end else begin
            bus_m1_n_prev_54 <= bus_m1_n;
            if (!m1_active) begin
                if (bus_m1_n_prev_54 == 1'b1 && bus_m1_n == 1'b0) begin
                    m1_active      <= 1'b1;
                    wait_m1        <= 1'b0;
                    m1_masked_en   <= 1'b0;
                    m1_masked_fall <= 1'b0;
                end
            end else begin
                if (clk_enable_cpu_54)  m1_masked_en   <= 1'b1;
                if (clk_falling_cpu_54) m1_masked_fall <= 1'b1;
                if ((m1_masked_en  || clk_enable_cpu_54) &&
                    (m1_masked_fall || clk_falling_cpu_54)) begin
                    wait_m1   <= 1'b1;
                    m1_active <= 1'b0;
                end
            end
        end
    end

    // ======== el T80 real ========
    G80a cpu1 (
        .RESET_n   (cpu_rst_n),
        .CLK_n     (clk_54m),
        .clk_enable (clk_enable_cpu_54 & wait_io & wait_m1),
        .clk_falling(clk_falling_cpu_54 & wait_io & wait_m1),
        .WAIT_n    (1'b1),
        .INT_n     (1'b1),
        .NMI_n     (1'b1),
        .BUSRQ_n   (1'b1),
        .M1_n      (bus_m1_n),
        .MREQ_n    (bus_mreq_n),
        .IORQ_n    (bus_iorq_n),
        .RD_n      (bus_rd_n),
        .WR_n      (bus_wr_n),
        .RFSH_n    (bus_rfsh_n),
        .HALT_n    (bus_halt_n),
        .BUSAK_n   ( ),
        .A         (bus_addr),
        .update_addr( ),
        .DI        (cpu_din),
        .DO        (cpu_dout),
        .Data_Reverse( )
    );

    // ======== memoria sombra (lo que la CPU escribio) ========
    reg [7:0] shadow [0:65535];
    reg [7:0] prog   [0:65535];

    // ======== cpu_din (top.v: registrado a 54 MHz; grupo g3 = mapper_read ? ram_dout) ========
    wire [7:0] ram_dout;
    always @ (posedge clk_54m)
        cpu_din <= mapper_read ? (ideal ? shadow[bus_addr] : ram_dout) : 8'hFF;

    // ======== memory_ctrl real + modelo de SDRAM ========
    wire        sd_clk, sd_cke, sd_cs_n, sd_cas_n, sd_ras_n, sd_wen_n;
    wire [15:0] sd_dq;
    wire [12:0] sd_addr;
    wire [1:0]  sd_ba, sd_dqm;
    wire [15:0] vram_dout, wv_dout, wv2_dout, wv3_dout;
    wire        wv_done, wv2_done, wv3_done;

    memory_ctrl mem1 (
        .clk_27m(clk_54m),
        .clk_108m(clk_108m),
        .bus_reset_n(bus_reset_n),
        .video_dhclk(VideoDHClk),
        .video_dlclk(VideoDLClk),
        .ram_din(ram_din),
        .ram_req(ram_req),
        .ram_write(ram_write),
        .ram_addr(ram_addr),
        .vram_din(8'h00),
        .vram_write(1'b0),
        .vram_addr(17'd0),
        .bus_rfsh_n(bus_rfsh_n),
        .cpu_run(cpu_rst_n),
        .ram_dout(ram_dout),
        .vram_dout(vram_dout),
        .ram_busy(ram_busy),
        .wv_req(1'b0), .wv_we(1'b0), .wv_addr(22'd0), .wv_wdata(8'd0), .wv_dout(wv_dout), .wv_done(wv_done),
        .wv2_req(1'b0), .wv2_we(1'b0), .wv2_addr(22'd0), .wv2_wdata(8'd0), .wv2_dout(wv2_dout), .wv2_done(wv2_done),
        .wv3_req(1'b0), .wv3_we(1'b0), .wv3_addr(22'd0), .wv3_wdata(8'd0), .wv3_dout(wv3_dout), .wv3_done(wv3_done),
        .O_sdram_clk(sd_clk),
        .O_sdram_cke(sd_cke),
        .O_sdram_cs_n(sd_cs_n),
        .O_sdram_cas_n(sd_cas_n),
        .O_sdram_ras_n(sd_ras_n),
        .O_sdram_wen_n(sd_wen_n),
        .IO_sdram_dq(sd_dq),
        .O_sdram_addr(sd_addr),
        .O_sdram_ba(sd_ba),
        .O_sdram_dqm(sd_dqm)
    );

    w9825_model sdram (
        .clk(sd_clk), .cke(sd_cke), .cs_n(sd_cs_n), .ras_n(sd_ras_n), .cas_n(sd_cas_n),
        .we_n(sd_wen_n), .addr(sd_addr), .ba(sd_ba), .dqm(sd_dqm), .dq(sd_dq)
    );

    // direccion de CPU (24 bits, aqui {8'h00, A}) -> indice del modelo {ba, fila, col}
    function [23:0] midx(input [23:0] a);
        midx = { a[22:21], 1'b0, a[23], a[12:2], a[20:13], a[1] };
    endfunction

    // ======== monitores ========
    integer n_wr = 0, n_cap = 0, n_err_dat = 0, n_err_adr = 0, n_err_do = 0, n_err_cnt = 0;
    integer n_reads = 0;
    reg [15:0] wr_a;
    reg [7:0]  wr_d;
    reg        wr_pend = 1'b0;
    reg        mw_d = 1'b0;
    realtime   t_din = 0, t_do = 0, t_wrfall = 0, t_req = 0;
    realtime   m_din_min = 1.0e9, m_do_min = 1.0e9, m_req_min = 1.0e9, m_req_max = 0, m_wr_min = 1.0e9;
    realtime   m_dowr_min = 1.0e9;   // ultimo cambio de DO -> subida de ram_write (la peticion)
    // retencion: captura -> siguiente cambio de ram_din (el dato tiene que seguir quieto hasta la captura)
    realtime   t_cap = 0, m_hold_min = 1.0e9;
    reg        hold_pend = 1'b0;
    always @(ram_din) begin
        t_din = $realtime;
        if (hold_pend) begin
            if ($realtime - t_cap < m_hold_min) m_hold_min = $realtime - t_cap;
            hold_pend = 1'b0;
        end
    end
    always @(cpu_dout) t_do  = $realtime;
    always @(negedge bus_wr_n) t_wrfall = $realtime;

    // (a)+(b): intencion de escritura = subida de mapper_write (vista en el flanco de 54)
    reg in_wr = 1'b0;
    always @(posedge clk_54m) begin
        mw_d <= mapper_write;
        if (mapper_write && !mw_d) begin
            if (wr_pend) begin
                n_err_cnt = n_err_cnt + 1;
                $display("ERROR [%0t] escritura %04x sin capturar antes de la siguiente (%04x)", $time, wr_a, bus_addr);
            end
            wr_a = bus_addr; wr_d = cpu_dout; wr_pend = 1'b1;
            t_req = $realtime;
            n_wr = n_wr + 1;
            shadow[bus_addr] = cpu_dout;
            in_wr = 1'b1;
            if ($realtime - t_do < m_dowr_min) m_dowr_min = $realtime - t_do;
        end else if (bus_wr_n == 1'b1) begin
            in_wr = 1'b0;
        end
        // (b) el DO no se mueve mientras /WR sigue bajo
        if (in_wr && bus_wr_n == 0 && cpu_dout !== wr_d) begin
            n_err_do = n_err_do + 1;
            $display("ERROR [%0t] DO cambia con /WR bajo: %02x -> %02x en %04x", $time, wr_d, cpu_dout, bus_addr);
        end
    end

    // captura del dato de la CPU en SdrDat (memory.v: ff_sdr_seq==010, CPU, escritura)
    wire cap_cpu_wr = (mem1.ff_sdr_seq == 3'b010) && (mem1.SdrSta[2] == 1'b1) && (mem1.SdrSta[0] == 1'b1)
                      && (VideoDLClk == 1'b0) && !mem1.SdrWav && !mem1.SdrWv2 && !mem1.SdrWv3;
    // (durante la init de memory_ctrl, RstSeq 8..23, SdrSta queda en 1xx con los bits bajos del MRS (11)
    //  y el controlador emite WRITEs de ram_din a la direccion 0 en las medias de CPU: es previo al commit,
    //  ocurre con la CPU en reset y en placa lo pisa la copia del pack. No se cuenta: se ignora con la CPU en reset.)
    integer n_cap_init = 0;
    always @(posedge clk_108m) begin
        if (cap_cpu_wr && !cpu_rst_n) n_cap_init = n_cap_init + 1;
        if (cap_cpu_wr && cpu_rst_n) begin
            n_cap = n_cap + 1;
            if (!wr_pend) begin
                n_err_cnt = n_err_cnt + 1;
                $display("ERROR [%0t] captura sin escritura pendiente (ram_din=%02x addr=%06x)", $time, ram_din, mem1.sdram_addr);
            end else begin
                if (ram_din !== wr_d) begin
                    n_err_dat = n_err_dat + 1;
                    if (n_err_dat <= 20)
                        $display("ERROR [%0t] dato capturado %02x, la CPU escribio %02x en %04x (ram_din cambio hace %0.2f ns)",
                                 $time, ram_din, wr_d, wr_a, $realtime - t_din);
                    if (n_err_dat == 20 && stop_on_err) begin
                        $display("escrituras CPU=%0d capturas SdrDat=%0d | errores: dato=%0d (se para al 20.o)", n_wr, n_cap, n_err_dat);
                        $display("RESULTADO: FAIL");
                        $finish;
                    end
                end
                if (mem1.sdram_addr[15:0] !== wr_a) begin
                    n_err_adr = n_err_adr + 1;
                    $display("ERROR [%0t] direccion capturada %06x, la CPU escribio en %04x", $time, mem1.sdram_addr, wr_a);
                end
                if ($realtime - t_din < m_din_min) m_din_min = $realtime - t_din;
                if ($realtime - t_do  < m_do_min)  m_do_min  = $realtime - t_do;
                if ($realtime - t_req < m_req_min) m_req_min = $realtime - t_req;
                if ($realtime - t_req > m_req_max) m_req_max = $realtime - t_req;
                if ($realtime - t_wrfall < m_wr_min) m_wr_min = $realtime - t_wrfall;
                wr_pend = 1'b0;
                t_cap = $realtime; hold_pend = 1'b1;
            end
        end
    end

    // ======== secuencia ========
    integer i, ok_img, bad_img, nfin;
    reg [7:0] mb;
    reg [15:0] w;
    reg fin_io = 1'b0;
    always @(posedge clk_54m)
        if (bus_iorq_n == 0 && bus_wr_n == 0 && bus_addr[7:0] == 8'hFF) fin_io <= 1'b1;

    initial begin
        if ($value$plusargs("turbo=%d", i)) turbo = i[0];
        if ($value$plusargs("ideal=%d", i)) ideal = i[0];
        if (!$value$plusargs("vph=%d", vph)) vph = 0;
        if (!$value$plusargs("rph=%d", rph)) rph = 0;
        if (!$value$plusargs("dump=%s", dumpname)) dumpname = "img.hex";

        // imagen inicial: programa + ceros (se carga en la SDRAM DESPUES de la init, como la copia del pack)
        for (i = 0; i < 65536; i = i + 1) prog[i] = 8'h00;
        $readmemh("prog.hex", prog);
        for (i = 0; i < 65536; i = i + 1) shadow[i] = prog[i];

        $display("=== tb_t80mem: DLY=%0d turbo=%0d ideal=%0d p27=%0d vph=%0d rph=%0d ===", DLY, turbo, ideal, p27, vph, rph);

        // reset global; el DOTSTATE arranca con su propio desfase
        repeat (8 + vph) @(posedge clk_27m);
        vdp_rst <= 1'b0;
        repeat (20 + rph) @(posedge clk_54m);
        bus_reset_n <= 1'b1;

        // init de la SDRAM acelerada (como sdr16_tb, T1) con el T80 en reset
        while (mem1.RstSeq !== 5'b11111) begin
            @(negedge clk_108m);
            force mem1.FreeCounter = 16'hFFF0;
            @(negedge clk_108m);
            release mem1.FreeCounter;
            repeat (90) @(posedge clk_108m);
        end
        repeat (64) @(posedge clk_108m);
        if (!sdram.mode_set) $display("ERROR: la SDRAM no recibio el MRS");
        for (i = 0; i < 65536; i = i + 2) sdram.mem[midx({8'h00, i[15:0]})] = { prog[i+1], prog[i] };
        $display("init de la SDRAM hecha en %0.1f us (capturas de init ignoradas: %0d); imagen cargada", $realtime/1000.0, n_cap_init);

        @(posedge clk_54m);
        cpu_rst_n <= 1'b1;

        // a correr hasta el OUT (0FFh),A
        wait (fin_io == 1'b1);
        repeat (400) @(posedge clk_108m);

        // (c) SDRAM = sombra, en los 64 KB
        bad_img = 0;
        for (i = 0; i < 65536; i = i + 1) begin
            w = sdram.mem[midx({8'h00, i[15:0]})];
            mb = i[0] ? w[15:8] : w[7:0];
            if (mb !== shadow[i]) begin
                bad_img = bad_img + 1;
                if (bad_img <= 10) $display("ERROR imagen: %04x SDRAM=%02x sombra=%02x", i, mb, shadow[i]);
            end
        end
        // (d) volcado 8000h-8FFFh de la sombra
        begin : volcado
            integer f;
            f = $fopen(dumpname, "w");
            for (i = 16'h8000; i < 16'h9000; i = i + 1) $fdisplay(f, "%02x", shadow[i]);
            $fclose(f);
        end

        $display("escrituras CPU=%0d capturas SdrDat=%0d | errores: dato=%0d direccion=%0d DO-con-WR=%0d cuenta=%0d imagen=%0d",
                 n_wr, n_cap, n_err_dat, n_err_adr, n_err_do, n_err_cnt + ((n_wr != n_cap) ? 1 : 0), bad_img);
        $display("margen minimo (captura en SdrDat - ultimo cambio de ram_din) = %0.2f ns = %0.2f ciclos de 54 MHz",
                 m_din_min, m_din_min / 18.52);
        $display("margen minimo (captura - ultimo cambio de cpu1/DO)            = %0.2f ns = %0.2f ciclos de 54 MHz",
                 m_do_min, m_do_min / 18.52);
        $display("subida de ram_write -> captura: min %0.2f ns (%0.2f ciclos) max %0.2f ns (%0.2f ciclos); /WR baja -> captura: min %0.2f ns",
                 m_req_min, m_req_min / 18.52, m_req_max, m_req_max / 18.52, m_wr_min);
        $display("ultimo cambio de DO -> subida de ram_write: min %0.2f ns = %0.2f ciclos de 54 MHz",
                 m_dowr_min, m_dowr_min / 18.52);
        $display("retencion (captura en SdrDat -> siguiente cambio de ram_din): min %0.2f ns = %0.2f ciclos de 54 MHz",
                 m_hold_min, m_hold_min / 18.52);
        $display("suma B10 en 8A00h = %02x%02x | fin en %0.1f us de simulacion",
                 shadow[16'h8A01], shadow[16'h8A00], $realtime / 1000.0);
        if (n_err_dat == 0 && n_err_adr == 0 && n_err_do == 0 && n_err_cnt == 0 && n_wr == n_cap && bad_img == 0 && n_wr > 0)
            $display("RESULTADO: PASS");
        else
            $display("RESULTADO: FAIL");
        $finish;
    end

    // perro guardian
    initial begin
        if (!$value$plusargs("tmo=%d", tmo_ns)) tmo_ns = 60000000;
        #(tmo_ns);
        $display("TIMEOUT pc~%04x wr=%0d cap=%0d", bus_addr, n_wr, n_cap);
        $display("RESULTADO: FAIL");
        $finish;
    end

endmodule
