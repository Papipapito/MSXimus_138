// ============================================================================
// tb_frame_trim.sv - v3.8.6: periodo del cuadro del VDP COMPLETO (con y sin el recorte de vdp_timing_control_ssg.v).
// Mide, en ciclos de clk (85,909 MHz), entre flancos de bajada de display_vs, y por cada cuadro:
//   - cuantos flancos de bajada de display_hs hay (el puente HDMI cuenta lineas con ellos: tienen que ser siempre 524),
//   - cuantas lineas con display_en hay (480),
//   - las lineas cuyo largo no es 2736 ciclos: con el recorte, UNA por cuadro de 2736 - 1840 = 896 ciclos, siempre en el mismo sitio.
// +R9=<n>      valor de R#9 (decimal): bit 7 = 212 lineas, bit 3 = entrelazado (el bit 1, NT, se ignora en este VDP). Por defecto 0
// +FRAMES=<n>  cuadros medidos (por defecto 6; se descartan los 3 primeros)
// Imprime una linea "RESULT ..." que run_frame_trim.sh compara con lo esperado. Compilar con -DFRAME_TRIM_OFF = sin recorte.
// Uso: bash run_frame_trim.sh     (WSL, Verilator)
// ============================================================================
`timescale 1ns/1ps

module tb_frame_trim;

localparam real CLK_HALF = 5.8207;
logic reset_n = 0;
logic clk = 0;
always #(CLK_HALF) clk = ~clk;

logic [2:0]  bus_address = 0;
logic        bus_ioreq = 0, bus_write = 0, bus_valid = 0;
logic [7:0]  bus_wdata = 0;
wire  [7:0]  bus_rdata;
wire         bus_rdata_en, bus_ready, int_n;
wire  [17:2] vram_address;
wire         vram_write, vram_valid, vram_refresh;
wire  [31:0] vram_wdata;
wire  [3:0]  vram_wdata_mask;
wire  [4:0]  vram_tag;
wire         display_hs, display_vs, display_en;
wire  [7:0]  display_r, display_g, display_b;

// VRAM muda: el temporizador no depende de ella (solo hay que escribir registros, que no tocan la VRAM)
vdp u_vdp (
    .reset_n(reset_n), .clk(clk), .initial_busy(1'b0),
    .bus_address(bus_address), .bus_ioreq(bus_ioreq), .bus_write(bus_write),
    .bus_valid(bus_valid), .bus_ready(bus_ready),
    .bus_wdata(bus_wdata), .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
    .int_n(int_n),
    .vram_address(vram_address), .vram_write(vram_write),
    .vram_valid(vram_valid), .vram_wdata(vram_wdata),
    .vram_wdata_mask(vram_wdata_mask),
    .vram_rdata(32'h0), .vram_rdata_en(1'b0),
    .vram_tag(vram_tag), .vram_rtag(5'd0),
    .vram_stall(1'b0),
    .vram_refresh(vram_refresh),
    .display_hs(display_hs), .display_vs(display_vs), .display_en(display_en),
    .display_r(display_r), .display_g(display_g), .display_b(display_b),
    .force_highspeed(1'b0), .button(2'b00),
    .pulse0(), .pulse1(), .pulse2(), .pulse3(),
    .pulse4(), .pulse5(), .pulse6(), .pulse7()
);

// ---- bus (como tb_sprite_yjk_vdp: asignaciones bloqueantes tras el flanco) ----
task bus_wr(input [2:0] a, input [7:0] d);
begin
    @(posedge clk); #1;
    bus_address = a; bus_wdata = d;
    bus_ioreq = 1; bus_write = 1; bus_valid = 1;
    @(posedge clk);
    while (!bus_ready) @(posedge clk);
    #1; bus_ioreq = 0; bus_write = 0; bus_valid = 0;
    repeat (20) @(posedge clk);
end
endtask
task vdp_reg(input [5:0] r, input [7:0] d);
begin bus_wr(3'd1, d); bus_wr(3'd1, {2'b10, r}); end
endtask

// ---- medida ----
integer r9 = 0, frames = 6;
longint cyc = 0;
logic   vs_d = 1, hs_d = 1, en_d = 0;
integer nvs = 0;                    // flancos de bajada de display_vs vistos
longint last_vs = 0, last_hs = 0;
integer hs_in_frame = 0, en_in_frame = 0;
integer nmeas = 0;
longint pmin = 64'h7FFFFFFFFFFFFFFF, pmax = 0;
integer hsmin = 1 << 30, hsmax = 0, enmin = 1 << 30, enmax = 0;
integer nshort = 0, nother = 0;     // lineas cortas (<2736) y otras lineas distintas de 2736
integer short_len = 0, short_pos_min = 1 << 30, short_pos_max = -1, short_in_frame = 0;
integer shortmax_per_frame = 0;
integer len;
bit counting = 0;                       // 1 desde el primer cuadro completo medido (alineado con un flanco de VS)

always @(posedge clk) begin
    cyc <= cyc + 1;
    vs_d <= display_vs;
    hs_d <= display_hs;
    en_d <= display_en;
    if (!display_vs && vs_d) begin                    // flanco de bajada de VS = inicio de cuadro
        if (nvs >= 3 && nmeas < frames + 1 && last_vs != 0) begin
            // cierra el cuadro anterior
            if (nvs > 3) begin
                if ((cyc - last_vs) < pmin) pmin = cyc - last_vs;
                if ((cyc - last_vs) > pmax) pmax = cyc - last_vs;
                if (hs_in_frame < hsmin) hsmin = hs_in_frame;
                if (hs_in_frame > hsmax) hsmax = hs_in_frame;
                if (en_in_frame < enmin) enmin = en_in_frame;
                if (en_in_frame > enmax) enmax = en_in_frame;
                if (short_in_frame > shortmax_per_frame) shortmax_per_frame = short_in_frame;
                nmeas <= nmeas + 1;
            end
        end
        last_vs <= cyc;
        nvs <= nvs + 1;
        hs_in_frame = 0; en_in_frame = 0; short_in_frame = 0;
        counting = (nvs >= 3);
    end
    if (counting) begin
        if (!display_hs && hs_d) begin                // flanco de bajada de HS
            if (last_hs != 0) begin
                len = cyc - last_hs;
                if (len < 2736) begin
                    nshort <= nshort + 1;
                    short_len <= len;
                    short_in_frame = short_in_frame + 1;
                    if (hs_in_frame < short_pos_min) short_pos_min <= hs_in_frame;
                    if (hs_in_frame > short_pos_max) short_pos_max <= hs_in_frame;
                end
                else if (len != 2736) nother <= nother + 1;
            end
            last_hs <= cyc;
            hs_in_frame = hs_in_frame + 1;
        end
        if (display_en && !en_d) en_in_frame = en_in_frame + 1;
    end
end

initial begin
    if (!$value$plusargs("R9=%d", r9)) r9 = 0;
    if (!$value$plusargs("FRAMES=%d", frames)) frames = 6;
    repeat (50) @(posedge clk);
    reset_n = 1;
    repeat (200) @(posedge clk);
    vdp_reg(6'd1, 8'h40);
    vdp_reg(6'd9, r9[7:0]);
    wait (nmeas >= frames);
    $display("RESULT R9=%0d frames=%0d period_min=%0d period_max=%0d hs_min=%0d hs_max=%0d en_min=%0d en_max=%0d short_lines=%0d short_len=%0d short_per_frame_max=%0d short_pos_min=%0d short_pos_max=%0d other_lines=%0d",
             r9, nmeas, pmin, pmax, hsmin, hsmax, enmin, enmax, nshort, short_len, shortmax_per_frame, short_pos_min, short_pos_max, nother);
    $finish;
end

initial begin
    #400000000;
    $display("TIMEOUT nvs=%0d nmeas=%0d", nvs, nmeas);
    $finish;
end

endmodule
