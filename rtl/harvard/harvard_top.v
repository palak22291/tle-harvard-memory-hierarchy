`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// harvard_top.v  –  Phase I Top-Level Integration
//
// Wires together all Phase I modules into a single Harvard memory subsystem:
//
//   Member 1  ──  program_counter.v     PC with stall / branch control
//             ──  instruction_memory.v  256×32 synchronous IMEM (ROM)
//
//   Member 2  ──  data_memory.v         256×32 synchronous DMEM with d_be
//
//   Member 3  ──  address_decoder.v     Bitmask decode → cs_dmem / cs_l2
//             ──  rw_control.v          FSM routing CPU ↔ DMEM / L2
//             ──  shared_l2_memory.v    512×32 synchronous shared L2
//
// Block diagram (all buses are independent – true Harvard split):
//
//   ┌─────────────────────────────────────────────────────────┐
//   │                      harvard_top                        │
//   │                                                         │
//   │  ┌──────────┐  i_addr  ┌──────────────────┐            │
//   │  │  program ├─────────►│  instruction_mem  ├► i_rdata  │
//   │  │  counter │  pc_out  │  (IMEM, 1 KB ROM) │  i_ready  │
//   │  └────┬─────┘          └──────────────────┘            │
//   │       │ stall ◄──────────────────────────── d_ready    │
//   │       │                                                 │
//   │  CPU driver (external ports)                            │
//   │       │ req / we / d_be / d_addr / d_wdata             │
//   │       ▼                                                 │
//   │  ┌───────────┐  d_valid  ┌──────────────────┐          │
//   │  │ rw_control├──────────►│ address_decoder  │          │
//   │  │           │◄──────────┤  (combinational) │          │
//   │  │           │ cs_dmem   └──────────────────┘          │
//   │  │           │ cs_l2                                    │
//   │  │           │ addr_err                                 │
//   │  │           │                                          │
//   │  │  rw_ctrl  ├──────────► data_memory  (DMEM, 1 KB)   │
//   │  │           ├──────────► shared_l2_memory  (L2, 2 KB) │
//   └──┴───────────┴─────────────────────────────────────────┘
//
// External CPU-driver ports
//   – Instruction path : pc_out, i_rdata, i_ready, stall, branch_en,
//                        branch_addr, imem_en
//   – Data path        : req, we, d_be, d_addr, d_wdata,
//                        d_rdata, d_ready, invalid_addr_err
// =============================================================================

module harvard_top #(
    parameter IMEM_INIT_FILE = "programs/test_program.hex",
    parameter DMEM_INIT_FILE = "",
    parameter L2_INIT_FILE   = ""
)(
    // -------------------------------------------------------------------------
    // Global
    // -------------------------------------------------------------------------
    input  wire                   clk,
    input  wire                   rst_n,          // Active-low synchronous reset

    // -------------------------------------------------------------------------
    // Instruction path  (Member 1 – PC + IMEM)
    // -------------------------------------------------------------------------
    input  wire                   imem_en,        // Instruction-fetch enable
    input  wire                   branch_en,      // 1 = take branch
    input  wire [`ADDR_WIDTH-1:0] branch_addr,    // Branch target address

    output wire [`ADDR_WIDTH-1:0] pc_out,         // Current PC (byte address)
    output wire [`DATA_WIDTH-1:0] i_rdata,        // Fetched instruction word
    output wire                   i_ready,        // Instruction valid

    // -------------------------------------------------------------------------
    // Data path  (Member 2 DMEM + Member 3 Decoder/RWCtrl/L2)
    // -------------------------------------------------------------------------
    input  wire                   req,            // Data transaction request
    input  wire                   we,             // 1 = write, 0 = read
    input  wire [3:0]             d_be,           // Byte write enables
    input  wire [`ADDR_WIDTH-1:0] d_addr,         // Data byte address
    input  wire [`DATA_WIDTH-1:0] d_wdata,        // Write data

    output wire [`DATA_WIDTH-1:0] d_rdata,        // Read data (from DMEM or L2)
    output wire                   d_ready,        // Data transaction complete
    output wire                   invalid_addr_err// Unmapped address flag
);

    // =========================================================================
    // Internal wires
    // =========================================================================

    // PC → IMEM (stall fed back from d_ready to freeze PC during data access)
    wire stall = req & ~d_ready;   // stall while a data transaction is pending

    // address_decoder ↔ rw_control
    wire                   d_valid;
    wire                   cs_dmem;
    wire                   cs_l2;
    wire                   addr_err_in;

    // rw_control → data_memory
    wire                   dmem_en;
    wire                   dmem_we;
    wire [3:0]             dmem_be;
    wire [`ADDR_WIDTH-1:0] dmem_addr;
    wire [`DATA_WIDTH-1:0] dmem_wdata;
    wire [`DATA_WIDTH-1:0] dmem_rdata;
    wire                   dmem_ready;

    // rw_control → shared_l2_memory
    wire                   l2_en;
    wire                   l2_we;
    wire [3:0]             l2_be;
    wire [`ADDR_WIDTH-1:0] l2_addr;
    wire [`DATA_WIDTH-1:0] l2_wdata;
    wire [`DATA_WIDTH-1:0] l2_rdata;
    wire                   l2_ready;

    // =========================================================================
    // Member 1 – Program Counter
    // =========================================================================
    program_counter u_pc (
        .clk         (clk),
        .rst_n       (rst_n),
        .stall       (stall),
        .branch_en   (branch_en),
        .branch_addr (branch_addr),
        .pc_out      (pc_out)
    );

    // =========================================================================
    // Member 1 – Instruction Memory (ROM)
    // =========================================================================
    instruction_memory #(
        .MEM_INIT_FILE (IMEM_INIT_FILE)
    ) u_imem (
        .clk     (clk),
        .imem_en (imem_en),
        .i_addr  (pc_out),
        .i_rdata (i_rdata),
        .i_ready (i_ready)
    );

    // =========================================================================
    // Member 3 – Address Decoder  (combinational)
    // =========================================================================
    address_decoder u_dec (
        .d_addr          (d_addr),
        .d_valid         (d_valid),
        .cs_dmem         (cs_dmem),
        .cs_l2           (cs_l2),
        .invalid_addr_err(addr_err_in)
    );

    // =========================================================================
    // Member 3 – Read/Write Control FSM
    // =========================================================================
    rw_control u_rwc (
        .clk             (clk),
        .rst_n           (rst_n),
        // CPU side
        .req             (req),
        .we              (we),
        .d_be            (d_be),
        .d_addr          (d_addr),
        .d_wdata         (d_wdata),
        .d_rdata         (d_rdata),
        .d_ready         (d_ready),
        .invalid_addr_err(invalid_addr_err),
        // Decoder side
        .d_valid         (d_valid),
        .cs_dmem         (cs_dmem),
        .cs_l2           (cs_l2),
        .addr_err_in     (addr_err_in),
        // DMEM port
        .dmem_en         (dmem_en),
        .dmem_we         (dmem_we),
        .dmem_be         (dmem_be),
        .dmem_addr       (dmem_addr),
        .dmem_wdata      (dmem_wdata),
        .dmem_rdata      (dmem_rdata),
        .dmem_ready      (dmem_ready),
        // L2 port
        .l2_en           (l2_en),
        .l2_we           (l2_we),
        .l2_be           (l2_be),
        .l2_addr         (l2_addr),
        .l2_wdata        (l2_wdata),
        .l2_rdata        (l2_rdata),
        .l2_ready        (l2_ready)
    );

    // =========================================================================
    // Member 2 – Data Memory  (DMEM, 1 KB local fast RAM)
    // =========================================================================
    data_memory #(
        .MEM_INIT_FILE (DMEM_INIT_FILE)
    ) u_dmem (
        .clk     (clk),
        .rst_n   (rst_n),
        .dmem_en (dmem_en),
        .dmem_we (dmem_we),
        .d_be    (dmem_be),
        .d_addr  (dmem_addr),
        .d_wdata (dmem_wdata),
        .d_rdata (dmem_rdata),
        .d_ready (dmem_ready)
    );

    // =========================================================================
    // Member 3 – Shared L2 Memory  (2 KB shared lower-level RAM)
    // =========================================================================
    shared_l2_memory #(
        .MEM_INIT_FILE (L2_INIT_FILE)
    ) u_l2 (
        .clk     (clk),
        .rst_n   (rst_n),
        .l2_en   (l2_en),
        .l2_we   (l2_we),
        .l2_be   (l2_be),
        .l2_addr (l2_addr),
        .l2_wdata(l2_wdata),
        .l2_rdata(l2_rdata),
        .l2_ready(l2_ready)
    );

endmodule
