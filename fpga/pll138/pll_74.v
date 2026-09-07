//============================================================================
// pll_74.v - MSXimus_138: PLL para la GW5AST-138 (primitivo PLL). Generado por
// gen_pll138.py a partir del video720/plla/pll_74.v del 60K (primitivo PLLA): mismos
// divisores (leidos del fichero, no copiados a mano), ICP/LPF dinamicos por
// PLL_INIT (pll138/pll_init.v, el que emite el IDE para gw5ast138b). Lista de
// puertos y resto de parametros = console138k/pll_ddr3_mod.v de nand2mario.
// Puerto nuevo init_clk; sin lock (como antes).
//============================================================================
module pll_74 (
    input  wire init_clk,   // 50 MHz (CLK_PERIOD = 20): reloj del PLL_INIT,
    input  wire clkin,
    output wire clkout0,
    output wire clkout1
);
wire [5:0] icpsel;
wire [2:0] lpfres;
wire pll_lock;
wire pll_rst;
    pll_74_MOD u_pll(
        .clkin(clkin),
        .reset(pll_rst),
        .lock(pll_lock),
        .icpsel(icpsel),
        .lpfres(lpfres),
        .lpfcap(2'b00),
        .clkout0(clkout0),
        .clkout1(clkout1)
    );
    PLL_INIT u_pll_init(
        .CLKIN(init_clk),
        .I_RST(1'b0),
        .O_RST(pll_rst),
        .PLLLOCK(pll_lock),
        .O_LOCK(),
        .ICPSEL(icpsel),
        .LPFRES(lpfres)
    );
    defparam u_pll_init.CLK_PERIOD = 20;
    defparam u_pll_init.MULTI_FAC = 55;
endmodule //pll_74
module pll_74_MOD (lock, clkout0, clkout1, clkin, reset, icpsel, lpfres, lpfcap);
output lock;
output clkout0;
output clkout1;
input clkin;
input reset;
input [5:0] icpsel;
input [2:0] lpfres;
input [1:0] lpfcap;
wire clkout2;
wire clkout3;
wire clkout4;
wire clkout5;
wire clkout6;
wire clkfbout;
wire gw_vcc;
wire gw_gnd;
assign gw_vcc = 1'b1;
assign gw_gnd = 1'b0;
PLL PLL_inst (
    .LOCK(lock),
    .CLKOUT0(clkout0),
    .CLKOUT1(clkout1),
    .CLKOUT2(clkout2),
    .CLKOUT3(clkout3),
    .CLKOUT4(clkout4),
    .CLKOUT5(clkout5),
    .CLKOUT6(clkout6),
    .CLKFBOUT(clkfbout),
    .CLKIN(clkin),
    .CLKFB(gw_gnd),
    .RESET(reset),
    .PLLPWD(gw_gnd),
    .RESET_I(gw_gnd),
    .RESET_O(gw_gnd),
    .FBDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .IDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .MDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .MDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL0({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL0_FRAC({gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL1({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL2({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL3({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL4({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL5({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ODSEL6({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT0({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT1({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT2({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .DT3({gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .ICPSEL(icpsel),
    .LPFRES(lpfres),
    .LPFCAP(lpfcap),
    .PSSEL({gw_gnd,gw_gnd,gw_gnd}),
    .PSDIR(gw_gnd),
    .PSPULSE(gw_gnd),
    .ENCLK0(gw_vcc),
    .ENCLK1(gw_vcc),
    .ENCLK2(gw_vcc),
    .ENCLK3(gw_vcc),
    .ENCLK4(gw_vcc),
    .ENCLK5(gw_vcc),
    .ENCLK6(gw_vcc),
    .SSCPOL(gw_gnd),
    .SSCON(gw_gnd),
    .SSCMDSEL({gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd,gw_gnd}),
    .SSCMDSEL_FRAC({gw_gnd,gw_gnd,gw_gnd})
);
defparam PLL_inst.FCLKIN = "27";
defparam PLL_inst.IDIV_SEL = 1;
defparam PLL_inst.FBDIV_SEL = 1;
defparam PLL_inst.ODIV0_SEL = 20;
defparam PLL_inst.ODIV1_SEL = 4;
defparam PLL_inst.ODIV2_SEL = 8;
defparam PLL_inst.ODIV3_SEL = 8;
defparam PLL_inst.ODIV4_SEL = 8;
defparam PLL_inst.ODIV5_SEL = 8;
defparam PLL_inst.ODIV6_SEL = 8;
defparam PLL_inst.MDIV_SEL = 55;
defparam PLL_inst.MDIV_FRAC_SEL = 0;
defparam PLL_inst.ODIV0_FRAC_SEL = 0;
defparam PLL_inst.CLKOUT0_EN = "TRUE";
defparam PLL_inst.CLKOUT1_EN = "TRUE";
defparam PLL_inst.CLKOUT2_EN = "FALSE";
defparam PLL_inst.CLKOUT3_EN = "FALSE";
defparam PLL_inst.CLKOUT4_EN = "FALSE";
defparam PLL_inst.CLKOUT5_EN = "FALSE";
defparam PLL_inst.CLKOUT6_EN = "FALSE";
defparam PLL_inst.CLKFB_SEL = "INTERNAL";
defparam PLL_inst.CLKOUT0_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT1_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT2_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT3_DT_DIR = 1'b1;
defparam PLL_inst.CLKOUT0_DT_STEP = 0;
defparam PLL_inst.CLKOUT1_DT_STEP = 0;
defparam PLL_inst.CLKOUT2_DT_STEP = 0;
defparam PLL_inst.CLKOUT3_DT_STEP = 0;
defparam PLL_inst.CLK0_IN_SEL = 1'b0;
defparam PLL_inst.CLK0_OUT_SEL = 1'b0;
defparam PLL_inst.CLK1_IN_SEL = 1'b0;
defparam PLL_inst.CLK1_OUT_SEL = 1'b0;
defparam PLL_inst.CLK2_IN_SEL = 1'b0;
defparam PLL_inst.CLK2_OUT_SEL = 1'b0;
defparam PLL_inst.CLK3_IN_SEL = 1'b0;
defparam PLL_inst.CLK3_OUT_SEL = 1'b0;
defparam PLL_inst.CLK4_IN_SEL = 2'b00;
defparam PLL_inst.CLK4_OUT_SEL = 1'b0;
defparam PLL_inst.CLK5_IN_SEL = 1'b0;
defparam PLL_inst.CLK5_OUT_SEL = 1'b0;
defparam PLL_inst.CLK6_IN_SEL = 1'b0;
defparam PLL_inst.CLK6_OUT_SEL = 1'b0;
defparam PLL_inst.DYN_DPA_EN = "FALSE";
defparam PLL_inst.CLKOUT0_PE_COARSE = 0;
defparam PLL_inst.CLKOUT0_PE_FINE = 0;
defparam PLL_inst.CLKOUT1_PE_COARSE = 0;
defparam PLL_inst.CLKOUT1_PE_FINE = 0;
defparam PLL_inst.CLKOUT2_PE_COARSE = 0;
defparam PLL_inst.CLKOUT2_PE_FINE = 0;
defparam PLL_inst.CLKOUT3_PE_COARSE = 0;
defparam PLL_inst.CLKOUT3_PE_FINE = 0;
defparam PLL_inst.CLKOUT4_PE_COARSE = 0;
defparam PLL_inst.CLKOUT4_PE_FINE = 0;
defparam PLL_inst.CLKOUT5_PE_COARSE = 0;
defparam PLL_inst.CLKOUT5_PE_FINE = 0;
defparam PLL_inst.CLKOUT6_PE_COARSE = 0;
defparam PLL_inst.CLKOUT6_PE_FINE = 0;
defparam PLL_inst.DYN_PE0_SEL = "FALSE";
defparam PLL_inst.DYN_PE1_SEL = "FALSE";
defparam PLL_inst.DYN_PE2_SEL = "FALSE";
defparam PLL_inst.DYN_PE3_SEL = "FALSE";
defparam PLL_inst.DYN_PE4_SEL = "FALSE";
defparam PLL_inst.DYN_PE5_SEL = "FALSE";
defparam PLL_inst.DYN_PE6_SEL = "FALSE";
defparam PLL_inst.DE0_EN = "FALSE";
defparam PLL_inst.DE1_EN = "FALSE";
defparam PLL_inst.DE2_EN = "FALSE";
defparam PLL_inst.DE3_EN = "FALSE";
defparam PLL_inst.DE4_EN = "FALSE";
defparam PLL_inst.DE5_EN = "FALSE";
defparam PLL_inst.DE6_EN = "FALSE";
defparam PLL_inst.RESET_I_EN = "FALSE";
defparam PLL_inst.RESET_O_EN = "FALSE";
defparam PLL_inst.ICP_SEL = 6'bXXXXXX;
defparam PLL_inst.LPF_RES = 3'bXXX;
defparam PLL_inst.LPF_CAP = 2'b00;
defparam PLL_inst.SSC_EN = "FALSE";
defparam PLL_inst.DYN_IDIV_SEL = "FALSE";
defparam PLL_inst.DYN_FBDIV_SEL = "FALSE";
defparam PLL_inst.DYN_MDIV_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV0_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV1_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV2_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV3_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV4_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV5_SEL = "FALSE";
defparam PLL_inst.DYN_ODIV6_SEL = "FALSE";
defparam PLL_inst.DYN_DT0_SEL = "FALSE";
defparam PLL_inst.DYN_DT1_SEL = "FALSE";
defparam PLL_inst.DYN_DT2_SEL = "FALSE";
defparam PLL_inst.DYN_DT3_SEL = "FALSE";
defparam PLL_inst.DYN_ICP_SEL = "TRUE";
defparam PLL_inst.DYN_LPF_SEL = "TRUE";
endmodule //pll_74_MOD
