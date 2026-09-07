// ============================================================================
// sd_card_model.sv — modelo de comportamiento de una tarjeta SD (modo SD, 1 bit)
// para el banco del sd_reader/sdcmd_ctrl del MSXimus (V3.5).
//
// Lo que modela (y nada mas):
//  - Recepcion de comandos por CMD (48 bits, muestreados en el flanco de SUBIDA).
//  - Respuestas R1/R1b/R2/R3/R6/R7 con CRC7 real, emitidas en el flanco de
//    BAJADA con un retardo de salida TOD (ns) — como una tarjeta real (tODLY).
//  - Secuencia de init: CMD0, CMD8, CMD55/ACMD41 (primera vez BUSY, luego listo
//    y CCS=1 = SDHC), CMD2 (CID), CMD3 (RCA), CMD9 (CSD v2), CMD10, CMD7, CMD16.
//  - CMD17: bloque de 512 B + CRC16 + end bit tras NAC ciclos.
//  - CMD24: recibe bloque + CRC16, contesta token de estado (010 ok / 101 CRC)
//    y se queda BUSY (DAT0=0) busy_clks ciclos.
//  - CMD12: R1b.
//  - Mandos de prueba (se tocan por referencia jerarquica desde el TB):
//      corrupt_read_bit  = indice del bit de datos a INVERTIR en la proxima
//                          lectura (el CRC va sobre los datos buenos) -> el host
//                          debe detectar CRC mal. -1 = nada. Se autolimpia.
//      reject_writes     = numero de escrituras a RECHAZAR (token 101).
//      no_data           = no enviar datos tras CMD17 (provoca timeout del host).
//      no_resp12         = no responder a CMD12 (la tarjeta "muerta" tras el
//                          timeout: es el caso que dejaba busy pegado).
//      tod_ns            = retardo de salida (se puede cambiar en caliente).
// ============================================================================
`timescale 1ns/1ps

module sd_card_model #(
    parameter integer NCR      = 4,     // ciclos entre fin de comando y respuesta
    parameter integer NAC      = 8,     // ciclos entre respuesta CMD17 y datos
    parameter integer NSEC     = 16     // sectores modelados
) (
    input  wire sdclk,
    inout  wire sdcmd,
    inout  wire sddat0
);

    // ---------------- mandos de prueba ----------------
    integer tod_ns           = 14;
    integer corrupt_read_bit = -1;
    integer reject_writes    = 0;
    reg     no_data          = 1'b0;
    reg     no_resp12        = 1'b0;
    integer busy_clks        = 20;

    // ---------------- estadisticas ----------------
    integer n_cmd = 0;
    integer last_cmd = -1;
    reg [31:0] last_arg = 0;
    integer n_reads = 0;
    integer n_writes = 0;
    integer n_write_crc_bad = 0;
    integer n_cmd_crc_bad = 0;
    integer n_cmd12 = 0;

    // ---------------- memoria ----------------
    reg [7:0] mem [0:NSEC*512-1];
    integer i;
    initial begin
        for (i = 0; i < NSEC*512; i = i + 1)
            mem[i] = ((i / 512) * 8'h11 + (i % 512) * 8'h07) & 8'hFF; // patron f(sector, offset)
    end

    // ---------------- lineas ----------------
    reg cmd_oe = 1'b0, cmd_o = 1'b1;
    reg dat_oe = 1'b0, dat_o = 1'b1;
    assign sdcmd  = cmd_oe ? cmd_o : 1'bz;
    assign sddat0 = dat_oe ? dat_o : 1'bz;

    // ---------------- CRC ----------------
    function [6:0] crc7_bits;   // sobre nbits bits (MSB primero) de un vector
        input [135:0] v;
        input integer nbits;
        integer k;
        reg [6:0] c;
        reg inb;
        begin
            c = 7'd0;
            for (k = nbits-1; k >= 0; k = k - 1) begin
                inb = v[k] ^ c[6];
                c = { c[5:0], 1'b0 } ^ { 3'b000, inb, 2'b00, inb };
            end
            crc7_bits = c;
        end
    endfunction

    function [15:0] crc16_step;
        input [15:0] c;
        input b;
        reg inv;
        begin
            inv = b ^ c[15];
            crc16_step = { c[14:0], 1'b0 } ^ ( inv ? 16'h1021 : 16'h0000 );
        end
    endfunction

    // ---------------- registros de la tarjeta ----------------
    reg        app_cmd = 1'b0;
    reg        acmd41_seen = 1'b0;
    reg [15:0] rca = 16'h1234;
    reg [127:0] cid;
    reg [127:0] csd;
    initial begin
        // CID: MID AB, OID "XY", PNM "MSXIM", PRV 1.0, PSN 12345678, MDT, CRC7, 1
        cid = { 8'hAB, 16'h5859, 40'h4D5358494D, 8'h10, 32'h12345678, 4'h0, 12'h123, 7'h00, 1'b1 };
        cid[7:1] = crc7_bits(cid[127:8], 120);
        // CSD v2.0: CSD_STRUCTURE=01, C_SIZE (bits 69:48) = 0x001E3F
        csd = 128'h0;
        csd[127:126] = 2'b01;
        csd[83:80]   = 4'h9;            // READ_BL_LEN = 9
        csd[69:48]   = 22'h001E3F;
        csd[0]       = 1'b1;
        csd[7:1]     = crc7_bits(csd[127:8], 120);
    end

    // ---------------- cola de transmision CMD ----------------
    reg [0:135] tx_bits;
    integer tx_len = 0, tx_pos = 0, tx_delay = 0;

    task queue_resp;             // resp[135:0] alineada a la IZQUIERDA (bit 135 = start)
        input [135:0] r;
        input integer len;
        integer k;
        begin
            for (k = 0; k < len; k = k + 1) tx_bits[k] = r[135-k];
            tx_len   = len;
            tx_pos   = 0;
            tx_delay = NCR;
        end
    endtask

    task resp_r1;                // {0,0,cmd,status,crc7,1}
        input [5:0] c;
        input [31:0] st;
        reg [135:0] r;
        begin
            r = 136'h0;
            r[135:88] = { 2'b00, c, st, 7'h00, 1'b1 };
            r[95:89]  = crc7_over48({ 2'b00, c, st });
            queue_resp(r, 48);
        end
    endtask

    function [6:0] crc7_over48;   // CRC7 de los 40 bits {start,T,cmd,arg}
        input [39:0] v;
        reg [135:0] w;
        begin
            w = 136'h0;
            w[39:0] = v;
            crc7_over48 = crc7_bits(w, 40);
        end
    endfunction

    task resp_r3;                // {0,0,111111,OCR,1111111,1}
        input [31:0] ocr;
        reg [135:0] r;
        begin
            r = 136'h0;
            r[135:88] = { 2'b00, 6'h3F, ocr, 7'h7F, 1'b1 };
            queue_resp(r, 48);
        end
    endtask

    task resp_r6;                // {0,0,000011,RCA,status16,crc7,1}
        reg [135:0] r;
        begin
            r = 136'h0;
            r[135:88] = { 2'b00, 6'd3, rca, 16'h0500, 7'h00, 1'b1 };
            r[95:89]  = crc7_over48({ 2'b00, 6'd3, rca, 16'h0500 });
            queue_resp(r, 48);
        end
    endtask

    task resp_r7;                // {0,0,001000,arg echo,crc7,1}
        input [31:0] a;
        reg [135:0] r;
        begin
            r = 136'h0;
            r[135:88] = { 2'b00, 6'd8, a, 7'h00, 1'b1 };
            r[95:89]  = crc7_over48({ 2'b00, 6'd8, a });
            queue_resp(r, 48);
        end
    endtask

    task resp_r2;                // {0,0,111111,REG[127:1],1}
        input [127:0] regv;
        reg [135:0] r;
        begin
            r = { 2'b00, 6'h3F, regv[127:1], 1'b1 };
            queue_resp(r, 136);
        end
    endtask

    // ---------------- cola de transmision DAT ----------------
    reg [0:4200] dtx_bits;
    integer dtx_len = 0, dtx_pos = 0, dtx_delay = 0;
    integer busy_left = 0;       // ciclos de DAT0=0 tras el token de escritura / CMD12

    task queue_block;            // datos del sector s con CRC16 y end bit
        input integer s;
        integer k, b;
        reg [15:0] c;
        reg bitv;
        begin
            c = 16'h0000;
            dtx_bits[0] = 1'b0;                          // start bit
            for (k = 0; k < 4096; k = k + 1) begin
                b = s*512 + (k / 8);
                bitv = mem[b][7 - (k % 8)];
                c = crc16_step(c, bitv);                  // CRC sobre el dato BUENO
                if (k == corrupt_read_bit) bitv = ~bitv;  // el bit corrupto viaja, el CRC no lo sabe
                dtx_bits[1+k] = bitv;
            end
            for (k = 0; k < 16; k = k + 1) dtx_bits[1+4096+k] = c[15-k];
            dtx_bits[1+4096+16] = 1'b1;                  // end bit
            dtx_len   = 1 + 4096 + 16 + 1;
            dtx_pos   = 0;
            dtx_delay = NCR + 48 + NAC;     // los datos empiezan NAC ciclos DESPUES de la respuesta R1 (48 bits)
            corrupt_read_bit = -1;
        end
    endtask

    task queue_status_token;     // {0, s2 s1 s0, 1} y luego busy
        input [2:0] st;
        begin
            dtx_bits[0] = 1'b0;
            dtx_bits[1] = st[2];
            dtx_bits[2] = st[1];
            dtx_bits[3] = st[0];
            dtx_bits[4] = 1'b1;
            dtx_len   = 5;
            dtx_pos   = 0;
            dtx_delay = 2;                               // NCRC = 2 ciclos tras el end bit del host
            busy_left = busy_clks;
        end
    endtask

    // ---------------- multibloque (V3.5c) ----------------
    reg        multi_rd  = 1'b0;     // CMD18 en curso: tras cada bloque viene otro (hasta CMD12)
    integer    rd_sector = 0;
    reg        wr_multi  = 1'b0;     // CMD25 en curso: tras cada bloque se espera otro (hasta CMD12)
    integer    n_cmd18 = 0, n_cmd25 = 0;

    // ---------------- receptor de escritura (DAT0) ----------------
    reg        wr_armed = 1'b0;      // esperando el start bit del host
    reg        wr_active = 1'b0;
    integer    wr_idx = 0;
    integer    wr_sector = 0;
    reg [15:0] wr_crc = 16'h0;
    reg [15:0] wr_crc_rx = 16'h0;
    reg [7:0]  wr_byte = 8'h0;
    reg [7:0]  wr_buf [0:511];

    // ---------------- receptor de comandos (CMD) ----------------
    reg        in_cmd = 1'b0;
    integer    cbits = 0;
    reg [47:0] shreg = 48'h0;
    reg [5:0]  ccmd;
    reg [31:0] carg;
    reg [6:0]  ccrc;
    integer    sector;

    // ---- flanco de SUBIDA: la tarjeta MUESTREA ----
    always @(posedge sdclk) begin
        // --- comando ---
        if (!in_cmd) begin
            if (cmd_oe == 1'b0 && sdcmd === 1'b0) begin
                in_cmd <= 1'b1;
                shreg  <= { 47'h0, 1'b0 };
                cbits  <= 1;
            end
        end else begin
            shreg <= { shreg[46:0], sdcmd };
            cbits <= cbits + 1;
            if (cbits == 47) begin
                in_cmd <= 1'b0;
                cbits  <= 0;
                process_cmd({ shreg[46:0], sdcmd });
            end
        end
        // --- datos de escritura ---
        if (wr_armed && !wr_active) begin
            if (dat_oe == 1'b0 && sddat0 === 1'b0) begin   // start bit del host
                wr_active <= 1'b1;
                wr_idx    <= 0;
                wr_crc    <= 16'h0;
            end
        end else if (wr_active) begin
            if (wr_idx < 4096) begin
                wr_byte <= { wr_byte[6:0], sddat0 };
                wr_crc  <= crc16_step(wr_crc, sddat0);
                if ((wr_idx % 8) == 7) wr_buf[wr_idx/8] <= { wr_byte[6:0], sddat0 };
            end else if (wr_idx < 4096+16) begin
                wr_crc_rx <= { wr_crc_rx[14:0], sddat0 };
            end else begin
                // end bit: veredicto
                wr_active <= 1'b0;
                wr_armed  <= wr_multi;          // V3.5c: en CMD25 se sigue esperando bloques
                n_writes  <= n_writes + 1;
                if (reject_writes > 0) begin
                    reject_writes = reject_writes - 1;
                    n_write_crc_bad <= n_write_crc_bad + 1;
                    queue_status_token(3'b101);
                end else if (wr_crc_rx != wr_crc) begin
                    n_write_crc_bad <= n_write_crc_bad + 1;
                    queue_status_token(3'b101);
                end else begin
                    for (i = 0; i < 512; i = i + 1) mem[wr_sector*512 + i] = wr_buf[i];
                    queue_status_token(3'b010);
                end
                if (wr_multi) wr_sector = (wr_sector + 1) % NSEC;   // V3.5c: siguiente sector
            end
            wr_idx <= wr_idx + 1;
        end
    end

    task process_cmd;
        input [47:0] c;
        reg [6:0] want;
        begin
            ccmd = c[45:40];
            carg = c[39:8];
            ccrc = c[7:1];
            want = crc7_over48(c[47:8]);
            n_cmd    = n_cmd + 1;
            last_cmd = ccmd;
            last_arg = carg;
            if (c[47] !== 1'b0 || c[46] !== 1'b1 || c[0] !== 1'b1 || ccrc !== want) begin
                n_cmd_crc_bad = n_cmd_crc_bad + 1;
                $display("[SDMODEL] %0t comando MAL FORMADO cmd=%0d crc=%02x esperado=%02x", $time, ccmd, ccrc, want);
            end
            if (app_cmd) begin
                app_cmd = 1'b0;
                case (ccmd)
                    6'd41: begin
                        if (!acmd41_seen) begin
                            acmd41_seen = 1'b1;
                            resp_r3(32'h00FF8000);              // busy (bit31=0): el host debe repetir
                        end else begin
                            resp_r3(32'hC0FF8000);              // listo, CCS=1 -> SDHC
                        end
                    end
                    default: resp_r1(ccmd, 32'h00000120);
                endcase
            end else begin
                case (ccmd)
                    6'd0:  begin app_cmd = 1'b0; acmd41_seen = 1'b0; end   // sin respuesta
                    6'd8:  resp_r7(carg);
                    6'd55: begin app_cmd = 1'b1; resp_r1(6'd55, 32'h00000120); end
                    6'd2:  resp_r2(cid);
                    6'd3:  resp_r6();
                    6'd9:  resp_r2(csd);
                    6'd10: resp_r2(cid);
                    6'd7:  resp_r1(6'd7, 32'h00000700);
                    6'd16: resp_r1(6'd16, 32'h00000900);
                    6'd17: begin
                        resp_r1(6'd17, 32'h00000900);
                        sector = carg;                          // SDHC: direccion de bloque
                        if (!no_data) begin
                            n_reads = n_reads + 1;
                            queue_block(sector % NSEC);
                        end
                    end
                    6'd24: begin
                        resp_r1(6'd24, 32'h00000900);
                        wr_sector = carg % NSEC;
                        wr_armed  = 1'b1;
                    end
                    6'd18: begin                                // V3.5c: READ_MULTIPLE_BLOCK
                        resp_r1(6'd18, 32'h00000900);
                        n_cmd18   = n_cmd18 + 1;
                        rd_sector = carg;
                        multi_rd  = 1'b1;
                        if (!no_data) begin
                            n_reads = n_reads + 1;
                            queue_block(rd_sector % NSEC);
                        end
                    end
                    6'd25: begin                                // V3.5c: WRITE_MULTIPLE_BLOCK
                        resp_r1(6'd25, 32'h00000900);
                        n_cmd25   = n_cmd25 + 1;
                        wr_sector = carg % NSEC;
                        wr_multi  = 1'b1;
                        wr_armed  = 1'b1;
                    end
                    6'd12: begin
                        n_cmd12 = n_cmd12 + 1;
                        multi_rd = 1'b0;                        // V3.5c: STOP corta el flujo
                        wr_multi = 1'b0;
                        wr_armed = 1'b0;
                        dtx_len  = 0;                           // lo que quedara por mandar, fuera
                        dtx_pos  = 0;
                        if (!no_resp12) begin
                            resp_r1(6'd12, 32'h00000900);
                            busy_left = 4;
                        end
                    end
                    default: resp_r1(ccmd, 32'h00000900);
                endcase
            end
        end
    endtask

    // ---- flanco de BAJADA: la tarjeta CONDUCE (con retardo tod_ns) ----
    always @(negedge sdclk) begin
        // CMD
        if (tx_delay > 0) begin
            tx_delay = tx_delay - 1;
            cmd_oe <= #(tod_ns) 1'b0;
        end else if (tx_pos < tx_len) begin
            cmd_oe <= #(tod_ns) 1'b1;
            cmd_o  <= #(tod_ns) tx_bits[tx_pos];
            tx_pos = tx_pos + 1;
        end else begin
            cmd_oe <= #(tod_ns) 1'b0;
        end
        // DAT0
        if (dtx_delay > 0) begin
            dtx_delay = dtx_delay - 1;
            dat_oe <= #(tod_ns) 1'b0;
        end else if (dtx_pos < dtx_len) begin
            dat_oe <= #(tod_ns) 1'b1;
            dat_o  <= #(tod_ns) dtx_bits[dtx_pos];
            dtx_pos = dtx_pos + 1;
        end else if (busy_left > 0) begin
            busy_left = busy_left - 1;
            dat_oe <= #(tod_ns) 1'b1;
            dat_o  <= #(tod_ns) 1'b0;
        end else if (multi_rd && dtx_len != 0 && !no_data) begin
            // V3.5c: CMD18: el bloque siguiente sale NAC ciclos despues del end bit
            // del anterior. Si el host para el reloj, no hay flancos y esto espera.
            rd_sector = rd_sector + 1;
            n_reads   = n_reads + 1;
            queue_block(rd_sector % NSEC);
            dtx_delay = NAC;
            dat_oe <= #(tod_ns) 1'b0;
        end else begin
            dat_oe <= #(tod_ns) 1'b0;
        end
    end

endmodule
