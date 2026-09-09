// tb_gm2.sv - banco del mapper Game Master 2 del slot 1 (gm2_slot1.v, V3.5f)
// Referencia: openMSX RomGameMaster2.cc. Comprueba reset, registros de banco,
// seleccion de SRAM, escritura SOLO en B000-BFFF, espejo de 4 KB y direcciones.
`timescale 1ns/1ps
module tb_gm2;
    reg         clk = 0;
    always #9.26 clk = ~clk;        // 54 MHz
    reg         reset_n = 0;
    reg  [15:0] bus_addr = 16'h0000;
    reg  [7:0]  cpu_dout = 8'h00;
    reg         bus_rd_n = 1;
    reg         bus_wr_n = 1;
    reg         gm2_req  = 0;
    wire        mem_req, mem_wrt;
    wire [21:0] addr;

    gm2_slot1 dut (
        .clk(clk), .reset_n(reset_n), .bus_addr(bus_addr), .cpu_dout(cpu_dout),
        .bus_rd_n(bus_rd_n), .bus_wr_n(bus_wr_n), .gm2_req(gm2_req),
        .gm2_mem_req(mem_req), .gm2_mem_wrt(mem_wrt), .gm2_addr(addr)
    );

    integer fallos = 0;
    integer pruebas = 0;

    task idle;
        begin
            gm2_req = 0; bus_rd_n = 1; bus_wr_n = 1;
            repeat (2) @(posedge clk);
        end
    endtask

    // escritura del Z80: el pegamento de top.v registra gm2_req un ciclo despues
    task wr(input [15:0] a, input [7:0] d);
        begin
            @(posedge clk); #1;
            bus_addr = a; cpu_dout = d; bus_wr_n = 0;
            @(posedge clk); #1; gm2_req = 1;
            repeat (3) @(posedge clk); #1;
            idle;
        end
    endtask

    // lectura: deja la peticion viva y comprueba
    task rd_chk(input [15:0] a, input exp_req, input [8:0] exp_seg, input [12:0] exp_off, input [200*8-1:0] txt);
        begin
            @(posedge clk); #1;
            bus_addr = a; bus_rd_n = 0;
            @(posedge clk); #1; gm2_req = 1;
            @(posedge clk); #1;
            pruebas = pruebas + 1;
            if (mem_req !== exp_req || (exp_req && (addr[21:13] !== exp_seg || addr[12:0] !== exp_off)) || mem_wrt !== 1'b0) begin
                fallos = fallos + 1;
                $display("FALLO %0s: rd %04X -> req=%b seg=%0d off=%04X (esperaba req=%b seg=%0d off=%04X)",
                         txt, a, mem_req, addr[21:13], addr[12:0], exp_req, exp_seg, exp_off);
            end
            idle;
        end
    endtask

    // escritura de memoria (SRAM): comprueba si hay peticion de escritura y adonde
    task wr_chk(input [15:0] a, input exp_wrt, input [8:0] exp_seg, input [12:0] exp_off, input [200*8-1:0] txt);
        begin
            @(posedge clk); #1;
            bus_addr = a; cpu_dout = 8'h5A; bus_wr_n = 0;
            @(posedge clk); #1; gm2_req = 1;
            @(posedge clk); #1;
            pruebas = pruebas + 1;
            if (mem_wrt !== exp_wrt || mem_req !== exp_wrt || (exp_wrt && (addr[21:13] !== exp_seg || addr[12:0] !== exp_off))) begin
                fallos = fallos + 1;
                $display("FALLO %0s: wr %04X -> wrt=%b req=%b seg=%0d off=%04X (esperaba wrt=%b seg=%0d off=%04X)",
                         txt, a, mem_wrt, mem_req, addr[21:13], addr[12:0], exp_wrt, exp_seg, exp_off);
            end
            repeat (2) @(posedge clk); #1;
            idle;
        end
    endtask

    initial begin
        repeat (4) @(posedge clk); #1;
        reset_n = 1;
        repeat (2) @(posedge clk);

        // --- reset: paginas 0,1,2,3 en ROM ---
        rd_chk(16'h4000, 1, 480, 13'h0000, "reset 4000 = pag 0");
        rd_chk(16'h5FFF, 1, 480, 13'h1FFF, "reset 5FFF = pag 0 fin");
        rd_chk(16'h6000, 1, 481, 13'h0000, "reset 6000 = pag 1");
        rd_chk(16'h8000, 1, 482, 13'h0000, "reset 8000 = pag 2");
        rd_chk(16'hA000, 1, 483, 13'h0000, "reset A000 = pag 3");
        rd_chk(16'hBFFF, 1, 483, 13'h1FFF, "reset BFFF = pag 3 fin");
        rd_chk(16'h3FFF, 0, 0, 0, "fuera: 3FFF");
        rd_chk(16'h0000, 0, 0, 0, "fuera: 0000");
        rd_chk(16'hC000, 0, 0, 0, "fuera: C000");
        rd_chk(16'hFFFF, 0, 0, 0, "fuera: FFFF");

        // --- registros de banco ROM ---
        wr(16'h6000, 8'h05);
        rd_chk(16'h7FFF, 1, 485, 13'h1FFF, "6000<-5: 7FFF");
        wr(16'h8000, 8'hCF);            // bits 7:6 se ignoran, bit4=0 -> pagina 15
        rd_chk(16'h9000, 1, 495, 13'h1000, "8000<-CF: 9000 = pag 15");
        wr(16'hA000, 8'h0A);
        rd_chk(16'hA000, 1, 490, 13'h0000, "A000<-0A");
        wr(16'h7000, 8'h09);            // 7000-7FFF NO es registro: 6000 sigue en 5
        rd_chk(16'h6000, 1, 485, 13'h0000, "7000 no es registro");
        wr(16'h9000, 8'h01);
        rd_chk(16'h8000, 1, 495, 13'h0000, "9000 no es registro");
        wr(16'h4000, 8'h07);            // 4000-5FFF: ni registro ni escritura
        rd_chk(16'h4000, 1, 480, 13'h0000, "4000 fijo");
        wr_chk(16'h4000, 0, 0, 0, "escritura en 4000 no pasa");
        wr_chk(16'h7800, 0, 0, 0, "escritura en 7800 (ROM) no pasa");

        // --- SRAM en la ventana A000 ---
        wr(16'hA000, 8'h10);            // SRAM, mitad 0
        rd_chk(16'hA123, 1, 496, 13'h0123, "SRAM mitad 0: A123");
        rd_chk(16'hB123, 1, 496, 13'h0123, "SRAM mitad 0: B123 espejo");
        wr_chk(16'hB456, 1, 496, 13'h0456, "escritura SRAM en B456");
        wr_chk(16'hA456, 0, 0, 0, "escritura en A456 = registro, no SRAM");
        rd_chk(16'hA000, 1, 496, 13'h0000, "A456<-5A: sigue SRAM (bit4=1, bit5=0)");
        wr(16'hA000, 8'h30);            // SRAM, mitad 1
        rd_chk(16'hA000, 1, 496, 13'h1000, "SRAM mitad 1: A000");
        rd_chk(16'hBFFF, 1, 496, 13'h1FFF, "SRAM mitad 1: BFFF");
        wr_chk(16'hB000, 1, 496, 13'h1000, "escritura SRAM mitad 1 en B000");

        // --- SRAM en 6000: se lee, NO se escribe ---
        wr(16'h6000, 8'h30);
        rd_chk(16'h6ABC, 1, 496, 13'h1ABC, "SRAM en 6000: 6ABC");
        rd_chk(16'h7ABC, 1, 496, 13'h1ABC, "SRAM en 6000: 7ABC espejo");
        wr_chk(16'h7ABC, 0, 0, 0, "escritura SRAM en 7ABC no pasa");
        wr(16'h8000, 8'h10);
        rd_chk(16'h9000, 1, 496, 13'h0000, "SRAM en 8000: 9000");
        wr_chk(16'h9000, 0, 0, 0, "escritura SRAM en 9000 no pasa");

        // --- volver a ROM en A000: B000 ya no se escribe ---
        wr(16'hA000, 8'h03);
        rd_chk(16'hB000, 1, 483, 13'h1000, "A000<-3: B000 = pag 3");
        wr_chk(16'hB000, 0, 0, 0, "escritura en B000 con ROM no pasa");

        // --- sin peticion no hay nada ---
        @(posedge clk); #1; bus_addr = 16'h4000; bus_rd_n = 0; gm2_req = 0;
        @(posedge clk); #1;
        pruebas = pruebas + 1;
        if (mem_req !== 0 || mem_wrt !== 0) begin
            fallos = fallos + 1; $display("FALLO: sin gm2_req hay peticion");
        end
        idle;

        // --- reset vuelve a 1,2,3 ---
        reset_n = 0; repeat (2) @(posedge clk); #1; reset_n = 1; repeat (2) @(posedge clk);
        rd_chk(16'h6000, 1, 481, 13'h0000, "tras reset 6000 = pag 1");
        rd_chk(16'hA000, 1, 483, 13'h0000, "tras reset A000 = pag 3");

        if (fallos == 0) $display("=== tb_gm2: TODO OK (%0d pruebas)", pruebas);
        else             $display("=== tb_gm2: %0d FALLOS de %0d", fallos, pruebas);
        $finish;
    end
endmodule
