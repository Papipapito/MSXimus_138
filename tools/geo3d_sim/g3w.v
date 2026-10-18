`timescale 1ns/1ps
// ============================================================================
// g3w.v -- envoltorios para pasar los bancos de Alex (geo3d/sim/tb_*.v) por el
// geo3d del 138K compilado con GEO3D_CE (fpga/geo3d/geo3d_ce.v).
//
// Cada envoltorio tiene la lista de puertos de Alex (sin ce) y dentro instancia
// la variante con clock enable. run_alex_ce.sh cambia en una copia del banco
// el nombre del modulo instanciado (geo3d_engine -> g3w_engine, etc.).
//
//   G3MODE 1: reloj del banco tal cual y ce = 1 fijo (tiene que dar lo mismo
//             que sin GEO3D_CE, ciclo a ciclo).
//   G3MODE 2: el motor a reloj DOBLE y ce a 1/2; ce = 1 en los flancos que caen
//             en el flanco de subida del reloj del banco (fase A).
//   G3MODE 3: igual, con ce = 1 en los flancos que caen en el de bajada (fase B).
//             Esos flancos van G3EPS ns despues de la bajada: los bancos de Alex
//             cambian sus entradas con asignaciones bloqueantes en la bajada, y
//             asi el motor no compite con ellas en el mismo instante.
//   g3w_bus en G3MODE 2/3 es el enganche real del 138K: clk_eng = clk (85,9) y
//   ce_eng un registro que cambia en cada ciclo (fase A: ce = 1 en los flancos
//   en que el banco de Alex sube su clk_eng; fase B: en los otros).
//
// G3Q = cuarto de periodo del reloj del banco (ns). El ce cambia en la bajada
// del reloj doble, lejos del flanco que lo usa (como un registro de verdad).
// ============================================================================
`ifndef G3MODE
`define G3MODE 1
`endif
`ifndef G3Q
`define G3Q 2.91
`endif
`ifndef G3EPS
`define G3EPS 0.5
`endif

module g3w_cegen #(parameter W = 4) (
    input  wire         clk,
    output wire         clk_e,
    output wire [W-1:0] ce
);
generate if (`G3MODE == 1) begin : g_fix
    assign clk_e = clk;
    assign ce    = {W{1'b1}};
end else begin : g_x2
    reg         c2  = 1'b0;
    reg [W-1:0] cer = (`G3MODE == 2) ? {W{1'b1}} : {W{1'b0}};
    always @(posedge clk) begin              // flanco del reloj doble alineado con la subida
        c2 = 1'b1;
        #(`G3Q) c2 = 1'b0;
        cer = (`G3MODE == 3) ? {W{1'b1}} : {W{1'b0}};   // para el flanco de la bajada
    end
    always @(negedge clk) begin              // flanco del reloj doble alineado con la bajada (+G3EPS)
        #(`G3EPS) c2 = 1'b1;
        #(`G3Q - `G3EPS) c2 = 1'b0;
        cer = (`G3MODE == 2) ? {W{1'b1}} : {W{1'b0}};   // para el flanco de la subida
    end
    assign clk_e = c2;
    assign ce    = cer;
end endgenerate
endmodule

module g3w_engine (
    input  wire       clk,
    input  wire       rst,
    input  wire       sel,
    input  wire       wr_stb,
    input  wire       rd_stb,
    input  wire [7:0] din,
    output wire [7:0] dout,
    output wire       cmd_wr,
    output wire [5:0] cmd_num,
    output wire [7:0] cmd_data,
    input  wire       cmd_ce,
    output wire       run_busy
);
    wire       clk_e;
    wire [3:0] ce;
    g3w_cegen #(.W(4)) u_cg (.clk(clk), .clk_e(clk_e), .ce(ce));
    geo3d_engine u (
        .clk(clk_e), .rst(rst), .ce(ce),
        .sel(sel), .wr_stb(wr_stb), .rd_stb(rd_stb), .din(din), .dout(dout),
        .cmd_wr(cmd_wr), .cmd_num(cmd_num), .cmd_data(cmd_data), .cmd_ce(cmd_ce),
        .run_busy(run_busy)
    );
endmodule

module g3w_core (
    input  wire        clk,
    input  wire        rst,
    input  wire        wr_en,
    input  wire [4:0]  wr_addr,
    input  wire [15:0] wr_data,
    output wire [15:0] sx,
    output wire [15:0] sy,
    output wire [15:0] zout,
    output wire [7:0]  flags,
    output wire        busy,
    output wire        done_pulse
);
    wire       clk_e;
    wire [0:0] ce;
    g3w_cegen #(.W(1)) u_cg (.clk(clk), .clk_e(clk_e), .ce(ce));
    geo3d_core u (
        .clk(clk_e), .rst(rst), .ce(ce[0]),
        .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .sx(sx), .sy(sy), .zout(zout), .flags(flags), .busy(busy), .done_pulse(done_pulse)
    );
endmodule

module g3w_bus #(
    parameter [2:0] PORT_INDEX = 3'd5,
    parameter [2:0] PORT_DATA  = 3'd7
)(
    input  wire       clk,
    input  wire       clk_eng,
    input  wire       reset_n,
    input  wire [2:0] bus_address,
    input  wire       bus_ioreq,
    input  wire       bus_write,
    input  wire       bus_valid,
    input  wire [7:0] bus_wdata,
    output wire       hit,
    output wire       bus_ready,
    output wire [7:0] bus_rdata,
    output wire       bus_rdata_en,
    output wire       cmd_wr,
    output wire [5:0] cmd_num,
    output wire [7:0] cmd_data,
    input  wire       cmd_ce,
    output wire       run_busy
);
    wire       clk_e;
    wire [4:0] ce;
generate if (`G3MODE == 1) begin : g_fix
    assign clk_e = clk_eng;                  // el clk_eng del banco (clk / 2) y ce = 1
    assign ce    = 5'h1F;
end else begin : g_138k
    reg [4:0] cer = (`G3MODE == 2) ? 5'h1F : 5'h00;
    always @(posedge clk) cer <= ~cer;       // como geo_ce del top.v
    assign clk_e = clk;
    assign ce    = cer;
end endgenerate
    geo3d_bus #(.PORT_INDEX(PORT_INDEX), .PORT_DATA(PORT_DATA)) u (
        .clk(clk), .clk_eng(clk_e), .ce_eng(ce), .reset_n(reset_n),
        .bus_address(bus_address), .bus_ioreq(bus_ioreq), .bus_write(bus_write),
        .bus_valid(bus_valid), .bus_wdata(bus_wdata), .hit(hit), .bus_ready(bus_ready),
        .bus_rdata(bus_rdata), .bus_rdata_en(bus_rdata_en),
        .cmd_wr(cmd_wr), .cmd_num(cmd_num), .cmd_data(cmd_data), .cmd_ce(cmd_ce),
        .run_busy(run_busy)
    );
endmodule
