// tb_pll_stub.sv - modelo del primitivo PLL de Gowin (GW5AST) SOLO para tb_pll_init_orden.sv.
// Engancha cuando: no esta en RESET, hay reloj en CLKIN y ICPSEL/LPFRES son los de la ULTIMA fila del barrido
// del PLL_INIT (hipotesis de modelo, ver el banco). CLKOUT0/1 solo salen con LOCK, como una referencia que
// "aparece" cuando el PLL de arriba ha enganchado.
`timescale 1ns/1ps
module PLL #(
    parameter integer MDIV_SEL = 1
) (
    output LOCK,
    output CLKOUT0, CLKOUT1, CLKOUT2, CLKOUT3, CLKOUT4, CLKOUT5, CLKOUT6, CLKFBOUT,
    input  CLKIN, CLKFB, RESET, PLLPWD, RESET_I, RESET_O,
    input  [5:0] FBDSEL, IDSEL,
    input  [6:0] MDSEL,
    input  [2:0] MDSEL_FRAC,
    input  [6:0] ODSEL0, ODSEL1, ODSEL2, ODSEL3, ODSEL4, ODSEL5, ODSEL6,
    input  [2:0] ODSEL0_FRAC,
    input  [3:0] DT0, DT1, DT2, DT3,
    input  [5:0] ICPSEL,
    input  [2:0] LPFRES,
    input  [1:0] LPFCAP,
    input  [2:0] PSSEL,
    input        PSDIR, PSPULSE,
    input        ENCLK0, ENCLK1, ENCLK2, ENCLK3, ENCLK4, ENCLK5, ENCLK6,
    input        SSCPOL, SSCON,
    input  [6:0] SSCMDSEL,
    input  [2:0] SSCMDSEL_FRAC
);
    // ultima fila del barrido de pll_init.v (fila 4): MULTI_FAC > 34 -> ICP 7 (0x1507); > 16 -> ICP 3 (0x1503); si no, ICP 1 (0x1501); LPF 5
    wire [5:0] good_icp = (MDIV_SEL > 34) ? 6'd7 : (MDIV_SEL > 16) ? 6'd3 : 6'd1;
    wire       good     = (ICPSEL === good_icp) && (LPFRES === 3'd5);
    integer cnt = 0;
    reg lock_r = 1'b0;
    always @(posedge CLKIN or posedge RESET) begin
        if (RESET) begin cnt <= 0; lock_r <= 1'b0; end
        else if (!good) begin cnt <= 0; lock_r <= 1'b0; end
        else begin
            if (cnt < 200) cnt <= cnt + 1;
            else lock_r <= 1'b1;
        end
    end
    assign LOCK     = lock_r;
    assign CLKOUT0  = lock_r & CLKIN;
    assign CLKOUT1  = lock_r & CLKIN;
    assign CLKOUT2  = 1'b0;
    assign CLKOUT3  = 1'b0;
    assign CLKOUT4  = 1'b0;
    assign CLKOUT5  = 1'b0;
    assign CLKOUT6  = 1'b0;
    assign CLKFBOUT = 1'b0;
endmodule
