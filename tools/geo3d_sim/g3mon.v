`timescale 1ns/1ps
// ============================================================================
// g3mon.v -- monitor para los bancos de Alex: registra CADA escritura de
// registro de comando que ve su modelo del V9968 (una linea por cmd_wr = 1 en
// el flanco de subida de clk):  <ciclo de clk> <num> <dato>
// Un cmd_wr (o num/dato con cmd_wr = 1) a X fuera del reset deja "X <ciclo>".
// Va como segundo modulo raiz (iverilog -s <banco> -s g3mon) y mira el banco
// por nombre jerarquico (-DG3TB=<banco>). +seq=<fichero> (por defecto seq.txt).
// ============================================================================
`ifndef G3TB
`define G3TB tb_engine
`endif
module g3mon;
    integer fw, cyc;
    reg [8*256-1:0] fn;
    initial begin
        if (!$value$plusargs("seq=%s", fn)) fn = "seq.txt";
        fw = $fopen(fn, "w"); cyc = 0;
    end
    always @(posedge `G3TB.clk) begin
        cyc = cyc + 1;
        if (`G3TB.rst !== 1'b1) begin
            if (`G3TB.cmd_wr === 1'b1) begin
                if ((^`G3TB.cmd_num === 1'bx) || (^`G3TB.cmd_data === 1'bx))
                    $fwrite(fw, "X %0d\n", cyc);
                else
                    $fwrite(fw, "%0d %0d %02x\n", cyc, `G3TB.cmd_num, `G3TB.cmd_data);
            end else if (`G3TB.cmd_wr !== 1'b0) begin
                $fwrite(fw, "X %0d\n", cyc);
            end
        end
    end
endmodule
