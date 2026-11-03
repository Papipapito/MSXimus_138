// ============================================================================
// geo3d_ce.v -- MSXimus 138K: geo3d (Alex Moncks, MIT) con clock enable.
//
// build.tcl compila ESTE fichero, y no los tres de Alex, cuando USE_GEO3D = 1.
// El define GEO3D_CE y los tres fuentes van asi en el MISMO fichero, sin
// depender del orden de la lista: en GowinSynthesis un `define solo alcanza a los
// ficheros que van DETRAS en build.tcl (medido el 17/10), y top.v, que es donde
// esta el GEO3D_CE del resto del diseno, va despues del bloque del V9968. Los
// fuentes de Alex no llevan ningun `include (sin GEO3D_CE son byte a byte los
// suyos, ver ORIGEN.txt).
// Las rutas son relativas a fpga/, el directorio desde el que corre gw_sh
// (lanzar_campana.ps1 y "cd fpga && gw_sh build.tcl"); para el lint, -I fpga.
// ============================================================================
`define GEO3D_CE
`include "geo3d/geo3d_core.v"
`include "geo3d/geo3d_engine.v"
`include "geo3d/geo3d_bus.v"
`undef GEO3D_CE
