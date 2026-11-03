// ============================================================================
// tb_pll_init_orden.sv - v3.8.4b: orden de arranque de la cadena de PLL del HDMI del 138K.
//
// Usa los .v REALES de fpga/pll138 (pll_init.v, pll_27.v, pll_hdmiref.v, pll_74.v) y sustituye SOLO el
// primitivo PLL de Gowin por un modelo (tb_pll_stub.sv). Dos cadenas desde el mismo pll_27:
//   A = como la v3.8.4: la referencia de 74,25 sale de un PLL que espera a pll27_lock (pll_ddr3 en el top; aqui
//       pll_hdmiref con reset=~pll27_lock hace de sustituto), y pll_74 arranca con I_RST fijo a 0
//   B = como la v3.8.4b: pll_hdmiref espera a pll27 y pll_74 espera al lock de pll_hdmiref (I_RST = ~lock)
// Ademas pll_86 (VDP, 85,9 MHz) en sus dos versiones: I_RST fijo a 0 (v3.8.4) y I_RST = ~pll27_lock (v3.8.4b).
//
// El PLL_INIT calibra ICP/LPF UNA SOLA VEZ (~2,6 ms por paso, 5 pasos de barrido + 1 de ajuste) y se queda
// en STATE7 para siempre. Si en esa ventana no hay reloj de entrada, todos los PLLLOCK muestreados son 0 y
// elige la fila por defecto (RomAddrVld = 8).
//
// QUE ES Y QUE NO ES: el modelo del PLL solo engancha si ICPSEL/LPFRES son los de la ULTIMA fila del barrido
// (hipotesis de trabajo, el silicio real puede tener una ventana mas ancha). Lo que demuestra es el MECANISMO
// (la calibracion necesita ver el reloj) y que las conexiones de los wrappers nuevos son correctas; no que el
// PLL real fallara de este modo en la v3.8.4.
// ============================================================================
`timescale 1ns/1ps

module tb_pll_init_orden;

    logic clk50 = 0;
    always #10 clk50 = ~clk50;

    // pll_27: desde el pad de 50 MHz, igual que el top
    wire clk27, pll27_lock;
    pll_27 u27 (.init_clk(clk50), .clkin(clk50), .clkout0(clk27), .lock_o(pll27_lock));

    // ---- A: v3.8.4 (I_RST fijo a 0 en la etapa que cuelga de otra) ----
    wire a_ref, a_hdmi5, a_pix, a_ref_lock, a_pix_lock;
    pll_hdmiref ua_ref (.init_clk(clk50), .clkin(clk27), .reset(~pll27_lock),
                        .clkout0(a_ref), .lock(a_ref_lock));
    pll_74      ua_pix (.init_clk(clk50), .clkin(a_ref), .reset(1'b0),
                        .clkout0(a_pix), .clkout1(a_hdmi5), .lock(a_pix_lock));

    // ---- B: v3.8.4b (cada etapa espera al lock de su referencia) ----
    wire b_ref, b_hdmi5, b_pix, b_ref_lock, b_pix_lock;
    pll_hdmiref ub_ref (.init_clk(clk50), .clkin(clk27), .reset(~pll27_lock),
                        .clkout0(b_ref), .lock(b_ref_lock));
    pll_74      ub_pix (.init_clk(clk50), .clkin(b_ref), .reset(~b_ref_lock),
                        .clkout0(b_pix), .clkout1(b_hdmi5), .lock(b_pix_lock));

    // pll_86 (VDP): v3.8.4 (I_RST fijo a 0) y v3.8.4b (I_RST = ~pll27_lock)
    wire a_86, b_86, a_86_lock, b_86_lock;
    pll_86 ua_86 (.init_clk(clk50), .clkin(clk27), .reset(1'b0),        .clkout0(a_86), .lock(a_86_lock));
    pll_86 ub_86 (.init_clk(clk50), .clkin(clk27), .reset(~pll27_lock), .clkout0(b_86), .lock(b_86_lock));

    // tiempos de subida de cada lock (ms)
    real t27 = -1, ta_ref = -1, ta_pix = -1, tb_ref = -1, tb_pix = -1, ta_86 = -1, tb_86 = -1;
    always @(posedge a_86_lock)    if (ta_86  < 0) ta_86  = $realtime / 1.0e6;
    always @(posedge b_86_lock)    if (tb_86  < 0) tb_86  = $realtime / 1.0e6;
    always @(posedge pll27_lock)   if (t27    < 0) t27    = $realtime / 1.0e6;
    always @(posedge a_ref_lock)   if (ta_ref < 0) ta_ref = $realtime / 1.0e6;
    always @(posedge a_pix_lock)   if (ta_pix < 0) ta_pix = $realtime / 1.0e6;
    always @(posedge b_ref_lock)   if (tb_ref < 0) tb_ref = $realtime / 1.0e6;
    always @(posedge b_pix_lock)   if (tb_pix < 0) tb_pix = $realtime / 1.0e6;

    integer errs = 0;
    task chk(input bit ok, input string msg);
        begin
            if (!ok) begin $display("FALLO: %s", msg); errs = errs + 1; end
        end
    endtask

    initial begin
        #70_000_000;   // 70 ms
        $display("pll_27       lock a los %0.2f ms", t27);
        $display("A (v3.8.4 ) pll_hdmiref: ICPSEL=%0d LPFRES=%0d lock=%0d (t=%0.2f ms)  pll_74: ICPSEL=%0d LPFRES=%0d lock=%0d (t=%0.2f ms)",
                 ua_ref.icpsel, ua_ref.lpfres, a_ref_lock, ta_ref, ua_pix.icpsel, ua_pix.lpfres, a_pix_lock, ta_pix);
        $display("B (v3.8.4b) pll_hdmiref: ICPSEL=%0d LPFRES=%0d lock=%0d (t=%0.2f ms)  pll_74: ICPSEL=%0d LPFRES=%0d lock=%0d (t=%0.2f ms)",
                 ub_ref.icpsel, ub_ref.lpfres, b_ref_lock, tb_ref, ub_pix.icpsel, ub_pix.lpfres, b_pix_lock, tb_pix);

        $display("pll_86  A (I_RST=0): lock=%0d (t=%0.2f ms)   B (I_RST=~pll27_lock): lock=%0d (t=%0.2f ms)", a_86_lock, ta_86, b_86_lock, tb_86);
        chk(pll27_lock === 1'b1,         "pll_27 no engancho");
        chk(b_86_lock === 1'b1,          "B: pll_86 no engancho");
        chk(b_ref_lock === 1'b1,         "B: pll_hdmiref no engancho");
        chk(b_pix_lock === 1'b1,         "B: pll_74 no engancho");
        chk(tb_ref > t27 && tb_pix > tb_ref, "B: el orden de locks no es pll_27 < hdmiref < pll_74");
        chk(a_ref_lock === 1'b1,         "A: la referencia (que espera a pll27) deberia enganchar");
        chk(a_pix_lock === 1'b0,         "A: se esperaba que pll_74 (I_RST=0, referencia tardia) NO engancho con el modelo");
        if (errs == 0) $display("*** PLL_INIT_ORDEN: TODO OK (B engancha en orden; A, pll_74 con I_RST fijo y la referencia tardia, no) ***");
        else           $display("*** PLL_INIT_ORDEN: %0d FALLOS ***", errs);
        $finish;
    end

endmodule
