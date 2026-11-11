`ifndef DEFINES_VH
`define DEFINES_VH

// Global Bus Widths
`define ADDR_WIDTH 32
`define DATA_WIDTH 32

// Memory Depths (Words)
`define IMEM_DEPTH 256
`define DMEM_DEPTH 256
`define L2_DEPTH   512

// Memory Map Boundaries (For Address Decoder)
// 0x0000_0000 to 0x0000_03FF -> Local Fast Data Memory (DMEM - 1 KB)
// 0x0000_0800 to 0x0000_0FFF -> Shared Lower-Level Memory (L2 - 2 KB, 2 KB-aligned)
// Unmapped (invalid_addr_err): 0x0000_0400 - 0x0000_07FF and >= 0x0000_1000
`define DMEM_BASE_ADDR 32'h0000_0000
`define DMEM_MASK      32'hFFFF_FC00

`define L2_BASE_ADDR   32'h0000_0800
`define L2_MASK        32'hFFFF_F800

// Simple CPU Driver Opcodes [31:28]
`define OP_NOP   4'b0000
`define OP_LOAD  4'b0001
`define OP_STORE 4'b0010
`define OP_ALU   4'b0011

`endif
