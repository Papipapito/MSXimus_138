
//--------------------------------------------------------------------------------------------------------
// Module  : sd_reader
// Type    : synthesizable, IP's top
// Standard: Verilog 2001 (IEEE1364-2001)
// Function: A SD-host to initialize SD-card and read sector
//           Support CardType   : SDv1.1 , SDv2  or SDHCv2
//--------------------------------------------------------------------------------------------------------
// SD Writing support added by Felipe Antoniosi for WonderTANG project

module sd_reader # (
    parameter [2:0] CLK_DIV = 3'd2,     // when clk =   0~ 25MHz , set CLK_DIV = 3'd1,
                                        // when clk =  25~ 50MHz , set CLK_DIV = 3'd2,
                                        // when clk =  50~100MHz , set CLK_DIV = 3'd3,
                                        // when clk = 100~200MHz , set CLK_DIV = 3'd4,
                                        // ......
    parameter       SIMULATE = 0,
    // V3.5: divisor del reloj RAPIDO como valor directo. Periodo de sdclk =
    // 2*FAST_DIV+4 ciclos de clk. Con clk=27 MHz: 4 -> 2,25 MHz (lo de siempre),
    // 1 -> 4,5 MHz, 0 -> 6,75 MHz. El muestreo de las entradas ya NO depende
    // del divisor (ver sddat0_s / sdcmdin_s), asi que 0 es seguro.
    parameter [15:0] FAST_DIV = 16'd4
) (
    // rstn active-low, 1:working, 0:reset
    input  wire         rstn,
    // clock
    input  wire         clk,
    // SDcard signals (connect to SDcard), this design do not use sddat1~sddat3.
    output wire         sdclk,
    inout               sdcmd,
    inout               sddat0,            // FPGA only read SDDAT signal but never drive it
    // show card status
    output wire [ 3:0]  card_stat,         // show the sdcard initialize status
    output reg  [ 1:0]  card_type,         // 0=UNKNOWN    , 1=SDv1    , 2=SDv2  , 3=SDHCv2
    // user read sector command interface (sync with clk)
    input  wire         rstart, 
    input  wire [31:0]  rsector,
    output wire         rbusy,
    output wire         rdone,
    // sector data output interface (sync with clk)
    output reg          outen,             // when outen=1, a byte of sector content is read out from outbyte
    output reg  [ 8:0]  outaddr,           // outaddr from 0 to 511, because the sector size is 512
    output reg  [ 7:0]  outbyte,            // a byte of sector content
    input  wire         wstart, 
    input  wire [ 7:0]  inbyte,
    output reg [21:0]   c_size,
    output reg [2:0]    c_size_mult,
    output reg [3:0]    read_bl_len,
    output reg [7:0]    mid,
    output reg [15:0]   oid,
    output reg [39:0]   pnm,
    output reg [31:0]   psn,
    output reg          crc_error,
    output reg          rcrc_error,        // V3.5: CRC16 de LECTURA incorrecto (sticky hasta el siguiente comando)
    output reg          timeout_error,
    input  wire         init,
    // V3.5c: MULTIBLOQUE (CMD18/CMD25) con UN solo bufer de 512 B.
    //   rcount  : bloques de la siguiente orden (0 o 1 = CMD17/CMD24 de siempre)
    //   buf_ack : pulso del host: "bufer vaciado" (lectura) / "bufer lleno" (escritura)
    //   blk_rdy : lectura: hay un bloque en el bufer esperando al host (el reloj
    //             de la tarjeta esta PARADO); escritura: el bufer esta libre
    //             para el siguiente bloque. Baja con buf_ack.
    input  wire [ 7:0]  rcount,
    input  wire         buf_ack,
    output reg          blk_rdy
);


initial {outen, outaddr, outbyte} = 0;

localparam [1:0] UNKNOWN = 2'd0,      // SD card type
                 SDv1    = 2'd1,
                 SDv2    = 2'd2,
                 SDHCv2  = 2'd3;

// V3.5: el rapido viene del parametro; el lento (init, <400 kHz) queda FIJO en
// lo que era con CLK_DIV=2 (4*48=192 -> 27M/388 = 69,6 kHz).
localparam [15:0] FASTCLKDIV = FAST_DIV;
localparam [15:0] SLOWCLKDIV = (SIMULATE ? 16'd20 : 16'd192);

