// ============================================================================
//  gm2_slot1.v - Konami GAME MASTER 2 (RC-755) emulado en el SLOT 1 (V3.5f)
//  Bloque 6 del plan 3.5 (idea de Albert, 02/09/2026; hecho el 08/09).
// ----------------------------------------------------------------------------
//  El GM2 real es un cartucho aparte: el juego (MG2, SD Snatcher, Snatcher...)
//  lo BUSCA por los slots y le llama a sus rutinas de SRAM por inter-slot. Aqui
//  se emula en el unico slot libre durante el juego, el 1 (0 = BIOS, 2 = la
//  megaram con el juego, 3 = expandido con RAM/menu/SD).
//
//  DONDE VIVE LA MEMORIA: en la MITAD ALTA de la megaram (bank B de la SDRAM,
//  segmentos >= 256), que solo tocan los juegos de 4 MB, con los que el menu
//  NO arma el GM2. Asi el menu carga la ROM y lee/escribe la SRAM con el MISMO
//  cargador del bloque 5 (write_sector_to_megaram / srm_rd con #46 bit4):
//     ROM  128 KB = 16 paginas de 8 KB -> segmentos 480..495
//     SRAM   8 KB                      -> segmento  496
//  (el 511 sigue siendo el descriptor del bloque 5; 497-510 quedan libres)
//
//  MAPPER (openMSX RomGameMaster2.cc, es la referencia):
//     4000-5FFF  pagina 0 de la ROM, FIJA
//     6000-7FFF  registro en 6000-6FFF   8000-9FFF  en 8000-8FFF
//     A000-BFFF  registro en A000-AFFF   (7000/9000/B000-xFFF NO son registro)
//     valor: bits 3..0 = pagina ROM; bit 4 = 1 SRAM / 0 ROM; bit 5 = mitad de
//     la SRAM (4 KB) cuando bit4=1; bits 7..6 se ignoran.
//     La SRAM solo se ESCRIBE en B000-BFFF con la SRAM seleccionada en A000.
//     Como se ven 4 KB de SRAM en una ventana de 8 KB, las dos mitades de la
//     ventana leen lo mismo. Reset: paginas 1,2,3 en 6000/8000/A000, ROM.
//
//  ARMADO: gm2_req llega YA registrado y ya filtrado por el slot 1 y por el bit
//  de armado (#46 bit6, volatil: el menu lo pone tras cargar la ROM y el core
//  lo borra en cada reset, para que el escaneo de slots de la BIOS no se
//  encuentre un "AB" en el slot 1 al arrancar el menu).
// ============================================================================
module gm2_slot1 (
    input  wire        clk,          // clk_54m (dominio del bus)
    input  wire        reset_n,
    input  wire [15:0] bus_addr,
    input  wire [7:0]  cpu_dout,
    input  wire        bus_rd_n,
    input  wire        bus_wr_n,
    input  wire        gm2_req,      // registrado: MREQ & (RD|WR) & slot 1 & armado

    output wire        gm2_mem_req,  // hay memoria detras (lectura 4000-BFFF / escritura SRAM)
    output wire        gm2_mem_wrt,  // escritura a la SRAM (B000-BFFF)
    output wire [21:0] gm2_addr      // direccion dentro de la megaram (A21 = 1 siempre)
);

    localparam [8:0] ROM_SEG  = 9'd480;  // 1_1110_0000: los 4 bits bajos = pagina
    localparam [8:0] SRAM_SEG = 9'd496;  // 1_1111_0000

    // registros de banco: [3:0] pagina ROM, [4] SRAM, [5] mitad de la SRAM
    reg [5:0] r6;
    reg [5:0] r8;
    reg [5:0] rA;

    always @(posedge clk) begin
        if (reset_n == 1'b0) begin
            r6 <= 6'd1;
            r8 <= 6'd2;
            rA <= 6'd3;
        end
        else if (gm2_req == 1'b1 && bus_wr_n == 1'b0 && bus_addr[12] == 1'b0) begin
            case (bus_addr[15:13])
                3'b011:  r6 <= cpu_dout[5:0];    // 6000-6FFF
                3'b100:  r8 <= cpu_dout[5:0];    // 8000-8FFF
                3'b101:  rA <= cpu_dout[5:0];    // A000-AFFF
                default: ;
            endcase
        end
    end

    // ventana de 8 KB por bus_addr[14:13]: 10 = 4000 (fija), 11 = 6000, 00 = 8000, 01 = A000
    wire       win_fixed = (bus_addr[14:13] == 2'b10);
    wire [5:0] rsel      = (bus_addr[14:13] == 2'b11) ? r6 :
                           (bus_addr[14:13] == 2'b00) ? r8 : rA;
    wire       in_win    = (bus_addr[15:14] == 2'b01) || (bus_addr[15:14] == 2'b10);   // 4000-BFFF
    wire       sram_sel  = (win_fixed == 1'b0) && (rsel[4] == 1'b1);
    wire       sram_wr   = (bus_addr[15:12] == 4'hB) && (rA[4] == 1'b1);              // B000-BFFF

    assign gm2_mem_req = gm2_req & in_win & ( ~bus_rd_n | (~bus_wr_n & sram_wr) );
    assign gm2_mem_wrt = gm2_req & ~bus_wr_n & sram_wr;

    wire [8:0]  seg = (sram_sel == 1'b1) ? SRAM_SEG :
                      (win_fixed == 1'b1) ? ROM_SEG : { ROM_SEG[8:4], rsel[3:0] };
    wire [12:0] off = (sram_sel == 1'b1) ? { rsel[5], bus_addr[11:0] } : bus_addr[12:0];

    assign gm2_addr = { seg, off };

endmodule
