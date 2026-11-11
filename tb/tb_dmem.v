`timescale 1ns / 1ps
`include "defines.vh"

// -----------------------------------------------------------------------------
// tb_dmem.v  (Member 2) - self-checking unit testbench for data_memory.v
//
// - Stimulus is driven on the FALLING edge so it is stable before the DUT
//   samples it on the rising edge (no testbench/DUT race).
// - Every read is compared against a reference model (model[]) that applies
//   the same byte-enable rules. Any mismatch is counted and printed.
// - Ends with $fatal if anything failed, so `make sim_dmem` exits non-zero.
// -----------------------------------------------------------------------------
module tb_dmem;

    reg                    clk;
    reg                    rst_n;
    reg                    dmem_en;
    reg                    dmem_we;
    reg  [3:0]             d_be;
    reg  [`ADDR_WIDTH-1:0] d_addr;
    reg  [`DATA_WIDTH-1:0] d_wdata;
    wire [`DATA_WIDTH-1:0] d_rdata;
    wire                   d_ready;

    data_memory u_dmem (
        .clk     (clk),
        .rst_n   (rst_n),
        .dmem_en (dmem_en),
        .dmem_we (dmem_we),
        .d_be    (d_be),
        .d_addr  (d_addr),
        .d_wdata (d_wdata),
        .d_rdata (d_rdata),
        .d_ready (d_ready)
    );

    always #5 clk = ~clk; // 100 MHz

    // ---------------------------------------------------------------- model
    reg [`DATA_WIDTH-1:0] model [0:`DMEM_DEPTH-1];
    integer errors = 0;
    integer checks = 0;
    integer k;

    task check(input [255:0] what, input [31:0] got, input [31:0] exp);
        begin
            checks = checks + 1;
            if (got !== exp) begin
                errors = errors + 1;
                $display("  FAIL %0s : got 0x%08h, expected 0x%08h (t=%0t)", what, got, exp, $time);
            end
        end
    endtask

    task idle;
        begin
            @(negedge clk);
            dmem_en = 0; dmem_we = 0; d_be = 4'b0000;
        end
    endtask

    // One write cycle. Model is updated with the same byte-enable rules.
    task do_write(input [31:0] addr, input [31:0] data, input [3:0] be);
        begin
            @(negedge clk);
            dmem_en = 1; dmem_we = 1; d_be = be; d_addr = addr; d_wdata = data;
            if (be[0]) model[addr[9:2]][7:0]   = data[7:0];
            if (be[1]) model[addr[9:2]][15:8]  = data[15:8];
            if (be[2]) model[addr[9:2]][23:16] = data[23:16];
            if (be[3]) model[addr[9:2]][31:24] = data[31:24];
            @(posedge clk); #1;
            check("write d_ready", d_ready, 1);
        end
    endtask

    // One read cycle; checks data 1 cycle after the address is presented.
    task do_read(input [31:0] addr);
        begin
            @(negedge clk);
            dmem_en = 1; dmem_we = 0; d_be = 4'b0000; d_addr = addr;
            @(posedge clk); #1;
            check("read d_ready", d_ready, 1);
            check("read d_rdata", d_rdata, model[addr[9:2]]);
        end
    endtask

    // ------------------------------------------------------------- stimulus
    integer cycles_start, cycles_end, n_reads;
    integer cycle_count = 0;
    always @(posedge clk) cycle_count = cycle_count + 1;

    reg [31:0] held, r_addr, r_data;
    reg [3:0]  r_be;
    integer    seed;

    initial begin
        $dumpfile("sim/dmem.vcd");
        $dumpvars(0, tb_dmem);

        for (k = 0; k < `DMEM_DEPTH; k = k + 1) model[k] = 32'h0;

        clk = 0; rst_n = 0; dmem_en = 0; dmem_we = 0; d_be = 0; d_addr = 0; d_wdata = 0;

        // T1: reset / idle
        $display("T1  reset and idle: d_ready stays low");
        @(posedge clk); #1;
        check("d_ready in reset", d_ready, 0);
        @(negedge clk); rst_n = 1;
        @(posedge clk); #1;
        check("d_ready idle", d_ready, 0);

        // T2: power-on contents are zero
        $display("T2  power-on contents read as zero");
        do_read(32'h0000_0000);
        do_read(32'h0000_03FC);

        // T3: full-word write then read
        $display("T3  full-word write / read-back");
        do_write(32'h0000_0000, 32'hDEAD_BEEF, 4'b1111);
        do_read (32'h0000_0000);

        // T4: synchronous read latency is exactly one clock
        $display("T4  read latency = 1 clock (data not visible before the edge)");
        do_write(32'h0000_0008, 32'h1234_5678, 4'b1111);
        do_read (32'h0000_0000);                       // d_rdata = DEADBEEF
        @(negedge clk);
        dmem_en = 1; dmem_we = 0; d_addr = 32'h0000_0008;
        #1 check("before edge (old data)", d_rdata, 32'hDEAD_BEEF);
        @(posedge clk); #1;
        check("after edge (new data)", d_rdata, 32'h1234_5678);

        // T5: boundary word
        $display("T5  last word 0x3FC");
        do_write(32'h0000_03FC, 32'hCAFE_F00D, 4'b1111);
        do_read (32'h0000_03FC);

        // T6: unique pattern in every word, then read all back (no aliasing)
        $display("T6  fill all %0d words with unique data, read all back", `DMEM_DEPTH);
        for (k = 0; k < `DMEM_DEPTH; k = k + 1)
            do_write(k * 4, {8'hA5, k[7:0], ~k[7:0], k[7:0]}, 4'b1111);
        for (k = 0; k < `DMEM_DEPTH; k = k + 1)
            do_read(k * 4);

        // T7: byte enables (SB / SH style writes)
        $display("T7  byte-lane writes");
        do_write(32'h0000_0010, 32'hAABB_CCDD, 4'b1111);
        do_write(32'h0000_0010, 32'h0000_0011, 4'b0001);  // byte 0
        do_read (32'h0000_0010);                          // AABBCC11
        check("byte0 result", d_rdata, 32'hAABB_CC11);
        do_write(32'h0000_0010, 32'h5566_0000, 4'b1100);  // upper half
        do_read (32'h0000_0010);                          // 5566CC11
        check("upper-half result", d_rdata, 32'h5566_CC11);
        do_write(32'h0000_0010, 32'hFFFF_FFFF, 4'b0000);  // no lanes
        do_read (32'h0000_0010);
        check("no-lane write", d_rdata, 32'h5566_CC11);

        // T8: dmem_en gates everything
        $display("T8  write with dmem_en = 0 is ignored");
        @(negedge clk);
        dmem_en = 0; dmem_we = 1; d_be = 4'b1111; d_addr = 32'h0000_0010; d_wdata = 32'h0BAD_0BAD;
        @(posedge clk); #1;
        check("d_ready when disabled", d_ready, 0);
        do_read(32'h0000_0010);                           // still 5566CC11

        // T9: byte offset bits [1:0] do not change the word index
        $display("T9  unaligned byte address 0x006 selects word 0x004");
        do_write(32'h0000_0006, 32'h7777_7777, 4'b1111);
        do_read (32'h0000_0004);
        check("word 0x004", d_rdata, 32'h7777_7777);

        // T10: read-during-write keeps old d_rdata (NO_CHANGE)
        $display("T10 d_rdata holds during a write cycle");
        do_read (32'h0000_0010);
        held = d_rdata;
        do_write(32'h0000_0010, 32'h9999_9999, 4'b1111);
        check("d_rdata held over write", d_rdata, held);
        do_read (32'h0000_0010);                          // now 99999999

        // T11: write followed immediately by a read of the same word
        $display("T11 write then read same word on the next cycle");
        do_write(32'h0000_0020, 32'h0102_0304, 4'b1111);
        do_read (32'h0000_0020);

        // T12: back-to-back reads, one per clock - measure throughput
        $display("T12 back-to-back reads, one per clock");
        n_reads = 16;
        @(negedge clk);
        dmem_en = 1; dmem_we = 0; d_be = 0; d_addr = 0;
        cycles_start = cycle_count;
        for (k = 1; k <= n_reads; k = k + 1) begin
            @(negedge clk);                               // result of read k-1 is out
            check("pipelined read", d_rdata, model[k - 1]);
            check("pipelined ready", d_ready, 1);
            d_addr = k * 4;
        end
        cycles_end = cycle_count;
        idle;
        $display("    %0d reads completed in %0d clock cycles", n_reads, cycles_end - cycles_start);

        // T13: random traffic vs. reference model (fixed seed = repeatable)
        $display("T13 500 random reads/writes against the reference model");
        seed = 2026;
        k = $urandom(seed);
        for (k = 0; k < 500; k = k + 1) begin
            r_addr = (($urandom % `DMEM_DEPTH) << 2) | ($urandom % 4);
            r_data = $urandom;
            r_be   = $urandom;
            if ($urandom % 2) do_write(r_addr, r_data, r_be);
            else              do_read (r_addr);
        end

        idle;
        @(posedge clk); #1;
        check("d_ready after idle", d_ready, 0);

        $display("");
        $display("tb_dmem: %0d checks, %0d errors", checks, errors);
        if (errors == 0) $display("tb_dmem: ALL TESTS PASSED");
        else             $fatal(1, "tb_dmem: TESTS FAILED");
        $finish;
    end

    // Safety net in case a task waits forever.
    initial begin
        #2_000_000;
        $fatal(1, "tb_dmem: timeout");
    end

endmodule
