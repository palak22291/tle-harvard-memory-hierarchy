`ifndef DEFINES_VH
`define DEFINES_VH
`define ADDR_WIDTH 32
`define DATA_WIDTH 32
`define IMEM_DEPTH 256
`define DMEM_DEPTH 256
`define L2_DEPTH   512
`define DMEM_BASE_ADDR 32'h0000_0000
`define DMEM_MASK      32'hFFFF_FC00
`define L2_BASE_ADDR   32'h0000_0800
`define L2_MASK        32'hFFFF_F800
`define OP_NOP   4'b0000
`define OP_LOAD  4'b0001
`define OP_STORE 4'b0010
`define OP_ALU   4'b0011
`endif
