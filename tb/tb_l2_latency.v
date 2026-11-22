`timescale 1ns / 1ps
`include "defines.vh"

// =============================================================================
// tb_l2_latency.v  (Member 2 - Phase II)
//
// Self-checking testbench for the multi-cycle latency model added to
// shared_l2_memory.v (parameter L2_LATENCY), plus an end-to-end latency
// measurement of the Harvard data hierarchy (rw_control -> DMEM / L2).
//
// Part A - shared_l2_memory standalone, three instances:
//          L2_LATENCY = 0 (Phase I behaviour), 2 and 4.
//   A1  l2_ready rises exactly L2_LATENCY+1 clocks after the l2_en pulse
//   A2  read data is correct and only changes when l2_ready rises
//   A3  byte-lane writes still work with latency
//   A4  a new l2_en while the memory is busy is ignored (no write, no ready)
//   A5  back-to-back accesses (next request issued right after l2_ready)
//
// Part B - full Harvard data path (address_decoder + rw_control + DMEM + L2)
//          with L2_LATENCY = 0, 2, 4: measures CPU-visible req -> d_ready
//          latency for DMEM (L1) and L2 reads and writes and prints a table.
//
// Stimulus is driven on the falling edge, checks are taken after #1 past the
// rising edge (same convention as the Phase I testbenches).
// =============================================================================

