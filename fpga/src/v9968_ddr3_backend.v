// ============================================================================
// v9968_ddr3_backend.v — VRAM del V9968 en la DDR3 del SOM (EXPERIMENTO _128X)
//
// Encargo: mover la VRAM de la SDRAM compartida del dock a la DDR3 del SOM.
// ADVERTENCIA HISTORICA (saga _94-_103): la DDR3 de esta placa es
// ANALOGICAMENTE MARGINAL — ojo de lectura mal-fijo por arranque (loteria de
// calibracion), corrupcion en lecturas frias. La wave OPL4 huyo de aqui a la
// SDRAM (_104) tras 8 builds de blindajes digitales. Este cliente hereda
// TODAS las vacunas de aquella guerra:
//   _87  watchdog de calibracion (~42ms, reintentos con reset de IP)
//   _95  watchdog de operacion (~0.9ms: completa EN FALSO con FF y cuenta)
//   _95  deteccion pegajosa de caida de calibracion (calib_drop)
//   _100/_101 recalibracion forzada con reset de PLL (billete nuevo del ojo)
//   _93/_97 disciplina de payloads: asentado 1 ciclo tras el flanco
//
// Cliente: DOS canales con el protocolo wv2 de memory.v (req NIVEL +
// done PULSO + dout[15:0]) en el dominio clk_x1 (74.25MHz, lo genera la IP).
// Los v9968_sdram_bridge existentes (CDC toggle 85.9<->far) se conectan tal
// cual con su lado far a clk_x1: el shim NO se toca.
//   canal A = bk del shim (lecturas palabra baja + TODAS las escrituras byte)
//   canal B = bk2 (solo lecturas, palabra alta)
// COMBO DE LINEA: bk y bk2 piden las dos mitades de la MISMA palabra de 32
// bits => misma linea de 128 bits => si ambos estan pendientes y comparten
// addr[21:4], UNA sola rafaga de lectura sirve a los dos (~175ns la palabra
// entera vs ~800ns de la danza SDRAM en serie).
//
// Escrituras byte: rafaga de escritura con mascara DM (1=NO escribir) — un
// byte por operacion, fire&forget (como la wave).
//
// Mapa: mismo mapeo de la wave ({7'd0, addr[21:4], 3'b000}, ventana de 4MB
// en la base del chip). La VRAM ocupa VRAM_BASE 0x280000..0x2BFFFF como en
// la SDRAM (la wave YA NO vive en la DDR3: el chip entero es nuestro).
//
// Dominios: clk_x1 (FSM + canales), clk_g50 (mdclk/watchdogs), clk_27
// (refclk del PLL). Receta PLL 297MHz + danza mDRP calcada de wave_ddr3
// (nand2mario ddr3_framebuffer, Apache-2.0).
// ============================================================================