reg        start  = 1'b0;
reg [15:0] precnt = 0;
reg [ 5:0] cmd    = 0;
reg [31:0] arg    = 0;
reg [15:0] clkdiv = SLOWCLKDIV;
reg [31:0] rsectoraddr = 0;

wire       busy, done, timeout, syntaxe;
wire[31:0] resparg;
wire[127:1] r2;

reg        sdv1_maybe = 1'b0;
reg [ 2:0] cmd8_cnt   = 0;
reg [15:0] rca = 0;

localparam [4:0] CMD0      = 5'd0,
                 CMD8      = 5'd1,
                 CMD55_41  = 5'd2,
                 ACMD41    = 5'd3,
                 CMD2      = 5'd4,
                 CMD3      = 5'd5,
                 CMD7      = 5'd6,
                 CMD9	   = 5'd7,
                 CMD10     = 5'd8,
                 CMD12     = 5'd9,
                 CMD16     = 5'd10,
                 CMD17     = 5'd11,
                 CMD24     = 5'd12,
                 READING   = 5'd13,
                 READING2  = 5'd14,
                 WRITING   = 5'd15,
                 WRITING2  = 5'd16,
                 IDLING    = 5'd17,
                 STANDBY   = 5'd18,
                 STOPBUSY  = 5'd19;     // V3.5c: tras el CMD12 de un CMD25, esperar el busy final

reg [4:0] sdcmd_stat = STANDBY;
//enum logic [3:0] {CMD0, CMD8, CMD55_41, ACMD41, CMD2, CMD3, CMD7, CMD16, CMD17, READING, READING2} sdcmd_stat = CMD0;

// AUDIT #4: bounded retries for CMD17/CMD24 relaunches and the CMD55/ACMD41 init
// loop (previously retried forever on timeout/syntaxe). On exhaustion the command
// FSM returns to IDLING and retry_fail (a level, cleared on the next IDLING launch)
// makes the data FSM raise timeout_error.
localparam [1:0] RETRY_MAX = 2'd3;
reg [1:0] retry_cnt  = 0;
reg       retry_fail = 1'b0;

reg        sdclkl = 1'b0;

localparam [3:0] RWAIT    = 4'd0,
                 RDURING  = 4'd1,
                 RTAIL    = 4'd2,
                 RDONE    = 4'd3,
                 RTIMEOUT = 4'd4,
                 WWAIT    = 4'd5,
                 WDURING  = 4'd6,
                 WTAIL    = 4'd7,
                 WBUSY    = 4'd8,
                 WDONE    = 4'd9,
                 WTIMEOUT = 4'd10,
                 RHOLD    = 4'd11,      // V3.5c: bloque en el bufer, reloj parado, esperando buf_ack
                 WHOLD    = 4'd12,      // V3.5c: bufer libre, esperando a que el host lo llene
                 WSTOP    = 4'd13,      // V3.5c: busy de programacion tras el CMD12 del CMD25
                 WDONE2   = 4'd14;      // V3.5c: el busy final ha terminado

reg [3:0] sddat_stat = RWAIT;

// V3.5c: estado del multibloque (lo lleva la FSM de datos; la de ordenes solo lo lee)
reg       multi       = 1'b0;   // la orden en curso es CMD18/CMD25
reg       op_wr       = 1'b0;   // la orden en curso es de escritura
reg [7:0] blocks_left = 8'd0;   // bloques que faltan (incluido el que esta en curso)
reg       clk_hold    = 1'b0;   // parar sdclk (RHOLD)

//enum logic [2:0] {RWAIT, RDURING, RTAIL, RDONE, RTIMEOUT} sddat_stat = RWAIT;

reg [31:0] ridx   = 0;

assign     rbusy  = (sdcmd_stat != IDLING) ;
// AUDIT #3: CMD12 belongs to the COMMAND enum (sdcmd_stat); in the DATA enum 9=WDONE,
// so the old "sddat_stat==CMD12" made the read-cancel termination impossible.
assign     rdone  = (sdcmd_stat == READING2 && sddat_stat==RDONE) || (sdcmd_stat == WRITING2 && sddat_stat==WDONE) || (sdcmd_stat == CMD12);