module tb_l2_latency;

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
    // Part A DUTs: three L2 instances that share one stimulus bus
    // -------------------------------------------------------------------------
    reg                    l2_en, l2_we;
    reg  [3:0]             l2_be;
    reg  [`ADDR_WIDTH-1:0] l2_addr;
    reg  [`DATA_WIDTH-1:0] l2_wdata;

    wire [`DATA_WIDTH-1:0] rdata0, rdata2, rdata4;
    wire                   ready0, ready2, ready4;

    shared_l2_memory #(.L2_LATENCY(0)) u_l2_lat0 (
        .clk(clk), .rst_n(rst_n), .l2_en(l2_en), .l2_we(l2_we), .l2_be(l2_be),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata), .l2_rdata(rdata0), .l2_ready(ready0));
    shared_l2_memory #(.L2_LATENCY(2)) u_l2_lat2 (
        .clk(clk), .rst_n(rst_n), .l2_en(l2_en), .l2_we(l2_we), .l2_be(l2_be),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata), .l2_rdata(rdata2), .l2_ready(ready2));
    shared_l2_memory #(.L2_LATENCY(4)) u_l2_lat4 (
        .clk(clk), .rst_n(rst_n), .l2_en(l2_en), .l2_we(l2_we), .l2_be(l2_be),
        .l2_addr(l2_addr), .l2_wdata(l2_wdata), .l2_rdata(rdata4), .l2_ready(ready4));

    // Cycle counter used to time-stamp ready pulses
    integer cyc = 0;
    always @(posedge clk) cyc <= cyc + 1;

    // Record the cycle at which each instance's ready was first seen high
    integer t_req, t_rdy0, t_rdy2, t_rdy4;
    always @(posedge clk) begin
        #1;
        if (ready0 && t_rdy0 < 0) t_rdy0 = cyc;
        if (ready2 && t_rdy2 < 0) t_rdy2 = cyc;
        if (ready4 && t_rdy4 < 0) t_rdy4 = cyc;
    end

    // One-cycle l2_en pulse (this is exactly what rw_control produces).
    // Returns when the slowest instance (latency 4) has answered.
    task l2_access;
        input                   we_i;
        input [3:0]             be_i;
        input [`ADDR_WIDTH-1:0] addr_i;
        input [`DATA_WIDTH-1:0] wdata_i;
        begin
            @(negedge clk);
            l2_en = 1; l2_we = we_i; l2_be = be_i; l2_addr = addr_i; l2_wdata = wdata_i;
            t_rdy0 = -1; t_rdy2 = -1; t_rdy4 = -1;
            @(posedge clk); t_req = cyc;        // memory samples l2_en here
            @(negedge clk);
            l2_en = 0; l2_we = 0; l2_be = 0;
            while (t_rdy4 < 0) @(posedge clk);
            #2;
        end
    endtask

    // -------------------------------------------------------------------------
    // Part B DUTs: three complete Harvard data paths (L2_LATENCY 0 / 2 / 4)
    // -------------------------------------------------------------------------
    reg                    req, we;
    reg  [3:0]             d_be;
    reg  [`ADDR_WIDTH-1:0] d_addr;
    reg  [`DATA_WIDTH-1:0] d_wdata;
    wire [`DATA_WIDTH-1:0] p_rdata [0:2];
    wire                   p_ready [0:2];
    wire                   p_err   [0:2];

    genvar g;
    generate
        for (g = 0; g < 3; g = g + 1) begin : path
            localparam LAT = 2 * g;      // 0, 2, 4
            wire d_valid, cs_dmem, cs_l2, addr_err_in;
            wire dmem_en, dmem_we, l2en, l2we, dmem_ready, l2rdy;
            wire [3:0] dmem_be, l2be;
            wire [`ADDR_WIDTH-1:0] dmem_addr, l2addr;
            wire [`DATA_WIDTH-1:0] dmem_wdata, dmem_rdata, l2wdata, l2rdata;
            wire [`DATA_WIDTH-1:0] rd;
            wire rdy, err;

            address_decoder u_dec (
                .d_addr(d_addr), .d_valid(d_valid),
                .cs_dmem(cs_dmem), .cs_l2(cs_l2), .invalid_addr_err(addr_err_in));

            rw_control u_rwc (
                .clk(clk), .rst_n(rst_n),
                .req(req), .we(we), .d_be(d_be), .d_addr(d_addr), .d_wdata(d_wdata),
                .d_rdata(rd), .d_ready(rdy), .invalid_addr_err(err),
                .d_valid(d_valid), .cs_dmem(cs_dmem), .cs_l2(cs_l2), .addr_err_in(addr_err_in),
                .dmem_en(dmem_en), .dmem_we(dmem_we), .dmem_be(dmem_be), .dmem_addr(dmem_addr),
                .dmem_wdata(dmem_wdata), .dmem_rdata(dmem_rdata), .dmem_ready(dmem_ready),
                .l2_en(l2en), .l2_we(l2we), .l2_be(l2be), .l2_addr(l2addr),
                .l2_wdata(l2wdata), .l2_rdata(l2rdata), .l2_ready(l2rdy));

            data_memory u_dmem (
                .clk(clk), .rst_n(rst_n), .dmem_en(dmem_en), .dmem_we(dmem_we),
                .d_be(dmem_be), .d_addr(dmem_addr), .d_wdata(dmem_wdata),
                .d_rdata(dmem_rdata), .d_ready(dmem_ready));

            shared_l2_memory #(.L2_LATENCY(LAT)) u_l2 (
                .clk(clk), .rst_n(rst_n), .l2_en(l2en), .l2_we(l2we), .l2_be(l2be),
                .l2_addr(l2addr), .l2_wdata(l2wdata), .l2_rdata(l2rdata), .l2_ready(l2rdy));

            assign p_rdata[g] = rd;
            assign p_ready[g] = rdy;
            assign p_err[g]   = err;
        end
    endgenerate

    // Issue one CPU transaction to all three paths at once; measure each
    // path's req -> d_ready latency in clocks.
    integer lat [0:2];
    reg [`DATA_WIDTH-1:0] got [0:2];
    integer k, start;

    task cpu_access;
        input                   we_i;
        input [`ADDR_WIDTH-1:0] addr_i;
        input [`DATA_WIDTH-1:0] wdata_i;
        begin
            @(negedge clk);
            req = 1; we = we_i; d_be = 4'b1111; d_addr = addr_i; d_wdata = wdata_i;
            start = cyc;
            for (k = 0; k < 3; k = k + 1) lat[k] = -1;
            while (lat[0] < 0 || lat[1] < 0 || lat[2] < 0) begin
                @(posedge clk); #1;
                for (k = 0; k < 3; k = k + 1)
                    if (p_ready[k] && lat[k] < 0) begin
                        lat[k] = cyc - start;
                        got[k] = p_rdata[k];
                    end
                // Drop req once the fastest path answered so no path
                // starts a second transaction (requester-side handshake).
                if (p_ready[0] || p_ready[1] || p_ready[2]) req = 0;
            end
            req = 0; we = 0;
            repeat (2) @(posedge clk);
        end
    endtask

    // Per-path latency table
    integer lat_dmem_wr [0:2], lat_dmem_rd [0:2], lat_l2_wr [0:2], lat_l2_rd [0:2];

    // -------------------------------------------------------------------------
    // Stimulus
    // -------------------------------------------------------------------------
    initial begin
        $dumpfile("sim/l2_latency.vcd");
        $dumpvars(0, tb_l2_latency);

        l2_en = 0; l2_we = 0; l2_be = 0; l2_addr = 0; l2_wdata = 0;
        req = 0; we = 0; d_be = 0; d_addr = 0; d_wdata = 0;
        t_rdy0 = -1; t_rdy2 = -1; t_rdy4 = -1;
        repeat (3) @(posedge clk);
        @(negedge clk) rst_n = 1;
        repeat (2) @(posedge clk);

        // ---------------- Part A ----------------
        $display("Part A: shared_l2_memory standalone latency");

        // A1/A3: full-word write, latency of the write acknowledge
        l2_access(1'b1, 4'b1111, 32'h0000_0800, 32'hCAFE_0001);
        check("A1 write lat0", t_rdy0 - t_req, 1);
        check("A1 write lat2", t_rdy2 - t_req, 3);
        check("A1 write lat4", t_rdy4 - t_req, 5);

        // A1/A2: read back, latency and data
        l2_access(1'b0, 4'b0000, 32'h0000_0800, 32'h0);
        check("A1 read lat0", t_rdy0 - t_req, 1);
        check("A1 read lat2", t_rdy2 - t_req, 3);
        check("A1 read lat4", t_rdy4 - t_req, 5);
        check("A2 rdata lat0", rdata0, 32'hCAFE_0001);
        check("A2 rdata lat2", rdata2, 32'hCAFE_0001);
        check("A2 rdata lat4", rdata4, 32'hCAFE_0001);

        // A2: data must not appear before ready. Write a new value at another
        // address, then read it and sample rdata one clock after the request.
        l2_access(1'b1, 4'b1111, 32'h0000_0FFC, 32'h1234_5678);
        @(negedge clk);
        l2_en = 1; l2_we = 0; l2_be = 0; l2_addr = 32'h0000_0FFC;
        @(posedge clk); @(negedge clk); l2_en = 0;
        // one clock after sampling: lat0 already has the new data,
        // lat2 / lat4 must still show the previous read value.
        check("A2 early rdata lat0", rdata0, 32'h1234_5678);
        check("A2 early rdata lat2", rdata2, 32'hCAFE_0001);
        check("A2 early rdata lat4", rdata4, 32'hCAFE_0001);
        check("A2 early ready lat2", ready2, 0);
        check("A2 early ready lat4", ready4, 0);
        repeat (5) @(posedge clk); #1;
        check("A2 final rdata lat2", rdata2, 32'h1234_5678);
        check("A2 final rdata lat4", rdata4, 32'h1234_5678);

        // A3: byte-lane write (upper half only) then read
        l2_access(1'b1, 4'b1100, 32'h0000_0800, 32'hBEEF_0000);
        l2_access(1'b0, 4'b0000, 32'h0000_0800, 32'h0);
        check("A3 byte-lane lat0", rdata0, 32'hBEEF_0001);
        check("A3 byte-lane lat2", rdata2, 32'hBEEF_0001);
        check("A3 byte-lane lat4", rdata4, 32'hBEEF_0001);

        // A4: second l2_en while the slow instances are still busy is ignored
        @(negedge clk);
        l2_en = 1; l2_we = 0; l2_be = 0; l2_addr = 32'h0000_0FFC;     // read (accepted)
        t_rdy0 = -1; t_rdy2 = -1; t_rdy4 = -1;
        @(posedge clk); t_req = cyc;
        @(negedge clk);
        l2_en = 1; l2_we = 1; l2_be = 4'b1111; l2_addr = 32'h0000_0804; l2_wdata = 32'hDEAD_DEAD; // while busy
        @(posedge clk);
        @(negedge clk); l2_en = 0; l2_we = 0; l2_be = 0;
        while (t_rdy4 < 0) @(posedge clk);
        #2;
        check("A4 busy read lat4 unchanged", t_rdy4 - t_req, 5);
        check("A4 busy read data lat4", rdata4, 32'h1234_5678);
        repeat (6) @(posedge clk);
        l2_access(1'b0, 4'b0000, 32'h0000_0804, 32'h0);
        // lat0 accepted the write (not busy), lat2/lat4 were busy and dropped it
        check("A4 lat0 accepted write", rdata0, 32'hDEAD_DEAD);
        check("A4 lat2 ignored write",  rdata2, 32'h0000_0000);
        check("A4 lat4 ignored write",  rdata4, 32'h0000_0000);

        // A5: back-to-back writes + reads over 8 words
        for (k = 0; k < 8; k = k + 1)
            l2_access(1'b1, 4'b1111, 32'h0000_0900 + 4*k, 32'hA000_0000 + k);
        for (k = 0; k < 8; k = k + 1) begin
            l2_access(1'b0, 4'b0000, 32'h0000_0900 + 4*k, 32'h0);
            check("A5 b2b lat0", rdata0, 32'hA000_0000 + k);
            check("A5 b2b lat2", rdata2, 32'hA000_0000 + k);
            check("A5 b2b lat4", rdata4, 32'hA000_0000 + k);
            check("A5 b2b timing lat4", t_rdy4 - t_req, 5);
        end

        // ---------------- Part B ----------------
        $display("Part B: end-to-end Harvard data-path latency (req -> d_ready)");

        cpu_access(1'b1, 32'h0000_0010, 32'h1111_0010);   // DMEM write
        for (k = 0; k < 3; k = k + 1) lat_dmem_wr[k] = lat[k];
        cpu_access(1'b0, 32'h0000_0010, 32'h0);           // DMEM read
        for (k = 0; k < 3; k = k + 1) begin
            lat_dmem_rd[k] = lat[k];
            check("B DMEM read data", got[k], 32'h1111_0010);
        end
        cpu_access(1'b1, 32'h0000_0A00, 32'h2222_0A00);   // L2 write
        for (k = 0; k < 3; k = k + 1) lat_l2_wr[k] = lat[k];
        cpu_access(1'b0, 32'h0000_0A00, 32'h0);           // L2 read
        for (k = 0; k < 3; k = k + 1) begin
            lat_l2_rd[k] = lat[k];
            check("B L2 read data", got[k], 32'h2222_0A00);
        end

        // DMEM latency must not depend on the L2 setting; every extra L2 wait
        // state must add exactly one clock to the L2 transaction.
        for (k = 0; k < 3; k = k + 1) begin
            check("B DMEM rd lat indep of L2", lat_dmem_rd[k], lat_dmem_rd[0]);
            check("B DMEM wr lat indep of L2", lat_dmem_wr[k], lat_dmem_wr[0]);
            check("B L2 rd lat = base + L", lat_l2_rd[k], lat_l2_rd[0] + 2*k);
            check("B L2 wr lat = base + L", lat_l2_wr[k], lat_l2_wr[0] + 2*k);
        end

        $display("");
        $display("  Measured CPU-visible latency (clocks from req to d_ready)");
        $display("  L2_LATENCY | DMEM write | DMEM read | L2 write | L2 read");
        for (k = 0; k < 3; k = k + 1)
            $display("  %10d | %10d | %9d | %8d | %7d",
                     2*k, lat_dmem_wr[k], lat_dmem_rd[k], lat_l2_wr[k], lat_l2_rd[k]);
        $display("");

        $display("tb_l2_latency: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("tb_l2_latency: ALL TESTS PASSED");
        else             $fatal(1, "tb_l2_latency: TESTS FAILED");
        $finish;
    end

    // Safety timeout
    initial begin
        #200000;
        $fatal(1, "tb_l2_latency: TIMEOUT");
    end

endmodule
