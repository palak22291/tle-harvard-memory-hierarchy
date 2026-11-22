`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// harvard_cpu_top.v  (Member 4 - Phase II)
//
// Harvard system used for the Phase II comparison:
//   simple_cpu_driver
//     instruction port ──► instruction_memory (own ROM, own bus)
//     data port        ──► rw_control + address_decoder ──► data_memory / L2
//
// The instruction and data ports never share anything, so a fetch can run in
// the same cycles as a LOAD / STORE. Compare with von_neumann_top.v, which
// uses the same driver with both ports funnelled through one bus_arbiter.
//
// harvard_top.v (Phase I) is unchanged; it is the port-level subsystem with
// its own free-running PC. This top replaces that PC with the CPU driver.
// =============================================================================
module harvard_cpu_top #(
    parameter IMEM_INIT_FILE = "programs/benchmark_suite.hex",
    parameter MAX_INSTR      = 16,
    parameter L2_LATENCY     = 0
)(
    input  wire                   clk,
    input  wire                   rst_n,

    output wire                   halted,
    output wire [`DATA_WIDTH-1:0] acc,
    output wire [31:0]            cycle_count,
    output wire [31:0]            retired,
    output wire [31:0]            load_count,
    output wire [31:0]            store_count,
    output wire [31:0]            alu_count,
    output wire [31:0]            nop_count,
    output wire [31:0]            data_cycles,
    output wire [31:0]            starve_cycles,
    output wire [31:0]            overlap_cycles,
    output wire                   invalid_addr_err,

    // probes for the comparison waveform
    output wire                   if_req,
    output wire                   if_ready,
    output wire                   d_req,
    output wire                   d_ready
);

    // driver <-> IMEM
    wire [`ADDR_WIDTH-1:0] if_addr;
    wire [`DATA_WIDTH-1:0] if_rdata;

    // driver <-> rw_control
    wire                   d_we;
    wire [3:0]             d_be;
    wire [`ADDR_WIDTH-1:0] d_addr;
    wire [`DATA_WIDTH-1:0] d_wdata, d_rdata;

    // rw_control <-> decoder / memories
    wire d_valid, cs_dmem, cs_l2, addr_err_in;
    wire dmem_en, dmem_we, dmem_ready, l2_en, l2_we, l2_ready;
    wire [3:0] dmem_be, l2_be;
    wire [`ADDR_WIDTH-1:0] dmem_addr, l2_addr;
    wire [`DATA_WIDTH-1:0] dmem_wdata, dmem_rdata, l2_wdata, l2_rdata;

    simple_cpu_driver #(
        .RESET_PC (32'h0000_0000),
        .MAX_INSTR(MAX_INSTR)
    ) u_cpu (
        .clk(clk), .rst_n(rst_n),
        .if_req(if_req), .if_addr(if_addr), .if_rdata(if_rdata), .if_ready(if_ready),
        .d_req(d_req), .d_we(d_we), .d_be(d_be), .d_addr(d_addr), .d_wdata(d_wdata),
        .d_rdata(d_rdata), .d_ready(d_ready),
        .halted(halted), .acc(acc), .cycle_count(cycle_count), .retired(retired),
        .load_count(load_count), .store_count(store_count), .alu_count(alu_count),
        .nop_count(nop_count), .data_cycles(data_cycles), .starve_cycles(starve_cycles),
        .overlap_cycles(overlap_cycles));

    // Instruction path: IMEM answers one clock after imem_en is sampled
    instruction_memory #(.MEM_INIT_FILE(IMEM_INIT_FILE)) u_imem (
        .clk(clk), .imem_en(if_req), .i_addr(if_addr),
        .i_rdata(if_rdata), .i_ready(if_ready));

    // Data path: Phase I modules, unchanged
    address_decoder u_dec (
        .d_addr(d_addr), .d_valid(d_valid),
        .cs_dmem(cs_dmem), .cs_l2(cs_l2), .invalid_addr_err(addr_err_in));

    rw_control u_rwc (
        .clk(clk), .rst_n(rst_n),
        .req(d_req), .we(d_we), .d_be(d_be), .d_addr(d_addr), .d_wdata(d_wdata),
        .d_rdata(d_rdata), .d_ready(d_ready), .invalid_addr_err(invalid_addr_err),
        .d_valid(d_valid), .cs_dmem(cs_dmem), .cs_l2(cs_l2), .addr_err_in(addr_err_in),
        .dmem_en(dmem_en), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
        .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
        .l2_en(l2_en), .l2_we(l2_we), .l2_be(l2_be), .l2_addr(l2_addr),
        .l2_wdata(l2_wdata), .l2_rdata(l2_rdata), .l2_ready(l2_ready));

    data_memory u_dmem (
        .clk(clk), .rst_n(rst_n), .dmem_en(dmem_en), .dmem_we(dmem_we),
        .d_be(dmem_be), .d_addr(dmem_addr), .d_wdata(dmem_wdata),
        .d_rdata(dmem_rdata), .d_ready(dmem_ready));

    shared_l2_memory #(.L2_LATENCY(L2_LATENCY)) u_l2 (
        .clk(clk), .rst_n(rst_n), .l2_en(l2_en), .l2_we(l2_we), .l2_be(l2_be),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata), .l2_rdata(l2_rdata), .l2_ready(l2_ready));

endmodule
