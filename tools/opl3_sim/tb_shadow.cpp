// tb_shadow.cpp - relectura de los registros FM del shadow de opl4fm.v (15/10/2026).
//
// El OPL3 del YMF278B tiene UN solo latch de direccion: C4h lo carga con el banco 0 y C6h con el banco 1, y el dato vale
// igual por C5h que por C7h ("0C7h is a mirror of the FM data register but use of 0C5h is preferred", doc tecnico del
// OPL4; openMSX: opl3latch unico, C5/C7 escriben y leen opl3latch). El shadow de lectura de opl4fm.v elegia el banco por el
// PUERTO de datos (C5h = banco 0 con el ultimo C4h, C7h = banco 1 con el ultimo C6h): con C6h=05h + C5h=03h (los drivers
// WAVEDRVR de Moonsoft) el dato caia en el banco 0 sobre el ultimo registro seleccionado por C4h y el banco 1 no se enteraba.
// Este banco ejercita las parejas cruzadas (C6h+C5h, C4h+C7h) y comprueba, ademas de la relectura:
//  - que el shadow de cada banco solo cambia donde debe,
//  - que el core OPL3 real recibe cada dato en el banco y el registro correctos (se vigila opl3_reg_wr, la salida de host_if).
// DUT: opl4fm.v (54/27 MHz) con el nucleo OPL3 (fpga/opl3). Verilator; ver run_shadow.sh. Estilo de tb_timer_stop.cpp.
#include "verilated.h"
#include "Vopl4fm.h"
#include "Vopl4fm___024root.h"
#include <cstdio>
#include <cstdint>
#include <vector>
#define REGWR d->rootp->opl4fm__DOT__u_opl3__DOT__opl3_reg_wr     // {valid, bank, address[7:0], data[7:0]}
static Vopl4fm *d;
static uint64_t now = 0, nxH = 9259, nxO = 9259;
static const uint64_t hpH = 9259, hpO = 18518, T = 279365;
struct Wr { int bank, reg, val; };
static std::vector<Wr> core_wr;               // escrituras que llegan al core (host_if -> banco de registros)
static std::vector<Wr> exp_wr;                // las que debe recibir, segun el modelo de un solo latch
static int lat_bank = 0, lat_reg = 0;         // modelo: latch de direccion unico
static void step() {
    uint64_t e = nxH < nxO ? nxH : nxO; now = e;
    bool orise = false;
    if (nxH == e) { d->clk_host = !d->clk_host; nxH += hpH; }
    if (nxO == e) { d->clk_opl3 = !d->clk_opl3; nxO += hpO; if (d->clk_opl3) orise = true; }
    d->eval();
    if (orise) {
        uint32_t v = (uint32_t)REGWR;
        if (v & (1u << 17)) core_wr.push_back({(int)((v >> 16) & 1), (int)((v >> 8) & 0xFF), (int)(v & 0xFF)});
    }
}
static void run_to(uint64_t t) { while ((nxH < nxO ? nxH : nxO) <= t) step(); now = t; }
static void tst(double n) { run_to(now + (uint64_t)(n * T)); }
static void us(double n) { run_to(now + (uint64_t)(n * 1e6)); }
static void io_wr(uint8_t port, uint8_t v) {
    d->addr = port; d->din = v; d->eval(); tst(1);
    d->iorq_n = 0; d->wr_n = 0; d->eval(); tst(2.5);
    d->iorq_n = 1; d->wr_n = 1; d->eval(); tst(0.5);
}
static uint8_t io_rd(uint8_t port) {
    d->addr = port; d->eval(); tst(1);
    d->iorq_n = 0; d->rd_n = 0; d->eval(); tst(2.5);
    uint8_t v = d->dout; d->iorq_n = 1; d->rd_n = 1; d->eval(); tst(0.5); return v;
}
// escritura FM por el puerto 'port' (C4..C7) con el modelo del latch unico
static void fm(uint8_t port, uint8_t v) {
    io_wr(port, v);
    if (port == 0xC4) { lat_bank = 0; lat_reg = v; }
    else if (port == 0xC6) { lat_bank = 1; lat_reg = v; }
    else exp_wr.push_back({lat_bank, lat_reg, v});
    tst(8);
}
static int errors = 0, checks = 0;
static void ok(bool c, const char *what) { checks++; if (!c) { errors++; printf("  [FAIL] %s\n", what); } else printf("  [ok]   %s\n", what); }
// relee el registro (banco, reg): selecciona con C4h/C6h y lee por el puerto de datos 'dport' (C5h o C7h)
static uint8_t rd(int bank, uint8_t reg, uint8_t dport) {
    io_wr(bank ? 0xC6 : 0xC4, reg); tst(8);
    lat_bank = bank; lat_reg = reg;
    return io_rd(dport);
}
static void chk(int bank, uint8_t reg, uint8_t dport, uint8_t esperado, const char *what) {
    uint8_t v = rd(bank, reg, dport);
    char buf[200]; snprintf(buf, sizeof buf, "%s: banco %d reg %02Xh por %02Xh = %02X (esperado %02X)", what, bank, reg, dport, v, esperado);
    ok(v == esperado, buf);
}
int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    d = new Vopl4fm;
    d->rst_n = 0; d->iorq_n = 1; d->rd_n = 1; d->wr_n = 1; d->m1_n = 1; d->addr = 0; d->din = 0; d->wave_status = 0;
    d->clk_host = 0; d->clk_opl3 = 0; d->eval();
    us(5); d->rst_n = 1; us(200);
    printf("===== shadow FM de opl4fm.v =====\n");

    // S1: parejas del mismo puerto (C4h+C5h, C6h+C7h): el caso de siempre
    fm(0xC4, 0x20); fm(0xC5, 0x11);
    fm(0xC6, 0x20); fm(0xC7, 0x22);
    chk(0, 0x20, 0xC5, 0x11, "S1 C4h+C5h / C6h+C7h");
    chk(1, 0x20, 0xC7, 0x22, "S1 C4h+C5h / C6h+C7h");

    // S2: un solo latch tambien al LEER: tras C6h el dato sale del banco 1 aunque se lea por C5h, y tras C4h del banco 0 por C7h
    chk(1, 0x20, 0xC5, 0x22, "S2 latch unico al leer (C6h + lectura por C5h)");
    chk(0, 0x20, 0xC7, 0x11, "S2 latch unico al leer (C4h + lectura por C7h)");

    // S3: el caso de WAVEDRVR: C6h=20h + dato por C5h va al banco 1 y el banco 0 no cambia
    fm(0xC6, 0x20); fm(0xC5, 0x5A);
    chk(1, 0x20, 0xC7, 0x5A, "S3 C6h=20h + C5h=5Ah: banco 1 recibe el dato");
    chk(0, 0x20, 0xC5, 0x11, "S3 el banco 0 no cambia");

    // S4: la pareja inversa: C4h + dato por C7h va al banco 0 y el banco 1 no cambia
    fm(0xC6, 0x23); fm(0xC7, 0x44);
    fm(0xC4, 0x23); fm(0xC7, 0x33);
    chk(0, 0x23, 0xC5, 0x33, "S4 C4h=23h + C7h=33h: banco 0 recibe el dato");
    chk(1, 0x23, 0xC7, 0x44, "S4 el banco 1 no cambia");

    // S5: la secuencia que activa NEW2 (105h): C6h=05h + C5h=03h; el banco 0 reg 05h no se toca
    fm(0xC4, 0x05); fm(0xC5, 0x99);
    fm(0xC6, 0x05); fm(0xC5, 0x03);
    chk(1, 0x05, 0xC7, 0x03, "S5 105h=03h por C5h: banco 1");
    chk(0, 0x05, 0xC5, 0x99, "S5 el banco 0 reg 05h no cambia");

    // S6: varias escrituras seguidas de datos con el mismo latch (no hay que reseleccionar), mezclando C5h y C7h
    fm(0xC6, 0x40); fm(0xC5, 0xA1); fm(0xC7, 0xA2); fm(0xC7, 0xA3);
    chk(1, 0x40, 0xC5, 0xA3, "S6 tres datos seguidos (C5h, C7h, C7h) al mismo registro: queda el ultimo");

    // el core OPL3 real recibe cada dato en el banco y registro del latch unico (esto ya iba bien: que no se rompa)
    us(50);
    bool igual = core_wr.size() == exp_wr.size();
    for (size_t i = 0; igual && i < exp_wr.size(); i++)
        igual = core_wr[i].bank == exp_wr[i].bank && core_wr[i].reg == exp_wr[i].reg && core_wr[i].val == exp_wr[i].val;
    printf("  core OPL3: %zu escrituras recibidas, %zu esperadas\n", core_wr.size(), exp_wr.size());
    if (!igual) {
        for (size_t i = 0; i < core_wr.size() || i < exp_wr.size(); i++) {
            if (i < exp_wr.size()) printf("    esperada %2zu: banco %d reg %02X dato %02X", i, exp_wr[i].bank, exp_wr[i].reg, exp_wr[i].val);
            if (i < core_wr.size()) printf("  | recibida: banco %d reg %02X dato %02X", core_wr[i].bank, core_wr[i].reg, core_wr[i].val);
            printf("\n");
        }
    }
    ok(igual, "el core OPL3 recibe cada dato en el banco y el registro del latch unico");

    printf("== %d comprobaciones, %d errores ==\n", checks, errors);
    printf(errors == 0 ? "RESULTADO: PASS\n" : "RESULTADO: FAIL\n");
    d->final(); delete d; return errors ? 1 : 0;
}
