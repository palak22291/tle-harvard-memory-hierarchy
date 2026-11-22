`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_von_neumann.v  (Member 3 - Phase II)
//
// Self-checking testbench for the Von Neumann baseline:
//   bus_arbiter.v + unified_memory.v (one memory, one port, one bus).
//
// The testbench plays two bus masters - an instruction-fetch master and a
// data master - that follow the same req/ready handshake as rw_control:
// req is held until a one-cycle ready pulse, then dropped.
//
//   V1  reset: no memory enable, no ready, no stall
//   V2  fetch alone reads the program loaded at CODE_BASE (0x1000)
//   V3  data write / read in the DMEM window (0x000-0x3FF)
//   V4  data store to 0x000 does not overwrite the instruction at 0x1000
//   V5  simultaneous fetch + data request: data wins, if_stall is high while
//       the fetch waits, fetch is served right after
//   V6  L2 window (0x800-0xFFF) pays L2_LATENCY extra clocks; code/DMEM do not
//   V7  byte-lane write through the arbiter
//   V8  200 random overlapping fetch/data requests checked against a
//       reference model; monitor checks every cycle that if_ready and
//       d_ready are never high together and m_en is never held two cycles
// =============================================================================

module tb_von_neumann;

    localparam L2_LAT    = 2;
    localparam CODE_BASE = 32'h0000_1000;

    reg clk = 0;
    reg rst_n = 0;
    always #5 clk = ~clk;

    integer errors = 0;
    integer checks = 0;

    task check;
        input [255:0] label;
        input [31:0]  got;
        input [31:0]  exp;
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s : got 0x%08h, expected 0x%08h", label, got, exp);
            end
        end
    endtask

    // -------------------------------------------------------------------------
    // DUT: arbiter + unified memory
    // -------------------------------------------------------------------------
    reg                    if_req;
    reg  [`ADDR_WIDTH-1:0] if_addr;
    wire [`DATA_WIDTH-1:0] if_rdata;
    wire                   if_ready;

    reg                    d_req, d_we;
    reg  [3:0]             d_be;
    reg  [`ADDR_WIDTH-1:0] d_addr;
    reg  [`DATA_WIDTH-1:0] d_wdata;
    wire [`DATA_WIDTH-1:0] d_rdata;
    wire                   d_ready;

    wire                   if_stall;
    wire [1:0]             bus_owner;

    wire                   m_en, m_we, m_ready;
    wire [3:0]             m_be;
    wire [`ADDR_WIDTH-1:0] m_addr;
    wire [`DATA_WIDTH-1:0] m_wdata, m_rdata;

    bus_arbiter u_arb (
        .clk(clk), .rst_n(rst_n),
        .if_req(if_req), .if_addr(if_addr), .if_rdata(if_rdata), .if_ready(if_ready),
        .d_req(d_req), .d_we(d_we), .d_be(d_be), .d_addr(d_addr), .d_wdata(d_wdata),
        .d_rdata(d_rdata), .d_ready(d_ready),
        .if_stall(if_stall), .bus_owner(bus_owner),
        .m_en(m_en), .m_we(m_we), .m_be(m_be), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_rdata(m_rdata), .m_ready(m_ready));

    unified_memory #(
        .MEM_INIT_FILE("programs/benchmark_suite.hex"),
        .CODE_BASE    (CODE_BASE),
        .L2_LATENCY   (L2_LAT)
    ) u_mem (
        .clk(clk), .rst_n(rst_n),
        .m_en(m_en), .m_we(m_we), .m_be(m_be), .m_addr(m_addr), .m_wdata(m_wdata),
        .m_rdata(m_rdata), .m_ready(m_ready));

    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // -------------------------------------------------------------------------
    // Bus monitor (runs every cycle)
    // -------------------------------------------------------------------------
    reg m_en_q = 0;
    integer stall_cycles = 0;
    integer mon_errors = 0;
    always @(posedge clk) begin
        #1;
        if (rst_n) begin
            if (if_ready && d_ready) begin
                mon_errors = mon_errors + 1;
                $display("  FAIL monitor: if_ready and d_ready high together at cycle %0d", cyc);
            end
            if (m_en && m_en_q) begin
                mon_errors = mon_errors + 1;
                $display("  FAIL monitor: m_en held for two cycles at cycle %0d", cyc);
            end
            if (if_stall) stall_cycles = stall_cycles + 1;
        end
        m_en_q = m_en;
    end

    // -------------------------------------------------------------------------
    // Master tasks (drive on negedge, sample #1 after posedge, drop req on ready)
    // -------------------------------------------------------------------------
    reg [`DATA_WIDTH-1:0] f_data, d_data;
    integer f_lat, d_lat, f_done_cyc, d_done_cyc;

    task fetch;
        input [`ADDR_WIDTH-1:0] addr;
        integer t0;
        begin
            @(negedge clk);
            if_req = 1; if_addr = addr; t0 = cyc;
            @(posedge clk); #1;
            while (!if_ready) begin @(posedge clk); #1; end
            f_data = if_rdata; f_lat = cyc - t0; f_done_cyc = cyc;
            if_req = 0;
        end
    endtask

    task data;
        input                   we_i;
        input [3:0]             be_i;
        input [`ADDR_WIDTH-1:0] addr;
        input [`DATA_WIDTH-1:0] wdata;
        integer t0;
        begin
            @(negedge clk);
            d_req = 1; d_we = we_i; d_be = be_i; d_addr = addr; d_wdata = wdata; t0 = cyc;
            @(posedge clk); #1;
            while (!d_ready) begin @(posedge clk); #1; end
            d_data = d_rdata; d_lat = cyc - t0; d_done_cyc = cyc;
            d_req = 0; d_we = 0;
        end
    endtask

    // -------------------------------------------------------------------------
    // Reference model for V8 (word-addressed, covers the whole 8 KB array)
    // -------------------------------------------------------------------------
    reg [`DATA_WIDTH-1:0] ref_mem [0:2047];
    reg [`DATA_WIDTH-1:0] prog    [0:255];
    integer i, n, lat_code, lat_dmem, lat_l2;
    reg [`ADDR_WIDTH-1:0] ra, fa;
    reg [`DATA_WIDTH-1:0] rv;
    reg                   rw;
    integer stall_before;

    initial begin
        $dumpfile("sim/von_neumann.vcd");
        $dumpvars(0, tb_von_neumann);

        if_req = 0; if_addr = 0;
        d_req = 0; d_we = 0; d_be = 0; d_addr = 0; d_wdata = 0;
        $readmemh("programs/benchmark_suite.hex", prog);
        for (i = 0; i < 2048; i = i + 1) ref_mem[i] = 32'h0;
        for (i = 0; i < 256; i = i + 1)  ref_mem[(CODE_BASE >> 2) + i] = prog[i];

        // ---- V1 reset ----
        repeat (3) @(posedge clk); #1;
        check("V1 m_en in reset",     m_en,     0);
        check("V1 if_ready in reset", if_ready, 0);
        check("V1 d_ready in reset",  d_ready,  0);
        check("V1 if_stall in reset", if_stall, 0);
        @(negedge clk) rst_n = 1;
        repeat (2) @(posedge clk);

        // ---- V2 fetch alone ----
        for (i = 0; i < 4; i = i + 1) begin
            fetch(CODE_BASE + 4*i);
            check("V2 fetch word", f_data, prog[i]);
        end
        lat_code = f_lat;

        // ---- V3 data write / read in DMEM window ----
        data(1'b1, 4'b1111, 32'h0000_0040, 32'h1357_9BDF);
        data(1'b0, 4'b0000, 32'h0000_0040, 32'h0);
        check("V3 DMEM-window read", d_data, 32'h1357_9BDF);
        lat_dmem = d_lat;
        ref_mem[32'h40 >> 2] = 32'h1357_9BDF;

        // ---- V4 store to 0x000 leaves code at 0x1000 intact ----
        data(1'b1, 4'b1111, 32'h0000_0000, 32'hFFFF_FFFF);
        ref_mem[0] = 32'hFFFF_FFFF;
        fetch(CODE_BASE);
        check("V4 code not overwritten", f_data, prog[0]);
        data(1'b0, 4'b0000, 32'h0000_0000, 32'h0);
        check("V4 data at 0x000", d_data, 32'hFFFF_FFFF);

        // ---- V5 simultaneous requests: data has priority ----
        stall_before = stall_cycles;
        fork
            data(1'b0, 4'b0000, 32'h0000_0040, 32'h0);
            fetch(CODE_BASE + 32'h8);
        join
        check("V5 data value",          d_data, 32'h1357_9BDF);
        check("V5 fetch value",         f_data, prog[2]);
        check("V5 data served first",   (d_done_cyc < f_done_cyc), 1);
        check("V5 fetch saw stalls",    (stall_cycles - stall_before) > 0, 1);
        check("V5 fetch delayed by data", f_lat, d_lat + lat_code);

        // ---- V6 L2-window latency ----
        data(1'b1, 4'b1111, 32'h0000_0A00, 32'h2468_ACE0);
        data(1'b0, 4'b0000, 32'h0000_0A00, 32'h0);
        lat_l2 = d_lat;
        ref_mem[32'hA00 >> 2] = 32'h2468_ACE0;
        check("V6 L2-window read",       d_data, 32'h2468_ACE0);
        check("V6 L2 extra latency",     lat_l2 - lat_dmem, L2_LAT);
        check("V6 code = DMEM latency",  lat_code, lat_dmem);

        // ---- V7 byte-lane write ----
        data(1'b1, 4'b0010, 32'h0000_0040, 32'h0000_AA00);
        data(1'b0, 4'b0000, 32'h0000_0040, 32'h0);
        check("V7 byte lane 1", d_data, 32'h1357_AADF);
        ref_mem[32'h40 >> 2] = 32'h1357_AADF;

        // ---- V8 random overlapping traffic vs. reference model ----
        for (n = 0; n < 200; n = n + 1) begin
            rw = $random;
            ra = ($random & 1) ? (($random & 32'h0FC))            // DMEM window
                               : (32'h800 | ($random & 32'h7FC)); // L2 window
            rv = $random;
            fa = CODE_BASE + (($random & 32'hF) << 2);
            fork
                data(rw, 4'b1111, ra, rv);
                fetch(fa);
            join
            if (rw) ref_mem[ra >> 2] = rv;
            else    check("V8 data read vs model", d_data, ref_mem[ra >> 2]);
            check("V8 fetch vs program", f_data, ref_mem[fa >> 2]);
        end

        check("monitor errors", mon_errors, 0);

        $display("");
        $display("  Unified memory latency (clocks, request -> ready, no contention)");
        $display("  code fetch = %0d | DMEM-window access = %0d | L2-window access = %0d",
                 lat_code, lat_dmem, lat_l2);
        $display("  if_stall cycles observed over the whole test = %0d", stall_cycles);
        $display("");
        $display("tb_von_neumann: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("tb_von_neumann: ALL TESTS PASSED");
        else             $fatal(1, "tb_von_neumann: TESTS FAILED");
        $finish;
    end

    initial begin
        #500000;
        $fatal(1, "tb_von_neumann: TIMEOUT");
    end

endmodule