module v9968_ddr3_backend #(
    // V3.7b: solo para el banco de pruebas: acorta las ventanas del motor de
    // reintentos 2^WD_SIM_SHIFT veces (0 en el chip).
    parameter integer WD_SIM_SHIFT = 0
) (
    // ---- canales VRAM (dominio clk_x1_out; protocolo wv2 nivel/pulso) ----
    input  wire        a_req,         // NIVEL: se mantiene hasta ver a_done
    input  wire        a_we,
    input  wire [21:0] a_addr,        // direccion de BYTE
    // _148 FIX B (COALESCING): escritura de PALABRA de 32 bits con mascara de
    // bytes (a_wmask, 1 = escribir). Antes 1 byte por operacion: con el menu
    // dibujando, 130627 escrituras-byte de backend para 34272 palabras del VDP
    // (3.81 ops/palabra) dejaban el canal A al 89% de ocupacion y las lecturas
    // de pantalla no entraban (12 miss/frame). Ahora 1 op = 1 palabra.
    input  wire [31:0] a_wdata,
    input  wire [3:0]  a_wmask,
    output reg  [15:0] a_dout,        // palabra 16b (addr[0] ignorado)
    output reg         a_done,        // PULSO 1 ciclo clk_x1

    input  wire        b_req,         // NIVEL (solo lecturas)
    input  wire [21:0] b_addr,
    output reg  [15:0] b_dout,
    output reg         b_done,        // PULSO 1 ciclo clk_x1

    output wire        clk_x1_out,    // 74.25MHz de la IP: reloj de los canales
    output wire        clk_7425_out,  // 138K: 74,25 MHz del PLL (VCO 891/12), NO se gatea con
                                      // pll_stop: referencia del PLL del HDMI (pll_74)
    output wire        ready,         // calibracion completada (dominio x1)

    // ---- telemetria (_95): {calib_drop, wd_fires[2:0], wd_ops[3:0]} ----
    output wire [7:0]  diag,
    // _129b: contadores de OPERACIONES servidas — {lecturas[31:16],
    // escrituras[15:0]}. Sano en marcha: ~1.3M lecturas/s (una palabra
    // cada 730ns) y escrituras a ritmo de la CPU. Si sale 0, el camino de
    // datos esta muerto aunque la calibracion diga OK.
    output wire [31:0] dbg_ops,
    // ---- V3.7b DIAGNOSTICO DEL ARRANQUE (puertos 2Ah-2Ch del MSX) ----
    output wire [6:0]  dbg_att,        // intentos de calibracion FALLIDOS (satura en 127)
    output wire [7:0]  dbg_calib_10ms, // duracion del intento que calibro, en 10 ms (satura 255)
    output wire [7:0]  dbg_boot_100ms, // del arranque a la calibracion, en 100 ms (satura 255)

    // ---- recalibracion forzada (_100; toggle, dominio libre) ----
    input  wire        recal_req,

    // ---- relojes ----
    input  wire        clk_27,        // 27MHz (cascada de video, refclk PLL)
    input  wire        clk_g50,       // pad 50MHz (ex_clk_27m, mal llamado)
    input  wire        pll27_lock,    // _87: no soltar el PLL sin el 27 vivo

    // ---- pines DDR3 (del SOM) ----
    output wire [14:0] ddr_addr,
    output wire [2:0]  ddr_bank,
    output wire        ddr_cs,
    output wire        ddr_ras,
    output wire        ddr_cas,
    output wire        ddr_we,
    output wire        ddr_ck,
    output wire        ddr_ck_n,
    output wire        ddr_cke,
    output wire        ddr_odt,
    output wire        ddr_reset_n,
    output wire [1:0]  ddr_dm,
    inout  wire [15:0] ddr_dq,
    inout  wire [1:0]  ddr_dqs,
    inout  wire [1:0]  ddr_dqs_n
);

// _130 FIDELIDAD ddr3_framebuffer (nand2mario, PROBADO con imagen en esta
// placa, IP byte-identica sha d5ca815e): NADA de POR, NADA de watchdog de
// calibracion, NADA de settle. Su receta exacta:
//   * pll_ddr3.reset = ~pll27_lock  (solo mientras el arbol de 27 arranca)
//   * IP rst_n = 1'b1               (UN intento de calibracion con tiempo
//                                    infinito; "occasionally fails;
//                                    power-cycle to retry")
//   * clk/mdclk = pad de 50MHz      (como el)
// Las _129* demostraron en HW que CUALQUIER intervencion sobre el reset
// durante el arranque (POR, settle, watchdog corto) mata la calibracion:
// la IP para su PLL a proposito mientras entrena y toda logica que
// interprete esa caida como fallo entra en bucle.

// (_100 recalibracion forzada: RETIRADA en _130 — implicaba resetear la
// IP, y la fidelidad manda. El puerto recal_req queda sin uso.)
wire rc_unused = recal_req;

// telemetria pasiva del lock (no gobierna nada)
wire pll_lock;
reg pll_lk_s1 = 1'b0, pll_lk_s2 = 1'b0;
always @(posedge clk_g50) begin
    pll_lk_s1 <= pll_lock;
    pll_lk_s2 <= pll_lk_s1;
end

