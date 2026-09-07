
//--------------------------------------------------------------------------------------------------------
// Module  : sdcmd_ctrl
// Type    : synthesizable, IP's sub module
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: sdcmd signal control,
//           instantiated by sd_reader
//--------------------------------------------------------------------------------------------------------

module sdcmd_ctrl (
    input  wire         rstn,
    input  wire         clk,
    // SDcard signals (sdclk and sdcmd)
    output reg          sdclk,
    input wire          sdcmdin,
    output reg          sdcmdout,
    output reg          sdcmdoe,
    // config clk freq
    input  wire  [15:0] clkdiv,
    // V3.5c: parar sdclk (en nivel BAJO) mientras hold=1. Lo usa el multibloque
    // (CMD18) entre bloque y bloque: con un solo bufer de 512 B, la tarjeta no
    // puede seguir mandando hasta que el Z80 lo haya vaciado, y la spec permite
    // parar el reloj en cualquier momento de la transferencia de datos.
    input  wire         hold,
    // user input signal
    input  wire         start,
    input  wire  [15:0] precnt,
    input  wire  [ 5:0] cmd,
    input  wire  [31:0] arg,
    // user output signal
    output reg          busy,
    output reg          done,
    output reg          timeout,
    output reg          syntaxe,
    output wire  [31:0] resparg,
    output wire  [127:1] r2
);


initial {busy, done, timeout, syntaxe} = 0;
initial sdclk = 1'b0;

localparam [7:0] TIMEOUT = 8'd250;

//reg sdcmdoe  = 1'b0;
//reg sdcmdout = 1'b1;

// sdcmd tri-state driver
//assign sdcmd = sdcmdoe ? sdcmdout : 1'bz;
//wire sdcmdin = sdcmdoe ? 1'b1 : sdcmd;

function  [6:0] CalcCrc7;
    input [6:0] crc;
    input [0:0] inbit;
//function automatic logic [6:0] CalcCrc7(input logic [6:0] crc, input logic inbit);
begin
    CalcCrc7 = ( {crc[5:0],crc[6]^inbit} ^ {3'b0,crc[6]^inbit,3'b0} );
end
endfunction

reg  [ 5:0] req_cmd = 6'd0;    // request[45:40]
reg  [31:0] req_arg = 0;       // request[39: 8]
reg  [ 6:0] req_crc = 7'd0;    // request[ 7: 1]
wire [51:0] request = {6'b111101, req_cmd, req_arg, req_crc, 1'b1};

//struct packed {
reg         resp_st;
reg  [ 5:0] resp_cmd;
reg  [31:0] resp_arg;
reg  [94:0] resp_r2; 
//} response = 0;

assign r2[127:1] = { resp_arg, resp_r2 };

// V3.5: LONGITUD DE RESPUESTA POR COMANDO. El original desplazaba SIEMPRE 134
// bits tras el start bit (la longitud de R2) y solo entonces daba 'done': con
// una R1 de 48 bits el host se quedaba CIEGO 87 ciclos despues del end bit. Si
// la tarjeta empezaba el bloque de datos en esa ventana (la spec permite NAC=2),
// la lectura salia desplazada. A 2,25 MHz eran 39 us y las tarjetas tardan mas
// en servir; a 6,75 MHz son 13 us, y ya no. Ahora R2 (CMD2/9/10) = 134, el
// resto = 46, y 'done' cae en el end bit. Los campos de una respuesta corta
// quedan en la parte baja del registro de desplazamiento (46 bits):
//   T = [45], cmd = [44:39], arg = [38:7], crc7 = [6:0].
reg         long_resp = 1'b0;
wire        eff_st  = long_resp ? resp_st  : resp_r2[45];
wire [5:0]  eff_cmd = long_resp ? resp_cmd : resp_r2[44:39];
assign resparg = long_resp ? resp_arg : resp_r2[38:7];

