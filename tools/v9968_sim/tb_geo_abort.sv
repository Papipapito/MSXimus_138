`timescale 1ns/1ps
// ============================================================================
// tb_geo_abort.sv - la fila de geo3d como HMMV de una fila (HRA 3d55af4, ff_geo_hmmv de vdp_command.v) debe dejar los
// registros que ve la CPU EXACTAMENTE como la LINE equivalente (span = 0) cuando el comando NO acaba solo: STOP de la CPU,
// escritura de NX/NY a mitad de fila (entera o de una sola mitad del registro), otro R#46 durante la fila o durante el
// vaciado de la cache, nuevo arranque rapido sin esperar, cambio de modo a mitad de fila. Cada escenario se corre dos
// veces (LINE de la CPU y fila rapida con register_fill_span) y se comparan los registros al acabar y la VRAM despues de
// una LINE posterior que reutiliza NX y NY (si la fila dejo NX/NY ajustados, esa LINE sale distinta).
// Solo toca nombres que ya existian antes del arreglo (reg_nx, reg_ny, ff_dx, ff_dy, reg_dx, ff_command, ff_geo_hmmv):
// sirve tambien para el A/B contra el RTL anterior (bash run_geo_abort.sh <raiz con el RTL viejo> debe dar FAIL).
// Uso: bash run_geo_abort.sh   (Verilator --timing, WSL)
// ============================================================================
module tb_geo_abort;
    reg clk = 0; always #5.82 clk = ~clk;
    reg reset_n = 0;
    reg [9:0] screen_mode = 64;
    reg high_speed = 0;
    reg memory_stalls = 0;
    reg wr = 0; reg [5:0] num = 0; reg [7:0] data = 0; reg span = 0;
    wire ce, bd, tr; wire [7:0] sc; wire [8:0] bp;
    wire [17:0] ma; wire mv, mw; wire [31:0] mwd; wire [3:0] mm; wire [31:0] mrd; wire mre;
    integer cycles = 0;
    reg hold_mem = 0;
    wire mready = (!memory_stalls || (cycles % 23 < 11)) && !hold_mem;
    vdp_command u (
        .reset_n(reset_n), .clk(clk),
        .command_vram_address(ma), .command_vram_valid(mv), .command_vram_ready(mready),
        .command_vram_write(mw), .command_vram_wdata(mwd), .command_vram_wdata_mask(mm),
        .command_vram_rdata(mrd), .command_vram_rdata_en(mre),
        .register_write(wr), .register_num(num), .register_data(data), .register_fill_span(span),
        .clear_border_detect(0), .read_color(0),
        .status_command_execute(ce), .status_border_detect(bd), .status_transfer_ready(tr),
        .status_color(sc), .status_border_position(bp),
        .screen_mode(screen_mode), .reg_yjk_mode(0), .vram_interleave(0),
        .reg_text_back_color(0), .reg_command_enable(0),
        .reg_command_high_speed_mode(high_speed), .reg_ext_command_mode(0),
        .reg_vram256k_mode(0), .vram_access_mask(), .intr_command_end()
    );
    reg [31:0] mem [0:65535]; reg [31:0] ref_m [0:65535];
    reg [31:0] rp [0:7]; reg [7:0] rv = 0; integer st;
    integer pw = 0;
    assign mrd = rp[7]; assign mre = rv[7];
    always @(posedge clk) begin
        if (!reset_n) begin cycles <= 0; rv <= 0; pw <= 0; end
        else begin
            cycles <= cycles + 1;
            rv <= {rv[6:0], mv && mready && !mw};
            if (mv && mready && !mw) rp[0] <= mem[ma[17:2]];
            for (st = 1; st < 8; st = st + 1) rp[st] <= rp[st-1];
            if (mv && mready && mw) begin
                if (!mm[0]) mem[ma[17:2]][7:0]   <= mwd[7:0];
                if (!mm[1]) mem[ma[17:2]][15:8]  <= mwd[15:8];
                if (!mm[2]) mem[ma[17:2]][23:16] <= mwd[23:16];
                if (!mm[3]) mem[ma[17:2]][31:24] <= mwd[31:24];
            end
            if (u.ff_cache_vram_valid && u.w_cache_vram_ready && u.ff_cache_vram_write) pw <= pw + 1;
        end
    end

    task automatic rst(input bit stalls, input bit hs);
        integer i;
        begin
            @(negedge clk); reset_n = 0; wr = 0; span = 0; memory_stalls = stalls; high_speed = hs; hold_mem = 0;
            screen_mode = 64;
            repeat (8) @(negedge clk);
            for (i = 0; i < 65536; i = i + 1) mem[i] = 1144201745 ^ (i * 16909320);
            reset_n = 1; repeat (12) @(negedge clk);
        end
    endtask
    task automatic w(input [5:0] n, input [7:0] d, input bit s);
        begin @(negedge clk); wr = 1; num = n; data = d; span = s; @(negedge clk); wr = 0; span = 0; end
    endtask
    task automatic wait_end;
        integer t;
        begin
            t = 0; while (!ce && t < 1000) begin @(negedge clk); t = t + 1; end
            t = 0; while (ce && t < 400000) begin @(negedge clk); t = t + 1; end
            if (ce) $fatal(1, "no acaba");
            repeat (6) @(negedge clk);
        end
    endtask
    task automatic wait_pix(input integer n);
        integer t;
        begin t = 0; while (pw < n && t < 400000) begin @(negedge clk); t = t + 1; end end
    endtask
    task automatic setup_line(input integer x, input integer pixels, input integer y, input [7:0] col);
        reg [10:0] nx;
        begin
            nx = pixels - 1;
            w(36, x[7:0], 0); w(37, x[8], 0); w(38, y[7:0], 0); w(39, 0, 0);
            w(40, nx[7:0], 0); w(41, nx[10:8], 0); w(42, 0, 0); w(43, 0, 0);
            w(44, col, 0); w(45, 0, 0);
        end
    endtask

    // instantanea de los registros que ve la CPU al acabar el comando del escenario (reg_nx, reg_ny, ff_dy = Y viva, reg_dx,
    // codigo de comando). ff_dx se imprime pero NO se compara: es el contador X interno, se recarga de reg_dx en cada arranque
    // y no lo ve la CPU (la LINE lo deja donde acabo; la HMMV, recargado)
    reg [10:0] s_nx, s_ny, s_dy; reg [8:0] s_dx, s_rdx; reg [3:0] s_cmd; reg s_geo; integer s_pw;
    reg [10:0] a_nx, a_ny, a_dy; reg [8:0] a_dx, a_rdx; reg [3:0] a_cmd; reg a_geo; integer a_pw;
    integer rapida_otra_vez;
    integer sweep_d = 0;
    task automatic snap;
        begin s_nx = u.reg_nx; s_ny = u.reg_ny; s_dy = u.ff_dy; s_dx = u.ff_dx; s_rdx = u.reg_dx;
              s_cmd = u.ff_command; s_geo = u.ff_geo_hmmv; s_pw = pw; end
    endtask

    // ids: 1 STOP a 20 px | 2 R#40/41 a mitad | 3 R#40 sola con acarreo al bit 8 (NX = 255) | 4 R#41 sola
    //      5 R#43 sola durante el vaciado + LINE nueva | 6 LINE de la CPU durante el vaciado de la fila | 7 mismo arranque sin esperar
    //      8 igual con NY puesto a 0 por la CPU (la fila rapida arranca otra vez) | 9 cambio de modo a mitad
    //      10 NX de la CPU y luego cambio de modo | 11 R#40 a mitad desde X = 0 (informativo: 1 pixel menos)
    //      12 STOP durante el vaciado de la fila (NX/NY aun ajustados)
    //      13 / 14 barrido: LINE (13) o STOP (14) de la CPU sweep_d ciclos despues de que la fila rapida llega a c_state_finish,
    //         sin retener la memoria: el R#46 cae antes, justo en y despues del fin del vaciado (w_geo_end)
    task automatic run_esc(input integer id, input bit sp, input bit stalls, input bit hs);
        integer t;
        begin
            rapida_otra_vez = 0;
            rst(stalls, hs);
            case (id)
            1: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); w(46, 0, 0); wait_end();
            end
            2: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); w(40, 250, 0); w(41, 0, 0); wait_end();
            end
            3: begin
                setup_line(0, 256, 17, 169); w(46, 112, sp); wait_pix(20); w(40, 5, 0); wait_end();
            end
            4: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); w(41, 1, 0); wait_end();
            end
            5: begin
                // (en mitad de fila la LINE de referencia cambiaria de pendiente con el NY nuevo, y la fila rapida no: por eso
                // la escritura va en el vaciado, con la fila ya dibujada)
                setup_line(10, 120, 17, 169); w(46, 112, sp);
                t = 0;
                while (t < 400000) begin
                    @(negedge clk); t = t + 1;
                    if (u.ff_state == 42 && u.ff_command_execute) break;
                end
                hold_mem = 1;
                w(43, 1, 0); w(46, 112, 0);
                repeat (40) @(negedge clk);
                hold_mem = 0;
                wait_end();
            end
            6: begin
                setup_line(10, 120, 17, 169); w(46, 112, sp);
                t = 0;
                while (t < 400000) begin
                    @(negedge clk); t = t + 1;
                    if (u.ff_state == 42 && u.ff_command_execute) break;
                end
                hold_mem = 1;
                w(46, 112, 0);
                repeat (40) @(negedge clk);
                hold_mem = 0;
                wait_end();
            end
            7: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); w(46, 112, sp); wait_end();
            end
            8: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20);
                w(42, 0, 0); w(43, 0, 0); w(46, 112, sp);
                rapida_otra_vez = u.ff_geo_hmmv;
                wait_end();
            end
            9: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); screen_mode = 32; wait_end();
            end
            10: begin
                setup_line(10, 200, 17, 169); w(46, 112, sp); wait_pix(20); w(40, 150, 0); w(41, 0, 0);
                screen_mode = 32; wait_end();
            end
            11: begin
                setup_line(0, 256, 17, 169); w(46, 112, sp); wait_pix(20); w(40, 100, 0); w(41, 0, 0); wait_end();
            end
            12: begin
                setup_line(10, 120, 17, 169); w(46, 112, sp);
                t = 0;
                while (t < 400000) begin
                    @(negedge clk); t = t + 1;
                    if (u.ff_state == 42 && u.ff_command_execute) break;
                end
                hold_mem = 1;
                w(46, 0, 0);
                repeat (40) @(negedge clk);
                hold_mem = 0;
                wait_end();
            end
            13, 14: begin
                setup_line(10, 120, 17, 169); w(46, 112, sp);
                t = 0;
                while (t < 400000) begin
                    @(negedge clk); t = t + 1;
                    if (u.ff_state == 42 && u.ff_command_execute) break;
                end
                repeat (sweep_d) @(negedge clk);
                if (id == 13) w(46, 112, 0); else w(46, 0, 0);
                wait_end();
            end
            endcase
            snap();
            // LINE posterior de la CPU que reutiliza NX y NY
            screen_mode = 64;
            w(36, 30, 0); w(38, 40, 0); w(44, 103, 0); w(46, 112, 0);
            wait_end();
        end
    endtask

    integer fails = 0, total = 0, i, dif;
    function automatic string nombre(input integer id);
        case (id)
        1:  nombre = "STOP a 20 px                     ";
        2:  nombre = "R#40/41 a mitad de fila           ";
        3:  nombre = "R#40 sola con acarreo (NX = 255)  ";
        4:  nombre = "R#41 sola a mitad de fila         ";
        5:  nombre = "R#43 sola en el vaciado + LINE   ";
        6:  nombre = "LINE de la CPU durante el vaciado  ";
        7:  nombre = "otro arranque sin esperar          ";
        8:  nombre = "arranque sin esperar, NY = 0 CPU   ";
        9:  nombre = "cambio de modo a mitad de fila     ";
        10: nombre = "NX de la CPU y cambio de modo      ";
        11: nombre = "R#40 a mitad desde X = 0 (info)    ";
        13: nombre = "barrido: LINE de la CPU en el fin  ";
        14: nombre = "barrido: STOP de la CPU en el fin  ";
        default: nombre = "STOP durante el vaciado            ";
        endcase
    endfunction

    // run_esc se llama desde UN solo sitio: Verilator inlinea las tareas con tiempo en cada llamada y el C++ se dispara
    integer cfg, k, pasada, id, ok;
    reg stalls_c, hs_c;
    string extra;
    initial begin
        for (cfg = 0; cfg < 3; cfg = cfg + 1) begin
            // 0: sin esperas, 1: VRAM con esperas, 2: modo rapido de comandos
            stalls_c = (cfg == 1); hs_c = (cfg == 2);
            for (k = 0; k < 140; k = k + 1) begin
                // k 0..11: 1..10, 12 y al final el informativo 11; k 12..139: barrido 13 y 14 (64 posiciones cada uno). El informativo 11: el contador de la fila rapida arranca en 1, asi que con NX reescrito a
                // mitad de fila acaba un pixel antes que la LINE (indefinido en el chip real; los registros SI quedan igual)
                id = (k < 10) ? k + 1 : (k == 10) ? 12 : (k == 11) ? 11 : 13 + (k - 12) / 64;
                sweep_d = (k >= 12) ? (k - 12) % 64 : 0;
                // Pixeles y VRAM exactos siempre que el instante de la pisada no dependa del ritmo del motor: en modo rapido de
                // comandos (hs = 1) la fila rapida es mas veloz que la LINE y una pisada a "20 px + unos ciclos" cae en otro pixel
                // (1, 7, 8, 9, 10); ahi solo se exigen los registros. Los escenarios 2, 3, 4 (acaban por borde) y 5, 6, 12, 13, 14
                // (disparo por estado) no dependen del ritmo.
                for (pasada = 0; pasada < 2; pasada = pasada + 1) begin
                    run_esc(id, pasada[0], stalls_c, hs_c);
                    if (pasada == 0) begin
                        a_nx = s_nx; a_ny = s_ny; a_dy = s_dy; a_dx = s_dx; a_rdx = s_rdx; a_cmd = s_cmd; a_geo = s_geo; a_pw = s_pw;
                        for (i = 0; i < 65536; i = i + 1) ref_m[i] = mem[i];
                    end
                end
                dif = 0; for (i = 0; i < 65536; i = i + 1) if (mem[i] !== ref_m[i]) dif = dif + 1;
                ok = (s_nx === a_nx) && (s_ny === a_ny) && (s_dy === a_dy) && (s_rdx === a_rdx) &&
                     (s_cmd === a_cmd) && (s_geo === 1'b0) &&
                     (id == 11 || !(!hs_c || id == 2 || id == 3 || id == 4 || id == 5 || id == 6 || id == 12 || id >= 13) || (s_pw == a_pw && dif == 0));
                if (id == 8 && !rapida_otra_vez) ok = 0;
                total = total + 1;
                if (!ok) fails = fails + 1;
                extra = (id == 8) ? (rapida_otra_vez ? " (arranca rapida otra vez)" : " (NO arranca rapida otra vez)") : "";
                // el barrido (64 posiciones por escenario) solo imprime las dos puntas y los fallos
                if (!ok || id < 13 || sweep_d == 0 || sweep_d == 63)
                $display("%s esc %2d %s stalls=%0d hs=%0d | LINE nx=%0d ny=%0d dx=%0d dy=%0d cmd=%0h pix=%0d | RAPIDA nx=%0d ny=%0d dx=%0d dy=%0d cmd=%0h geo=%0d pix=%0d | VRAM distinta=%0d%s",
                         ok ? "PASS" : "FAIL", id, nombre(id), stalls_c, hs_c, a_nx, a_ny, a_dx, a_dy, a_cmd, a_pw,
                         s_nx, s_ny, s_dx, s_dy, s_cmd, s_geo, s_pw, dif, extra);
                if (id >= 13 && !ok) $display("   (barrido: sweep_d = %0d)", sweep_d);
            end
        end
        if (fails == 0) $display("PASS all geo abort tests (%0d escenarios)", total);
        else $display("FAIL geo abort tests: %0d de %0d escenarios", fails, total);
        $finish;
    end
endmodule
