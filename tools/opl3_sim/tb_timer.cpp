// tb_timer.cpp — _108/_109: semantica canon de los timers del OPL4.
// Test 1: la secuencia EXACTA del OPL3_DetectPort de VGMPlay (Grauw) —
//   el cleanup enmascara (reg4=0x78) SIN 0x80 final: en el chip real la
//   mascara LIMPIA los flags (canon ymfm) y la IRQ baja. Sin eso, la IRQ
//   queda clavada -> tormenta al EI -> el cuelgue "al detectar" de la _108.
// Test 2: el patron del ISR de VGMPlay: T1=-11 (1130Hz), ack con 0x80 y
//   el timer debe SEGUIR corriendo (el bug _84 lo paraba).
#include "Vopl3.h"
#include "verilated.h"
#include <cstdio>
#include <cstdint>
#include <cmath>
#include <complex>
#include <vector>
#include <algorithm>

static Vopl3 *dut = nullptr;
static uint64_t cycle = 0;

static void tick() {
    dut->clk = 0; dut->clk_host = 0; dut->eval();
    dut->clk = 1; dut->clk_host = 1; dut->eval();
    cycle++;
}
static void ticks(int n) { for (int i = 0; i < n; ++i) tick(); }
// sample_l es de 24 BITS (muestra de 16 << DAC_LEFT_SHIFT=5): la nativa es
// s24>>5. Un (int16_t)sample_l se queda con los 16 bits BAJOS = la onda
// plegada cada 2048 cuentas (el "vibrato de 4.6 kHz" del test 4 antiguo).
static int32_t muestra_l() { return ((int32_t)(dut->sample_l << 8) >> 8) >> 5; }

static void wr_addr(uint8_t reg, bool bank) {
    dut->address = bank ? 2 : 0; dut->din = reg;
    dut->cs_n = 0; dut->wr_n = 0; tick();
    dut->cs_n = 1; dut->wr_n = 1; dut->din = 0; ticks(6);
}
static void wr_data(uint8_t v) {
    dut->address = 1; dut->din = v;
    dut->cs_n = 0; dut->wr_n = 0; tick();
    dut->cs_n = 1; dut->wr_n = 1; dut->din = 0; ticks(36);
}
static void wr(uint16_t reg, uint8_t v) { wr_addr(reg & 0xff, (reg & 0x100) != 0); wr_data(v); }

static uint64_t wait_irq(uint64_t maxc) {
    uint64_t start = cycle;
    while (cycle - start < maxc) {
        tick();
        if (!dut->irq_n) return cycle;
    }
    return 0;
}

// === test 3: nota FM sostenida +/- acks del ISR a 1130Hz (VGMPlay toca FM
// mientras ackea su timer: si cada ack perturba la sintesis, la nota vibra)
static void run_note_isr(bool isr, int16_t *buf, int nsamp) {
    wr(0x105, 0x01);            // NEW
    wr(0x20, 0x01); wr(0x40, 0x1C); wr(0x60, 0xF4); wr(0x80, 0x01);
    wr(0x23, 0x01); wr(0x43, 0x00); wr(0x63, 0xF2); wr(0x83, 0x01);
    wr(0xC0, 0x3C);
    wr(0xA0, 0x41); wr(0xB0, 0x32);  // keyon blk4
    if (isr) { wr(0x02, 0xF5); wr(0x04, 0x80); wr(0x04, 0x39); }
    int n = 0;
    uint64_t last_ack = cycle;
    int sv_d = dut->sample_valid;
    while (n < nsamp) {
        tick();
        if (dut->sample_valid && !sv_d) buf[n++] = (int16_t)muestra_l();
        sv_d = dut->sample_valid;
        if (isr && !dut->irq_n && cycle - last_ack > 2000) {
            wr(0x04, 0x80); last_ack = cycle;
        }
    }
    wr(0xB0, 0x12);
    wr(0x04, 0x78); wr(0x04, 0x80);
}