assign card_stat = sdcmd_stat;

reg sdcmdoe;
reg sdcmdout;

// PORT60K (audit 5.B): 2FF synchronizers on the asynchronous SD pad INPUT paths
// only (sdcmd/sddat0 -> clk domain); the output/OE paths are untouched. Both
// lines idle high, hence the 2'b11 init. The 2-clk delay is harmless: the FSMs
// sample several clk cycles per sdclk half-period.
reg [1:0] sdcmd_in_ff  = 2'b11;
reg [1:0] sddat0_in_ff = 2'b11;
always @ (posedge clk) begin
    sdcmd_in_ff  <= {sdcmd_in_ff[0],  sdcmd};
    sddat0_in_ff <= {sddat0_in_ff[0], sddat0};
end
wire sdcmd_in  = sdcmd_in_ff[1];
wire sddat0_in = sddat0_in_ff[1];

// V3.5: PUNTO DE MUESTREO INDEPENDIENTE DEL DIVISOR.
// La FSM de datos avanza en ev_rise (el ciclo en que el registro sdclk acaba de
// subir). Con el sincronizador de 2 FF, sddat0_in en ese ciclo es el pad de DOS
// ciclos ANTES = todavia en la fase baja anterior. Con periodo 12 sobraba
// margen; con periodo 4 caia justo sobre el flanco de bajada, donde la tarjeta
// CAMBIA el dato. Aqui se captura el pad tal como estaba EN el flanco de subida
// (ev_rise + 2 ciclos = el sincronizador ya trae el pad de ev_rise) y la FSM
// consume esa muestra en el ev_rise SIGUIENTE: un periodo de retardo uniforme
// para todos los bits, que no cambia nada mas que el punto de muestreo.
reg  ev_rise_d1 = 1'b0;
reg  ev_rise_d2 = 1'b0;
reg  sddat0_s   = 1'b1;
wire ev_rise    = ~sdclkl & sdclk;
always @ (posedge clk) begin
    ev_rise_d1 <= ev_rise;
    ev_rise_d2 <= ev_rise_d1;
    if (ev_rise_d2) sddat0_s <= sddat0_in;
end

