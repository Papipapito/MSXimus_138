# Histórico

Documentos que se escribieron durante el desarrollo y que ya no describen el estado actual del MSXimus. Se conservan porque explican por qué se tomaron decisiones que hoy están en el RTL, y porque las cazas de errores de la v2 son referencia para cazas futuras. Nada de aquí es documentación vigente: para eso están el [manual](../manual/) y la [referencia técnica](../tecnica/).

| Documento | Fecha | Qué era |
|---|---|---|
| `AUDIT_PRE_PORT_60K.md` | 6 de julio de 2026 | Auditoría del core del MSXnano antes de portarlo a la Console 60K |
| `BOARD_60K.md` | 6 de julio | Inventario de la placa: SOM, DDR3, SDRAM, pines |
| `CLOCK_CONSTANTS.md`, `CLOCK_PLAN.md` | 6 de julio | Todas las constantes del core que dependen del reloj y el plan para derivarlas del PLL del 60K |
| `DDR3_WRAPPER.md`, `MEMORY_CONTRACT.md`, `MEMORY_OPTIONS.md`, `SDR_MEMORY_PORT.md`, `VRAM_BRAM_DESIGN.md` | 6 a 12 de julio | Las opciones que se barajaron para la memoria del port: DDR3 como RAM principal, VRAM en BRAM, SDRAM de 16 bits. Ganó la SDRAM de 16 bits para el MSX y la DDR3 para la VRAM del V9968 |
| `FILE_MANIFEST.md` | 6 de julio | Inventario fichero a fichero del árbol heredado |
| `GW5A_IP.md` | 6 de julio | Las IP de Gowin disponibles en la GW5A y cuáles se usaron |
| `PORT_PLAN.md`, `PORT_FINDINGS.md`, `MIGRATION_STATUS.md` | 6 a 8 de julio | El plan del port y lo que se fue encontrando |
| `ROADMAP.md` | 12 de julio | El plan de la v2: V9968, OPL4, V9990, frontend |
| `email_ducasp_bl616.md` | 11 de julio | Correo a ducasp sobre el firmware UNAPI del BL616 |
| `EXPEDIENTE_CAZA_V9968_v212_y_V3.md` | 18 de agosto | El expediente de la caza de errores del V9968 entre la v2.1.2 y la v3 |
| `informes_v2/` | julio y agosto | Los informes de las cazas y estudios de la v2: ADPCM, bordes, ganancia de audio, niquelado del motor de comandos, openMSX, ROM de 2 MB, salto de dirección, upfixes, fixes del V9968, viabilidad del V9990 y del SPC700, WebMSX, carcasa |