// === medidor de vibrato / tremolo (test 4) ================================
// El medidor anterior no media el core: (1) el (int16_t) de 24 bits
// plegaba la onda (f=4.6 kHz, +/-1244 c), (2) analizaba vbuf DESPUES de
// rellenarlo con el tremolo, (3) suponia fs=44100 (la real es 27e6/545 =
// 49541 Hz) y (4) la frecuencia ciclo a ciclo esta muestreada a f0: un LFO
// cerca de f0/2 (el del core, ~218 Hz) no se ve.
// Ahora: demodulacion I/Q a la f0 del control (x*e^{-j2pi f0 n/fs}), paso
// bajo con DOS medias de un periodo de portadora (una sola dejaba +/-12 c
// de rizado a 2f0), desviacion instantanea = arg(z[n]*conj(z[n-1])) y
// amplitud = 2|z|. A 6 Hz el filtro no toca nada; a ~218 Hz atenua ~0.4
// (la profundidad de un LFO rapido sale por lo bajo; la tasa, bien).
// Tasa: la fm cuyo PAR de bandas laterales (+fm y -fm en la banda base
// compleja, cada pasada demodulada a su propia f0) tiene mas energia DE MAS
// que el control. Una modulacion pone las dos simetricas; un espolon DDS de
// la portadora (truncado de fase: ~98 Hz en el control, otros con VIB) pone
// una sola. Con el pico simple, un espolon a 240 Hz le ganaba al LFO real.
typedef std::complex<double> cplx;
static const int VN = 132000, VSKIP = 44100;   // ~0.9 s de ataque fuera

static double f0_cruces(const int32_t *x, int n, double fs) {
    double t0 = -1, t1 = 0; int k = 0;
    for (int i = 0; i + 1 < n; ++i)
        if (x[i] < 0 && x[i+1] >= 0) {
            double t = i + (double)(-x[i]) / (x[i+1] - x[i]);
            if (t0 < 0) t0 = t;
            t1 = t; k++;
        }
    return k > 1 ? (k - 1) * fs / (t1 - t0) : 0;
}
static std::vector<cplx> demod(const int32_t *x, int n, double f0, double fs) {
    std::vector<cplx> z(n);
    for (int i = 0; i < n; ++i) z[i] = (double)x[i] * std::polar(1.0, -2*M_PI*f0*i/fs);
    int M = (int)lround(fs / f0);
    for (int pasada = 0; pasada < 2; ++pasada) {
        std::vector<cplx> o; cplx s = 0;
        for (size_t i = 0; i < z.size(); ++i) {
            s += z[i];
            if (i >= (size_t)M) s -= z[i-M];
            if (i + 1 >= (size_t)M) o.push_back(s / (double)M);
        }
        z.swap(o);
    }
    return z;
}
static std::vector<double> desviacion(const std::vector<cplx> &z, double fs) {  // Hz sobre f0
    std::vector<double> d(z.size() - 1);
    for (size_t i = 1; i < z.size(); ++i) d[i-1] = std::arg(z[i] * std::conj(z[i-1])) * fs / (2*M_PI);
    return d;
}
static std::vector<double> amplitud_db(const std::vector<cplx> &z) {
    std::vector<double> a(z.size());
    for (size_t i = 0; i < z.size(); ++i) a[i] = 20*log10(2*std::abs(z[i]) + 1e-9);
    return a;
}
static double pico_pico(const std::vector<double> &y) {
    auto mm = std::minmax_element(y.begin(), y.end());
    return *mm.second - *mm.first;
}
static double tasa_par(const std::vector<cplx> &on, const std::vector<cplx> &off,
                       double fs, double lo, double hi) {
    const int D = 16;                       // diezmado: el paso bajo ya esta hecho
    auto prep = [](const std::vector<cplx> &z) {
        std::vector<cplx> r; cplx m = 0;
        for (size_t i = 0; i < z.size(); i += D) r.push_back(z[i]);
        for (cplx v : r) m += v;
        m /= (double)r.size();
        for (cplx &v : r) v -= m;
        return r;
    };
    std::vector<cplx> a = prep(on), b = prep(off);
    auto par = [fs](const std::vector<cplx> &z, double f) {   // min(|Z(+f)|^2, |Z(-f)|^2)
        cplx w = std::polar(1.0, -2*M_PI*f*D/fs), r = 1, sp = 0, sn = 0;
        for (cplx v : z) { sp += v * r; sn += v * std::conj(r); r *= w; }
        return std::min(std::norm(sp), std::norm(sn));
    };
    double best = lo, emax = -1e300;
    for (double f = lo; f < hi; f += 0.05) {
        double e = par(a, f) - par(b, f);
        if (e > emax) { emax = e; best = f; }
    }
    for (double f = best - 0.05, c = best; f < c + 0.05; f += 0.002) {
        double e = par(a, f) - par(b, f);
        if (e > emax) { emax = e; best = f; }
    }
    return best;
}

