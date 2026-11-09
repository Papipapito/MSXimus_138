# ============================================================================
#  msx_geo3d.sdc — multiciclo del motor de geo3d con clock enable (GEO3D_CE).
#  build.tcl lo añade al SDC combinado SOLO con USE_GEO3D=1: sin geo3d en el
#  netlist cada linea seria un match vacio (TA2003 = ERROR).
#
#  QUE SE RESTRINGE. El motor va a clk_86 con un clock enable a 1/2 (geo_ce en
#  top.v): sus registros, sus seis BSRAM y sus DSP solo cambian en los ciclos
#  con CE, uno si y otro no. Un camino que SALE de un registro del grupo y
#  LLEGA a otro del grupo tiene dos ciclos (22,6 ns con el clk_86 de 11,30):
#  setup -end 2. Hold -end 1: el chequeo de hold vuelve al flanco de
#  lanzamiento (relacion 0), lo estandar con un CE a 1/2. NO es el -hold -end 2
#  de los multiciclo del T80: un multiciclo demasiado ancho esconde violaciones
#  que solo se verian en placa.
#
#  QUE SIGUE A UN CICLO, y tiene que seguir (en la Zynq eran los cruces
#  86 <-> 43, tambien a un ciclo de 86):
#   - las replicas geo_ce* del top -> pines CE (cambian CADA ciclo; viven fuera
#     de u_geo3d a proposito);
#   - bus -> motor: req_t, a_sel, a_wr, a_data (lado bus de geo3d_bus);
#   - motor -> bus: dout, ack_r, cmd_t, cmd_num_e, cmd_data_e -> lado bus/glue/VDP;
#   - VDP -> ce_s (el CE de S#2) y geo_rst_n -> rst_e.
#  Por eso el lado motor de geo3d_bus solo es ORIGEN (rst_e, e_wr, e_rd, ce_s,
#  lo que entra al motor), nunca destino.
#
#  NOMBRES. GowinSynthesis conserva la jerarquia (u_geo3d/u_engine/u_core/...).
#  En get_pins el * NO cruza niveles de jerarquia (medido en un PnR de
#  prueba: u_geo3d/u_engine/*/Q no casa con u_core), asi que cada nivel va en
#  su linea. Y UN PATRON POR get_pins: un patron vacio suelto es TA2003 (la
#  build se para y se ve), pero dentro de una lista Gowin lo ignora en silencio.
#  Origenes: Q de los FF, DO* = salidas de BSRAM (DO) y de DSP (DOUT).
#  Destinos: todos los pines del nivel (D, CE, RESET/SET de FF; DI, AD, CE,
#  WRE de BSRAM; A, B, C, CE de DSP).
#
#  PRECONDICION DEL MULTICICLO: un registro del grupo no captura en el ciclo
#  sin CE. Se cumple si el CE llega a su pin de enable (CE de DFF*E, CEA/CEB/
#  OCE de BSRAM, CE de DSP). La sintesis, en cambio, deja unos pocos FF con
#  CE = VCC y el CE metido en el D (un mux de "mantener"): esos capturan en
#  todos los ciclos y su D tiene que asentarse en UNO. Cuales son cambia de un
#  netlist a otro (17/10: 7 FF en un PnR de prueba de geo3d solo, 5 DISTINTOS
#  en la sintesis del diseno entero), asi que no van aqui: build.tcl, entre
#  run syn y run pnr, pasa geo3d/geo3d_ce_audit.py --emit sobre el netlist y
#  añade al SDC combinado un set_max_delay de un ciclo para el D de cada uno
#  (en Gowin set_max_delay manda sobre set_multicycle_path, SUG940 3.8). El
#  script para la build si algun FF, BSRAM o DSP del motor se queda sin CE.
#  Los dos toggles del lado motor del bus (ack_r, cmd_t) tambien salen asi,
#  pero no son destino de ningun multiciclo.
#
#  ⚠ Tras el PnR: ningun TA2003; en "Timing Exceptions" de project.tr.html,
#  relacion 22,6 en setup y 0 en hold para cada set_multicycle_path, y 11,30
#  para los set_max_delay que añadio el script (al final del SDC combinado).
# ============================================================================

# --- motor -> motor (FF, BSRAM y DSP de geo3d_engine) ---
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/Q}]           -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/DO*}]         -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
# --- motor -> geo3d_core (las BSRAM y DSP del motor no llegan directas al core: sin linea DO*) ---
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/Q}]           -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -setup -end 2
# --- geo3d_core -> geo3d_core y -> motor ---
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/Q}]    -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/DO*}]  -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/Q}]    -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
# --- lado motor de geo3d_bus (solo origen) -> motor y core ---
set_multicycle_path -from [get_pins {u_geo3d/rst_e*/Q}]               -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/rst_e*/Q}]               -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/e_wr*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/e_rd*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2
set_multicycle_path -from [get_pins {u_geo3d/ce_s*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -setup -end 2

# --- hold: relacion 0 (las mismas lineas con -hold -end 1) ---
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/Q}]           -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/DO*}]         -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/u_engine/*/Q}]           -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/Q}]    -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/DO*}]  -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/u_engine/u_core/*/Q}]    -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/rst_e*/Q}]               -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/rst_e*/Q}]               -to [get_pins {u_geo3d/u_engine/u_core/*/*}] -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/e_wr*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/e_rd*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
set_multicycle_path -from [get_pins {u_geo3d/ce_s*/Q}]                -to [get_pins {u_geo3d/u_engine/*/*}]        -hold -end 1