sdcmd_ctrl u_sdcmd_ctrl (
    .rstn        ( rstn         ),
    .clk         ( clk          ),
    .sdclk       ( sdclk        ),
    .sdcmdin     ( sdcmdoe ? 1'b1 : sdcmd_in     ),
    .sdcmdout    ( sdcmdout     ),
    .sdcmdoe     ( sdcmdoe      ),
    .clkdiv      ( clkdiv       ),
    .hold        ( clk_hold     ),
    .start       ( start        ),
    .precnt      ( precnt       ),
    .cmd         ( cmd          ),
    .arg         ( arg          ),
    .busy        ( busy         ),
    .done        ( done         ),
    .timeout     ( timeout      ),
    .syntaxe     ( syntaxe      ),
    .resparg     ( resparg      ),
    .r2          ( r2           )
    );
reg sddat0oe = 0;
reg sddat0out;

assign sdcmd = (sdcmdoe) ? sdcmdout : 1'bz;
assign sddat0 = (sddat0oe) ? sddat0out : 1'bz;


task set_cmd;
    input [ 0:0] _start;
    input [15:0] _precnt;
    input [ 5:0] _cmd;
    input [31:0] _arg;
//task automatic set_cmd(input _start, input[15:0] _precnt='0, input[5:0] _cmd='0, input[31:0] _arg='0 );
begin
    start  <= _start;
    precnt <= _precnt;
    cmd    <= _cmd;
    arg    <= _arg;
end
endtask




always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        set_cmd(0,0,0,0);
        clkdiv      <= SLOWCLKDIV;
        rsectoraddr <= 0;
        rca         <= 0;
        sdv1_maybe  <= 1'b0;
        card_type   <= UNKNOWN;
        sdcmd_stat  <= STANDBY;
        cmd8_cnt    <= 0;
        retry_cnt   <= 0;
        retry_fail  <= 1'b0;

        mid <= 0;
        oid <= 16'h2020;
        pnm <= 40'h2020202020;
        psn <= 0;
        c_size <= 0;
        c_size_mult <= 0;
        read_bl_len <= 0;
    end else begin
        set_cmd(0,0,0,0);
        if(sdcmd_stat == READING2) begin
            if(sddat_stat==RTIMEOUT) begin
                sdcmd_stat <= CMD12;    // cancel reading
            end else if(sddat_stat==RDONE)
                sdcmd_stat <= multi ? CMD12 : IDLING;   // V3.5c: el CMD18 se cierra con STOP
        end else if(sdcmd_stat == WRITING2) begin

            if(sddat_stat==WTIMEOUT) begin
                sdcmd_stat <= CMD12;    // cancel write
            end else if(sddat_stat==WDONE)
                sdcmd_stat <= multi ? CMD12 : IDLING;   // V3.5c: el CMD25 se cierra con STOP + busy
        end else if(sdcmd_stat == STOPBUSY) begin
            // V3.5c: tras el CMD12 de un CMD25 la tarjeta programa el ultimo
            // bloque con DAT0=0; la FSM de datos (WSTOP) espera a que lo suelte.
            if (sddat_stat == WDONE2 || sddat_stat == WTIMEOUT || sddat_stat == RTIMEOUT)
                sdcmd_stat <= IDLING;
        end else if(~busy) begin
            case(sdcmd_stat)
                CMD0    :   set_cmd(1, (SIMULATE?512:64000),  0,  'h00000000);
                CMD8    :   set_cmd(1,                 512 ,  8,  'h000001aa);
                CMD55_41:   set_cmd(1,                 512 , 55,  'h00000000);
                ACMD41  :   set_cmd(1,                 256 , 41,  'h40100000);
                CMD2    :   set_cmd(1,                 256 ,  2,  'h00000000);
                CMD3    :   set_cmd(1,                 256 ,  3,  'h00000000);
                CMD7    :   set_cmd(1,                 256 ,  7, {rca,16'h0});
                CMD9    :   set_cmd(1,                 256 ,  9, {rca,16'h0});
                CMD10   :   set_cmd(1,                 256 , 10, {rca,16'h0});
                CMD12   :   set_cmd(1,                 256 , 12,  'h00000000);
                CMD16   :   set_cmd(1, (SIMULATE?512:64000), 16,  'h00000200);
                IDLING  :  begin
                                if(rstart) begin
                                    // V3.5c: rcount > 1 -> CMD18 (READ_MULTIPLE_BLOCK)
                                    set_cmd(1, 96, (rcount > 8'd1) ? 6'd18 : 6'd17, (card_type==SDHCv2) ? rsector : {rsector[22:0], 9'b0} );
                                    rsectoraddr <= (card_type==SDHCv2) ? rsector : {rsector[22:0], 9'b0};
                                    sdcmd_stat <= READING;
                                    retry_cnt  <= 0;        // AUDIT #4
                                    retry_fail <= 1'b0;
                                end else
                                if(wstart) begin
                                    // V3.5c: rcount > 1 -> CMD25 (WRITE_MULTIPLE_BLOCK)
                                    set_cmd(1, 96, (rcount > 8'd1) ? 6'd25 : 6'd24, (card_type==SDHCv2) ? rsector : {rsector[22:0], 9'b0} );
                                    rsectoraddr <= (card_type==SDHCv2) ? rsector : {rsector[22:0], 9'b0};
                                    sdcmd_stat <= WRITING;
                                    retry_cnt  <= 0;        // AUDIT #4
                                    retry_fail <= 1'b0;
                                end
                            end
                STANDBY :   if (init) sdcmd_stat <= CMD0;
            endcase
        end else if(done) begin
            case(sdcmd_stat)
                CMD0    :   sdcmd_stat <= CMD8;
                CMD8    :   if(~timeout && ~syntaxe && resparg[7:0]==8'haa) begin
                                sdcmd_stat <= CMD55_41;
                            end else if(timeout) begin
                                cmd8_cnt <= cmd8_cnt + 3'd1;
                                if (cmd8_cnt == 3'b111) begin
                                    sdv1_maybe <= 1'b1;
                                    sdcmd_stat <= CMD55_41;
                                end
                            end
                CMD55_41:   if(~timeout && ~syntaxe)
                                sdcmd_stat <= ACMD41;
                            else if(retry_cnt != RETRY_MAX) begin   // AUDIT #4: bounded retry
                                retry_cnt  <= retry_cnt + 2'd1;
                            end else begin
                                sdcmd_stat <= IDLING;
                                retry_fail <= 1'b1;
                            end
                ACMD41  :   if(~timeout && ~syntaxe && resparg[31]) begin
                                card_type <= sdv1_maybe ? SDv1 : (resparg[30] ? SDHCv2 : SDv2);
                                sdcmd_stat <= CMD2;
                                retry_cnt  <= 0;
                            end else if(~timeout && ~syntaxe) begin
                                sdcmd_stat <= CMD55_41;     // card busy: legit poll, not an error
                                retry_cnt  <= 0;
                            end else if(retry_cnt != RETRY_MAX) begin   // AUDIT #4: bounded retry
                                sdcmd_stat <= CMD55_41;
                                retry_cnt  <= retry_cnt + 2'd1;
                            end else begin
                                sdcmd_stat <= IDLING;
                                retry_fail <= 1'b1;
                            end
                CMD2    :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= CMD3;
                CMD3    :   if(~timeout && ~syntaxe) begin
                                rca <= resparg[31:16];
                                sdcmd_stat <= CMD9;
                            end
                CMD9   :    if(~timeout && ~syntaxe) begin
                                 sdcmd_stat <= CMD10;
                                 if (r2[127:126] == 2'b01) begin // CSD 2.0 ?
                                    c_size <= r2[69:48];
                                    c_size_mult <= 3'h2;
                                    read_bl_len <= 4'hF; // 2(+2) + 15 = 19 (512KB blocks)
                                 end else begin
                                    c_size <= { 10'b0, r2[73:62] };
                                    c_size_mult <= r2[49:47];
                                    read_bl_len <= r2[83:80];
                                 end
                            end

                CMD10   :   if(~timeout && ~syntaxe) begin
                                sdcmd_stat <= CMD7;
                                mid <= r2[127:120];
                                oid <= r2[119:104];
                                pnm <= r2[103:64];
                                psn <= r2[55:24];
                            end
                CMD7    :   if(~timeout && ~syntaxe) begin
                                clkdiv  <= FASTCLKDIV;
                                sdcmd_stat <= (card_type==SDHCv2) ? IDLING : CMD16;
                            end
                CMD16   :   if(~timeout && ~syntaxe)
                                sdcmd_stat <= IDLING;

                READING :   if(~timeout && ~syntaxe) begin
                                sdcmd_stat <= READING2;
                                retry_cnt  <= 0;
                            end else if(retry_cnt != RETRY_MAX) begin   // AUDIT #4: bounded retry
                                retry_cnt  <= retry_cnt + 2'd1;
                                set_cmd(1, 128, multi ? 6'd18 : 6'd17, rsectoraddr);
                            end else begin
                                sdcmd_stat <= IDLING;
                                retry_fail <= 1'b1;
                            end
                WRITING :   if(~timeout && ~syntaxe) begin
                                sdcmd_stat <= WRITING2;
                                retry_cnt  <= 0;
                            end else if(retry_cnt != RETRY_MAX) begin   // AUDIT #4: bounded retry
                                retry_cnt  <= retry_cnt + 2'd1;
                                set_cmd(1, 128, multi ? 6'd25 : 6'd24, rsectoraddr);
                            end else begin
                                sdcmd_stat <= IDLING;
                                retry_fail <= 1'b1;
                            end
                CMD12	:   if(~timeout && ~syntaxe) begin
                                // V3.5c: el STOP de un CMD25 deja a la tarjeta programando
                                // el ultimo bloque: esperar su busy antes de IDLING.
                                sdcmd_stat <= (multi && op_wr) ? STOPBUSY : IDLING;
                            end else if(retry_cnt != RETRY_MAX) begin
                                // V3.5: CMD12 ACOTADO. Antes, si la tarjeta no
                                // respondia al cancel (justo el caso en que se
                                // llega aqui), se reemitia CMD12 para siempre:
                                // busy pegado hasta el reset. Ahora 4 intentos
                                // y a IDLING con timeout_error (retry_fail).
                                retry_cnt  <= retry_cnt + 2'd1;
                            end else begin
                                sdcmd_stat <= IDLING;
                                retry_fail <= 1'b1;
                            end
                default:		sdcmd_stat <= IDLING;
            endcase
        end
    end

reg crc_init;
reg [15:0] crc_out;
reg crc_ena = 0;
reg crc_bit;

sd_crc_16 u_sd_crc_16 (      // V3.5: con nombre (Icarus exige instancia nombrada; Gowin lo aceptaba anonimo)
.BITVAL(crc_bit),
.ENABLE(crc_ena), 
.BITSTRB(clk), 
.CLEAR(crc_init), 
.CRC(crc_out)
);

reg [3:0] crc_stat;
reg [9:0] raddr;
reg [9:0] waddr;
reg       rcrc_bad = 1'b0;      // V3.5: algun bit del CRC16 recibido no cuadra

always @ (posedge clk or negedge rstn)
    if(~rstn) begin
        outen   <= 1'b0;
        outaddr <= 0;
        outbyte <= 0;
        sdclkl  <= 1'b0;
        sddat_stat <= RWAIT;
        ridx    <= 0;
        sddat0oe <= 0;
        crc_init <= 0;
        crc_error <= 0;
        rcrc_error <= 0;
        rcrc_bad <= 0;
        timeout_error <= 0;
        blk_rdy  <= 0;
        clk_hold <= 0;
        multi    <= 0;
        op_wr    <= 0;
        blocks_left <= 0;
    end else begin
        outen   <= 1'b0;
        //outaddr <= 0;
        sdclkl  <= sdclk;
        crc_ena <= 0;
        crc_init <= 0;
        if (sdcmd_stat == IDLING) begin
            sddat0oe <= '0;
            blk_rdy  <= '0;
            clk_hold <= '0;
        end else if (sdcmd_stat == READING) begin
            sddat_stat <= RWAIT;
            outaddr <= '1;
            raddr <= '0;
            timeout_error <= 0;
            // V3.5c: tomar nota de la orden (rcount es del host; aqui se latchea)
            multi       <= (rcount > 8'd1);
            op_wr       <= 1'b0;
            blocks_left <= (rcount == 8'd0) ? 8'd1 : rcount;
            blk_rdy     <= 1'b0;
            clk_hold    <= 1'b0;
            // V3.5 (AUDIT #6): una lectura NO hereda el veredicto de la ultima
            // escritura. Antes bit0 de SDC_STATUS en lecturas era el CRC rancio
            // del ultimo CMD24; tras un give-up de escritura envenenaba TODAS las
            // lecturas.
            crc_error <= 0;
            rcrc_error <= 0;
            rcrc_bad <= 0;
            ridx   <= 0;
        end else if (sdcmd_stat == WRITING) begin
            sddat_stat <= WWAIT;
            outaddr <= '0;
            waddr <= '0;
            crc_error <= 0;
            rcrc_error <= 0;
            timeout_error <= 0;
            ridx   <= 0;
            multi       <= (rcount > 8'd1);
            op_wr       <= 1'b1;
            blocks_left <= (rcount == 8'd0) ? 8'd1 : rcount;
            blk_rdy     <= 1'b0;
            clk_hold    <= 1'b0;
        end else if (sddat_stat == RHOLD) begin
            // V3.5c: reloj parado con un bloque en el bufer. El host lo vacia y
            // manda buf_ack: reloj en marcha y a esperar el start bit del siguiente.
            if (buf_ack) begin
                blk_rdy    <= 1'b0;
                clk_hold   <= 1'b0;
                sddat_stat <= RWAIT;
                ridx       <= 0;
                outaddr    <= '1;
                rcrc_bad   <= 1'b0;
            end
        end else if (sddat_stat == WHOLD) begin
            // V3.5c: bufer libre; el host lo llena y manda buf_ack: siguiente bloque
            if (buf_ack) begin
                blk_rdy    <= 1'b0;
                sddat_stat <= WWAIT;
                ridx       <= 0;
                outaddr    <= '0;
            end
        end else if (sdcmd_stat == STOPBUSY && sddat_stat == WDONE) begin
            sddat_stat <= WSTOP;            // V3.5c: el CMD12 ya respondio: vigilar DAT0
            ridx       <= 0;
        end else if(ev_rise) begin
            sddat0oe <= 0;
            case(sddat_stat)
                // reading
                RWAIT   : begin
                    if(~sddat0_s) begin         // start bit = 0
                        sddat_stat <= RDURING;
                        ridx   <= 0;
                        crc_init <= 1;          // V3.5: CRC16 de lectura desde cero
                    end else begin
                        if(ridx > 1000000)      // SD datasheet: 1ms basta para el DAT. Timeout = 1e6 PERIODOS de sdclk (148 ms a 6,75 MHz; la spec pide <=100 ms de Nac)
                            sddat_stat <= RTIMEOUT;
                        ridx   <= ridx + 1;
                    end
                end
                RDURING : begin
                    outbyte[3'd7 - ridx[2:0]] <= sddat0_s;
                    crc_bit <= sddat0_s;        // V3.5: mismo generador que la escritura
                    crc_ena <= 1;

                    if(ridx[2:0] == 3'd7) begin
                        outen  <= 1'b1;
                        //outaddr<= ridx[11:3];
                        outaddr <= outaddr + 9'd1;
                    end
                    if(ridx >= 512*8-1) begin
                        sddat_stat <= RTAIL;
                        ridx   <= 0;
                    end else begin
                        ridx   <= ridx + 1;
                    end
                end
                RTAIL   : begin
                    // V3.5 (AUDIT #6 cerrado): los 16 bits que siguen a los datos
                    // son el CRC16 (MSB primero), comparados bit a bit contra el
                    // mismo sd_crc_16 que la tarjeta acepta en escritura. Un fallo
                    // sale por rcrc_error (bit2 de SDC_STATUS) y top.v reintenta
                    // el CMD17 solo, como ya hacia con el token de escritura.
                    if (ridx < 16) begin
                        if (sddat0_s != crc_out[4'd15 - ridx[3:0]])
                            rcrc_bad <= 1'b1;
                    end else if (ridx == 16) begin
                        rcrc_error <= rcrc_bad;
                    end
                    // V3.5c multibloque (CMD18): en el end bit (ridx==16), si quedan
                    // bloques y este ha llegado bien, PARAR EL RELOJ y avisar al host
                    // (blk_rdy); se sigue cuando vacie el bufer (buf_ack -> RHOLD).
                    // Ultimo bloque o CRC mal -> RDONE y la FSM de ordenes manda CMD12.
                    if (multi) begin
                        if (ridx == 16) begin
                            if (blocks_left > 8'd1 && !rcrc_bad) begin
                                sddat_stat  <= RHOLD;
                                clk_hold    <= 1'b1;
                                blk_rdy     <= 1'b1;
                                blocks_left <= blocks_left - 8'd1;
                            end else
                                sddat_stat <= RDONE;
                        end
                    end else if(ridx >= 8*8-1)  // end bit + 7 de cortesia
                        sddat_stat <= RDONE;
                    ridx   <= ridx + 1;
                end
                RTIMEOUT :timeout_error <= 1;

                ////////////
                // writing
                ////////////
                WWAIT   : begin
                    // V3.5: NWR >= 2 ciclos entre el fin de la respuesta R1 y el
                    // start bit de datos (antes iba a la primera subida).
                    if (ridx < 2) begin
                        ridx <= ridx + 1;
                    end else begin
                        sddat0out <= 1'b0; // start bit
                        sddat0oe <= '1;
                        sddat_stat <= WDURING;
                        ridx   <= 0;
                        crc_init <= 1;
                        outen  <= 1'b1;   // bring in first byte
                    end
                end
                WDURING : begin

                    if (ridx < 512*8) begin
                        sddat0out <= inbyte[3'd7 - ridx[2:0]]; // send data bit
                        sddat0oe <= 1;
                        crc_bit <= inbyte[3'd7 - ridx[2:0]]; // crc in data bit
                        crc_ena <= 1;
                    end else if (ridx < 512*8+16) begin
                        sddat0out <= crc_out[4'd15 - ridx[3:0]]; // send crc16
                        sddat0oe <= 1;
                    end else if (ridx < 512*8+16+1) begin
                        sddat0out <= 1'b1;      // stop bit
                        sddat0oe <= 1;
                    end else if (ridx < 512*8+16+1+2) begin
                        sddat0oe <= 0;          // wait for crc status 2 cycles                   
                    end else begin
                        if (!sddat0_s) begin    // start bit del token de estado
                            sddat_stat <= WTAIL;
                        end
                        if(ridx > 13000000)
                             sddat_stat <= WTIMEOUT;
                    end

                    if(ridx[2:0] == 3'd7) begin
                        outen  <= 1'b1;         // bring next byte from sram
                        //outaddr<= ridx[11:3];
                        outaddr <= outaddr + 9'd1;
                    end
                    // V3.5 — EL BUG QUE HACIA INVISIBLE EL RECHAZO DE LA TARJETA.
                    // Aqui habia un "ridx <= ridx + 1" incondicional DESPUES del
                    // "ridx <= 0" de la transicion a WTAIL: el ultimo NBA gana,
                    // asi que WTAIL entraba con ridx ~4118, nunca capturaba los 3
                    // bits del token (crc_stat se quedaba en X), crc_error NUNCA
                    // se asignaba, y saltaba a WBUSY/WDONE con el primer 0 del
                    // propio token. Consecuencia: el host daba la escritura por
                    // terminada dentro del token, SIN esperar el busy de
                    // programacion (DAT0=0), y el Z80 mandaba el CMD24 siguiente
                    // con la tarjeta aun programando: ese bloque se perdia
                    // "aceptado y no escrito". La pausa de ~2 ms que lo curaba
                    // en el menu es, justamente, el tiempo de programacion.
                    ridx   <= ((ridx >= 512*8+16+1+2) && !sddat0_s) ? 32'd0 : ridx + 1;
                end
                WTAIL   : begin                 // token de estado: s2 s1 s0, end bit, y luego BUSY
                    if (ridx < 3) begin
                        crc_stat <= { crc_stat[1:0], sddat0_s };
                        ridx <= ridx + 1;
                    end else if (ridx == 3) begin
                        ridx <= ridx + 1;       // end bit del token
                    end else begin
                        crc_error <= (crc_stat[2:0] != 3'b010);   // 010 = aceptado; 101 = CRC mal
                        sddat_stat <= WBUSY;
                        ridx <= 0;
                    end
                end
                WBUSY   :  begin                // la tarjeta mantiene DAT0=0 mientras programa
                    if (sddat0_s) begin
                        // V3.5c multibloque (CMD25): bloque aceptado y programado. Si
                        // quedan mas, ceder el bufer al host (blk_rdy) y esperar a que
                        // lo llene (buf_ack -> WHOLD). Token rechazado -> WDONE con
                        // crc_error=1 y la FSM de ordenes para con CMD12.
                        if (multi && blocks_left > 8'd1 && !crc_error) begin
                            sddat_stat  <= WHOLD;
                            blk_rdy     <= 1'b1;
                            blocks_left <= blocks_left - 8'd1;
                        end else
                            sddat_stat <= WDONE;
                        ridx <= 0;
                    end else if (ridx > 13000000) begin
                        sddat_stat <= WTIMEOUT;
                    end else begin
                        ridx <= ridx + 1;
                    end
                end
                WSTOP   : begin                 // V3.5c: busy de programacion tras el CMD12 del CMD25
                    if (ridx < 16)
                        ridx <= ridx + 1;       // margen: la tarjeta baja DAT0 justo tras la R1b
                    else if (sddat0_s)
                        sddat_stat <= WDONE2;
                    else if (ridx > 13000000)
                        sddat_stat <= WTIMEOUT;
                    else
                        ridx <= ridx + 1;
                end
                WTIMEOUT : timeout_error <= 1;


            endcase
        end
        if (retry_fail)         // AUDIT #4: command retries exhausted -> surface as timeout
            timeout_error <= 1;
    end


endmodule