struct Vib  { double f0, desplaz_c, prof_c, prof0_c, tasa; };
struct Trem { double pp_db, pp0_db, tasa; };
static Vib medir_vibrato(const int32_t *on, const int32_t *off, double fs) {
    Vib v; int n = VN - VSKIP; on += VSKIP; off += VSKIP;
    v.f0 = f0_cruces(off, n, fs);
    v.desplaz_c = 1200*log2(f0_cruces(on, n, fs) / v.f0);
    std::vector<cplx> z0 = demod(off, n, v.f0, fs);
    std::vector<double> d1 = desviacion(demod(on, n, v.f0, fs), fs), d0 = desviacion(z0, fs);
    auto semi_c = [&](const std::vector<double> &d) {
        auto mm = std::minmax_element(d.begin(), d.end());
        return 600*log2((v.f0 + *mm.second) / (v.f0 + *mm.first));
    };
    v.prof_c = semi_c(d1); v.prof0_c = semi_c(d0);
    // sin excursion por encima del ruido del control no hay tasa que medir
    v.tasa = v.prof_c > 1.2 * v.prof0_c + 0.05
           ? tasa_par(demod(on, n, v.f0 * pow(2, v.desplaz_c / 1200), fs), z0, fs, 1, 400) : 0;
    return v;
}
static Trem medir_tremolo(const int32_t *on, const int32_t *off, double fs) {
    Trem t; int n = VN - VSKIP; on += VSKIP; off += VSKIP;
    double f0 = f0_cruces(off, n, fs);
    std::vector<cplx> z1 = demod(on, n, f0, fs), z0 = demod(off, n, f0, fs);
    t.pp_db = pico_pico(amplitud_db(z1)); t.pp0_db = pico_pico(amplitud_db(z0));
    t.tasa = t.pp_db > 1.2 * t.pp0_db + 0.1 ? tasa_par(z1, z0, fs, 1, 50) : 0;
    return t;
}
// Canon YMF262 para la nota del test (fnum 0x241 -> fnum>>7 = 4, DVB=1):
// escalera 0,+2,+4,+2,0,-2,-4,-2 sobre fnum, pasos de 1024 muestras
// (fs/8192 = 6.05 Hz), +/-4/577 = +/-12 c CENTRADA (tono medio = control).
// Los 14 c del datasheet son el maximo (fnum>>7 = 7). Tremolo DAM=1:
// 26 x 0.1875 dB = 4.9 dB a fs/13440 = 3.7 Hz.
static bool vib_canon(const Vib &v) {
    return v.prof_c > 8 && v.prof_c < 16 && v.tasa > 5.5 && v.tasa < 6.6 && fabs(v.desplaz_c) < 1;
}
static bool trem_canon(const Trem &t) {
    return t.pp_db > 4 && t.pp_db < 5.6 && t.tasa > 3.4 && t.tasa < 4.0;
}
// DVB=0: el desplazamiento se parte a la mitad (+/-6 c); DAM=0: el tremolo se
// parte entre 4 (6 x 0.1875 = 1.1 dB), como en Nuked (vibshift y tremoloshift)
static bool vib_canon_mitad(const Vib &v) {
    return v.prof_c > 4 && v.prof_c < 8 && v.tasa > 5.5 && v.tasa < 6.6 && fabs(v.desplaz_c) < 1;
}
static bool trem_canon_mitad(const Trem &t) {
    return t.pp_db > 0.8 && t.pp_db < 1.5 && t.tasa > 3.4 && t.tasa < 4.0;
}
static void informe_vib(const char *quien, const Vib &v) {
    printf("%s: f0=%.3fHz, tono medio %+.2f c, profundidad +/-%.2f c (control +/-%.2f), ",
           quien, v.f0, v.desplaz_c, v.prof_c, v.prof0_c);
    if (v.tasa > 0) printf("tasa %.3f Hz\n", v.tasa); else printf("sin modulacion medible\n");
}
static void informe_trem(const char *quien, const Trem &t) {
    printf("%s: %.2f dB pico-pico (control %.2f), ", quien, t.pp_db, t.pp0_db);
    if (t.tasa > 0) printf("tasa %.3f Hz\n", t.tasa); else printf("sin modulacion medible\n");
}
// senal canon sintetica (algoritmo de Nuked-OPL3: vibpos cada 1024 muestras,
// tremolo de 210 pasos de 64 muestras), misma nota y fase de 19 bits
static void sintetica(int32_t *x, bool vib, bool trem) {
    const int fnum = 0x241, blk = 4;
    uint32_t ph = 0;
    for (int k = 0; k < VN; ++k) {
        int r = 0;
        if (vib) {
            int vp = (k >> 10) & 7;
            r = (fnum >> 7) & 7;
            if (!(vp & 3)) r = 0; else if (vp & 1) r >>= 1;
            if (vp & 4) r = -r;
        }
        ph = (ph + (((fnum + r) << blk) >> 1)) & 0x7FFFF;
        int att = 0;
        if (trem) { int tp = (k >> 6) % 210; att = (tp < 105 ? tp : 210 - tp) >> 2; }
        x[k] = (int32_t)lround(4000 * pow(10, -att * 0.1875 / 20) * sin(2*M_PI*ph / 524288.0));
    }
}
// captura VN muestras nativas; devuelve ciclos de reloj por muestra
static double captura(int32_t *buf) {
    int n = 0, sv = dut->sample_valid; uint64_t c0 = 0;
    while (n < VN) {
        tick();
        if (dut->sample_valid && !sv) { if (n == 0) c0 = cycle; buf[n++] = muestra_l(); }
        sv = dut->sample_valid;
    }
    return (double)(cycle - c0) / (VN - 1);
}
static void volcar(const char *nombre, const int32_t *x) {   // int16 nativo
    FILE *f = fopen(nombre, "wb");
    if (!f) return;
    for (int i = 0; i < VN; ++i) { int16_t s = (int16_t)x[i]; fwrite(&s, 2, 1, f); }
    fclose(f);
}

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    dut = new Vopl3;
    dut->cs_n = 1; dut->wr_n = 1; dut->ic_n = 0;
    ticks(64);
    dut->ic_n = 1;
    ticks(4096);

    // === modo VGM (_113d): ./Vopl3 vgm <fichero> — reproduce el volcado de
    // escrituras de un VGM YMF262 real (bank reg val espera_en_muestras) y
    // mide el RMS de salida por bloques de 0.1s. Para el caso "OPL3 Demo
    // muda en VGMPlay": si aqui TAMBIEN calla, el bug es del core/wrapper;
    // si suena, el problema esta en el camino MSX (VGMPlay/mixer/status).
    if (argc > 2 && argv[1][0] == 'v') {
        FILE *f = fopen(argv[2], "r");
        if (!f) { printf("*** no puedo abrir %s ***\n", argv[2]); return 1; }
        int bank, reg, val, wait; long nsamp = 0; double acc = 0; int blk = 0;
        int sv = dut->sample_valid; double peak_rms = 0;
        // _115-diag: sample_l es de 24 BITS (el cast a int16 de antes media
        // basura). Modela la cadena REAL del wrapper con los DOS ordenes:
        //   HW hoy:  mono>>5 -> clamp16 -> x0.375 (F8=3/3)   [clamp ANTES]
        //   fix:     mono>>5 -> x0.375 -> clamp16            [atten ANTES]
        long clipA = 0, clipB = 0; int smin = 0, smax = 0;
        while (fscanf(f, "%d %d %d %d", &bank, &reg, &val, &wait) == 4) {
            while (wait > 0) {
                tick();
                if (dut->sample_valid && !sv) {
                    wait--; nsamp++;
                    // sign-extend 24 bits (mono = L, el TB no promedia L/R)
                    int32_t s24 = (int32_t)(dut->sample_l << 8) >> 8;
                    int32_t nat = s24 >> 5;                  // mono_n nativo
                    if (nat > smax) smax = nat;
                    if (nat < smin) smin = nat;
                    // orden HW hoy: clamp16 -> x0.375
                    int32_t a = nat > 32767 ? 32767 : nat < -32768 ? -32768 : nat;
                    if (a != nat) clipA++;
                    // orden fix: x0.375 -> clamp16
                    int32_t b = (nat >> 1) + (nat >> 2);
                    if (b > 32767 || b < -32768) clipB++;
                    double s = (double)a * 0.375;
                    acc += s * s;
                    if (++blk == 4410) {
                        double rms = sqrt(acc / 4410);
                        if (rms > peak_rms) peak_rms = rms;
                        printf("t=%4.1fs rms=%6.0f natMin=%7d natMax=%7d "
                               "clipHOY=%ld clipFIX=%ld\n",
                               nsamp / 44100.0, rms, smin, smax, clipA, clipB);
                        acc = 0; blk = 0; smin = 0; smax = 0;
                    }
                }
                sv = dut->sample_valid;
            }
            wr((bank << 8) | reg, (uint8_t)val);
        }
        fclose(f);
        for (int i = 0; i < 44100; ) {   // cola de 1s
            tick();
            if (dut->sample_valid && !sv) {
                i++; double s = muestra_l() * 0.375; acc += s * s;
                if (++blk == 4410) {
                    double rms = sqrt(acc / 4410);
                    if (rms > peak_rms) peak_rms = rms;
                    printf("cola   rms=%6.0f\n", rms); acc = 0; blk = 0;
                }
            }
            sv = dut->sample_valid;
        }
        printf(peak_rms > 500 ? "*** VGM OPL3: EL CORE SUENA (pico rms=%.0f) ***\n"
                              : "*** VGM OPL3: SILENCIO EN EL CORE (pico rms=%.0f) ***\n", peak_rms);
        return 0;
    }

    // === test 1: OPL3_DetectPort de VGMPlay (Grauw), secuencia exacta ===
    wr(0x04, 0x80);          // reset flags
    wr(0x02, 0xFF);          // T1 = -1 -> 80us
    wr(0x04, 0x39);          // 00111001: arranca T1 (T1 sin mascara)
    ticks(27000 * 2);        // >160us: T1 debe haber desbordado
    if (dut->irq_n) { printf("*** FALLO detect: flag/irq no subio ***\n"); return 1; }
    wr(0x04, 0x78);          // cleanup de Grauw: MASCARAS, sin 0x80
    if (!dut->irq_n) { printf("*** FALLO detect: la mascara NO limpio el flag (irq clavada => tormenta) ***\n"); return 1; }
    printf("detect AdLib: la mascara limpia flag e irq -> OK\n");

    // === test 2: patron del ISR de VGMPlay (el ack no para el timer) ===
    wr(0x02, 0xF5);          // T1 = -11 -> 11 x 80us = 880us (23760 c @27M)
    wr(0x04, 0x80);          // reset flags (VGMPlay lo hace primero)
    wr(0x04, 0x39);          // mt2 + st1 (patron VGMPlay)

    uint64_t t[4] = {0,0,0,0};
    for (int i = 0; i < 4; ++i) {
        t[i] = wait_irq(60000);
        if (!t[i]) { printf("*** FALLO: IRQ %d no llego (timeout) ***\n", i+1); return 1; }
        printf("IRQ %d en ciclo %llu\n", i+1, (unsigned long long)t[i]);
        wr(0x04, 0x80);      // ack del ISR
        if (!dut->irq_n) { printf("*** FALLO: irq_n no subio tras el ack ***\n"); return 1; }
    }
    long long p1 = (long long)(t[1]-t[0]), p2 = (long long)(t[2]-t[1]), p3 = (long long)(t[3]-t[2]);
    printf("periodos: %lld %lld %lld ciclos (nominal ~23760 mas el coste del ack)\n", p1, p2, p3);
    bool ok = p1 > 20000 && p1 < 28000 && (p2-p1) < 200 && (p2-p1) > -200 && (p3-p2) < 200 && (p3-p2) > -200;
    printf(ok ? "*** TIMER CANON: PASA ***\n" : "*** PERIODOS MAL ***\n");
    if (!ok) return 1;

    // === test 5 (_114): el REGIMEN DE MBWAVE — replayer por IRQ del OPL4
    //     a 48-100Hz (teambomba: "uses the OPL4 interrupt", hook #FD9A).
    //     48.8Hz = T1 preset 0 (256 x 80us = 20.48ms = 552960 c @27M).
    //     Nunca validado: VGMPlay usa preset -11; MBWave el maximo.
    wr(0x04, 0x78); wr(0x04, 0x80);
    wr(0x02, 0x00);          // T1 preset 0 -> periodo maximo
    wr(0x04, 0x21);          // mt2 + st1 (T1 sin mascara)
    {
        uint64_t m[3];
        for (int i = 0; i < 3; ++i) {
            m[i] = wait_irq(700000);
            if (!m[i]) { printf("*** FALLO MBWave-T1: IRQ %d no llego ***\n", i+1); return 1; }
            wr(0x04, 0x80);
        }
        long long q1 = (long long)(m[1]-m[0]), q2 = (long long)(m[2]-m[1]);
        printf("MBWave T1=0: periodos %lld %lld (nominal ~552960)\n", q1, q2);
        bool okm = q1 > 530000 && q1 < 580000 && q2 > 530000 && q2 < 580000;
        printf(okm ? "*** MBWAVE T1 (48.8Hz): PASA ***\n" : "*** MBWAVE T1: PERIODOS MAL ***\n");
        if (!okm) return 1;
        wr(0x04, 0x78); wr(0x04, 0x80);
    }
    //     T2 (nunca ejercitado en ninguna sim): preset 0xF0 -> 16 x 320us
    //     = 5.12ms = 138240 c. Arranca con bit1 (ST2), T1 enmascarado.
    wr(0x03, 0xF0);          // T2 preset
    wr(0x04, 0x42);          // mt1 + st2 (T2 sin mascara)
    {
        uint64_t m[3];
        for (int i = 0; i < 3; ++i) {
            m[i] = wait_irq(200000);
            if (!m[i]) { printf("*** FALLO T2: IRQ %d no llego ***\n", i+1); return 1; }
            wr(0x04, 0x80);
        }
        long long q1 = (long long)(m[1]-m[0]), q2 = (long long)(m[2]-m[1]);
        printf("T2=0xF0: periodos %lld %lld (nominal ~138240)\n", q1, q2);
        bool okt = q1 > 130000 && q1 < 147000 && q2 > 130000 && q2 < 147000;
        printf(okt ? "*** T2 (canon 320us/tick): PASA ***\n" : "*** T2: PERIODOS MAL ***\n");
        if (!okt) return 1;
        wr(0x04, 0x78); wr(0x04, 0x80);
    }

    // === test 3: nota sostenida — control (A vs A2, ambas sin ISR) y
    //     experimento (A vs B, con acks a 1130Hz) ===
    static int16_t bufA[24000], bufA2[24000], bufB[24000];
    run_note_isr(false, bufA, 24000);
    ticks(200000);
    run_note_isr(false, bufA2, 24000);
    ticks(200000);
    run_note_isr(true,  bufB, 24000);
    // rugosidad AUTOCONTENIDA: variacion bloque-a-bloque de la envolvente
    // dentro de CADA pasada (detrend local: cociente entre bloques vecinos).
    // Inmune a la fase/desalineacion entre pasadas.
    auto rough = [](int16_t *buf) {
        double prev = -1, worst = 0;
        for (int b = 8; b < 24000/256; ++b) {
            double r = 0;
            for (int k = 0; k < 256; ++k) r += (double)buf[b*256+k]*buf[b*256+k];
            r /= 256;
            if (prev > 1000 && r > 100) {
                double q = r/prev; if (q>1) q=1/q;
                if (1-q > worst) worst = 1-q;
            }
            prev = r;
        }
        return worst;
    };
    double rA = rough(bufA), rA2 = rough(bufA2), rB = rough(bufB);
    printf("rugosidad envolvente: A=%.2f%% A2=%.2f%% B(con ISR)=%.2f%%\n", rA*100, rA2*100, rB*100);
    double base = (rA > rA2 ? rA : rA2);
    printf(rB > base*2 && rB > 0.05 ? "*** FM + ISR: MODULADO (senal real) ***\n"
                                    : "*** FM + ISR: LIMPIO (rugosidad comparable al control) ***\n");

    // === test 4: VIBRATO y TREMOLO del FM (canon: ver vib_canon) ===
    // Los parches de toda la saga llevaban VIB=0: vibrato.sv JAMAS se ha
    // validado. Las canciones reales (MoonDriver/MBWave) lo encienden en
    // casi todo: si la tasa/profundidad esta mal, "los instrumentos vibran".
    {
        // primero el medidor contra el canon sintetico: si no lo clava, el
        // fallo es del banco y no del core
        static int32_t son[VN], soff[VN], strem[VN];
        sintetica(son, true, false); sintetica(soff, false, false); sintetica(strem, false, true);
        Vib sv = medir_vibrato(son, soff, 27e6 / 545);
        Trem st = medir_tremolo(strem, soff, 27e6 / 545);
        informe_vib("medidor (canon sintetico)", sv);
        informe_trem("medidor (canon sintetico)", st);
        if (!vib_canon(sv) || !trem_canon(st)) {
            printf("*** MEDIDOR ROTO: no reconoce el canon sintetico ***\n");
            return 1;
        }
    }
    static int32_t von[VN], voff[VN], tron[VN];
    ticks(200000);
    wr(0x105, 0x01);
    wr(0x20, 0x61); wr(0x40, 0x10); wr(0x60, 0xF0); wr(0x80, 0x0F);  // op1 VIB+EGT (sostiene)
    wr(0x23, 0x61); wr(0x43, 0x00); wr(0x63, 0xF0); wr(0x83, 0x0F);  // op2 VIB+EGT (con 0x41 caia
                                       // en release y ON sonaba con un operador menos que el control)
    wr(0xC0, 0x31);                    // salida L+R, alg aditivo
    wr(0xBD, 0x40);                    // DVB=1 (vibrato profundo)
    wr(0xA0, 0x41); wr(0xB0, 0x32);    // keyon blk4 (~436Hz a 49541 Hz)
    double cpm = captura(von);
    wr(0xB0, 0x12);
    // control: misma nota con VIB=0
    ticks(200000);
    wr(0x20, 0x21); wr(0x23, 0x21);    // VIB off, EGT on
    wr(0xA0, 0x41); wr(0xB0, 0x32);
    captura(voff);
    wr(0xB0, 0x12);
    // tremolo: AM=1 en ambos ops + DAM=1 (canon: 4.9dB a 3.7Hz)
    ticks(200000);
    wr(0x20, 0xA1); wr(0x23, 0xA1);    // AM+EGT, VIB off
    wr(0xBD, 0x80);                    // DAM=1 (tremolo profundo)
    wr(0xA0, 0x41); wr(0xB0, 0x32);
    captura(tron);
    wr(0xB0, 0x12);
    // mitad de profundidad: VIB con DVB=0 y AM con DAM=0
    static int32_t vmid[VN], tmid[VN];
    ticks(200000);
    wr(0x20, 0x61); wr(0x23, 0x61);    // VIB on, AM off
    wr(0xBD, 0x00);                    // DVB=0, DAM=0
    wr(0xA0, 0x41); wr(0xB0, 0x32);
    captura(vmid);
    wr(0xB0, 0x12);
    ticks(200000);
    wr(0x20, 0xA1); wr(0x23, 0xA1);    // AM on, VIB off
    wr(0xA0, 0x41); wr(0xB0, 0x32);
    captura(tmid);
    wr(0xB0, 0x12);
    volcar("vib_on.raw", von); volcar("vib_off.raw", voff); volcar("trem_on.raw", tron);
    double fs = 27e6 / cpm;
    printf("dumps vib_on/vib_off/trem_on escritos (int16 nativo, fs=%.1f Hz = 27MHz/%.0f)\n", fs, cpm);
    Vib v = medir_vibrato(von, voff, fs);
    Trem tr = medir_tremolo(tron, voff, fs);
    informe_vib("VIBRATO FM", v);
    printf("canon YMF262 para esta nota (DVB=1): +/-12 c centrados a %.2f Hz (fs/8192)\n", fs / 8192);
    printf(vib_canon(v) ? "*** VIBRATO: DENTRO DEL CANON ***\n" : "*** VIBRATO: FUERA DE CANON ***\n");
    informe_trem("TREMOLO FM", tr);
    printf("canon YMF262 (DAM=1): 4.9 dB a %.2f Hz (fs/13440)\n", fs / 13440);
    printf(trem_canon(tr) ? "*** TREMOLO: DENTRO DEL CANON ***\n" : "*** TREMOLO: FUERA DE CANON ***\n");
    Vib vm = medir_vibrato(vmid, voff, fs);
    Trem tm = medir_tremolo(tmid, voff, fs);
    informe_vib("VIBRATO FM (DVB=0)", vm);
    printf("canon YMF262 para esta nota (DVB=0): +/-6 c centrados a %.2f Hz\n", fs / 8192);
    printf(vib_canon_mitad(vm) ? "*** VIBRATO DVB=0: DENTRO DEL CANON ***\n" : "*** VIBRATO DVB=0: FUERA DE CANON ***\n");
    informe_trem("TREMOLO FM (DAM=0)", tm);
    printf("canon YMF262 (DAM=0): 1.1 dB a %.2f Hz\n", fs / 13440);
    printf(trem_canon_mitad(tm) ? "*** TREMOLO DAM=0: DENTRO DEL CANON ***\n" : "*** TREMOLO DAM=0: FUERA DE CANON ***\n");
    return 0;

}