reg  [17:0] clkdivr = 18'h3FFFF;
reg  [17:0] clkcnt  = 0;
// V3.5: la respuesta se muestrea con el pad tal como estaba EN el flanco de
// subida de sdclk (clkcnt==2: el sincronizador de 2 FF del padre ya trae el
// pad del ciclo clkcnt==0, que es cuando el registro sdclk acaba de subir), y
// la FSM la consume en el flanco siguiente. Antes se leia sdcmdin en el ciclo
// de la subida = pad de 2 ciclos ANTES, en plena fase baja: valido solo si el
// periodo era largo. Asi el punto de muestreo no depende del divisor.
reg         sdcmdin_s = 1'b1;
reg  [15:0] cnt1 = 0;
reg  [ 5:0] cnt2 = 6'h3F;
reg  [ 7:0] cnt3 = 0;
reg  [ 7:0] cnt4 = 8'hFF;


always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        {busy, done, timeout, syntaxe} <= 0;
        sdclk <= 1'b0;
        {sdcmdoe, sdcmdout} <= 2'b01;
        {req_cmd, req_arg, req_crc} <= 0;
        {resp_st, resp_cmd, resp_arg} <= 0;
        clkdivr <= 18'h3FFFF;
        clkcnt  <= 0;
        sdcmdin_s <= 1'b1;
        long_resp <= 1'b0;
        cnt1 <= 0;
        cnt2 <= 6'h3F;
        cnt3 <= 0;
        cnt4 <= 8'hFF;
    end else begin
        {done, timeout, syntaxe} <= 0;
        
        // V3.5c: con hold, el contador se congela justo despues del flanco de
        // bajada (clkcnt == clkdivr+1, sdclk ya a 0) y ahi se queda: ni flancos
        // ni muestreo hasta que hold baje. El resto del ciclo no cambia.
        if (hold && ~sdclk && clkcnt == clkdivr + 18'd1)
            clkcnt <= clkcnt;
        else
            clkcnt <= ( clkcnt < {clkdivr[16:0],1'b1} ) ? (clkcnt+18'd1) : 18'd0;
        
        if     (clkcnt == 18'd0)
            clkdivr <= {2'h0, clkdiv} + 18'd1;
        
        if (clkcnt == clkdivr)
            sdclk <= 1'b0;
        else if (clkcnt == {clkdivr[16:0],1'b1} )
            sdclk <= 1'b1;

        if (clkcnt == 18'd2)
            sdcmdin_s <= sdcmdin;

        if(~busy) begin
            if(start) busy <= 1'b1;
            req_cmd <= cmd;
            req_arg <= arg;
            req_crc <= 0;
            cnt1 <= precnt;
            cnt2 <= 6'd51;
            cnt3 <= TIMEOUT;
            long_resp <= (cmd == 6'd2 || cmd == 6'd9 || cmd == 6'd10);
            cnt4 <= (cmd == 6'd2 || cmd == 6'd9 || cmd == 6'd10) ? 8'd134 : 8'd46;
        end else if(done) begin
            busy <= 1'b0;
        end else if( clkcnt == clkdivr) begin
            {sdcmdoe, sdcmdout} <= 2'b01;
            if     (cnt1 != 16'd0) begin
                cnt1 <= cnt1 - 16'd1;
            end else if(cnt2 != 6'h3F) begin
                cnt2 <= cnt2 - 6'd1;
                {sdcmdoe, sdcmdout} <= {1'b1, request[cnt2]};
                if(cnt2>=8 && cnt2<48) req_crc <= CalcCrc7(req_crc, request[cnt2]);
            end
        end else if( clkcnt == {clkdivr[16:0],1'b1} && cnt1==16'd0 && cnt2==6'h3F ) begin
            if(cnt3 != 8'd0) begin
                cnt3 <= cnt3 - 8'd1;
                if(~sdcmdin_s)
                    cnt3 <= 8'd0;
                else if(cnt3 == 8'd1)
                    {done, timeout, syntaxe} <= 3'b110;
            end else if(cnt4 != 8'hFF) begin
                cnt4 <= cnt4 - 8'd1;
                if(cnt4 >= 8'd1)
                    {resp_st, resp_cmd, resp_arg, resp_r2} <= {resp_cmd, resp_arg, resp_r2, sdcmdin_s};
                if(cnt4 == 8'd0) begin
                    {done, timeout} <= 2'b10;
                    syntaxe <= eff_st || ((eff_cmd!=req_cmd) && (eff_cmd!=6'h3F) && (eff_cmd!=6'd0));
                end
            end
        end
    end

endmodule