wire       init_calib_complete;
// _131 LA FUSION (todo el HW en una formula): la base fiel de la _130 + el
// MOTOR DE REINTENTOS de la _128Z — la unica build que ha calibrado aqui,
// y lo hizo AL 7º REINTENTO (~1/7 de exito por intento en nuestro
// bitstream; nand2mario a un intento "occasionally fails; power-cycle").
// El watchdog da a cada intento 335ms LIMPIOS (sin settle, sin POR, sin
// tocar el PLL — todo lo que las _129* demostraron que mata la calib) y si
// no completa, pulso de reset de 256 ciclos a la IP = billete nuevo.
// V3.7b (17/09 noche) MOTOR DE REINTENTOS ESCALONADO. Lo que dio la placa
// con la 3.6g/3.7: dados que calibran a la primera (3593, 4001), uno que
// tarda >10 s (4139: el MSX arranca a ciegas a los 5 s y se pierde el logo) y
// dados que no calibran NUNCA con el pulso de 335 ms (3557, 3623, 4153),
// con el cargador peor que con el USB del PC. La probabilidad por intento
// depende del dado y de la alimentacion (~1/7 en la _128Z, ~1 en el 4001,
// ~0 en el 4153). Dos palancas, ninguna DURANTE un intento (leccion _129*):
//   1. VENTANAS CRECIENTES: 8 intentos de 335 ms (como hasta hoy: un dado
//      normal calibra en los primeros), 4 de 671 ms, 4 de 1,34 s y despues
//      2,68 s. Si un intento necesita mas de 335 ms, aqui lo consigue.
//   2. RESET DEL PLL en el pulso de reset a partir del 17o intento (~11 s
//      fallando): la IP mueve la fase del PLL con la danza mDRP y un intento
//      abortado la deja donde estuviera; el siguiente arranca con la IP en su
//      estado inicial y el PLL en otro. El remedio de nand2mario para un
//      fallo es el power-cycle, que es exactamente esto. La IP se queda en
//      reset hasta que el PLL vuelve a enganchar (tope 20 ms), asi nunca ve
//      una caida de lock que no haya pedido ella.
// Un dado que calibra a la primera no nota nada. Diagnostico por puertos:
// intentos fallidos, duracion del intento bueno y tiempo total de arranque.
localparam integer WB0 = 24 - WD_SIM_SHIFT;   // 335 ms  (2^24 / 50 MHz)
localparam integer WB1 = 25 - WD_SIM_SHIFT;   // 671 ms
localparam integer WB2 = 26 - WD_SIM_SHIFT;   // 1,34 s
localparam integer WB3 = 27 - WD_SIM_SHIFT;   // 2,68 s
localparam integer WBL = 20 - WD_SIM_SHIFT;   // tope de espera del lock del PLL (~20 ms)
reg [27:0] wd_cnt = 28'd0;
reg        wd_rst = 1'b0;
reg        wd_rst_d = 1'b0;
reg [2:0]  wd_fires = 3'd0;         // telemetria vieja (satura en 7)
reg [6:0]  wd_att = 7'd0;           // intentos fallidos (satura en 127)
reg [1:0]  wd_st = 2'd0;            // 0 intento en curso, 1 pulso de reset, 2 esperando lock del PLL
reg        wd_pll_rst = 1'b0;
wire       wd_win_end = (wd_att < 7'd8)  ? wd_cnt[WB0] :
                        (wd_att < 7'd12) ? wd_cnt[WB1] :
                        (wd_att < 7'd16) ? wd_cnt[WB2] : wd_cnt[WB3];
wire       wd_pll_due = (wd_att >= 7'd16);
always @(posedge clk_g50) begin
    case (wd_st)
    2'd0: begin
        if (init_calib_complete)
            wd_cnt <= 28'd0;
        else if (wd_win_end) begin
            wd_cnt     <= 28'd0;
            wd_rst     <= 1'b1;
            wd_pll_rst <= wd_pll_due;
            if (wd_att != 7'd127) wd_att <= wd_att + 7'd1;
            wd_st      <= 2'd1;
        end
        else
            wd_cnt <= wd_cnt + 28'd1;
    end
    2'd1: begin                          // pulso de 256 ciclos (IP y, si toca, PLL)
        wd_cnt <= wd_cnt + 28'd1;
        if (wd_cnt[7:0] == 8'hFF) begin
            wd_cnt <= 28'd0;
            if (wd_pll_rst) begin
                wd_pll_rst <= 1'b0;      // el PLL sale de reset; la IP sigue en el
                wd_st      <= 2'd2;
            end
            else begin
                wd_rst <= 1'b0;
                wd_st  <= 2'd0;
            end
        end
    end
    default: begin                       // 2: el PLL reengancha; la IP sale con lock (o al tope)
        wd_cnt <= wd_cnt + 28'd1;
        if (pll_lk_s2 || wd_cnt[WBL]) begin
            wd_cnt <= 28'd0;
            wd_rst <= 1'b0;
            wd_st  <= 2'd0;
        end
    end
    endcase
    wd_rst_d <= wd_rst;
    if (wd_rst && !wd_rst_d && wd_fires != 3'd7) wd_fires <= wd_fires + 3'd1;
end
wire       ip_rst_n = ~wd_rst;

// ---- diagnostico del arranque (dominio g50, 54 MHz; lo lee el MSX por puertos) ----
localparam integer MS10 = (540000 >> WD_SIM_SHIFT) - 1;
reg [19:0] ms10_pre = 20'd0;
wire       ms10_tick = (ms10_pre == MS10[19:0]);
reg [3:0]  ms10_dec = 4'd0;
wire       ms100_tick = ms10_tick && (ms10_dec == 4'd9);
reg [7:0]  att_10ms = 8'd0;         // duracion del intento en curso
reg [7:0]  calib_10ms = 8'd0;       // la del intento que calibro (la primera vez)
reg [7:0]  boot_100ms = 8'd0;       // del arranque a la primera calibracion
reg        calib_done_g = 1'b0;
always @(posedge clk_g50) begin
    ms10_pre <= ms10_tick ? 20'd0 : ms10_pre + 20'd1;
    if (ms10_tick) ms10_dec <= (ms10_dec == 4'd9) ? 4'd0 : ms10_dec + 4'd1;
    if (wd_st != 2'd0)
        att_10ms <= 8'd0;                              // reset de la IP: intento nuevo
    else if (init_calib_complete) begin
        if (!calib_done_g) begin calib_10ms <= att_10ms; calib_done_g <= 1'b1; end
    end
    else if (ms10_tick && att_10ms != 8'd255)
        att_10ms <= att_10ms + 8'd1;
    if (!calib_done_g && ms100_tick && boot_100ms != 8'd255)
        boot_100ms <= boot_100ms + 8'd1;
end
assign dbg_att        = wd_att;
assign dbg_calib_10ms = calib_done_g ? calib_10ms : att_10ms;   // sin calibrar: el intento en curso
assign dbg_boot_100ms = boot_100ms;


// ---------------------------------------------------------------------------
// PLL 297MHz + danza mDRP — verbatim de wave_ddr3 (_101: la recal resetea
// TAMBIEN el PLL: re-lock con fase nueva = billete de ojo INDEPENDIENTE)
// ---------------------------------------------------------------------------
wire memory_clk;
wire pll_stop;
// 138K (MSXimus_138): el PLL del 138 no tiene mDRP. El pll_stop de la IP
// va DIRECTO al enable del CLKOUT2 (asi lo cablea nand2mario en la Console
// 138K, ddr3_framebuffer_gowin); PLL_INIT vive dentro de pll_ddr3.
pll_ddr3 pll_ddr3_inst (
    .lock    (pll_lock),
    .clkout0 (),
    .clkout1 (clk_7425_out),
    .clkout2 (memory_clk),
    .clkin   (clk_27),
    .reset   (~pll27_lock | wd_pll_rst),   // _130: el arranque del arbol de 27; V3.7b: y el reintento tardio
    .init_clk(clk_g50),
    .enclk0  (1'b1),
    .enclk2  (pll_stop)
);

// ---------------------------------------------------------------------------
// IP DDR3 (cmd/128b en clk_x1, que la propia IP genera)
// ---------------------------------------------------------------------------
wire         clk_x1;
wire         ddr_rst;
wire [13:0]  ddr_addr_ip;                // _128Y: la IP solo saca 14 bits
assign ddr_addr = {1'b0, ddr_addr_ip};   // A14 CONDUCIDA A 0 (no flotante)

wire         app_rdy;
reg          app_en;
reg  [2:0]   app_cmd;
reg  [27:0]  app_addr;
wire         app_wdf_rdy;
reg          app_wdf_wren;
reg  [15:0]  app_wdf_mask;
wire         app_wdf_end = 1'b1;
reg  [127:0] app_wdf_data;
wire         app_rd_data_valid;
wire         app_rd_data_end;
wire [127:0] app_rd_data;

DDR3_Memory_Interface_Top u_ddr3 (
    .memory_clk      (memory_clk),
    .pll_stop        (pll_stop),
    .clk             (clk_g50),
    .rst_n           (ip_rst_n),
    .cmd_ready       (app_rdy),
    .cmd             (app_cmd),
    .cmd_en          (app_en),
    .addr            (app_addr),
    .wr_data_rdy     (app_wdf_rdy),
    .wr_data         (app_wdf_data),
    .wr_data_en      (app_wdf_wren),
    .wr_data_end     (app_wdf_end),
    .wr_data_mask    (app_wdf_mask),
    .rd_data         (app_rd_data),
    .rd_data_valid   (app_rd_data_valid),
    .rd_data_end     (app_rd_data_end),
    .sr_req          (1'b0),
    // _156: con la IP regenerada (User_Refresh=OFF) el controlador hace
    // AUTO-REFRESH y este 0 es inocuo. Con la IP heredada de nand2mario
    // (User_Refresh=ON) este 0 significaba CERO REFRESCOS: la DRAM se pudria
    // en segundos salvo lo que el trafico re-activaba (caso Aleste/VRAMSOAK).
    .ref_req         (1'b0),
    .sr_ack          (),
    .ref_ack         (),
    .init_calib_complete(init_calib_complete),
    .clk_out         (clk_x1),
    .pll_lock        (pll_lock),
    .burst           (1'b1),
    .ddr_rst         (ddr_rst),
    // _128Y: la IP saca 14 bits (O_ddr_addr[13:0]) pero la placa tiene 15
    // lineas (A14 = pin D1). Conectando el bus de 15 al puerto de 14, el
    // BIT 14 QUEDABA FLOTANDO (WARN EX3670 en el log, ignorado desde la
    // era wave _86): una linea de direccion flotante en una DDR3 la lee el
    // chip como ruido y puede cambiar POR ARRANQUE — sospechoso numero uno
    // de la "loteria del ojo" de la saga _94-_103. Ahora A14 se conduce a 0
    // explicitamente (la IP direcciona 14 bits de fila: A14 no se usa).
    .O_ddr_addr      (ddr_addr_ip),
    .O_ddr_ba        (ddr_bank),
    .O_ddr_cs_n      (ddr_cs),
    .O_ddr_ras_n     (ddr_ras),
    .O_ddr_cas_n     (ddr_cas),
    .O_ddr_we_n      (ddr_we),
    .O_ddr_clk       (ddr_ck),
    .O_ddr_clk_n     (ddr_ck_n),
    .O_ddr_cke      (ddr_cke),
    .O_ddr_odt       (ddr_odt),
    .O_ddr_reset_n   (ddr_reset_n),
    .O_ddr_dqm       (ddr_dm),
    .IO_ddr_dq       (ddr_dq),
    .IO_ddr_dqs      (ddr_dqs),
    .IO_ddr_dqs_n    (ddr_dqs_n)
);

assign clk_x1_out = clk_x1;

// ---------------------------------------------------------------------------
// FSM de los dos canales (clk_x1). Protocolo wv2: req NIVEL, servir UNA vez
// por flanco de subida (flag *_srv), done PULSO, dout estable tras done.
// Prioridad A > B (A lleva las escrituras y es el canal primario del shim).
// COMBO: si A(lectura) y B pendientes con la misma linea addr[21:4], una
// sola rafaga responde a ambos.
// ---------------------------------------------------------------------------
reg a_srv, b_srv;                      // ya servido (hasta que baje el req)
reg op_b;                              // op en curso: canal B
reg op_combo;                          // esta lectura responde a A y B
reg op_we;
reg [21:0] op_addr;
reg [21:0] op_baddr;                   // addr de B en un combo
reg [31:0] op_wdata;                   // _148: palabra completa
reg [3:0]  op_wmask;                   // _148: 1 = escribir ese byte

// _148: bit del byte 0 de la palabra escrita dentro de la linea de 128b
wire [6:0] cl_off = {op_addr[3:2], 5'b00000};   // = op_addr[3:2] * 32

reg [1:0] st;
localparam ST_IDLE = 2'd0, ST_ISSUE = 2'd1, ST_WAITRD = 2'd2;

// _132 HANDSHAKE ROBUSTO: la IP solo acepta con en && rdy EN EL MISMO
// CICLO. El patron viejo (comprobar rdy y pulsar en al ciclo siguiente)
// PIERDE la operacion en silencio si rdy cae justo entonces (pasa en cada
// auto-refresh); peor aun, cmd y dato pueden perderse POR SEPARADO y las
// FIFOs internas quedan desincronizadas PARA SIEMPRE (cada escritura
// posterior escribe el byte anterior en el offset anterior = las franjas
// y los glifos repetidos de las fotos del 23/07). A nand2mario el mismo
// patron no le duele porque su framebuffer se reescribe entero cada
// frame; nuestra VRAM no se cura sola. Ahora en/wren se RETIENEN hasta
// ver su rdy, y solo se avanza cuando ambos han sido aceptados.
wire cmd_acc = app_en       && app_rdy;       // aceptacion de comando
wire dat_acc = app_wdf_wren && app_wdf_rdy;   // aceptacion de dato
wire iss_free = !app_en && !app_wdf_wren;     // nada pendiente de aceptar

// _132 ANTI-DESINCRONIZACION de lecturas: si el rescate _95 abandona una
// lectura ya ACEPTADA (lenta, no perdida), su dato llega mas tarde y la
// siguiente lectura lo tomaria como suyo (a partir de ahi TODAS las
// lecturas devuelven la linea anterior). rd_pend cuenta las lecturas en
// vuelo: en WAITRD solo se toma el dato cuando rd_pend==1; los beats
// rancios (rd_pend>1) se consumen y descartan.
reg [3:0] rd_pend;

// _130 CACHE DE LINEA (una linea de 128b por canal): el fetch bg del shim
// es SECUENCIAL (pfq drena palabras consecutivas) => 8 palabras de 16b por
// linea => tras el miss inicial, ~7 hits servidos EN 1 CICLO sin tocar la
// DDR3. Trafico DDR3 /8 y el presupuesto de 730ns respira (el peor caso
// refresh+write del informe F deja de ser por-palabra). Coherencia: las
// escrituras (write-through) ACTUALIZAN el byte en las lineas cacheadas de
// AMBOS canales si el tag casa (el VDP escribe VRAM constantemente).
reg [127:0] clA_data, clB_data;
reg [17:0]  clA_tag,  clB_tag;         // addr[21:4]
reg         clA_v = 1'b0, clB_v = 1'b0;
wire a_hit = clA_v && (a_addr[21:4] == clA_tag);
wire b_hit = clB_v && (b_addr[21:4] == clB_tag);

// _95: watchdog de operacion
reg [16:0] op_wd;
reg [3:0]  wd_ops;

// _95: caida de calibracion pegajosa
reg calib_seen = 1'b0, calib_drop = 1'b0;
always @(posedge clk_x1) begin
    if (init_calib_complete) calib_seen <= 1'b1;
    if (calib_seen && !init_calib_complete) calib_drop <= 1'b1;
end
// _128Y: telemetria AMPLIADA para localizar el bloqueo exacto. El byte pasa
// a ser {clkx1_vivo, pll_lock, por_done, calib_ever, wd_fires[2:0], ovf} —
// asi se distingue "el PLL no engancha" de "la IP no arranca su reloj" de
// "el PHY no calibra" (que es lo unico realmente fisico).
reg [3:0] x1_tick = 4'd0;               // contador libre en clk_x1
always @(posedge clk_x1) x1_tick <= x1_tick + 4'd1;
reg [2:0] x1_s = 3'd0;                  // ¿late clk_x1? (visto desde g50)
reg [7:0] x1_win = 8'd0;
reg       x1_alive = 1'b0;
always @(posedge clk_g50) begin
    x1_s <= {x1_s[1:0], x1_tick[3]};
    x1_win <= x1_win + 8'd1;
    if (x1_s[2] != x1_s[1]) x1_alive <= 1'b1;   // pegajoso: hubo actividad
end
reg calib_ever_g = 1'b0;
always @(posedge clk_g50) if (init_calib_complete) calib_ever_g <= 1'b1;

assign diag = {x1_alive, pll_lk_s2, 1'b1, calib_ever_g,
               wd_fires, calib_drop}; // _131: reintentos de vuelta al diag

// _129b/_132: contadores de operaciones servidas (dominio clk_x1; el lector
// los muestrea desde otro dominio — cuasi-estaticos, tearing irrelevante).
// _132: pulsos dedicados desde las ramas exactas del FSM. El esquema viejo
// (a_done && op_we) contaba los HITS de lectura como escrituras cuando la
// op anterior habia sido un write (op_we rancio) y contaba los rescates
// FFFF como operaciones servidas. Ahora: rd = datos reales entregados,
// wr = escrituras ACEPTADAS por la IP; los rescates solo van a wd_ops.
reg inc_rd_a, inc_rd_b, inc_wr;
reg [15:0] op_rd_cnt = 16'd0, op_wr_cnt = 16'd0;
always @(posedge clk_x1) begin
    op_rd_cnt <= op_rd_cnt + {15'd0, inc_rd_a} + {15'd0, inc_rd_b};
    if (inc_wr) op_wr_cnt <= op_wr_cnt + 16'd1;
end
assign dbg_ops = {op_rd_cnt, op_wr_cnt};
assign ready = init_calib_complete;    // mismo dominio que los canales

always @(posedge clk_x1 or posedge ddr_rst) begin
    if (ddr_rst) begin
        app_en <= 1'b0; app_wdf_wren <= 1'b0;
        app_cmd <= 3'd0; app_addr <= 28'd0;
        app_wdf_data <= 128'd0; app_wdf_mask <= 16'hFFFF;
        st <= ST_IDLE;
        a_srv <= 1'b0; b_srv <= 1'b0;
        a_done <= 1'b0; b_done <= 1'b0;
        a_dout <= 16'd0; b_dout <= 16'd0;
        op_b <= 1'b0; op_combo <= 1'b0; op_we <= 1'b0;
        op_addr <= 22'd0; op_baddr <= 22'd0; op_wdata <= 32'd0; op_wmask <= 4'd0;
        op_wd <= 17'd0; wd_ops <= 4'd0;
        clA_v <= 1'b0; clB_v <= 1'b0;
        clA_tag <= 18'd0; clB_tag <= 18'd0;
        clA_data <= 128'd0; clB_data <= 128'd0;
        rd_pend <= 4'd0;
        inc_rd_a <= 1'b0; inc_rd_b <= 1'b0; inc_wr <= 1'b0;
    end
    else begin
        a_done <= 1'b0;                          // pulsos de 1 ciclo
        b_done <= 1'b0;
        inc_rd_a <= 1'b0; inc_rd_b <= 1'b0; inc_wr <= 1'b0;

        // _132: en/wren RETENIDOS hasta su aceptacion (nunca se sueltan a
        // medias: soltar un lado con el otro pendiente desincroniza las
        // FIFOs internas de la IP)
        if (cmd_acc) app_en       <= 1'b0;
        if (dat_acc) app_wdf_wren <= 1'b0;

        // _132: lecturas en vuelo (aceptada +1, beat devuelto -1)
        rd_pend <= rd_pend
                   + ((cmd_acc && app_cmd == 3'b001) ? 4'd1 : 4'd0)
                   - ((app_rd_data_valid && rd_pend != 4'd0) ? 4'd1 : 4'd0);

        // watchdog de operacion: cuenta fuera de IDLE y TAMBIEN en IDLE si
        // hay peticion esperando con la emision atascada (en retenido)
        if (st == ST_IDLE && (iss_free ||
            (!(a_req && !a_srv) && !(b_req && !b_srv))))
             op_wd <= 17'd0;
        else op_wd <= op_wd + 17'd1;

        if (!a_req) a_srv <= 1'b0;               // rearme por bajada del nivel
        if (!b_req) b_srv <= 1'b0;

        case (st)
        ST_IDLE:
            if (init_calib_complete) begin
                // _130: HITS de la cache de linea — servidos AQUI MISMO, sin
                // tocar la DDR3 ni salir de IDLE (ambos canales pueden
                // acertar el mismo ciclo). Solo lecturas.
                if (a_req && !a_srv && !a_we && a_hit) begin
                    a_dout <= clA_data[a_addr[3:1]*16 +: 16];
                    a_done <= 1'b1; a_srv <= 1'b1;
                    inc_rd_a <= 1'b1;
                end
                if (b_req && !b_srv && b_hit) begin
                    b_dout <= clB_data[b_addr[3:1]*16 +: 16];
                    b_done <= 1'b1; b_srv <= 1'b1;
                    inc_rd_b <= 1'b1;
                end
                // _132: solo se emite con el canal de emision LIBRE (nada
                // retenido de una op anterior); payload y en en el mismo
                // flanco — la IP los muestrea juntos
                if (iss_free && a_req && !a_srv && !(!a_we && a_hit)) begin
                    op_b    <= 1'b0;
                    op_we   <= a_we;
                    op_addr <= a_addr;           // payload estable: el bridge
                    op_wdata <= a_wdata;         // lo mantiene hasta el done
                    op_wmask <= a_wmask;         // _148
                    // combo: B pendiente, lectura, misma linea de 128b
                    op_combo <= (!a_we && b_req && !b_srv && !b_hit
                                 && b_addr[21:4] == a_addr[21:4]);
                    op_baddr <= b_addr;
                    app_addr <= {7'd0, a_addr[21:4], 3'b000};
                    app_en   <= 1'b1;
                    if (a_we) begin
                        app_cmd      <= 3'b000;
                        app_wdf_wren <= 1'b1;
                        // _148 FIX B: la palabra de 32b se replica en los 4
                        // carriles de la linea de 128b y la DM deja pasar SOLO
                        // los 4 bytes del carril que toca (a_addr[3:2]) y de
                        // ellos SOLO los habilitados por a_wmask. La mascara
                        // viene de la DQM del propio VDP => es IMPOSIBLE
                        // escribir un byte que el VDP no pidiera escribir.
                        // (DDR3: 1 = NO escribir.)
                        app_wdf_data <= {4{a_wdata}};
                        app_wdf_mask <= ~({12'd0, a_wmask} << {a_addr[3:2], 2'b00});
                    end
                    else app_cmd <= 3'b001;
                    st <= ST_ISSUE;
                end
                else if (iss_free && b_req && !b_srv && !b_hit) begin
                    op_b    <= 1'b1;
                    op_we   <= 1'b0;
                    op_addr <= b_addr;
                    op_combo <= 1'b0;
                    app_addr <= {7'd0, b_addr[21:4], 3'b000};
                    app_cmd  <= 3'b001;
                    app_en   <= 1'b1;
                    st <= ST_ISSUE;
                end
                else if (!iss_free && op_wd[16]) begin
                    // _132: emision atascada para siempre (rdy muerto) con
                    // clientes esperando — rescate FFFF desde IDLE para no
                    // colgar la CPU (antes esta espera era eterna)
                    if (a_req && !a_srv) begin
                        a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                    end
                    if (b_req && !b_srv) begin
                        b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                    end
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                end
            end
        ST_ISSUE:
            if (op_we) begin
                if (iss_free) begin              // cmd Y dato aceptados
                    a_done <= 1'b1; a_srv <= 1'b1;
                    inc_wr <= 1'b1;
                    // _130: coherencia de la cache — actualizar el byte en
                    // las lineas cacheadas de AMBOS canales si el tag casa
                    // _148 FIX B: ahora son HASTA 4 bytes (los de op_wmask),
                    // en el carril op_addr[3:2] de la linea de 128 bits.
                    // cl_off = op_addr[3:2]*32 = bit del byte 0 de la palabra.
                    if (clA_v && op_addr[21:4] == clA_tag) begin
                        if (op_wmask[0]) clA_data[cl_off + 7'd0  +: 8] <= op_wdata[ 7: 0];
                        if (op_wmask[1]) clA_data[cl_off + 7'd8  +: 8] <= op_wdata[15: 8];
                        if (op_wmask[2]) clA_data[cl_off + 7'd16 +: 8] <= op_wdata[23:16];
                        if (op_wmask[3]) clA_data[cl_off + 7'd24 +: 8] <= op_wdata[31:24];
                    end
                    if (clB_v && op_addr[21:4] == clB_tag) begin
                        if (op_wmask[0]) clB_data[cl_off + 7'd0  +: 8] <= op_wdata[ 7: 0];
                        if (op_wmask[1]) clB_data[cl_off + 7'd8  +: 8] <= op_wdata[15: 8];
                        if (op_wmask[2]) clB_data[cl_off + 7'd16 +: 8] <= op_wdata[23:16];
                        if (op_wmask[3]) clB_data[cl_off + 7'd24 +: 8] <= op_wdata[31:24];
                    end
                    st <= ST_IDLE;
                end
                else if (op_wd[16]) begin
                    // _95: escritura sin aceptar en ~0.9ms — completar en
                    // falso al cliente, pero en/wren QUEDAN RETENIDOS: si
                    // el rdy vuelve, la escritura tardia sigue siendo la
                    // correcta (soltarla a medias = desincronizar)
                    a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    st <= ST_IDLE;
                end
            end
            else begin
                if (!app_en) st <= ST_WAITRD;    // lectura aceptada
                else if (op_wd[16]) begin        // _95: rdy atascado — rescate
                    if (op_combo) begin
                        a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                        b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                    end
                    else if (op_b) begin
                        b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                    end
                    else begin
                        a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                    end
                    if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                    st <= ST_IDLE;
                end
            end
        ST_WAITRD:
            if (app_rd_data_valid) begin
                // _132: solo es NUESTRO dato si no hay beats rancios por
                // delante (lecturas rescatadas cuyo dato llego tarde). Los
                // rancios se consumen y descartan aqui mismo — sin esto,
                // un solo rescate desplazaba TODAS las lecturas siguientes
                // una posicion (cada lectura devolvia la linea anterior).
                if (rd_pend == 4'd1) begin
                    if (op_combo) begin
                        a_dout <= app_rd_data[op_addr[3:1]*16 +: 16];
                        b_dout <= app_rd_data[op_baddr[3:1]*16 +: 16];
                        a_done <= 1'b1; a_srv <= 1'b1;
                        b_done <= 1'b1; b_srv <= 1'b1;
                        inc_rd_a <= 1'b1; inc_rd_b <= 1'b1;
                        // _130: la linea aterriza en AMBAS caches
                        clA_data <= app_rd_data; clA_tag <= op_addr[21:4]; clA_v <= 1'b1;
                        clB_data <= app_rd_data; clB_tag <= op_addr[21:4]; clB_v <= 1'b1;
                    end
                    else if (op_b) begin
                        b_dout <= app_rd_data[op_addr[3:1]*16 +: 16];
                        b_done <= 1'b1; b_srv <= 1'b1;
                        inc_rd_b <= 1'b1;
                        clB_data <= app_rd_data; clB_tag <= op_addr[21:4]; clB_v <= 1'b1;
                    end
                    else begin
                        a_dout <= app_rd_data[op_addr[3:1]*16 +: 16];
                        a_done <= 1'b1; a_srv <= 1'b1;
                        inc_rd_a <= 1'b1;
                        clA_data <= app_rd_data; clA_tag <= op_addr[21:4]; clA_v <= 1'b1;
                    end
                    st <= ST_IDLE;
                end
            end
            else if (op_wd[16]) begin            // _95: lectura que nunca vuelve
                if (op_combo) begin
                    a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                    b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                end
                else if (op_b) begin
                    b_dout <= 16'hFFFF; b_done <= 1'b1; b_srv <= 1'b1;
                end
                else begin
                    a_dout <= 16'hFFFF; a_done <= 1'b1; a_srv <= 1'b1;
                end
                if (wd_ops != 4'd15) wd_ops <= wd_ops + 4'd1;
                st <= ST_IDLE;
            end
        default: st <= ST_IDLE;
        endcase
    end
end

endmodule
