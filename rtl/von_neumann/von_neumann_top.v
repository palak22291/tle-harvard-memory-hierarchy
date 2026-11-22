`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// von_neumann_top.v  (Member 4 - Phase II)
//
// Von Neumann system used for the Phase II comparison:
//   simple_cpu_driver
//     instruction port ─┐
//                       ├─► bus_arbiter ──► unified_memory (one port)
//     data port        ─┘
//
// Same driver and same instruction stream as harvard_cpu_top.v. The program
// sits in the code segment of unified_memory (CODE_BASE = 0x1000), so the
// driver starts at that address; data addresses are the same as in Harvard.
// =============================================================================
module von_neumann_top #(
    parameter MEM_INIT_FILE = "programs/benchmark_suite.hex",
    parameter CODE_BASE     = 32'h0000_1000,
    parameter MAX_INSTR     = 16,
    parameter L2_LATENCY    = 0
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
    output wire                   if_stall,

    // probes for the comparison waveform
    output wire                   if_req,
    output wire                   if_ready,
    output wire                   d_req,
    output wire                   d_ready
);

    wire [`ADDR_WIDTH-1:0] if_addr;
    wire [`DATA_WIDTH-1:0] if_rdata;
    wire                   d_we;
    wire [3:0]             d_be;
    wire [`ADDR_WIDTH-1:0] d_addr;
    wire [`DATA_WIDTH-1:0] d_wdata, d_rdata;
    wire [1:0]             bus_owner;

    wire                   m_en, m_we, m_ready;
    wire [3:0]             m_be;
    wire [`ADDR_WIDTH-1:0] m_addr;
    wire [`DATA_WIDTH-1:0] m_wdata, m_rdata;

    simple_cpu_driver #(
        .RESET_PC (CODE_BASE),
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

    bus_arbiter u_arb (
        .clk(clk), .rst_n(rst_n),
        .if_req(if_req), .if_addr(if_addr), .if_rdata(if_rdata), .if_ready(if_ready),
        .d_req(d_req), .d_we(d_we), .d_be(d_be), .d_addr(d_addr), .d_wdata(d_wdata),
        .d_rdata(d_rdata), .d_ready(d_ready),
        .if_stall(if_stall), .bus_owner(bus_owner),
        .m_en(m_en), .m_we(m_we), .m_be(m_be), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_rdata(m_rdata), .m_ready(m_ready));

    unified_memory #(
        .MEM_INIT_FILE(MEM_INIT_FILE),
        .CODE_BASE    (CODE_BASE),
        .L2_LATENCY   (L2_LATENCY)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .m_en(m_en), .m_we(m_we), .m_be(m_be), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_rdata(m_rdata), .m_ready(m_ready));

endmodule
